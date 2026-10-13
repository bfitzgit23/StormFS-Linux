#!/bin/bash
#
# lfs-mkstage3.sh - build or pack an LFS root filesystem into a stage3 archive.
#
# Adapted from the Vylen `make_tarball.sh` (which drives `emerald` and
# `.epkg.tar.xz` packages) for LFS systems whose package manager is either
# **scratchpkg** or **pacman**.  The flow and the config file, package list and
# --clean/--compress/--force interface are kept; the package manager, the world
# or explicit-install bookkeeping, the caches that must not be captured and the
# chroot helper are replaced by the real ones of each manager:
#
#   scratchpkg : pkgadd --root=ROOTFS <pkg>.spkg.tar.*   DB var/lib/scratchpkg/db
#                world file var/lib/scratchpkg/world     helper xchroot
#   pacman     : pacman --root ROOTFS --dbpath ... -U    DB var/lib/pacman
#                explicit set via -D --asexplicit        helper chroot + mounts
#
# Modes
#   assemble (default)   install --packages from --pkg-dir into --rootfs, run
#                        the post-install steps.  Add --compress to then pack.
#   pack (--compress)    with an existing --rootfs: pack it and nothing else
#                        (the source script's --compress, i.e. the stage3 step).
#   --clean              delete --rootfs and exit.
#
# Examples
#
#   # LFS + scratchpkg: assemble from a cache of built packages, then pack
#   sudo scripts/lfs-mkstage3.sh --pkgmgr scratchpkg --rootfs /mnt/lfs \
#        --pkg-dir /var/cache/scratchpkg/packages \
#        --packages lfs-packages.txt --compress
#
#   # LFS + pacman: pack an installed system (no package cache needed)
#   sudo scripts/lfs-mkstage3.sh --pkgmgr pacman --rootfs /mnt/lfs \
#        --compress --compressor zstd -l 19
#
#   # Both: dry-run first - prints every command and every exclude, changes nothing
#   scripts/lfs-mkstage3.sh --rootfs /mnt/lfs --compress --dry-run
#
# Restore an archive with:
#
#   sudo tar --numeric-owner -xpf lfs-stage3-*.tar.zst -C /mnt/lfs
#
# Exit status is 0 only when every requested step succeeded.  The archive is
# written to a .partial file and moved into place only after it has been
# re-read, so a failed run never replaces a good archive with a partial one.

set -euo pipefail

