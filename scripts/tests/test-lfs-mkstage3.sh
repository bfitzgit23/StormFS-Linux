#!/bin/bash
#
# test-lfs-mkstage3.sh - regression test for scripts/lfs-mkstage3.sh.
#
# Builds throwaway LFS-shaped roots for both package managers and checks the
# packer end to end (archive contents, excludes, checksum, output naming), the
# assemble paths through --dry-run (the real pkgadd/pacman runs need root and a
# Linux host), and every refusal path.
#
# Usage: bash scripts/tests/test-lfs-mkstage3.sh
#
# (Like the other regression tests in this directory it is deliberately not
# marked executable in Git: run it through bash/sh.)
#
# Exit status 0 means every assertion held.  Individual cases that cannot run on
# the host (privileged cleanup without any escalation tool) are reported as
# SKIP and do not fail the suite.

set -uo pipefail

ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/lfs-mkstage3.sh"
WORK=$(mktemp -d) || { echo "cannot create a work directory" >&2; exit 1; }
if [ "${KEEP_WORK:-0}" = 1 ]; then
	trap 'echo "keeping work directory: $WORK" >&2' EXIT
else
	trap 'rm -rf "$WORK"' EXIT
fi

PASS=0
FAILED=0
SKIPPED=0

# Privileged steps are exercised only where the host can really escalate: a
# `sudo` that exists but refuses to run (a fresh Windows host, for example) is
# not enough, so probe it non-interactively first.
have_priv() {
	[ "$(id -u)" = 0 ] && return 0
	if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then return 0; fi
	if command -v doas >/dev/null 2>&1 && doas true >/dev/null 2>&1; then return 0; fi
	return 1
}

pass() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
skip() { SKIPPED=$((SKIPPED + 1)); printf '  SKIP  %s (%s)\n' "$1" "$2"; }
fail() {
	FAILED=$((FAILED + 1))
	printf '  FAIL  %s\n' "$1" >&2
	shift
	for line in "$@"; do printf '        %s\n' "$line" >&2; done
}

[ -x "$SCRIPT" ] || { echo "not executable: $SCRIPT" >&2; exit 1; }

# Run the script, capturing status and output.  Sets RUN_OUT / RUN_STATUS.
run() {
	RUN_OUT=$("$SCRIPT" "$@" 2>&1)
	RUN_STATUS=$?
}

expect_status() {
	local want=$1 name=$2
	if [ "$RUN_STATUS" -eq "$want" ]; then
		pass "$name"
	else
		fail "$name" "expected exit $want, got $RUN_STATUS" "$(printf '%s\n' "$RUN_OUT" | head -5)"
	fi
}

expect_grep() {
	local pattern=$1 name=$2
	if printf '%s\n' "$RUN_OUT" | grep -qF -- "$pattern"; then
		pass "$name"
	else
		fail "$name" "missing in output: $pattern" "$(printf '%s\n' "$RUN_OUT" | head -8)"
	fi
}

# Archive contents are read once into a listing file: a `tar | grep -q` pipeline
# would report false negatives under pipefail, because grep exits on its first
# match and tar then dies on SIGPIPE.
list_archive() { # list_archive <archive> <listing file>
	tar -tf "$1" > "$2" 2>/dev/null || true
	echo "$2"
}

in_archive() { # in_archive <listing file> <member>
	grep -qx "./$2" "$1"
}

not_in_archive() { # not_in_archive <listing file> <member>
	! grep -qx "./$2" "$1"
}

# ---------------------------------------------------------------------------
# Fixtures: an LFS-shaped root with caches, build trees and pseudo-filesystems
# ---------------------------------------------------------------------------