PROGRAM=${0##*/}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)

# ---------------------------------------------------------------------------
# Defaults (a config file and the environment may override all of these)
# ---------------------------------------------------------------------------

PKGMGR=${PKGMGR:-}                      # scratchpkg | pacman | empty = autodetect
ROOTFS=${ROOTFS:-/mnt/lfs}              # root filesystem to assemble and/or pack
PKG_DIR=${PKG_DIR:-}                    # directory holding the built packages
PACKAGES=${PACKAGES:-}                  # file: one package name per line
WORLD=${WORLD:-}                        # file: names to mark as explicitly installed
OUTPUT=${OUTPUT:-${TARBALL_IMG:-}}      # archive path (TARBALL_IMG is the old name)
COMPRESSOR=${COMPRESSOR:-xz}            # xz | zstd | gzip | none
LEVEL=${LEVEL:-}
LEVEL_GIVEN=no
THREADS=${THREADS:-}
EXCLUDES=()
LOCALES=${LOCALES:-"C.UTF-8 en_US.ISO-8859-1 en_US.UTF-8"}
CHECKSUM=${CHECKSUM:-sha256sum}         # sha256sum | sha512sum | b3sum | none
HOST_PACMAN_CONF=${HOST_PACMAN_CONF:-}  # --config for pacman when the root has none
CHROOT_CMD=${CHROOT_CMD:-}              # override the chroot helper (xchroot, chroot)
PACMAN_CONF=${PACMAN_CONF:-}
PKGADD=${PKGADD:-pkgadd}
PACMAN=${PACMAN:-pacman}

DRY_RUN=no
NUMERIC_OWNER=yes
VERIFY=yes
DO_CLEAN=0
DO_PACK=0
DO_FORCE=0
NO_HOOKS=no
NO_LOCALES=no
NO_DEFAULT_EXCLUDES=no
ONE_BY_ONE=no
ONE_FILE_SYSTEM=no
IGNORE_CONFLICT=no
NO_SCRIPTLET=no
REBUILD=no
CHECK_FILES=no
REVDEP_REBUILD=no
VERBOSE=no

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

msg_info() { printf '==> %s\n' "$*"; }
msg_warn() { printf '%s: warning: %s\n' "$PROGRAM" "$*" >&2; }
die()      { printf '%s: ERROR: %s\n' "$PROGRAM" "$*" >&2; exit 1; }

usage() {
	cat <<EOF
Usage: $PROGRAM [options]

Assemble and/or pack an LFS root filesystem as a stage3 archive, using either
scratchpkg or pacman as the package manager.

Modes:
  (default)                 install --packages from --pkg-dir into --rootfs and
                            run the post-install steps
      --compress            pack --rootfs (alone if it is populated, otherwise
                            after assembling); repeats are cheap
      --clean               delete --rootfs and exit
      --force               assemble even if --rootfs is not empty

Packages:
      --pkgmgr NAME         scratchpkg or pacman (default: autodetect from
                            --rootfs, then from \$PATH)
  -d, --pkg-dir DIR         built packages (default: \$PKG_DIR, else the
                            manager's cache: /var/cache/scratchpkg/packages or
                            /var/cache/pacman/pkg)
  -p, --packages FILE       package names, in install order, one per line
                            (only the first field is used, so \`scratch installed\`
                            and \`pacman -Qq\` output can be used directly)
  -w, --world FILE          names to mark explicitly installed
                            (default: every name in --packages)
      --ignore-conflict     pass -c/--ignore-conflict to pkgadd
      --reinstall           pkgadd -r: reinstall already-installed packages
      --one-by-one          install one package per transaction, in list order
                            (slower; use when a single transaction trips over
                            ordering or scriptlets)
      --no-scriptlet        pacman --noscriptlet (do not run .INSTALL scripts)
      --pacman-config FILE  pacman --config (default: the root's /etc/pacman.conf)
  -r, --rootfs DIR          root filesystem (default: $ROOTFS)
  -o, --output FILE         archive path
                            (default: lfs-stage3-<version>-<date>-<arch>.tar.<ext>)

Packing:
  -C, --compressor NAME     xz (default), zstd, gzip, or none
  -l, --level N             compression level (default: 6 xz, 19 zstd, 9 gzip)
  -T, --threads N           compressor threads (default: all CPUs)
  -x, --exclude PATTERN     extra tar exclude, repeatable
      --no-default-excludes keep /sources, /tools, /root/* and /home/*
      --one-file-system     do not cross filesystem boundaries (skips separately
                            mounted /boot or /home)
      --no-numeric-owner    do not force numeric owners
      --no-verify           do not re-read the archive after writing it
      --checksum CMD        sha256sum (default), sha512sum, b3sum, or none;
                            written as <archive>.sha256/.sha512/.b3
      --no-checksum         same as --checksum none
      --no-hooks            skip the post-install steps (ldconfig, locales,
                            triggers, database checks)
      --no-locales          skip locale-archive generation
      --check-files         pacman: also run \`pacman -Qkk\` inside the root
      --revdep-rebuild      scratchpkg: \`revdep -r -y\` (rebuild broken packages)
      --chroot-cmd CMD      chroot helper (default: xchroot, else an own chroot
                            with /dev, /proc, /sys, /run mounted)
      --config FILE         source FILE first (default:
                            \$SCRIPT_DIR/lfs-mkstage3.conf when it exists)
      --dry-run             print every command and exclude, change nothing
  -v, --verbose             print each command as it runs
  -h, --help                this help

Environment: PKGMGR ROOTFS PKG_DIR PACKAGES WORLD TARBALL_IMG COMPRESSOR LEVEL
             THREADS LOCALES CHECKSUM HOST_PACMAN_CONF PACMAN_CONF CHROOT_CMD
             PKGADD PACMAN

Exit status: 0 on success, 1 on any failure.
EOF
}

# ---------------------------------------------------------------------------
# Temporary files: one trap, removed on every exit path
# ---------------------------------------------------------------------------

TMP_FILES=()
PARTIAL=
MOUNTS=()

cleanup_mounts() {
	local i m
	for ((i = ${#MOUNTS[@]} - 1; i >= 0; i--)); do
		m=${MOUNTS[i]}
		umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true
	done
	MOUNTS=()
}

cleanup() {
	local f
	[ -n "$PARTIAL" ] && rm -f -- "$PARTIAL"
	for f in ${TMP_FILES[@]+"${TMP_FILES[@]}"}; do
		rm -f -- "$f"
	done
	cleanup_mounts
}
trap cleanup EXIT INT TERM

new_tmp() {
	local t
	t=$(mktemp) || die "cannot create a temporary file"
	TMP_FILES+=("$t")
	printf '%s' "$t"
}

# ---------------------------------------------------------------------------
# Command execution (privilege + dry-run aware)
# ---------------------------------------------------------------------------

# Run a command as root, using whichever privilege escalation is available.
# `su -c` needs a single shell string, which is what printf %q is for; the
# source script used "$*", which broke on arguments containing spaces.
as_root() {
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
	elif command -v sudo >/dev/null 2>&1; then
		sudo "$@"
	elif command -v doas >/dev/null 2>&1; then
		doas "$@"
	elif command -v su >/dev/null 2>&1; then
		# shellcheck disable=SC2016
		su -c "$(printf '%q ' "$@")"
	else
		die "need root for: $* (no sudo, doas or su found)"
	fi
}

# Privileged step.
step_root() {
	if [ "$DRY_RUN" = yes ]; then
		printf '  + %s\n' "$*"
		return 0
	fi
	[ "$VERBOSE" = yes ] && printf '  + %s\n' "$*"
	as_root "$@"
}

# Unprivileged step: tar reads, inspection tools.
step() {
	if [ "$DRY_RUN" = yes ]; then
		printf '  + %s\n' "$*"
		return 0
	fi
	[ "$VERBOSE" = yes ] && printf '  + %s\n' "$*"
	"$@"
}

# A dry run must work on a host that has none of the tools installed, so tool
# availability is only enforced when something is really going to run.
have_or_die() {
	command -v "$1" >/dev/null 2>&1 || [ "$DRY_RUN" = yes ] || die "$2"
}

# ---------------------------------------------------------------------------
# chroot helper
#
# xchroot (shipped by scratchpkg) mounts /dev, /dev/pts, /dev/shm, /proc, /run,
# /sys and /tmp and unmounts them again on exit.  When it is not installed we do
# the same ourselves, and the shared cleanup trap never leaves a mount behind.
# ---------------------------------------------------------------------------

mount_into() {
	local rel=$1
	shift
	local target="$ROOTFS/$rel"
	mkdir -p "$target" 2>/dev/null || return 1
	mount "$@" "$target" || return 1
	MOUNTS+=("$target")
}

# in_root <command...> - run a command inside ROOTFS.  The status is the
# status of the command, so callers can decide whether a failure is fatal.
in_root() {
	if [ -n "$CHROOT_CMD" ]; then
		step_root "$CHROOT_CMD" "$ROOTFS" "$@" || return 1
		return 0
	fi
	if command -v xchroot >/dev/null 2>&1; then
		step_root xchroot "$ROOTFS" "$@" || return 1
		return 0
	fi
	if [ "$DRY_RUN" = yes ]; then
		printf '  + chroot %s %s\n' "$ROOTFS" "$*"
		return 0
	fi

	command -v chroot >/dev/null 2>&1 || die "chroot not found; install scratchpkg's xchroot or use --chroot-cmd"
	msg_info "Mounting /dev, /dev/pts, /dev/shm, /proc, /run, /sys, /tmp for the chroot..."
	mount_into dev --bind /dev || die "failed to bind-mount /dev into $ROOTFS"
	mount_into dev/pts -t devpts devpts -o gid=5,mode=620 || die "failed to mount devpts into $ROOTFS"
	mount_into dev/shm -t tmpfs tmpfs -o nosuid,nodev || die "failed to mount /dev/shm into $ROOTFS"
	mount_into proc -t proc proc || die "failed to mount /proc into $ROOTFS"
	mount_into run -t tmpfs tmpfs || die "failed to mount /run into $ROOTFS"
	mount_into sys -t sysfs sysfs || die "failed to mount /sys into $ROOTFS"
	mount_into tmp -t tmpfs tmpfs -o mode=1777,nosuid,nodev || die "failed to mount /tmp into $ROOTFS"

	[ "$VERBOSE" = yes ] && printf '  + chroot %s %s\n' "$ROOTFS" "$*"
	local status=0
	chroot "$ROOTFS" /usr/bin/env -i \
		HOME=/root TERM="${TERM:-dumb}" PATH=/bin:/usr/bin:/sbin:/usr/sbin \
		"$@" || status=$?
	cleanup_mounts
	return "$status"
}

# ---------------------------------------------------------------------------
# Package manager backends
# ---------------------------------------------------------------------------

# Package archive suffix, as produced by each manager.
pkg_glob() {
	case $PKGMGR in
		scratchpkg) printf '%s' '*.spkg.tar.*' ;;
		pacman)     printf '%s' '*.pkg.tar.*' ;;
	esac
}

# Strip the manager's suffix from a package file name.
pkg_basename() {
	local base=${1##*/}
	case $PKGMGR in
		scratchpkg) base=${base%.spkg.tar.*} ;;
		pacman)     base=${base%.pkg.tar.*} ;;
	esac
	printf '%s' "$base"
}

# Print the .PKGINFO of a pacman package, whatever it is compressed with.
read_pkginfo() {
	local f=$1
	case $f in
		*.zst | *.zstd) command -v zstd >/dev/null 2>&1 || return 1
		                zstd -dc -- "$f" 2>/dev/null | tar -xO -f - .PKGINFO 2>/dev/null ;;
		*.xz)  command -v xz >/dev/null 2>&1 || return 1
		       xz -dc -- "$f" 2>/dev/null | tar -xO -f - .PKGINFO 2>/dev/null ;;
		*.gz)  command -v gzip >/dev/null 2>&1 || return 1
		       gzip -dc -- "$f" 2>/dev/null | tar -xO -f - .PKGINFO 2>/dev/null ;;
		*.bz2) command -v bzip2 >/dev/null 2>&1 || return 1
		       bzip2 -dc -- "$f" 2>/dev/null | tar -xO -f - .PKGINFO 2>/dev/null ;;
		*.lz4) command -v lz4 >/dev/null 2>&1 || return 1
		       lz4 -dc -- "$f" 2>/dev/null | tar -xO -f - .PKGINFO 2>/dev/null ;;
		*)     tar -xO -f "$f" .PKGINFO 2>/dev/null ;;
	esac
}

# pkg_identity <file> -> "name version release".
#
# A pacman archive carries its identity in .PKGINFO, so use it when it can be
# read (names may contain dashes and versions may carry epochs, and the file
# name also ends in the architecture).  Older archives without readable
# metadata fall back to peeling "name-version-release-arch" from the file name,
# which is what a scratchpkg package is: `pkgbuild` writes a plain tar of the
# staged files with no embedded metadata, so there the file name is the only
# source of truth.
pkg_identity() {
	local f=$1 base rest name version release arch info pkgname pkgver

	if [ "$PKGMGR" = pacman ]; then
		info=$(read_pkginfo "$f") || info=
		if [ -n "$info" ]; then
			pkgname=$(printf '%s\n' "$info" | awk -F' *= *' '$1 == "pkgname" { print $2; exit }')
			pkgver=$(printf '%s\n' "$info" | awk -F' *= *' '$1 == "pkgver" { print $2; exit }')
			if [ -n "$pkgname" ] && [ -n "$pkgver" ]; then
				printf '%s %s %s\n' "$pkgname" "${pkgver%-*}" "${pkgver##*-}"
				return 0
			fi
		fi
	fi

	base=$(pkg_basename "$f")
	if [ "$PKGMGR" = pacman ]; then
		# name-version-release-arch: drop the architecture first, but only when
		# it is not numeric (a release always is).
		arch=${base##*-}
		case $arch in
			'' | *[!0-9]*) base=${base%-*} ;;
		esac
	fi
	release=${base##*-}
	rest=${base%-*}
	version=${rest##*-}
	name=${rest%-*}
	printf '%s %s %s\n' "$name" "$version" "$release"
}

detect_pkgmgr() {
	local candidates=()
	if [ -d "$ROOTFS/var/lib/scratchpkg/db" ]; then
		candidates+=(scratchpkg)
	fi
	if [ -d "$ROOTFS/var/lib/pacman" ]; then
		candidates+=(pacman)
	fi
	if [ ${#candidates[@]} -eq 0 ]; then
		command -v "$PKGADD" >/dev/null 2>&1 && candidates+=(scratchpkg)
		command -v "$PACMAN" >/dev/null 2>&1 && candidates+=(pacman)
	fi
	case ${#candidates[@]} in
		1) PKGMGR=${candidates[0]} ;;
		0) die "cannot tell whether this is a scratchpkg or a pacman system; pass --pkgmgr" ;;
		*) die "$ROOTFS has both a scratchpkg and a pacman database; pass --pkgmgr" ;;
	esac
	msg_info "Package manager: $PKGMGR (detected)"
}

default_pkg_dir() {
	case $PKGMGR in
		scratchpkg) printf '%s' '/var/cache/scratchpkg/packages' ;;
		pacman)     printf '%s' '/var/cache/pacman/pkg' ;;
	esac
}

# ---------------------------------------------------------------------------
# Package list handling
# ---------------------------------------------------------------------------

# read_package_list <list file> <output file>
# One package per line; '#' starts a comment; only the first field is taken, so
# `scratch installed` ("name version-release"), `pacman -Qq` and plain name
# lists all work.  Writes through a file rather than a subshell so that the
# emptiness check below actually aborts the script.
read_package_list() {
	local file=$1 out=$2 line name count=0
	[ -r "$file" ] || die "package list not readable: $file"
	: > "$out"
	while IFS= read -r line || [ -n "$line" ]; do
		line=${line%%#*}
		name=$(printf '%s' "$line" | awk '{print $1}')
		[ -n "$name" ] || continue
		printf '%s\n' "$name" >> "$out"
		count=$((count + 1))
	done < "$file"
	[ "$count" -gt 0 ] || die "package list is empty: $file"
}

# Fill PKG_FILE_OF[name] with the archive that provides it, and check the cache
# for duplicate versions and for packages that nobody asked for (the source
# script's check_needed_files).
index_package_dir() {
	local glob f base rest version release name want found
	declare -gA PKG_FILE_OF=()
	local -A seen_versions=()
	local -a files=()

	glob=$(pkg_glob)
	shopt -s nullglob
	# shellcheck disable=SC2206  # the glob is intended: expand $glob inside $PKG_DIR
	files=("$PKG_DIR"/$glob)
	shopt -u nullglob
	[ ${#files[@]} -gt 0 ] || die "no packages found in $PKG_DIR (expected $glob)"

	for f in "${files[@]}"; do
		# name version release, from the package metadata when it has any
		read -r name version release <<<"$(pkg_identity "$f")"
		base=$(pkg_basename "$f")

		[ -z "${seen_versions[$name]:-}" ] ||
			die "multiple versions of '$name' in $PKG_DIR: ${seen_versions[$name]} and $base"
		seen_versions[$name]=$base

		found=0
		for want in "${PACKAGE_LIST[@]}"; do
			if [ "$want" = "$name" ]; then
				found=1
				break
			fi
		done
		[ "$found" -eq 1 ] || die "unexpected package in $PKG_DIR (not in the list): $base"

		PKG_FILE_OF[$name]=$f
		[ "$VERBOSE" = yes ] && printf '  %s -> %s-%s-%s\n' "$name" "$name" "$version" "$release"
	done

	for want in "${PACKAGE_LIST[@]}"; do
		[ -n "${PKG_FILE_OF[$want]:-}" ] || die "missing package: $want ($glob not found in $PKG_DIR)"
	done
}

# ---------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------

prepare_root() {
	msg_info "Preparing $ROOTFS..."
	case $PKGMGR in
		scratchpkg)
			step_root mkdir -p \
				"$ROOTFS/var/lib/scratchpkg/db" \
				"$ROOTFS/var/cache/scratchpkg/packages" \
				"$ROOTFS/var/cache/scratchpkg/sources" \
				"$ROOTFS/var/cache/scratchpkg/work" \
				"$ROOTFS/etc"
			;;
		pacman)
			step_root mkdir -p \
				"$ROOTFS/var/lib/pacman/local" \
				"$ROOTFS/var/cache/pacman/pkg" \
				"$ROOTFS/etc"
			;;
	esac
}

install_packages() {
	local name file
	local -a files=() cmd=()
	for name in "${PACKAGE_LIST[@]}"; do
		files+=("${PKG_FILE_OF[$name]}")
	done

	msg_info "Installing ${#files[@]} packages from $PKG_DIR..."
	case $PKGMGR in
		scratchpkg)
			command -v "$PKGADD" >/dev/null 2>&1 || [ "$DRY_RUN" = yes ] ||
				die "$PKGADD not found in \$PATH (install scratchpkg, or set PKGADD)"
			cmd=("$PKGADD" --root="$ROOTFS" --no-backup)
			[ "$IGNORE_CONFLICT" = yes ] && cmd+=(-c)
			[ "$REBUILD" = yes ] && cmd+=(-r)
			;;
		pacman)
			command -v "$PACMAN" >/dev/null 2>&1 || [ "$DRY_RUN" = yes ] ||
				die "$PACMAN not found in \$PATH (install pacman, or set PACMAN)"
			cmd=("$PACMAN" --root "$ROOTFS" --dbpath "$ROOTFS/var/lib/pacman"
				--cachedir "$PKG_DIR" --config "$PACMAN_CONF" --noconfirm)
			[ "$NO_SCRIPTLET" = yes ] && cmd+=(--noscriptlet)
			cmd+=(-U)
			;;
	esac

	if [ "$ONE_BY_ONE" = yes ]; then
		for file in "${files[@]}"; do
			step_root "${cmd[@]}" "$file"
		done
	else
		step_root "${cmd[@]}" "${files[@]}"
	fi
}

# Mark the requested packages as explicitly installed: scratchpkg keeps this in
# its world file, pacman in the %REASON% field of its local database.
set_world() {
	local -a want=()
	local list_tmp world_file world_tmp

	if [ -n "$WORLD" ]; then
		world_tmp=$(new_tmp)
		read_package_list "$WORLD" "$world_tmp"
		mapfile -t want < "$world_tmp"
	else
		want=("${PACKAGE_LIST[@]}")
	fi

	msg_info "Marking ${#want[@]} packages as explicitly installed..."
	case $PKGMGR in
		scratchpkg)
			world_file="$ROOTFS/var/lib/scratchpkg/world"
			if [ "$DRY_RUN" = yes ]; then
				printf '  + merge %s (%s entries)\n' "$world_file" "${#want[@]}"
				return 0
			fi
			# Merge with what is already there, so assembling with --force
			# cannot silently drop entries from the world list.
			list_tmp=$(new_tmp)
			if [ -r "$world_file" ]; then cat "$world_file" > "$list_tmp"; fi
			printf '%s\n' "${want[@]}" >> "$list_tmp"
			sort -u "$list_tmp" -o "$list_tmp"
			step_root install -D -m0644 "$list_tmp" "$world_file"
			;;
		pacman)
			step_root "$PACMAN" --root "$ROOTFS" --dbpath "$ROOTFS/var/lib/pacman" \
				--config "$PACMAN_CONF" --noconfirm -D --asexplicit "${want[@]}"
			;;
	esac
}

# Post-install steps are reported, not hidden: a step that fails is counted in
# POST_ISSUES, and the script exits non-zero at the end (after anything that was
# asked for has still been packed).
POST_ISSUES=0

post_step() {
	local what=$1
	shift
	if ! "$@"; then
		POST_ISSUES=$((POST_ISSUES + 1))
		msg_warn "post-install step failed: $what"
		return 0
	fi
	[ "$VERBOSE" = yes ] && printf '  ok: %s\n' "$what"
	return 0
}

post_install() {
	if [ "$NO_HOOKS" = yes ]; then
		msg_info "Skipping post-install steps (--no-hooks)"
		return 0
	fi

	local bin loc lang map
	msg_info "Running post-install steps inside $ROOTFS..."

	# ldconfig: rebuild the shared library cache.
	for bin in /sbin/ldconfig /usr/sbin/ldconfig; do
		if [ -x "$ROOTFS$bin" ]; then
			post_step ldconfig in_root ldconfig
			break
		fi
	done

	# locale-archive: only when the root has localedef and no archive yet (the
	# same three locales the source script generated).
	if [ "$NO_LOCALES" = no ] && [ ! -f "$ROOTFS/usr/lib/locale/locale-archive" ] &&
		[ -x "$ROOTFS/usr/bin/localedef" ]; then
		for loc in $LOCALES; do
			lang=${loc%%.*}
			map=${loc##*.}
			post_step "localedef -i $lang -f $map $loc" in_root localedef -i "$lang" -f "$map" "$loc"
		done
	fi

	# hwdb: only exists when eudev or systemd is installed.
	if [ -x "$ROOTFS/usr/bin/udevadm" ]; then
		post_step "udevadm hwdb --update" in_root udevadm hwdb --update
	fi

	case $PKGMGR in
		scratchpkg)
			if [ -x "$ROOTFS/usr/bin/scratch" ]; then
				post_step "scratch trigger" in_root scratch trigger
				post_step "scratch integrity" in_root scratch integrity
			fi
			if [ -x "$ROOTFS/usr/bin/revdep" ]; then
				# The rebuild is opt-in: it needs the ports tree and a
				# compiler, which an assembled root may not have.
				if [ "$REVDEP_REBUILD" = yes ]; then
					post_step "revdep -r -y" in_root revdep -r -y
				fi
				post_step "revdep -f" in_root revdep -f
			fi
			;;
		pacman)
			if [ -x "$ROOTFS/usr/bin/pacman" ]; then
				post_step "pacman -Dk" in_root pacman -Dk
				if [ "$CHECK_FILES" = yes ]; then
					post_step "pacman -Qkk" in_root pacman -Qkk
				fi
			else
				msg_warn "pacman is not installed in $ROOTFS; skipping the database checks"
			fi
			;;
	esac
}

# ---------------------------------------------------------------------------
# Packing
# ---------------------------------------------------------------------------

build_exclude_list() {
	EXCLUDES_DEFAULT=(
		# pseudo-filesystems and filesystem bookkeeping: always excluded
		./proc ./sys ./dev ./run ./tmp ./var/tmp ./var/run ./var/lock
		./mnt ./media ./lost+found
	)
	if [ "$NO_DEFAULT_EXCLUDES" = no ]; then
		EXCLUDES_DEFAULT+=(
			# LFS build trees and per-machine state
			./sources ./tools ./root/* ./home/*
		)
	fi
	case $PKGMGR in
		scratchpkg)
			EXCLUDES_DEFAULT+=(
				./var/cache/scratchpkg/packages/* ./var/cache/scratchpkg/sources/*
				./var/cache/scratchpkg/work/* ./var/lib/scratchpkg/cbuild/*
				./etc/*.spkgnew ./usr/ports/*
			)
			;;
		pacman)
			EXCLUDES_DEFAULT+=(
				./var/cache/pacman/pkg/* ./var/lib/pacman/sync/*
				./etc/*.pacnew ./etc/*.pacsave ./var/log/pacman.log
			)
			;;
	esac
}

resolve_output() {
	[ -n "$OUTPUT" ] && return 0
	local version='' v=''
	if [ -r "$ROOTFS/etc/lfs-release" ]; then
		v=$(head -n1 "$ROOTFS/etc/lfs-release" | tr -d "[:space:]'\""); [ -n "$v" ] && version=$v
	fi
	if [ -z "$version" ] && [ -r "$ROOTFS/etc/lfs-version" ]; then
		v=$(head -n1 "$ROOTFS/etc/lfs-version" | tr -d "[:space:]'\""); [ -n "$v" ] && version=$v
	fi
	if [ -z "$version" ] && [ -r "$ROOTFS/etc/os-release" ]; then
		v=$(sed -n 's/^VERSION_ID="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$ROOTFS/etc/os-release" | head -n1)
		[ -n "$v" ] && version=$v
	fi
	[ -n "$version" ] || version=lfs
	OUTPUT="$PWD/lfs-stage3-${version}-$(date +%Y%m%d)-$(uname -m).tar.${EXT}"
}

pack_rootfs() {
	local output_abs output_dir status size count elapsed start pattern
	local -a tar_excludes=() tar_opts=() compress_opts=()

	[ -d "$ROOTFS" ] || die "root filesystem not found: $ROOTFS"
	[ -n "$(ls -A "$ROOTFS" 2>/dev/null)" ] || die "root filesystem is empty: $ROOTFS"
	ROOTFS=$(cd "$ROOTFS" && pwd -P)

	resolve_output
	case $OUTPUT in
		/*) output_abs=$OUTPUT ;;
		*)  output_abs=$PWD/${OUTPUT#./} ;;
	esac
	case $output_abs in
		"$ROOTFS"/*) die "output path is inside the root being archived: $output_abs" ;;
	esac

	for pattern in "${EXCLUDES_DEFAULT[@]}" ${EXCLUDES[@]+"${EXCLUDES[@]}"}; do
		tar_excludes+=(--exclude="$pattern")
	done

	tar_opts=("${tar_excludes[@]}")
	tar_opts+=(--warning=no-file-changed --warning=no-file-removed --ignore-failed-read)
	[ "$NUMERIC_OWNER" = yes ] && tar_opts+=(--numeric-owner)
	[ "$ONE_FILE_SYSTEM" = yes ] && tar_opts+=(--one-file-system)
	tar_opts+=(-C "$ROOTFS")

	[ -n "$COMPRESS_CMD" ] && compress_opts=(-I "$COMPRESS_CMD")

	if [ "$DRY_RUN" = yes ]; then
		printf '%s: would run (from %s):\n' "$PROGRAM" "$ROOTFS"
		printf '  tar %s %s -cpf %s .\n' \
			"${compress_opts[*]:-(no compression)}" "${tar_opts[*]}" "$output_abs"
		printf '%s: excluded paths:\n' "$PROGRAM"
		for pattern in "${EXCLUDES_DEFAULT[@]}" ${EXCLUDES[@]+"${EXCLUDES[@]}"}; do
			printf '  %s\n' "$pattern"
		done
		return 0
	fi

	output_dir=$(dirname "$output_abs")
	[ -d "$output_dir" ] || die "output directory does not exist: $output_dir"
	[ -w "$output_dir" ] || die "output directory is not writable: $output_dir (run with sudo?)"
	command -v tar >/dev/null 2>&1 || die "tar not found"

	# Write beside the target and move into place only when complete, so a
	# failed run never destroys an existing good archive (the source script
	# moved the old archive to .bak and restored it on failure).
	PARTIAL="$output_abs.partial.$$"

	msg_info "Archiving $ROOTFS -> $output_abs (${COMPRESSOR})"
	start=$(date +%s)
	status=0
	step tar ${compress_opts[@]+"${compress_opts[@]}"} "${tar_opts[@]}" -cpf "$PARTIAL" . || status=$?
	if [ "$status" -ne 0 ]; then
		rm -f -- "$PARTIAL"; PARTIAL=
		# tar exits 1 when files changed or vanished while being read, which is
		# normal on a live root and already covered by --ignore-failed-read.
		if [ "$status" -eq 1 ]; then
			msg_warn "tar reported changed files while reading $ROOTFS (exit 1); archive kept"
		else
			die "tar failed with status $status; no archive written"
		fi
	fi
	[ -s "$PARTIAL" ] || { rm -f -- "$PARTIAL"; PARTIAL=; die "archive is empty: nothing was captured"; }

	mv -f -- "$PARTIAL" "$output_abs"
	PARTIAL=

	if [ "$VERIFY" = yes ]; then
		msg_info "Verifying archive..."
		step tar -tf "$output_abs" >/dev/null || die "archive verification failed (truncated or corrupt): $output_abs"
	fi

	if [ "$CHECKSUM" != none ]; then
		command -v "$CHECKSUM" >/dev/null 2>&1 || die "$CHECKSUM not found (use --checksum none)"
		# sha256sum -> .sha256, sha512sum -> .sha512, b3sum -> .b3, i.e. the
		# names release files usually carry
		local suffix=${CHECKSUM%sum}
		step "$CHECKSUM" "$output_abs" > "$output_abs.$suffix"
		msg_info "Checksum: $output_abs.$suffix"
	fi

	elapsed=$(( $(date +%s) - start ))
	size=$(du -h "$output_abs" 2>/dev/null | cut -f1)
	count=$(tar -tf "$output_abs" 2>/dev/null | wc -l)
	printf '%s: wrote %s (%s, %s entries, %ss)\n' "$PROGRAM" "$output_abs" "${size:-?}" "$count" "$elapsed"
	printf '%s: restore with: sudo tar --numeric-owner -xpf %s -C <target>\n' "$PROGRAM" "$output_abs"
}

# ---------------------------------------------------------------------------
# Option parsing
# ---------------------------------------------------------------------------

# A config file is sourced first (the source script's `config`); the command
# line and the environment still win over it.
CONFIG=
for ((i = 1; i <= $#; i++)); do
	if [ "${!i}" = --config ]; then
		j=$((i + 1))
		CONFIG=${!j:-}
		break
	fi
done
if [ -z "$CONFIG" ] && [ -f "$SCRIPT_DIR/lfs-mkstage3.conf" ]; then
	CONFIG=$SCRIPT_DIR/lfs-mkstage3.conf
fi
if [ -n "$CONFIG" ]; then
	[ -r "$CONFIG" ] || die "config file not readable: $CONFIG"
	# shellcheck disable=SC1090
	. "$CONFIG"
	OUTPUT=${OUTPUT:-${TARBALL_IMG:-}}
	msg_info "Loaded config: $CONFIG"
fi

while [ $# -gt 0 ]; do
	case $1 in
		--pkgmgr) [ $# -ge 2 ] || die "$1 needs an argument"; PKGMGR=$2; shift 2 ;;
		-d|--pkg-dir) [ $# -ge 2 ] || die "$1 needs an argument"; PKG_DIR=$2; shift 2 ;;
		-p|--packages) [ $# -ge 2 ] || die "$1 needs an argument"; PACKAGES=$2; shift 2 ;;
		-w|--world) [ $# -ge 2 ] || die "$1 needs an argument"; WORLD=$2; shift 2 ;;
		-r|--rootfs) [ $# -ge 2 ] || die "$1 needs an argument"; ROOTFS=$2; shift 2 ;;
		-o|--output) [ $# -ge 2 ] || die "$1 needs an argument"; OUTPUT=$2; shift 2 ;;
		-C|--compressor) [ $# -ge 2 ] || die "$1 needs an argument"; COMPRESSOR=$2; shift 2 ;;
		-l|--level) [ $# -ge 2 ] || die "$1 needs an argument"; LEVEL=$2; LEVEL_GIVEN=yes; shift 2 ;;
		-T|--threads) [ $# -ge 2 ] || die "$1 needs an argument"; THREADS=$2; shift 2 ;;
		-x|--exclude) [ $# -ge 2 ] || die "$1 needs an argument"; EXCLUDES+=("$2"); shift 2 ;;
		--config) [ $# -ge 2 ] || die "$1 needs an argument"; shift 2 ;;
		--pacman-config) [ $# -ge 2 ] || die "$1 needs an argument"; PACMAN_CONF=$2; shift 2 ;;
		--chroot-cmd) [ $# -ge 2 ] || die "$1 needs an argument"; CHROOT_CMD=$2; shift 2 ;;
		--checksum) [ $# -ge 2 ] || die "$1 needs an argument"; CHECKSUM=$2; shift 2 ;;
		--no-checksum) CHECKSUM=none; shift ;;
		--compress|--pack-only) DO_PACK=1; shift ;;
		--clean) DO_CLEAN=1; shift ;;
		--force) DO_FORCE=1; shift ;;
		--no-hooks) NO_HOOKS=yes; shift ;;
		--no-locales) NO_LOCALES=yes; shift ;;
		--no-default-excludes) NO_DEFAULT_EXCLUDES=yes; shift ;;
		--one-by-one) ONE_BY_ONE=yes; shift ;;
		--one-file-system) ONE_FILE_SYSTEM=yes; shift ;;
		--ignore-conflict) IGNORE_CONFLICT=yes; shift ;;
		--reinstall) REBUILD=yes; shift ;;
		--no-scriptlet) NO_SCRIPTLET=yes; shift ;;
		--check-files) CHECK_FILES=yes; shift ;;
		--revdep-rebuild) REVDEP_REBUILD=yes; shift ;;
		--no-verify) VERIFY=no; shift ;;
		--no-numeric-owner) NUMERIC_OWNER=no; shift ;;
		--dry-run) DRY_RUN=yes; shift ;;
		-v|--verbose) VERBOSE=yes; shift ;;
		-h|--help) usage; exit 0 ;;
		*) die "unknown argument: $1 (try --help)" ;;
	esac
done

if [ "$LEVEL_GIVEN" = yes ]; then
	case $LEVEL in
		''|*[!0-9]*) die "invalid compression level: $LEVEL" ;;
	esac
fi

case $PKGMGR in
	''|scratchpkg|pacman) ;;
	*) die "unknown package manager: $PKGMGR (expected scratchpkg or pacman)" ;;
esac

# ---------------------------------------------------------------------------
# --clean: delete the rootfs and stop
# ---------------------------------------------------------------------------

if [ "$DO_CLEAN" -eq 1 ]; then
	case $ROOTFS in
		/|''|.|..) die "refusing to remove '$ROOTFS'" ;;
	esac
	# A tree that looks like a bootable system is only removed with --force, so
	# a mistyped --rootfs cannot wipe the machine the script runs on.
	if [ -e "$ROOTFS/etc/passwd" ] || [ -e "$ROOTFS/bin/sh" ]; then
		[ "$DO_FORCE" -eq 1 ] || die "refusing to remove $ROOTFS: it looks like a bootable system (use --force)"
	fi
	msg_info "Cleaning rootfs $ROOTFS..."
	step_root rm -rf -- "$ROOTFS"
	exit 0
fi

# ---------------------------------------------------------------------------
# Compressor (not needed for --clean)
# ---------------------------------------------------------------------------

case $COMPRESSOR in
	zstd|zst)
		COMPRESSOR=zstd
		have_or_die zstd "zstd not found; install it or use -C xz/-C gzip"
		[ "$LEVEL_GIVEN" = yes ] || LEVEL=19
		[ -n "$THREADS" ] || THREADS=0
		COMPRESS_CMD="zstd -T$THREADS -$LEVEL"
		EXT=zst
		;;
	xz)
		have_or_die xz "xz not found"
		[ "$LEVEL_GIVEN" = yes ] || LEVEL=6
		[ -n "$THREADS" ] || THREADS=0
		COMPRESS_CMD="xz -T$THREADS -$LEVEL"
		EXT=xz
		;;
	gzip|gz)
		COMPRESSOR=gzip
		have_or_die gzip "gzip not found"
		[ "$LEVEL_GIVEN" = yes ] || LEVEL=9
		COMPRESS_CMD="gzip -$LEVEL"
		EXT=gz
		;;
	none|tar)
		COMPRESSOR=none
		COMPRESS_CMD=
		EXT=tar
		;;
	*)
		die "unknown compressor: $COMPRESSOR (xz, zstd, gzip or none)"
		;;
esac

# ---------------------------------------------------------------------------
# Resolve the package manager, then pack and/or assemble
# ---------------------------------------------------------------------------

if [ -n "$PKGMGR" ]; then
	msg_info "Package manager: $PKGMGR"
else
	[ -d "$ROOTFS" ] || die "root filesystem not found: $ROOTFS"
	detect_pkgmgr
fi

build_exclude_list

# --compress on an existing populated rootfs is the stage3 step on its own (the
# source script's behaviour).  Otherwise --compress means "pack afterwards".
if [ "$DO_PACK" -eq 1 ] && [ -d "$ROOTFS" ] && [ -n "$(ls -A "$ROOTFS" 2>/dev/null)" ]; then
	pack_rootfs
	msg_info "Done!"
	exit 0
fi

# ---------------------------------------------------------------------------
# Assemble
# ---------------------------------------------------------------------------

case $ROOTFS in
	/|''|.|..) die "refusing to assemble into '$ROOTFS'" ;;
esac
[ -n "$PACKAGES" ] || die "no package list: pass --packages FILE"
[ -r "$PACKAGES" ] || die "package list not readable: $PACKAGES"
[ -n "$PKG_DIR" ] || PKG_DIR=$(default_pkg_dir)
[ -d "$PKG_DIR" ] || die "package directory not found: $PKG_DIR"

if [ -d "$ROOTFS" ] && [ -n "$(ls -A "$ROOTFS" 2>/dev/null)" ] && [ "$DO_FORCE" -eq 0 ]; then
	die "$ROOTFS already exists and is not empty (use --force to assemble into it, or --compress to pack it)"
fi

if [ "$PKGMGR" = pacman ] && [ -z "$PACMAN_CONF" ]; then
	if [ -r "$ROOTFS/etc/pacman.conf" ]; then
		PACMAN_CONF=$ROOTFS/etc/pacman.conf
	elif [ -n "$HOST_PACMAN_CONF" ] && [ -r "$HOST_PACMAN_CONF" ]; then
		PACMAN_CONF=$HOST_PACMAN_CONF
	elif [ "$DRY_RUN" = no ]; then
		die "no pacman config: create $ROOTFS/etc/pacman.conf or pass --pacman-config FILE"
	else
		PACMAN_CONF=$ROOTFS/etc/pacman.conf
	fi
fi
if [ "$PKGMGR" = pacman ] && [ "$DRY_RUN" = no ]; then
	[ -r "$PACMAN_CONF" ] || die "pacman config not readable: $PACMAN_CONF"
fi

LIST_TMP=$(new_tmp)
read_package_list "$PACKAGES" "$LIST_TMP"
mapfile -t PACKAGE_LIST < "$LIST_TMP"
unset LIST_TMP

index_package_dir

prepare_root
install_packages
set_world
post_install

if [ "$DO_PACK" -eq 1 ]; then
	pack_rootfs
fi

if [ "$POST_ISSUES" -gt 0 ]; then
	die "$POST_ISSUES post-install step(s) failed inside $ROOTFS (see the warnings above); the root filesystem and any archive are otherwise complete"
fi

if [ "$DO_PACK" -eq 1 ]; then
	msg_info "Done!"
else
	msg_info "Root filesystem assembled at $ROOTFS"
	msg_info "Pack it with: $PROGRAM --rootfs $ROOTFS --compress"
fi