make_root() { # make_root <dir> <scratchpkg|pacman>
	local dir=$1 mgr=$2
	# Every directory a fixture file is written into has to exist, otherwise the
	# redirect fails silently here and the matching assertion passes trivially.
	mkdir -p "$dir"/{etc,bin,tmp,proc,sys,dev,run,sources,tools/lib,root,home/u,usr/bin,usr/lib/locale,var/log}
	mkdir -p "$dir"/boot/grub
	printf '12.2\n' > "$dir/etc/lfs-release"
	printf 'root:x:0:0:root:/root:/bin/bash\n' > "$dir/etc/passwd"
	printf '#!/bin/sh\n' > "$dir/bin/sh"
	printf 'keep me\n' > "$dir/etc/keep.conf"
	printf 'secret\n' > "$dir/root/.bashrc"
	printf 'user data\n' > "$dir/home/u/file"
	printf 'tmp junk\n' > "$dir/tmp/junk"
	printf 'lfs sources\n' > "$dir/sources/tarball.tar.xz"
	printf 'tools\n' > "$dir/tools/lib/libc.so"
	printf 'kernel\n' > "$dir/boot/vmlinuz"
	# A tool that only exists on the target system: this is what makes the
	# post-install step assertions meaningful in --dry-run.
	printf '#!/bin/sh\nexit 0\n' > "$dir/usr/bin/localedef"
	chmod +x "$dir/usr/bin/localedef"
	printf '#!/bin/sh\nexit 0\n' > "$dir/usr/bin/pacman"
	chmod +x "$dir/usr/bin/pacman"
	case $mgr in
		scratchpkg)
			mkdir -p "$dir/var/lib/scratchpkg/db" "$dir/var/cache/scratchpkg/packages" \
				"$dir/var/cache/scratchpkg/sources" "$dir/var/cache/scratchpkg/work" \
				"$dir/var/lib/scratchpkg/cbuild" "$dir/usr/ports/core/bzip2"
			printf '1.0 1\n/usr/bin/bzip2\n' > "$dir/var/lib/scratchpkg/db/bzip2"
			printf 'bzip2\n' > "$dir/var/lib/scratchpkg/world"
			printf 'cached pkg\n' > "$dir/var/cache/scratchpkg/packages/bzip2-1.0-1.spkg.tar.zst"
			printf 'work\n' > "$dir/var/cache/scratchpkg/work/tmpfile"
			printf 'cbuild\n' > "$dir/var/lib/scratchpkg/cbuild/bzip2"
			printf 'recipe\n' > "$dir/usr/ports/core/bzip2/.spkgbuild"
			printf 'new config\n' > "$dir/etc/keep.conf.spkgnew"
			;;
		pacman)
			mkdir -p "$dir/var/lib/pacman/local/bzip2-1.0-1" "$dir/var/lib/pacman/sync" \
				"$dir/var/cache/pacman/pkg"
			printf '%%NAME%%\nbzip2\n\n%%VERSION%%\n1.0-1\n\n%%REASON%%\n0\n' \
				> "$dir/var/lib/pacman/local/bzip2-1.0-1/desc"
			printf 'cached pkg\n' > "$dir/var/cache/pacman/pkg/bzip2-1.0-1-x86_64.pkg.tar.zst"
			printf 'sync db\n' > "$dir/var/lib/pacman/sync/core.db"
			printf 'new config\n' > "$dir/etc/keep.conf.pacnew"
			printf 'log\n' > "$dir/var/log/pacman.log"
			;;
	esac
}

# Real pacman archives carry their identity in .PKGINFO, so the fixtures are
# real tar archives with that metadata - a plain file would only exercise the
# file-name fallback.
make_pacman_pkg() { # make_pacman_pkg <dir> <name>-<version>-<release>-<arch>
	local dir=$1 base=$2 arch name version release stage
	mkdir -p "$dir"
	arch=${base##*-}
	base=${base%-*}
	release=${base##*-}
	base=${base%-*}
	version=${base##*-}
	name=${base%-*}

	stage=$(mktemp -d)
	mkdir -p "$stage/usr/bin"
	printf '#!/bin/sh\nexit 0\n' > "$stage/usr/bin/$name"
	{
		printf 'pkgname = %s\n' "$name"
		printf 'pkgver = %s-%s\n' "$version" "$release"
		printf 'arch = %s\n' "$arch"
		printf 'size = 1\n'
	} > "$stage/.PKGINFO"
	(cd "$stage" && tar -c --owner=0 --group=0 -f - .PKGINFO usr) | xz -T0 > "$dir/$name-$version-$release-$arch.pkg.tar.xz"
	rm -rf "$stage"
}

make_pkg_dir() { # make_pkg_dir <dir> <scratchpkg|pacman> <name>-<version>-<release>...
	local dir=$1 mgr=$2
	shift 2
	local name
	mkdir -p "$dir"
	for name in "$@"; do
		case $mgr in
			scratchpkg)
				printf 'package payload\n' > "$dir/$name.spkg.tar.xz"
				;;
			pacman)
				make_pacman_pkg "$dir" "$name"
				;;
		esac
	done
}

echo "test-lfs-mkstage3.sh: $SCRIPT"

# ---------------------------------------------------------------------------
# 1. Dry runs print the command and the excludes, and change nothing
# ---------------------------------------------------------------------------

SP_ROOT="$WORK/sp-root"
make_root "$SP_ROOT" scratchpkg
run --pkgmgr scratchpkg --rootfs "$SP_ROOT" --compress --dry-run
expect_status 0 "pack dry-run (scratchpkg) exits 0"
expect_grep "tar " "pack dry-run prints the tar command"
expect_grep "--exclude=./var/cache/scratchpkg/work/*" "pack dry-run lists the scratchpkg work cache"
expect_grep "--exclude=./etc/*.spkgnew" "pack dry-run lists scratchpkg .spkgnew backups"
expect_grep "--exclude=./usr/ports/*" "pack dry-run lists the ports tree"
expect_grep "--exclude=./sources" "pack dry-run lists the LFS sources tree"
expect_grep "xz -T0 -6" "xz is the default compressor with all threads"
if [ -z "$(ls "$WORK"/*.tar.* 2>/dev/null)" ]; then
	pass "pack dry-run writes no archive"
else
	fail "pack dry-run writes no archive" "found: $(ls "$WORK"/*.tar.* 2>/dev/null)"
fi

SP_ROOT_PAC="$WORK/sp-root-pac"
make_root "$SP_ROOT_PAC" pacman
run --pkgmgr pacman --rootfs "$SP_ROOT_PAC" --compress --dry-run
expect_status 0 "pack dry-run (pacman) exits 0"
expect_grep "--exclude=./var/cache/pacman/pkg/*" "pack dry-run lists the pacman package cache"
expect_grep "--exclude=./etc/*.pacnew" "pack dry-run lists .pacnew backups"
expect_grep "--exclude=./var/log/pacman.log" "pack dry-run lists pacman.log"

# ---------------------------------------------------------------------------
# 2. Autodetection from the rootfs database
# ---------------------------------------------------------------------------

run --rootfs "$SP_ROOT" --compress --dry-run
expect_status 0 "autodetects scratchpkg from var/lib/scratchpkg/db"
expect_grep "Package manager: scratchpkg (detected)" "autodetect reports scratchpkg"

run --rootfs "$SP_ROOT_PAC" --compress --dry-run
expect_status 0 "autodetects pacman from var/lib/pacman"
expect_grep "Package manager: pacman (detected)" "autodetect reports pacman"

mkdir -p "$WORK/both-root"/{var/lib/scratchpkg/db,var/lib/pacman}
run --rootfs "$WORK/both-root" --compress --dry-run
expect_status 1 "refuses a root with both databases"
expect_grep "both a scratchpkg and a pacman database" "says why the detection is ambiguous"

# ---------------------------------------------------------------------------
# 3. Real packing: contents, excludes, verification, checksum, naming
# ---------------------------------------------------------------------------

cd "$WORK" || exit 1
run --pkgmgr scratchpkg --rootfs "$SP_ROOT" --compress -C gzip
expect_status 0 "packs a scratchpkg root with gzip"
ARCHIVE="$WORK/lfs-stage3-12.2-$(date +%Y%m%d)-$(uname -m).tar.gz"
if [ -f "$ARCHIVE" ]; then
	pass "output name carries the lfs-release version and the host architecture"
else
	fail "output name carries the lfs-release version and the host architecture" "expected $ARCHIVE" "$(ls "$WORK")"
fi

if [ -f "$ARCHIVE" ]; then
	SP_LISTING=$(list_archive "$ARCHIVE" "$WORK/sp-listing.txt")
	# The archive is written by the script outside the root; the root holds the
	# package database and the machine's own state must not be captured.
	if [ -f "$WORK/$(basename "$ARCHIVE").sha256" ]; then
		pass "writes a sha256 checksum file"
	else
		fail "writes a sha256 checksum file" "work directory: $(find "$WORK" -maxdepth 1 -name 'lfs-stage3*' -printf '%f ' 2>/dev/null)"
	fi

	for member in etc/lfs-release etc/keep.conf var/lib/scratchpkg/db/bzip2 boot/vmlinuz; do
		if in_archive "$SP_LISTING" "$member"; then
			pass "archive keeps $member"
		else
			fail "archive keeps $member" "archive: $(basename "$ARCHIVE")" "listing: $(tr '\n' ' ' < "$SP_LISTING")"
		fi
	done

	for member in \
		var/cache/scratchpkg/packages/bzip2-1.0-1.spkg.tar.zst \
		var/cache/scratchpkg/sources \
		var/cache/scratchpkg/work/tmpfile \
		var/lib/scratchpkg/cbuild/bzip2 \
		usr/ports/core/bzip2/.spkgbuild \
		etc/keep.conf.spkgnew \
		sources/tarball.tar.xz tools/lib/libc.so home/u/file root/.bashrc tmp/junk; do
		if not_in_archive "$SP_LISTING" "$member"; then
			pass "archive drops $member"
		else
			fail "archive drops $member" "still present in $(basename "$ARCHIVE")"
		fi
	done

	if command -v sha256sum >/dev/null 2>&1; then
		if (cd "$WORK" && sha256sum -c "$(basename "$ARCHIVE").sha256" >/dev/null 2>&1); then
			pass "checksum verifies against the archive"
		else
			fail "checksum verifies against the archive"
		fi
	fi
fi

# --no-default-excludes keeps the LFS build trees and per-machine state
run --pkgmgr scratchpkg --rootfs "$SP_ROOT" --compress -C gzip -o "$WORK/keep-all.tar.gz" --no-default-excludes --no-checksum
expect_status 0 "packs with --no-default-excludes"
if [ -f "$WORK/keep-all.tar.gz" ]; then
	KEEP_LISTING=$(list_archive "$WORK/keep-all.tar.gz" "$WORK/keep-all-listing.txt")
	for member in sources/tarball.tar.xz tools/lib/libc.so home/u/file root/.bashrc; do
		if in_archive "$KEEP_LISTING" "$member"; then
			pass "--no-default-excludes keeps $member"
		else
			fail "--no-default-excludes keeps $member" "listing: $(tr '\n' ' ' < "$KEEP_LISTING")"
		fi
	done
	if not_in_archive "$KEEP_LISTING" tmp/junk; then pass "--no-default-excludes still drops tmp"; else fail "--no-default-excludes still drops tmp"; fi
fi

# pacman root: caches out, database in
run --pkgmgr pacman --rootfs "$SP_ROOT_PAC" --compress -C gzip -o "$WORK/pac.tar.gz"
expect_status 0 "packs a pacman root"
if [ -f "$WORK/pac.tar.gz" ]; then
	PAC_LISTING=$(list_archive "$WORK/pac.tar.gz" "$WORK/pac-listing.txt")
	if in_archive "$PAC_LISTING" var/lib/pacman/local/bzip2-1.0-1/desc; then
		pass "pacman archive keeps the local database"
	else
		fail "pacman archive keeps the local database" "listing: $(tr '\n' ' ' < "$PAC_LISTING")"
	fi
	for member in var/cache/pacman/pkg/bzip2-1.0-1-x86_64.pkg.tar.zst var/lib/pacman/sync/core.db etc/keep.conf.pacnew var/log/pacman.log; do
		if not_in_archive "$PAC_LISTING" "$member"; then pass "pacman archive drops $member"; else fail "pacman archive drops $member"; fi
	done
fi

# The default compressor (xz) end to end, including verification and checksum
run --pkgmgr scratchpkg --rootfs "$SP_ROOT_PAC" --compress -o "$WORK/default.tar.xz"
expect_status 0 "packs with the default compressor (xz)"
if [ -f "$WORK/default.tar.xz" ]; then
	XZ_LISTING=$(list_archive "$WORK/default.tar.xz" "$WORK/xz-listing.txt")
	if in_archive "$XZ_LISTING" etc/passwd; then
		pass "the xz archive is readable and holds the root's files"
	else
		fail "the xz archive is readable and holds the root's files" "listing: $(tr '\n' ' ' < "$XZ_LISTING")"
	fi
	if [ -f "$WORK/default.tar.xz.sha256" ]; then
		pass "the default checksum file is <archive>.sha256"
	else
		fail "the default checksum file is <archive>.sha256" "work directory: $(find "$WORK" -maxdepth 1 -name 'default*' -printf '%f ' 2>/dev/null)"
	fi
else
	fail "packs with the default compressor (xz)" "work directory: $(find "$WORK" -maxdepth 1 -printf '%f ' 2>/dev/null)"
fi

# zstd must fail cleanly when the tool is missing rather than writing nothing
if ! command -v zstd >/dev/null 2>&1; then
	run --pkgmgr scratchpkg --rootfs "$SP_ROOT" --compress -C zstd
	expect_status 1 "missing zstd is a clean error"
	expect_grep "zstd not found" "missing zstd names the tool"
fi

# The same for a missing checksum tool
if ! command -v b3sum >/dev/null 2>&1; then
	run --pkgmgr scratchpkg --rootfs "$SP_ROOT" --compress -C gzip -o "$WORK/b3.tar.gz" --checksum b3sum
	expect_status 1 "missing b3sum is a clean error"
	expect_grep "b3sum not found" "missing b3sum names the tool"
fi

# ---------------------------------------------------------------------------
# 4. Refusals
# ---------------------------------------------------------------------------

run --pkgmgr scratchpkg --rootfs "$SP_ROOT" --compress -o "$SP_ROOT/inside.tar.gz"
expect_status 1 "refuses an output path inside the root"
expect_grep "inside the root being archived" "says why the output path is refused"

mkdir -p "$WORK/empty-root"
run --pkgmgr scratchpkg --rootfs "$WORK/empty-root" --compress
expect_status 1 "refuses to pack an empty root"

run --pkgmgr scratchpkg --rootfs "$SP_ROOT" --compress -C nope
expect_status 1 "refuses an unknown compressor"
expect_grep "unknown compressor" "names the bad compressor"

run --pkgmgr nosuchmgr --rootfs "$SP_ROOT" --compress
expect_status 1 "refuses an unknown package manager"

run --bogus-argument
expect_status 1 "refuses an unknown argument"

run --pkgmgr scratchpkg --rootfs "$SP_ROOT" --compress -l abc
expect_status 1 "refuses a non-numeric compression level"

# --clean refuses a tree that looks bootable unless --force is given
run --pkgmgr scratchpkg --rootfs "$SP_ROOT" --clean
expect_status 1 "--clean refuses a bootable-looking root without --force"
expect_grep "looks like a bootable system" "says why --clean refused"
if [ -d "$SP_ROOT/etc" ]; then pass "--clean left the refused root alone"; else fail "--clean left the refused root alone"; fi

if have_priv; then
	mkdir -p "$WORK/scratch-root/usr"
	run --pkgmgr scratchpkg --rootfs "$WORK/scratch-root" --clean
	expect_status 0 "--clean removes a plain directory"
	if [ ! -d "$WORK/scratch-root" ]; then pass "--clean really removed it"; else fail "--clean really removed it"; fi
else
	skip "--clean removes a plain directory" "no root and no sudo/doas/su on this host"
fi

# ---------------------------------------------------------------------------
# 5. Assembly (dry-run: the real install needs root and a Linux host)
# ---------------------------------------------------------------------------

# Without privileges the assemble path must stop loudly instead of half-doing
# the work: the first privileged step is the rootfs preparation.
if ! have_priv; then
	mkdir -p "$WORK/nopriv"
	run --pkgmgr scratchpkg --rootfs "$WORK/nopriv" --pkg-dir "$WORK/does-not-exist" \
		--packages "$WORK/sp-packages.txt"
	expect_status 1 "assemble without privileges fails instead of pretending"
	if [ -z "$(ls -A "$WORK/nopriv" 2>/dev/null)" ]; then
		pass "the failed assemble left the target untouched"
	else
		fail "the failed assemble left the target untouched" "$(ls -A "$WORK/nopriv")"
	fi
fi

PKG_DIR_SP="$WORK/pkgs-sp"
make_pkg_dir "$PKG_DIR_SP" scratchpkg bzip2-1.0.8-1 zlib-1.3-1
printf 'zlib\nbzip2\n' > "$WORK/sp-packages.txt"
printf 'bzip2\n' > "$WORK/sp-world.txt"
mkdir -p "$WORK/sp-target/usr/bin"
printf '#!/bin/sh\nexit 0\n' > "$WORK/sp-target/usr/bin/localedef"
chmod +x "$WORK/sp-target/usr/bin/localedef"

# --force because this root is prepared (it already has localedef);
# --chroot-cmd keeps the expected command lines the same whether or not the
# host has scratchpkg's xchroot installed.
run --pkgmgr scratchpkg --rootfs "$WORK/sp-target" --pkg-dir "$PKG_DIR_SP" \
	--packages "$WORK/sp-packages.txt" --world "$WORK/sp-world.txt" --dry-run --force --chroot-cmd chroot
expect_status 0 "assemble dry-run (scratchpkg) exits 0"
expect_grep "mkdir -p" "assemble creates the scratchpkg database directories"
expect_grep "$WORK/sp-target/var/lib/scratchpkg/db" "assemble names the scratchpkg db directory"
expect_grep "pkgadd --root=$WORK/sp-target --no-backup" "assemble calls pkgadd with --root"
expect_grep "$PKG_DIR_SP/zlib-1.3-1.spkg.tar.xz" "assemble passes the package file to pkgadd"
expect_grep "merge $WORK/sp-target/var/lib/scratchpkg/world" "assemble merges the world file"
expect_grep "chroot $WORK/sp-target localedef -i en_US -f UTF-8 en_US.UTF-8" "assemble runs localedef for en_US.UTF-8 inside the root"
expect_grep "chroot $WORK/sp-target localedef -i C -f UTF-8 C.UTF-8" "assemble runs localedef for C.UTF-8 inside the root"
expect_grep "chroot $WORK/sp-target localedef -i en_US -f ISO-8859-1 en_US" "assemble runs localedef for en_US"

run --pkgmgr scratchpkg --rootfs "$WORK/sp-target" --pkg-dir "$PKG_DIR_SP" \
	--packages "$WORK/sp-packages.txt" --dry-run --force --chroot-cmd chroot --no-hooks
expect_status 0 "assemble dry-run with --no-hooks exits 0"
expect_grep "Skipping post-install steps" "--no-hooks skips the post-install steps"

# A dry run writes nothing, even into an empty target
mkdir -p "$WORK/sp-empty"
run --pkgmgr scratchpkg --rootfs "$WORK/sp-empty" --pkg-dir "$PKG_DIR_SP" \
	--packages "$WORK/sp-packages.txt" --dry-run --chroot-cmd chroot
if [ -z "$(ls -A "$WORK/sp-empty")" ]; then pass "assemble dry-run changed nothing"; else fail "assemble dry-run changed nothing" "$(ls -A "$WORK/sp-empty")"; fi

PKG_DIR_PAC="$WORK/pkgs-pac"
make_pkg_dir "$PKG_DIR_PAC" pacman bzip2-1.0.8-1-x86_64 zlib-1.3-1-x86_64
printf 'zlib\nbzip2\n' > "$WORK/pac-packages.txt"
mkdir -p "$WORK/pac-target/etc" "$WORK/pac-target/usr/bin"
printf '[options]\n' > "$WORK/pac-target/etc/pacman.conf"
printf '#!/bin/sh\nexit 0\n' > "$WORK/pac-target/usr/bin/pacman"
chmod +x "$WORK/pac-target/usr/bin/pacman"

# This root already has its pacman.conf and pacman installed, which is the
# normal starting point when you convert an LFS install to pacman.
run --pkgmgr pacman --rootfs "$WORK/pac-target" --pkg-dir "$PKG_DIR_PAC" \
	--packages "$WORK/pac-packages.txt" --dry-run --force --chroot-cmd chroot
expect_status 0 "assemble dry-run (pacman) exits 0"
expect_grep "pacman --root $WORK/pac-target --dbpath $WORK/pac-target/var/lib/pacman" "assemble points pacman at the target root and database"
expect_grep "--cachedir $PKG_DIR_PAC" "assemble uses the package directory as pacman's cache"
expect_grep "--config $WORK/pac-target/etc/pacman.conf" "assemble uses the target's pacman.conf when present"
expect_grep "$PKG_DIR_PAC/zlib-1.3-1-x86_64.pkg.tar.xz" "assemble passes the pacman package to -U"
expect_grep "$PKG_DIR_PAC/bzip2-1.0.8-1-x86_64.pkg.tar.xz" "assemble passes every listed package"
expect_grep "==> Marking 2 packages as explicitly installed" "assemble marks both packages, parsed from .PKGINFO"
expect_grep "-D --asexplicit zlib bzip2" "assemble marks the packages explicit in list order"

expect_grep "chroot $WORK/pac-target pacman -Dk" "assemble runs the pacman dependency check inside the root"

run --pkgmgr pacman --rootfs "$WORK/pac-target" --pkg-dir "$PKG_DIR_PAC" \
	--packages "$WORK/pac-packages.txt" --dry-run --force --chroot-cmd chroot --no-scriptlet --one-by-one
expect_status 0 "assemble dry-run with --no-scriptlet --one-by-one exits 0"
expect_grep "--noscriptlet" "--no-scriptlet reaches the pacman command"

run --pkgmgr scratchpkg --rootfs "$WORK/sp-target" --pkg-dir "$PKG_DIR_SP" \
	--packages "$WORK/sp-packages.txt" --dry-run --force --ignore-conflict --reinstall
expect_status 0 "assemble dry-run with --ignore-conflict --reinstall exits 0"
expect_grep "pkgadd --root=$WORK/sp-target --no-backup -c -r" "--ignore-conflict and --reinstall reach pkgadd"

# A pacman archive's identity comes from .PKGINFO, not from its file name: a
# name that disagrees with the file name must be reported, so the metadata wins.
PKG_DIR_META="$WORK/pkgs-meta"
mkdir -p "$PKG_DIR_META/stage"
printf 'pkgname = realname\npkgver = 1.0-1
arch = x86_64
' > "$PKG_DIR_META/stage/.PKGINFO"
(cd "$PKG_DIR_META/stage" && tar -c -f - .PKGINFO) | xz -T0 > "$PKG_DIR_META/misleading-1.0-1-x86_64.pkg.tar.xz"
rm -rf "$PKG_DIR_META/stage"
printf 'realname\n' > "$WORK/meta-list.txt"
run --pkgmgr pacman --rootfs "$WORK/sp-target" --pkg-dir "$PKG_DIR_META" \
	--packages "$WORK/meta-list.txt" --dry-run --force --pacman-config /etc/pacman.conf
if [ "$RUN_STATUS" -eq 0 ]; then
	pass "pacman package identity is taken from .PKGINFO"
else
	fail "pacman package identity is taken from .PKGINFO" "$(printf '%s\n' "$RUN_OUT" | head -3)"
fi

printf 'misleading\n' > "$WORK/meta-wrong-list.txt"
run --pkgmgr pacman --rootfs "$WORK/sp-target" --pkg-dir "$PKG_DIR_META" \
	--packages "$WORK/meta-wrong-list.txt" --dry-run --force --pacman-config /etc/pacman.conf
expect_status 1 "a list naming the file name instead of pkgname is rejected"

# ---------------------------------------------------------------------------
# 6. Package list handling and validation
# ---------------------------------------------------------------------------

# A word after the name (scratch installed / pacman -Qqi style) must be ignored,
# a missing package must be fatal, and duplicates must be reported.
# Each of these uses the prepared sp-target, hence --force.
printf 'zlib 1.3-1\nbzip2 1.0.8-1\n# comment\n\n' > "$WORK/verbose-list.txt"
run --pkgmgr scratchpkg --rootfs "$WORK/sp-target" --pkg-dir "$PKG_DIR_SP" \
	--packages "$WORK/verbose-list.txt" --dry-run --force
expect_status 0 "accepts 'name version' lines from scratch installed output"

printf 'zlib\nbzip2\nnosuchpkg\n' > "$WORK/missing-list.txt"
run --pkgmgr scratchpkg --rootfs "$WORK/sp-target" --pkg-dir "$PKG_DIR_SP" \
	--packages "$WORK/missing-list.txt" --dry-run --force
expect_status 1 "a listed package with no file is fatal"
expect_grep "missing package: nosuchpkg" "names the missing package"

PKG_DIR_DUP="$WORK/pkgs-dup"
make_pkg_dir "$PKG_DIR_DUP" scratchpkg bzip2-1.0.8-1 bzip2-1.0.9-1
printf 'bzip2\n' > "$WORK/dup-list.txt"
run --pkgmgr scratchpkg --rootfs "$WORK/sp-target" --pkg-dir "$PKG_DIR_DUP" \
	--packages "$WORK/dup-list.txt" --dry-run --force
expect_status 1 "two versions of one package are fatal"
expect_grep "multiple versions of 'bzip2'" "names the duplicated package"

run --pkgmgr scratchpkg --rootfs "$WORK/sp-target" --pkg-dir "$PKG_DIR_SP" \
	--packages "$WORK/dup-list.txt" --dry-run --force
expect_status 1 "a package in the cache but not in the list is fatal"
expect_grep "unexpected package in" "names the unexpected package"

: > "$WORK/empty-list.txt"
run --pkgmgr scratchpkg --rootfs "$WORK/sp-target" --pkg-dir "$PKG_DIR_SP" \
	--packages "$WORK/empty-list.txt" --dry-run --force
expect_status 1 "an empty package list is fatal"

# An existing populated root needs --force to assemble into
run --pkgmgr scratchpkg --rootfs "$SP_ROOT" --pkg-dir "$PKG_DIR_SP" \
	--packages "$WORK/sp-packages.txt" --dry-run
expect_status 1 "refuses to assemble into a populated root without --force"

run --pkgmgr scratchpkg --rootfs "$SP_ROOT" --pkg-dir "$PKG_DIR_SP" \
	--packages "$WORK/sp-packages.txt" --dry-run --force
expect_status 0 "--force allows assembling into a populated root"

# ---------------------------------------------------------------------------
# 7. Config file
# ---------------------------------------------------------------------------

cat > "$WORK/lfs-mkstage3.conf" <<EOF
PKGMGR="pacman"
ROOTFS="$SP_ROOT_PAC"
COMPRESSOR="gzip"
CHECKSUM="none"
OUTPUT="$WORK/from-config.tar.gz"
EOF
run --config "$WORK/lfs-mkstage3.conf" --compress
expect_status 0 "a config file supplies defaults"
expect_grep "Loaded config: $WORK/lfs-mkstage3.conf" "reports the config file it loaded"
if [ -f "$WORK/from-config.tar.gz" ]; then pass "the config file's OUTPUT is honoured"; else fail "the config file's OUTPUT is honoured"; fi

# The command line still wins over the config file
run --config "$WORK/lfs-mkstage3.conf" --compress -C gzip -o "$WORK/override.tar.gz"
expect_status 0 "the command line overrides the config file"
if [ -f "$WORK/override.tar.gz" ]; then pass "the overridden OUTPUT is used"; else fail "the overridden OUTPUT is used"; fi

# ---------------------------------------------------------------------------

echo
printf 'lfs-mkstage3: %s passed, %s failed, %s skipped\n' "$PASS" "$FAILED" "$SKIPPED"
[ "$FAILED" -eq 0 ] || exit 1
