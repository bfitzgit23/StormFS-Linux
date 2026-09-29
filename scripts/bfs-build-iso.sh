#!/usr/bin/env bash
set -Eeuo pipefail

# BFSOS ISO builder - reusable verified-base workflow and local-package/repository implementation.
# Includes USB live-media discovery retry, live console accessibility, and
# current 0.9.0 live-session policy. Boot/install acceptance still requires
# fresh VM + USB-emulation + bare-metal validation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_PROJECT_DIR="$PROJECT_DIR"
ARCH="x86_64"
BUILD_DATE="$(date +%Y%m%d)"
WORK_DIR="${BFS_ISO_WORK_DIR:-/var/tmp/bfsos-iso-${USER:-builder}}"
OUTPUT_DIR="${BFS_ISO_OUTPUT_DIR:-$HOME/BFSOS-ISO}"
BASE_CACHE_DIR="${BFS_ISO_BASE_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/bfsos/iso}"
VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION" 2>/dev/null || printf '0.9.0')"
BASE_FILENAME="${BFS_ISO_BASE_FILENAME:-BFSOS-base-${VERSION}-${ARCH}.tar.zst}"
BASE_URL="${BFS_ISO_BASE_URL:-https://downloads.sourceforge.net/project/bfsos/BFSOS/base/latest/${BASE_FILENAME}}"
BASE_SHA256_URL="${BFS_ISO_BASE_SHA256_URL:-https://downloads.sourceforge.net/project/bfsos/BFSOS/base/latest/${BASE_FILENAME}.sha256}"
BASE_MODE="${BFS_ISO_BASE_MODE:-auto}"
REFRESH_BASE="${BFS_ISO_REFRESH_BASE:-no}"
LOCAL_BASE_PATH="${BFS_ISO_LOCAL_BASE:-}"
BASE_SOURCE="unknown"
GIT_URL="${BFS_ISO_GIT_URL:-https://github.com/bmadonnaster/BFSOS.git}"
GIT_REF="${BFS_ISO_GIT_REF:-main}"
GIT_COMMIT="unknown"
GIT_COMMIT_FULL="unknown"
ISO_LABEL=""
ISO_NAME=""
ISO_PATH=""
ASSUME_YES="${BFS_ISO_ASSUME_YES:-no}"
SKIP_BOOTSTRAP="${BFS_ISO_SKIP_BOOTSTRAP:-no}"
LIVE_MEDIA_WAIT="${BFS_ISO_LIVE_MEDIA_WAIT:-15}"

required_tools=(bash git sudo tar xz zstd rsync wget sha256sum find awk sed grep mount umount chroot mksquashfs xorriso grub-mkrescue mformat)
optional_tools=(qemu-system-x86_64)

declare -A tool_packages=(
    [git]=git [zstd]=zstd [rsync]=rsync [wget]=wget [mksquashfs]=squashfs-tools
    [xorriso]=libisoburn [grub-mkrescue]=grub [mformat]=mtools [qemu-system-x86_64]=qemu
)

# Everything the current installer can select or require dynamically, plus
# the live-media services/tools. Dependencies are resolved by prt-get.
iso_packages=(
    linux-firmware dracut
    networkmanager-iso openssh git sudo wget wpa_supplicant wireless-regdb gpm lynx-iso chrony kbd
    cryptsetup lvm2 mdadm snapper pciutils parted
    dialog squashfs-tools grub grub-efi dosfstools mtools efibootmgr libisoburn syslinux
)

log() { printf '[BFSOS ISO] %s\n' "$*"; }
die() { printf '[BFSOS ISO] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [--refresh-base] [--sourceforge-base] [--local-base PATH] [--git-ref REF]

  (default)         Prefer a verified maintainer-generated base under archives/base.
                    If none exists, offer rebuild/download/cancel instead of silently downloading.
  --local-base PATH Use exactly the supplied verified local base archive.
  --sourceforge-base
                    Explicitly use the SourceForge release base/cache path.
  --refresh-base    Force a fresh SourceForge base download (implies --sourceforge-base).
  --git-ref REF     Build from this GitHub branch, tag, or commit (default: main).
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            --refresh-base) REFRESH_BASE=yes; BASE_MODE=sourceforge ;;
            --sourceforge-base) BASE_MODE=sourceforge ;;
            --local-base)
                shift
                (($#)) || die "--local-base requires a path"
                LOCAL_BASE_PATH="$1"
                BASE_MODE=local-path
                ;;
            --local-base=*)
                LOCAL_BASE_PATH="${1#*=}"
                BASE_MODE=local-path
                ;;
            --git-ref)
                shift
                (($#)) || die "--git-ref requires a value"
                GIT_REF="$1"
                ;;
            --git-ref=*) GIT_REF="${1#*=}" ;;
            -h|--help) usage; exit 0 ;;
            *) die "Unknown ISO builder argument: $1" ;;
        esac
        shift
    done
}

load_project_metadata() {
    local project="$1" label_version=""
    VERSION="$(tr -d '[:space:]' < "$project/VERSION" 2>/dev/null || printf '0.9.0')"
    GIT_COMMIT_FULL="$(git -C "$project" rev-parse HEAD 2>/dev/null || printf 'unknown')"
    GIT_COMMIT="${GIT_COMMIT_FULL:0:12}"
    label_version="${VERSION//[.-]/_}"
    ISO_LABEL="BFSOS_${label_version}_${ARCH}"
    ISO_NAME="BFSOS-${VERSION}-${ARCH}-${BUILD_DATE}-${GIT_COMMIT}.iso"
    ISO_PATH="$OUTPUT_DIR/$ISO_NAME"
}

verify_sha256_file() {
    local archive="$1" sumfile="$2" expected="" actual=""
    [ -s "$archive" ] && [ -s "$sumfile" ] || return 1
    expected="$(awk 'NF {print $1; exit}' "$sumfile")"
    case "$expected" in
        [0-9A-Fa-f][0-9A-Fa-f]*) ;;
        *) return 1 ;;
    esac
    [ "${#expected}" -eq 64 ] || return 1
    actual="$(sha256sum "$archive" | awk '{print $1}')"
    [ "${actual,,}" = "${expected,,}" ]
}

fetch_sourceforge_base() {
    local -n result_ref="$1"
    local archive="$BASE_CACHE_DIR/$BASE_FILENAME"
    local sumfile="$archive.sha256"
    local tmp_sum="$sumfile.tmp" tmp_archive="$archive.tmp"
    result_ref=""
    BASE_SOURCE="sourceforge:$BASE_URL"
    mkdir -p "$BASE_CACHE_DIR"

    log "Checking SourceForge for current BFSOS base: $BASE_URL"
    rm -f "$tmp_sum" "$tmp_archive"
    if ! wget --max-redirect=20 -O "$tmp_sum" "$BASE_SHA256_URL" >&2; then
        if validate_base_archive "$archive" && verify_sha256_file "$archive" "$sumfile"; then
            log "SourceForge checksum check unavailable; reusing verified cached base: $archive"
            result_ref="$archive"
            return 0
        fi
        die "Could not download SourceForge base checksum and no verified cached base is available"
    fi
    grep -Eq '^[[:space:]]*[0-9A-Fa-f]{64}([[:space:]]|$)' "$tmp_sum" || \
        die "SourceForge checksum download did not contain a SHA256 digest"

    if [ "$REFRESH_BASE" != yes ] && verify_sha256_file "$archive" "$tmp_sum" && validate_base_archive "$archive"; then
        mv -f "$tmp_sum" "$sumfile"
        log "Cached SourceForge base is current and verified: $archive"
        result_ref="$archive"
        return 0
    fi

    log "Downloading current BFSOS base archive from SourceForge"
    log "Progress from wget follows; this can take a while on slower mirrors."
    if ! wget --show-progress --max-redirect=20 -O "$tmp_archive" "$BASE_URL" >&2; then
        rm -f "$tmp_archive" "$tmp_sum"
        die "Failed to download BFSOS base archive from SourceForge"
    fi
    verify_sha256_file "$tmp_archive" "$tmp_sum" || {
        rm -f "$tmp_archive" "$tmp_sum"
        die "SourceForge BFSOS base SHA256 verification failed"
    }
    validate_base_archive "$tmp_archive" || {
        log "Downloaded file size: $(du -h "$tmp_archive" 2>/dev/null | awk '{print $1}')"
        log "Archive path retained for diagnosis: $tmp_archive"
        die "Downloaded SourceForge file passed transfer but failed BFSOS base-content validation"
    }
    mv -f "$tmp_archive" "$archive"
    mv -f "$tmp_sum" "$sumfile"
    result_ref="$archive"
}

prepare_build_project() {
    local dest="$WORK_DIR/source-tree"
    log "Fetching authoritative BFSOS Git tree: $GIT_URL ($GIT_REF)"
    rm -rf "$dest"
    git clone --no-tags "$GIT_URL" "$dest" >/dev/null 2>&1 || die "Failed to clone BFSOS Git repository"
    git -C "$dest" fetch --force --tags origin >/dev/null 2>&1 || die "Failed to fetch BFSOS Git refs"
    if git -C "$dest" show-ref --verify --quiet "refs/remotes/origin/$GIT_REF"; then
        # A normal branch build must leave the copy shipped in the live ISO on
        # a real tracking branch. bfs-live-init can then safely use
        # `git pull --ff-only` instead of failing on a detached HEAD.
        git -C "$dest" checkout -B "$GIT_REF" "origin/$GIT_REF" >/dev/null 2>&1 ||             die "Failed to checkout tracking branch origin/$GIT_REF"
        git -C "$dest" branch --set-upstream-to="origin/$GIT_REF" "$GIT_REF" >/dev/null 2>&1 ||             die "Failed to set upstream for $GIT_REF"
    elif git -C "$dest" rev-parse --verify "$GIT_REF^{commit}" >/dev/null 2>&1; then
        # Explicit tags/commit IDs are immutable build inputs and intentionally
        # remain detached for reproducibility.
        git -C "$dest" checkout --detach "$GIT_REF" >/dev/null 2>&1 || die "Failed to checkout $GIT_REF"
    else
        die "Requested BFSOS Git ref cannot be resolved: $GIT_REF"
    fi
    BUILD_PROJECT_DIR="$dest"
    load_project_metadata "$BUILD_PROJECT_DIR"
    log "BFSOS build source resolved to $GIT_COMMIT_FULL"

    bash -n "$BUILD_PROJECT_DIR/bootstrap.sh" || die "Fetched bootstrap.sh has shell syntax errors"
    bash -n "$BUILD_PROJECT_DIR/scripts/install-bfs-menu-current.sh" || die "Fetched installer has shell syntax errors"
    if [ -x "$BUILD_PROJECT_DIR/scripts/bfs-release-static-audit.sh" ]; then
        "$BUILD_PROJECT_DIR/scripts/bfs-release-static-audit.sh" || die "Fetched BFSOS release static audit failed"
    fi
}


sync_host_time() {
    log "Synchronizing host clock before BFSOS base/ISO build"

    # The ISO builder intentionally runs as a regular user, so time correction
    # must be requested through sudo. Prefer chrony when available because it
    # can step a badly skewed clock immediately; otherwise fall back to
    # timedatectl/systemd-timesyncd where available.
    if command -v chronyc >/dev/null 2>&1; then
        sudo systemctl start chronyd.service 2>/dev/null || \
            sudo systemctl start chrony.service 2>/dev/null || true

        if sudo chronyc -a makestep >/dev/null 2>&1; then
            sudo chronyc -a waitsync 10 0.5 >/dev/null 2>&1 || true
            log "Host clock synchronized with chrony"
            return 0
        fi
    fi

    if command -v timedatectl >/dev/null 2>&1; then
        sudo timedatectl set-ntp true >/dev/null 2>&1 || true
        sudo systemctl start systemd-timesyncd.service >/dev/null 2>&1 || true

        # Give the service a short opportunity to acquire time. Do not block a
        # release build forever if the configured NTP service is unavailable.
        local i synced=""
        for i in {1..20}; do
            synced="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)"
            [ "$synced" = yes ] && {
                log "Host clock synchronized with systemd time service"
                return 0
            }
            sleep 0.5
        done
    fi

    die "Unable to synchronize host clock. Check network/time service before building the BFSOS base/ISO."
}

preflight() {
    local t pkg
    local -a missing=() optional_missing=()
    log "Preflight: checking ISO build tools"
    for t in "${required_tools[@]}"; do
        if command -v "$t" >/dev/null 2>&1; then
            printf '  [OK]      %s\n' "$t"
        else
            missing+=("$t")
            pkg="${tool_packages[$t]:-unknown}"
            printf '  [MISSING] %-22s package: %s\n' "$t" "$pkg"
        fi
    done
    for t in "${optional_tools[@]}"; do
        if command -v "$t" >/dev/null 2>&1; then
            printf '  [OK/OPT]  %s\n' "$t"
        else
            optional_missing+=("$t")
            pkg="${tool_packages[$t]:-unknown}"
            printf '  [WARN]    %-22s optional package: %s\n' "$t" "$pkg"
        fi
    done
    if [ ! -d /usr/lib/grub/i386-pc ]; then
        missing+=("grub-platform:i386-pc")
        printf '  [MISSING] %-22s package: %s\n' "GRUB i386-pc modules" "grub"
    fi
    if [ ! -d /usr/lib/grub/x86_64-efi ]; then
        missing+=("grub-platform:x86_64-efi")
        printf '  [MISSING] %-22s package: %s\n' "GRUB x86_64-efi modules" "grub-efi"
    fi

    if ((${#missing[@]})); then
        printf '\nISO build cannot continue. Missing required tools/platforms:\n' >&2
        for t in "${missing[@]}"; do
            case "$t" in
                grub-platform:i386-pc) pkg=grub ;;
                grub-platform:x86_64-efi) pkg=grub-efi ;;
                *) pkg="${tool_packages[$t]:-unknown}" ;;
            esac
            printf '  %-28s BFSOS package: %s\n' "$t" "$pkg" >&2
        done
        exit 2
    fi
    if ((${#optional_missing[@]})); then
        printf '\nOptional VM boot-test tools are missing; ISO creation can still continue.\n'
    fi

    return 0
}

project_base_candidates() {
    local dir=""
    # Automatic/local reuse is release-scoped. A base from another BFSOS
    # release is never eligible merely because it is newer on disk.
    for dir in "$PROJECT_DIR/archives/base" "$PROJECT_DIR/archive/base"; do
        [ -d "$dir" ] || continue
        find "$dir" -maxdepth 1 -type f \
            \( -name "bfs-rootfs-${VERSION}-*.tar.zst" -o -name "bfs-rootfs-${VERSION}-*.tar.xz" -o -name "bfs-rootfs-${VERSION}-*.tar.gz" \
               -o -name "BFSOS-base-${VERSION}-${ARCH}.tar.zst" -o -name "BFSOS-base-${VERSION}-${ARCH}.tar.xz" -o -name "BFSOS-base-${VERSION}-${ARCH}.tar.gz" \) \
            -printf '%T@ %p\n' 2>/dev/null
    done | sort -nr
}

latest_base_archive() {
    project_base_candidates | head -n1 | cut -d' ' -f2-
}

archive_list() {
    local archive="$1"
    case "$archive" in
        *.tar.xz|*.tar.xz.tmp) tar -tJf "$archive" ;;
        *.tar.zst|*.tar.zst.tmp) tar --zstd -tf "$archive" ;;
        *.tar.gz|*.tar.gz.tmp) tar -tzf "$archive" ;;
        *) return 1 ;;
    esac
}

validate_base_archive() {
    local archive="$1" listing="" required="" alternate=""
    [ -n "$archive" ] && [ -s "$archive" ] || return 1

    listing="$(archive_list "$archive" 2>/dev/null)" || return 1
    # Match the canonical archive producer in bootstrap.sh.  Account shadow
    # files are deliberately not used as archive-validity sentinels because
    # older published bases may regenerate them during installation.
    for required in \
        ./usr/bin/bash \
        ./usr/bin/pkgmk \
        ./etc/os-release \
        ./etc/passwd \
        ./etc/group
    do
        # Do not pipe the full archive listing into `grep -q` while pipefail is
        # enabled.  Once grep finds a match it exits early; printf can then take
        # SIGPIPE, making a valid archive look invalid.  A here-string avoids
        # that false failure.  Accept tar listings with or without the leading
        # "./" as both are equivalent archive member spellings.
        alternate="${required#./}"
        if ! grep -Fxq -- "$required" <<<"$listing" && \
           ! grep -Fxq -- "$alternate" <<<"$listing"; then
            log "Base archive validation failed: missing $required in $archive" >&2
            return 1
        fi
    done
    return 0
}

latest_usable_base_archive() {
    local candidate=""
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        if validate_base_archive "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(project_base_candidates | cut -d' ' -f2-)
    return 1
}

choose_base_action() {
    local existing="" newest="" answer=""
    newest="$(latest_base_archive 2>/dev/null || true)"
    existing="$(latest_usable_base_archive 2>/dev/null || true)"

    if [ "$SKIP_BOOTSTRAP" = yes ]; then
        validate_base_archive "$existing" || \
            die "BFS_ISO_SKIP_BOOTSTRAP=yes was requested, but no usable verified base archive exists"
        log "BFS_ISO_SKIP_BOOTSTRAP=yes: using existing verified base archive: $existing" >&2
        printf '%s\n' use-existing
        return 0
    fi

    if validate_base_archive "$existing"; then
        if [ "$ASSUME_YES" = yes ]; then
            log "Using existing verified base archive: $existing" >&2
            printf '%s\n' use-existing
            return 0
        fi

        printf '\nA usable BFSOS base archive already exists:\n  %s\n' "$existing" >&2
        printf 'Use existing base, rebuild it, or cancel? [U/r/c]: ' >&2
        read -r answer
        case "$answer" in
            r|R|rebuild|REBUILD|Rebuild) printf '%s\n' rebuild ;;
            c|C|cancel|CANCEL|Cancel) printf '%s\n' cancel ;;
            *) printf '%s\n' use-existing ;;
        esac
        return 0
    fi

    if [ -n "$newest" ]; then
        log "No usable verified base archive was found; newest candidate failed validation: $newest" >&2
    else
        log "No existing base archive was found" >&2
    fi

    if [ "$ASSUME_YES" = yes ]; then
        printf '%s\n' rebuild
        return 0
    fi

    printf '\nNo usable verified BFSOS base archive is available.\n' >&2
    printf 'Choose: [R]ebuild local base, [S]ourceForge download, or [C]ancel: ' >&2
    read -r answer
    case "$answer" in
        r|R|rebuild|REBUILD|Rebuild) printf '%s\n' rebuild ;;
        s|S|sourceforge|SOURCEFORGE|SourceForge) printf '%s\n' sourceforge ;;
        *) printf '%s\n' cancel ;;
    esac
}

bootstrap_resume_stage_hint() {
    local root=/tmp/lfs-rootfs
    if [ -f "$root/.bfs-verification-passed" ]; then printf '%s\n' 5
    elif [ -f "$root/.bfs-stage3-complete" ]; then printf '%s\n' 4
    elif [ -f "$root/.bfs-stage2-complete" ]; then printf '%s\n' 3
    elif [ -f "$PROJECT_DIR/archives/toolchain/toolchain.tar.zst" ] || \
         [ -f "$PROJECT_DIR/toolchain.tar.zst" ]; then printf '%s\n' 2
    else printf '%s\n' 1
    fi
}

choose_bootstrap_recovery_action() {
    local stage answer
    stage="$(bootstrap_resume_stage_hint)"
    [ "$stage" -gt 1 ] || { printf '%s\n' restart; return 0; }

    if [ "$ASSUME_YES" = yes ]; then
        printf '%s\n' resume
        return 0
    fi

    printf '\nAn incomplete BFSOS bootstrap is present; Stage %s is the first incomplete stage.\n' "$stage" >&2
    printf 'Choose: [R]esume existing work, re[S]tart clean, or [C]ancel: ' >&2
    read -r answer
    case "$answer" in
        r|R|resume|RESUME|Resume) printf '%s\n' resume ;;
        s|S|restart|RESTART|Restart) printf '%s\n' restart ;;
        *) printf '%s\n' cancel ;;
    esac
}

run_full_bootstrap() {
    local requested_mode="${1:-auto}" recovery_action bootstrap_mode=full

    if [ "$requested_mode" = rebuild ]; then
        recovery_action=restart
        log "Rebuild selected: ignoring all existing base archives and cached base images"
    else
        recovery_action="$(choose_bootstrap_recovery_action)"
    fi
    case "$recovery_action" in
        resume)
            bootstrap_mode=resume-full
            log "Resuming BFSOS base bootstrap at the first incomplete stage"
            ;;
        restart)
            bootstrap_mode=full
            log "Rebuilding complete BFSOS base (bootstrap stages 1 -> 5)"
            ;;
        cancel)
            log "Fresh-base rebuild cancelled"
            return 130
            ;;
    esac

    # The bootstrap uses terminal/session handling internally. When launched
    # directly from the ISO builder, allocate a pseudo-terminal when possible.
    if command -v script >/dev/null 2>&1; then
        (
            cd "$PROJECT_DIR"
            export BFS_FULL_BOOTSTRAP_ASSUME_YES=yes
            export BFS_FULL_BOOTSTRAP_NO_INSTALL_PROMPT=yes
            export BFS_ISO_BUILD=yes
            script -qec "./bootstrap.sh $bootstrap_mode" /dev/null
        )
    else
        BFS_FULL_BOOTSTRAP_ASSUME_YES=yes \
        BFS_FULL_BOOTSTRAP_NO_INSTALL_PROMPT=yes \
        BFS_ISO_BUILD=yes \
            "$PROJECT_DIR/bootstrap.sh" "$bootstrap_mode"
    fi
}

extract_archive() {
    local archive="$1" dest="$2"
    mkdir -p "$dest"
    case "$archive" in
        *.tar.xz) tar -xJpf "$archive" -C "$dest" ;;
        *.tar.zst) tar --zstd -xpf "$archive" -C "$dest" ;;
        *.tar.gz) tar -xzpf "$archive" -C "$dest" ;;
        *) die "Unsupported base archive format: $archive" ;;
    esac
}

mount_chroot_fs() {
    local root="$1"
    mount --bind /dev "$root/dev"
    mount -t proc proc "$root/proc"
    mount -t sysfs sysfs "$root/sys"
    mount -t devpts devpts "$root/dev/pts"
}

umount_chroot_fs() {
    local root="$1"
    umount -l "$root/dev/pts" 2>/dev/null || true
    umount -l "$root/proc" 2>/dev/null || true
    umount -l "$root/sys" 2>/dev/null || true
    umount -l "$root/dev" 2>/dev/null || true
}

build_iso_package_set() {
    local root="$1"
    local kernel_flavor="${BFS_ISO_KERNEL:-lts}"
    local kernel_pkg kernel_pattern

    case "$kernel_flavor" in
        lts)
            kernel_pkg="linux-lts"
            kernel_pattern="vmlinuz-*-BFS-LTS"
            ;;
        mainline)
            kernel_pkg="linux"
            kernel_pattern="vmlinuz-*-BFS-Linux"
            ;;
        *)
            die "Unknown BFS_ISO_KERNEL='$kernel_flavor' (expected: lts or mainline)"
            ;;
    esac

    log "Building/installing complete ISO live + installer package set in isolated root"
    rm -rf "$root/usr/ports"
    mkdir -p "$root/usr/ports"
    cp -a "$BUILD_PROJECT_DIR/ports/." "$root/usr/ports/"
    grep -Fqx 'prtdir /usr/ports/iso' "$root/etc/prt-get.conf" || echo 'prtdir /usr/ports/iso' >> "$root/etc/prt-get.conf"
    cp -a /etc/resolv.conf "$root/etc/resolv.conf" 2>/dev/null || true

    mount_chroot_fs "$root"
    trap 'umount_chroot_fs "$root"' RETURN

    log "Refreshing ports metadata in isolated root"
    chroot "$root" /usr/bin/env -i \
        HOME=/root TERM="${TERM:-linux}" PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        /bin/bash -lc "ports -u" ||
        die "Failed to refresh ports in ISO root"

    log "Updating pkgutils before system upgrade"
    chroot "$root" /usr/bin/env -i \
        HOME=/root TERM="${TERM:-linux}" PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        /bin/bash -lc "prt-get update pkgutils" ||
        die "Failed to update pkgutils in ISO root"

    chroot "$root" /usr/bin/env -i \
        HOME=/root TERM="${TERM:-linux}" PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        /bin/bash -lc 'grep -Fq "# BFSOS: command-line options override Pkgfile/pkgmk.conf." /usr/bin/pkgmk' ||
        die "Updated pkgutils does not contain CLI precedence fix"

    log "Running full system upgrade in isolated root"
    chroot "$root" /usr/bin/env -i \
        HOME=/root TERM="${TERM:-linux}" PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        /bin/bash -lc "prt-get sysup" ||
        die "Failed to complete ISO root system upgrade"

    log "Ensuring gobject-introspection is installed"
    chroot "$root" /usr/bin/env -i \
        HOME=/root TERM="${TERM:-linux}" PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        /bin/bash -lc "prt-get depinst gobject-introspection" ||
        die "Failed to install gobject-introspection in ISO root"

    log "Ensuring GLib introspection support required by ISO dependencies"
    chroot "$root" /usr/bin/env -i \
        HOME=/root TERM="${TERM:-linux}" PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        /bin/bash -lc '
            if [ ! -r /usr/share/gir-1.0/Gio-2.0.gir ] || \
               [ ! -r /usr/lib/girepository-1.0/Gio-2.0.typelib ]; then
                rm -f /var/cache/pkg/packages/glib#*.pkg.tar.zst
                rm -rf /var/cache/pkg/build-work/pkgmk-glib
                cd /usr/ports/opt/glib || exit 1
                pkgmk -d -if || exit 1
                glib_pkg="$(ls -1t /var/cache/pkg/packages/glib#*.pkg.tar.zst 2>/dev/null | head -n1)"
                [ -n "$glib_pkg" ] || exit 1
                pkgadd -u "$glib_pkg" || exit 1
            fi
            [ -r /usr/share/gir-1.0/Gio-2.0.gir ] || exit 1
            [ -r /usr/lib/girepository-1.0/Gio-2.0.typelib ] || exit 1
        ' || die "Failed to prepare GLib introspection support"

    log "GLib introspection support verified"

    log "Building/installing selected ISO kernel: $kernel_pkg"
    chroot "$root" /usr/bin/env -i \
        HOME=/root TERM="${TERM:-linux}" PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        /bin/bash -lc "prt-get depinst $kernel_pkg" ||
        die "Failed to build/install selected ISO kernel package set: $kernel_pkg"

    if ! find "$root/boot" -maxdepth 1 -type f -name "$kernel_pattern" -print -quit | grep -q .; then
        die "Selected kernel package '$kernel_pkg' completed without installing $kernel_pattern"
    fi

    if [ ! -d "$root/lib/modules" ] || ! find "$root/lib/modules" -mindepth 1 -maxdepth 1 -type d -print -quit | grep -q .; then
        die "Selected kernel package '$kernel_pkg' installed no kernel modules"
    fi

    log "Selected ISO kernel installed successfully: $kernel_pkg"

    log "Building/installing remaining ISO live + installer packages"
    chroot "$root" /usr/bin/env -i \
        HOME=/root TERM="${TERM:-linux}" PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        /bin/bash -lc "prt-get depinst ${iso_packages[*]}" ||
        die "Failed to build/install remaining ISO package set"

    umount_chroot_fs "$root"
    trap - RETURN
}

install_live_runtime() {
    local root="$1"
    log "Installing BFSOS live-session policy"
    mkdir -p "$root/home/bfs" "$root/usr/local/sbin" "$root/etc/systemd/system" "$root/etc/sudoers.d"
    mkdir -p "$root/etc/systemd/system/getty@tty1.service.d"
    mkdir -p "$root/home/bfs/BFSOS"
    rsync -a --delete \
        --exclude '/iso-work/' \
        --exclude '/iso-output/' \
        "$BUILD_PROJECT_DIR/" "$root/home/bfs/BFSOS/"

    chroot "$root" /bin/bash -lc '
        getent group bfs >/dev/null 2>&1 || groupadd bfs

        live_groups=()
        for g in wheel audio video input storage; do
            getent group "$g" >/dev/null 2>&1 || groupadd -r "$g"
            live_groups+=("$g")
        done

        if ! id bfs >/dev/null 2>&1; then
            useradd -m -g bfs -G "$(IFS=,; echo "${live_groups[*]}")" -s /bin/bash bfs
        fi

        passwd -l bfs >/dev/null 2>&1 || true

        # The source checkout is staged while the ISO root is assembled as
        # root. Normalize the complete live checkout to the normal live user
        # immediately afterward so git/edit/copy workflows never require sudo.
        chown -R bfs:bfs /home/bfs/BFSOS
        chown bfs:bfs /home/bfs
        if find /home/bfs/BFSOS \( ! -user bfs -o ! -group bfs \) -print -quit | grep -q .; then
            echo "BFSOS live checkout ownership normalization failed" >&2
            exit 1
        fi
    '
    cat > "$root/etc/sudoers.d/90-bfs-live" <<'EOS'
# Disposable live-media account. Local console auto-login is enabled.
# Passwordless sudo applies only to the live image and must never be copied to an installed system.
bfs ALL=(ALL:ALL) NOPASSWD: ALL
EOS
    chmod 0440 "$root/etc/sudoers.d/90-bfs-live"

    cat > "$root/etc/systemd/system/getty@tty1.service.d/10-bfs-live-autologin.conf" <<'EOS'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin bfs --noclear %I $TERM
EOS

    cat > "$root/usr/local/sbin/bfs-live-console-font" <<'EOS'
#!/usr/bin/env bash
set -u

FONT_DIRS="/usr/share/kbd/consolefonts /usr/share/consolefonts"
STATE_FILE=/run/bfsos-live-console-font

find_font() {
    local candidate dir path

    for candidate in "$@"; do
        for dir in $FONT_DIRS; do
            for path in \
                "$dir/$candidate" \
                "$dir/$candidate.psf" \
                "$dir/$candidate.psfu" \
                "$dir/$candidate.psf.gz" \
                "$dir/$candidate.psfu.gz"; do
                [ -r "$path" ] && {
                    printf '%s\n' "$path"
                    return 0
                }
            done
        done
    done

    return 1
}

find_any_font() {
    local dir pattern path

    for pattern in "$@"; do
        for dir in $FONT_DIRS; do
            [ -d "$dir" ] || continue
            path="$(find "$dir" -maxdepth 1 -type f \
                \( -name "$pattern.psf" \
                   -o -name "$pattern.psfu" \
                   -o -name "$pattern.psf.gz" \
                   -o -name "$pattern.psfu.gz" \) \
                2>/dev/null | sort | head -n1)"
            [ -n "$path" ] && {
                printf '%s\n' "$path"
                return 0
            }
        done
    done

    return 1
}

apply_font() {
    local path="$1" current_tty="" rc=0
    current_tty="$(tty 2>/dev/null || true)"

    if [[ "$current_tty" != /dev/tty[0-9]* ]]; then
        printf 'Console font changes only apply to a local Linux virtual console.\n'
        return 0
    fi

    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        setfont -C "$current_tty" "$path" 2>/dev/null || rc=$?
    else
        sudo setfont -C "$current_tty" "$path" 2>/dev/null || rc=$?
    fi

    if [ "$rc" -eq 0 ]; then
        basename "$path" | sed -E 's/\.(psfu?|psfu?\.gz)$//' > "$STATE_FILE"
        printf 'Applied console font: %s\n' "$(cat "$STATE_FILE")"
        return 0
    fi
    printf 'WARNING: Unable to apply console font %s; keeping current font.\n' "$path" >&2
    return 1
}

choose_font() {
    local large="" medium="" choice=""
    command -v setfont >/dev/null 2>&1 || {
        printf 'setfont is unavailable; keeping the current console font.\n'
        return 0
    }
    [ -t 0 ] && [ -t 1 ] || return 0

    large="$(find_font latarcyrheb-sun32 ter-v32n ter-132n 2>/dev/null || true)"
    medium="$(find_font latarcyrheb-sun16 ter-v24n ter-v20n 2>/dev/null || true)"

    # Do not make the accessibility menu useless merely because the preferred
    # fonts are unavailable. Fall back to installed 32/28/24 and 20/18/16
    # pixel console fonts.
    [ -n "$large" ] || large="$(find_any_font '*32*' '*28*' '*24*' 2>/dev/null || true)"
    [ -n "$medium" ] || medium="$(find_any_font '*20*' '*18*' '*16*' 2>/dev/null || true)"

    printf '\nBFSOS console font\n==================\n'
    printf '  1) Keep current/default\n'
    [ -n "$large" ] && printf '  2) Large / high visibility (%s)\n' "$(basename "$large")"
    [ -n "$medium" ] && printf '  3) Medium (%s)\n' "$(basename "$medium")"
    printf '\nChoice [1]: '
    read -r choice || choice=1
    case "$choice" in
        2) [ -n "$large" ] && apply_font "$large" || true ;;
        3) [ -n "$medium" ] && apply_font "$medium" || true ;;
        *) printf 'Keeping current console font.\n' ;;
    esac
}

choose_font
EOS
    chmod 0755 "$root/usr/local/sbin/bfs-live-console-font"

    cat > "$root/usr/local/sbin/bfs-live-init" <<'EOS'
#!/usr/bin/env bash
set -u
exec </dev/tty1 >/dev/tty1 2>&1
printf '\nBFSOS live environment\n======================\n'
printf 'Local console: automatic login as bfs with passwordless sudo.\n'
printf 'SSH is disabled by default. Enter 3) Shell from the live menu for manual SSH setup instructions.\n\n'

# SSH host keys are intentionally not generated during normal live boot.
# Users who need SSH explicitly generate keys and start the service from Shell.

# Accessibility choice must happen before the normal live menu appears.
/usr/local/sbin/bfs-live-console-font || true

if command -v nm-online >/dev/null 2>&1 && nm-online -q --timeout=20; then
    printf '\nNetwork is available. Starting live time synchronization...\n'
    systemctl stop systemd-timesyncd.service 2>/dev/null || true
    if command -v chronyd >/dev/null 2>&1; then
        systemctl start chronyd.service 2>/dev/null || \
            systemctl start chrony.service 2>/dev/null || \
            chronyd >/dev/null 2>&1 || true
        if command -v chronyc >/dev/null 2>&1; then
            chronyc waitsync 10 0.5 >/dev/null 2>&1 || true
        fi
    fi

    printf '\nRefreshing the bundled BFSOS project tree...\n'
    if [ -d /home/bfs/BFSOS/.git ]; then
        runuser -u bfs -- bash -c 'cd /home/bfs/BFSOS && if git diff --quiet && git diff --cached --quiet; then git pull --ff-only || true; else echo "Local BFSOS tree has changes; automatic pull skipped."; fi'
    fi
else
    printf '\nNo network detected; using the BFSOS project tree shipped on the ISO.\n'
fi

printf '\nLive initialization complete. Starting bfs console session.\n'
EOS
    chmod 0755 "$root/usr/local/sbin/bfs-live-init"

    cat > "$root/etc/systemd/system/bfs-live-init.service" <<'EOS'
[Unit]
Description=BFSOS live-session initialization
After=NetworkManager.service
Before=getty@tty1.service
ConditionKernelCommandLine=bfs.live=1

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/bfs-live-init
StandardInput=tty-force
StandardOutput=tty
StandardError=tty
TTYPath=/dev/tty1
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOS

    cat > "$root/usr/local/sbin/bfs-live-menu" <<'EOS'
#!/usr/bin/env bash
set -u
PROJECT=/home/bfs/BFSOS
while true; do
    printf '\nBFSOS Live Menu\n===============\n'
    printf '  1) Bootstrap BFSOS\n  2) Run BFSOS installer\n  3) Shell\n  4) Change console font\n\nChoice: '
    read -r choice
    case "$choice" in
        1)
            cd "$PROJECT" || continue
            if command -v script >/dev/null 2>&1; then
                script -qec './bootstrap.sh' /dev/null
            else
                ./bootstrap.sh
            fi
            ;;
        2)
            cd "$PROJECT" || continue
            if command -v script >/dev/null 2>&1; then
                script -qec 'sudo ./scripts/install-bfs-menu-current.sh' /dev/null
            else
                sudo ./scripts/install-bfs-menu-current.sh
            fi
            ;;
        3)
            printf '\nBFSOS Live Shell\n================\n\n'
            printf 'You are in the disposable BFSOS live environment.\n'
            printf 'Type exit to return to the BFSOS Live Menu.\n\n'
            printf 'The live bfs account has passwordless sudo for this live session only.\n\n'
            printf 'SSH is disabled by default. To enable it for this live session:\n'
            printf '  sudo passwd bfs\n'
            printf '  sudo ssh-keygen -A\n'
            printf '  sudo systemctl start sshd.service  # or ssh.service if that is the installed unit\n\n'
            if command -v script >/dev/null 2>&1; then
                script -qec 'bash -il' /dev/null
            else
                bash -il
            fi
            ;;
        4) /usr/local/sbin/bfs-live-console-font ;;
        *) printf 'Invalid choice.\n' ;;
    esac
done
EOS
    chmod 0755 "$root/usr/local/sbin/bfs-live-menu"

    cat > "$root/home/bfs/.bash_profile" <<'EOS'
if [ -z "${BFS_LIVE_MENU_STARTED:-}" ] && [ -t 0 ]; then
    export BFS_LIVE_MENU_STARTED=1
    /usr/local/sbin/bfs-live-menu
fi
EOS
    chown 0:0 "$root/etc/systemd/system/bfs-live-init.service"
    rm -f "$root"/etc/ssh/ssh_host_*
    chroot "$root" /bin/bash -lc '
        mkdir -p /etc/systemd/system/multi-user.target.wants
        ln -sfn /etc/systemd/system/bfs-live-init.service /etc/systemd/system/multi-user.target.wants/bfs-live-init.service
        if [ -e /usr/lib/systemd/system/NetworkManager.service ]; then
            ln -sfn /usr/lib/systemd/system/NetworkManager.service /etc/systemd/system/multi-user.target.wants/NetworkManager.service
        fi
        # Chrony is the live ISO time-sync policy. Do not run a competing
        # systemd-timesyncd instance on live media. bfs-live-init starts chrony
        # only after NetworkManager reports usable connectivity.
        systemctl disable systemd-timesyncd.service 2>/dev/null || true
    ' || true

    # BFSOS preset policy must keep package-provided network daemons disabled
    # unless explicitly enabled by the administrator/installer. This is the
    # primary policy; the checks below are a live-media release invariant.
    local preset_file="$root/usr/lib/systemd/system-preset/99-bfsos.preset"
    local unit state

    [ -r "$preset_file" ] || \
        die "BFSOS preset policy missing from live root: /usr/lib/systemd/system-preset/99-bfsos.preset"
    grep -Eq '^[[:space:]]*disable[[:space:]]+\*[[:space:]]*$' "$preset_file" || \
        die "BFSOS preset policy does not contain the required default-disable rule"

    for unit in \
        sshd.service ssh.service sshd.socket ssh.socket \
        rsyncd.service rsync.service rsyncd.socket rsync.socket
    do
        # Remove stale enablement from reused bases/live roots, but only from
        # wants/requires directories. Do not delete canonical unit aliases.
        systemctl --root="$root" disable "$unit" 2>/dev/null || true
        find "$root/etc/systemd/system" "$root/usr/lib/systemd/system" \
            -type l \
            \( -path "*/system/*.wants/$unit" -o -path "*/system/*.requires/$unit" \) \
            -delete 2>/dev/null || true

        state="$(systemctl --root="$root" is-enabled "$unit" 2>/dev/null || true)"
        case "$state" in
            enabled|enabled-runtime|linked|linked-runtime)
                die "Live ISO policy violation: $unit is enabled ($state)"
                ;;
        esac
    done

    # Verify the BFSOS default-disable preset policy itself.
    # Explicit rules in earlier preset files still take precedence.
    grep -Eq '^[[:space:]]*disable[[:space:]]+\*[[:space:]]*$' "$preset_file" || \
        die "Live ISO preset policy violation: BFSOS default-disable rule is missing"

    log "Verified: BFSOS default-disable preset policy is installed and SSH/rsync have no boot enablement"
}

install_dracut_live_module() {
    local root="$1"
    local module="$root/usr/lib/dracut/modules.d/95bfs-live"
    mkdir -p "$module"
    cat > "$module/module-setup.sh" <<'EOS'
#!/bin/bash
check() { return 0; }
depends() { echo "rootfs-block"; }
installkernel() { instmods squashfs overlay loop iso9660; }
install() {
    # udevadm + sleep are required by the USB-media discovery retry loop.
    # A hybrid ISO presented as USB may not enumerate until after pre-mount
    # begins, even though the same image is immediately available as /dev/sr0.
    inst_multiple mount umount mkdir blkid losetup udevadm sleep
    inst_hook cmdline 95 "$moddir/bfs-live-cmdline.sh"
    inst_hook pre-mount 90 "$moddir/bfs-live-root.sh"
}
EOS
    cat > "$module/bfs-live-cmdline.sh" <<'EOS'
#!/bin/sh

getargbool 0 bfs.live || return 0

case "$(getarg root=)" in
    bfs-live|"")
        root="bfs-live"
        rootok=1
        ;;
esac
EOS
    cat > "$module/bfs-live-root.sh" <<'EOS'
#!/bin/sh
# Dracut pre-mount hook for BFSOS ISO media.
getargbool 0 bfs.live || return 0
label="$(getarg bfs.live.label=)"
squash="$(getarg bfs.live.squash=)"
[ -n "$label" ] || label="BFSOS_LIVE"
[ -n "$squash" ] || squash="/bfsos/rootfs.squashfs"
wait_seconds="$(getarg bfs.live.wait=)"
[ -n "$wait_seconds" ] || wait_seconds=15
case "$wait_seconds" in
    *[!0-9]*|'') wait_seconds=15 ;;
esac
[ "$wait_seconds" -lt 1 ] && wait_seconds=1
[ "$wait_seconds" -gt 60 ] && wait_seconds=60
mkdir -p /run/bfs-media /run/bfs-root /run/bfs-overlay /sysroot

# USB mass-storage media can enumerate after this pre-mount hook starts.
# The failure reproduced in QEMU USB mode showed the old one-shot probe
# failing at ~2.30s while /dev/sda and its partitions appeared at ~3.19s.
# Wait/retry rather than treating an early missing /dev/disk/by-label link as
# a permanent failure.  Mount by label regardless of whether the hybrid image
# is exposed as ISO9660, HFS+, or another mountable hybrid-ISO view.
media=""
tries=0
max_tries=$((wait_seconds * 4))
while [ "$tries" -lt "$max_tries" ]; do
    udevadm settle --timeout=1 2>/dev/null || true
    media="$(blkid -L "$label" 2>/dev/null || true)"
    [ -n "$media" ] && [ -b "$media" ] || media=""

    if [ -z "$media" ]; then
        for dev in "/dev/disk/by-label/$label" /dev/sr0 /dev/sr1; do
            if [ -e "$dev" ]; then
                media="$dev"
                break
            fi
        done
    fi

    if [ -n "$media" ]; then
        umount /run/bfs-media 2>/dev/null || true
        if mount -o ro "$media" /run/bfs-media 2>/dev/null &&
           [ -r "/run/bfs-media$squash" ]; then
            break
        fi
        umount /run/bfs-media 2>/dev/null || true
        media=""
    fi

    tries=$((tries + 1))
    sleep 0.25
done

[ -r "/run/bfs-media$squash" ] || {
    warn "BFSOS live root not found after USB/media wait: label=$label squash=$squash"
    return 1
}
mount -t squashfs -o loop,ro "/run/bfs-media$squash" /run/bfs-root || return 1
mount -t tmpfs -o mode=0755 tmpfs /run/bfs-overlay || return 1
mkdir -p /run/bfs-overlay/upper /run/bfs-overlay/work
mount -t overlay overlay -o lowerdir=/run/bfs-root,upperdir=/run/bfs-overlay/upper,workdir=/run/bfs-overlay/work /sysroot || return 1
rootok=1
EOS
    chmod 0755 \
        "$module/module-setup.sh" \
        "$module/bfs-live-cmdline.sh" \
        "$module/bfs-live-root.sh"
}

create_live_initramfs() {
    local root="$1" kernel image initrd
    local kernel_flavor="${BFS_ISO_KERNEL:-lts}"

    case "$kernel_flavor" in
        lts)
            kernel="$(find "$root/boot" -maxdepth 1 -type f -name 'vmlinuz-*-BFS-LTS' -printf '%f\n' | sort -V | tail -n1)"
            [ -n "$kernel" ] || die "No BFSOS LTS kernel found in live root"
            ;;
        mainline)
            kernel="$(find "$root/boot" -maxdepth 1 -type f -name 'vmlinuz-*-BFS-Linux' -printf '%f\n' | sort -V | tail -n1)"
            [ -n "$kernel" ] || die "No BFSOS mainline kernel found in live root"
            ;;
        *)
            die "Unknown BFS_ISO_KERNEL='$kernel_flavor' (expected: lts or mainline)"
            ;;
    esac

    log "Selected ISO kernel: $kernel_flavor ($kernel)"
    image="${kernel#vmlinuz-}"
    initrd="initramfs-${image}-live.img"
    log "Generating live initramfs for $image"
    mount_chroot_fs "$root"
    trap 'umount_chroot_fs "$root"' RETURN
    chroot "$root" dracut --force --no-hostonly --add 'bfs-live' "/boot/$initrd" "$image"
    umount_chroot_fs "$root"
    trap - RETURN
    printf '%s\n%s\n' "$kernel" "$initrd"
}

audit_live_root() {
    local root="$1" bad=""
    # gettext ships this compressed development archive as package data.
    # It is not needed by the BFSOS live environment and would trip the
    # no-source-archives ISO audit.
    rm -f "$root/usr/share/gettext/archive.dir.tar.xz"

    log "Auditing live root for forbidden source/package archives"
    bad="$(find "$root" -xdev -type f \( \
        -name '*.tar' -o -name '*.tar.gz' -o -name '*.tar.bz2' -o -name '*.tar.xz' -o -name '*.tar.zst' -o \
        -name '*.tgz' -o -name '*.tbz2' -o -name '*.txz' -o -name '*.pkg.tar.*' \
        \) -print 2>/dev/null | head -n 50)"
    if [ -n "$bad" ]; then
        printf '%s\n' "$bad" >&2
        die "Forbidden tar/package archives remain in live root; ISO creation stopped"
    fi
}

write_build_info() {
    local root="$1" base_archive="$2" base_sha=""
    base_sha="$(sha256sum "$base_archive" | awk '{print $1}')"
    cat > "$root/etc/bfs-build-info" <<EOF_INFO
BFSOS_VERSION=$VERSION
ARCH=$ARCH
BUILD_DATE=$BUILD_DATE
ISO_LABEL=$ISO_LABEL
GIT_URL=$GIT_URL
GIT_REF=$GIT_REF
GIT_COMMIT=$GIT_COMMIT_FULL
BASE_ARCHIVE=$(basename "$base_archive")
BASE_SHA256=$base_sha
BASE_URL=$BASE_URL
BASE_SOURCE=$BASE_SOURCE
SQUASHFS_COMPRESSION=xz
SQUASHFS_BLOCK_SIZE=1M
SQUASHFS_X86_BCJ=yes
EOF_INFO
}

stage_iso() {
    local root="$1" base_archive="$2" kernel="$3" initrd="$4"
    local stage="$WORK_DIR/iso-tree"
    local root_bytes squash_bytes iso_bytes base_sha
    rm -rf "$stage"
    mkdir -p "$stage/boot/grub" "$stage/bfsos"

    log "Removing all package/source/build archives and caches from live root"
    sudo rm -rf "$root/var/cache/pkg/sources" "$root/var/cache/pkg/packages" \
        "$root/var/cache/pkg/build-work" "$root/var/cache/pkg/build-work-disk"
    sudo mkdir -p "$root/var/cache/pkg/sources" "$root/var/cache/pkg/packages" "$root/var/cache/pkg/build-work"
    sudo bash -c "$(declare -f audit_live_root die log); audit_live_root '$root'"
    sudo bash -c "$(declare -f write_build_info); VERSION='$VERSION'; ARCH='$ARCH'; BUILD_DATE='$BUILD_DATE'; ISO_LABEL='$ISO_LABEL'; GIT_URL='$GIT_URL'; GIT_REF='$GIT_REF'; GIT_COMMIT_FULL='$GIT_COMMIT_FULL'; BASE_URL='$BASE_URL'; BASE_SOURCE='$BASE_SOURCE'; write_build_info '$root' '$base_archive'"

    root_bytes="$(sudo du -sb "$root" | awk '{print $1}')"
    sudo cp "$root/boot/$kernel" "$stage/bfsos/vmlinuz"
    sudo cp "$root/boot/$initrd" "$stage/bfsos/initramfs.img"
    log "Creating size-optimized SquashFS (xz, 1 MiB blocks, x86 BCJ)"
    sudo mksquashfs "$root" "$stage/bfsos/rootfs.squashfs" \
        -comp xz -b 1M -Xdict-size 100% -Xbcj x86 -noappend -wildcards -e 'tmp/*'
    sudo chown -R "$(id -u):$(id -g)" "$stage"
    squash_bytes="$(stat -c %s "$stage/bfsos/rootfs.squashfs")"
    base_sha="$(sha256sum "$base_archive" | awk '{print $1}')"

    cat > "$stage/bfsos/build-info" <<EOF_INFO
BFSOS_VERSION=$VERSION
ARCH=$ARCH
BUILD_DATE=$BUILD_DATE
ISO_LABEL=$ISO_LABEL
GIT_URL=$GIT_URL
GIT_REF=$GIT_REF
GIT_COMMIT=$GIT_COMMIT_FULL
BASE_ARCHIVE=$(basename "$base_archive")
BASE_SHA256=$base_sha
BASE_URL=$BASE_URL
BASE_SOURCE=$BASE_SOURCE
SQUASHFS_COMPRESSION=xz
SQUASHFS_BLOCK_SIZE=1M
SQUASHFS_X86_BCJ=yes
LIVE_ROOT_BYTES=$root_bytes
SQUASHFS_BYTES=$squash_bytes
EOF_INFO

    cat > "$stage/boot/grub/grub.cfg" <<EOF_GRUB
set default=0
set timeout=5
set gfxmode=1024x768,800x600,auto
set gfxpayload=keep
terminal_output gfxterm
menuentry "BFSOS $VERSION Live / Installer" {
    linux /bfsos/vmlinuz root=bfs-live bfs.live=1 bfs.live.label=$ISO_LABEL bfs.live.squash=/bfsos/rootfs.squashfs bfs.live.wait=$LIVE_MEDIA_WAIT rw consoleblank=1800
    initrd /bfsos/initramfs.img
}
EOF_GRUB

    mkdir -p "$OUTPUT_DIR"
    rm -f "$ISO_PATH" "$ISO_PATH.sha256" "$ISO_PATH.build-info"
    log "Mastering hybrid GRUB ISO: $ISO_PATH"
    grub-mkrescue -o "$ISO_PATH" -iso-level 3 -volid "$ISO_LABEL" "$stage"
    sha256sum "$ISO_PATH" > "$ISO_PATH.sha256"
    iso_bytes="$(stat -c %s "$ISO_PATH")"
    cat "$stage/bfsos/build-info" > "$ISO_PATH.build-info"
    printf 'ISO_BYTES=%s\n' "$iso_bytes" >> "$ISO_PATH.build-info"

    log "ISO size report: live-root=$root_bytes bytes squashfs=$squash_bytes bytes iso=$iso_bytes bytes"
    log "ISO complete: $ISO_PATH"
    log "Checksum: $ISO_PATH.sha256"
    log "Build provenance: $ISO_PATH.build-info"
}

main() {
    local base_action="" base_archive=""

    [ "$(id -u)" -ne 0 ] || die "Run the ISO creator as a regular user; it uses sudo when root access is required."
    parse_args "$@"
    case "$LIVE_MEDIA_WAIT" in
        ''|*[!0-9]*) die "BFS_ISO_LIVE_MEDIA_WAIT must be an integer number of seconds" ;;
    esac
    [ "$LIVE_MEDIA_WAIT" -ge 1 ] && [ "$LIVE_MEDIA_WAIT" -le 60 ] || \
        die "BFS_ISO_LIVE_MEDIA_WAIT must be between 1 and 60 seconds"
    preflight
    sync_host_time

    case "$BASE_MODE" in
        local-path)
            base_archive="$LOCAL_BASE_PATH"
            validate_base_archive "$base_archive" || die "Explicit --local-base archive is missing or invalid: $base_archive"
            BASE_SOURCE="local-explicit:$base_archive"
            ;;
        sourceforge)
            fetch_sourceforge_base base_archive
            ;;
        auto|local)
            base_archive="$(latest_usable_base_archive 2>/dev/null || true)"
            if validate_base_archive "$base_archive"; then
                BASE_SOURCE="local-project:$base_archive"
                log "Using maintainer-generated local base: $base_archive"
            else
                base_action="$(choose_base_action)"
                case "$base_action" in
                    use-existing)
                        base_archive="$(latest_usable_base_archive 2>/dev/null || true)"
                        BASE_SOURCE="local-project:$base_archive"
                        ;;
                    rebuild)
                        run_full_bootstrap rebuild
                        base_archive="$(latest_usable_base_archive 2>/dev/null || true)"
                        BASE_SOURCE="local-rebuilt:$base_archive"
                        ;;
                    sourceforge)
                        fetch_sourceforge_base base_archive
                        ;;
                    cancel) log "ISO build cancelled"; exit 0 ;;
                    *) die "Internal error: unknown base action '$base_action'" ;;
                esac
            fi
            ;;
        *) die "Unknown BFS_ISO_BASE_MODE='$BASE_MODE' (expected auto, local, local-path, or sourceforge)" ;;
    esac
    validate_base_archive "$base_archive" || die "No usable verified base archive is available"
    log "Base source: $BASE_SOURCE"
    log "Using verified base archive: $base_archive"

    case "$WORK_DIR" in
        /var/tmp/bfsos-iso-*) ;;
        *) die "Refusing to remove unsafe ISO work directory: $WORK_DIR" ;;
    esac
    if [ -d "$WORK_DIR/live-root" ]; then
        sudo bash -c "$(declare -f umount_chroot_fs); umount_chroot_fs '$WORK_DIR/live-root'" || true
    fi
    sudo rm -rf -- "$WORK_DIR"
    mkdir -p "$WORK_DIR"

    prepare_build_project

    sudo mkdir -p "$WORK_DIR/live-root"
    sudo chown root:root "$WORK_DIR/live-root"
    log "Extracting verified base into isolated ISO live root"
    sudo bash -c "$(declare -f extract_archive die); extract_archive '$base_archive' '$WORK_DIR/live-root'"

    sudo env BUILD_PROJECT_DIR="$BUILD_PROJECT_DIR" WORK_DIR="$WORK_DIR" BFS_ISO_KERNEL="${BFS_ISO_KERNEL:-lts}" bash -c "$(declare -f log die mount_chroot_fs umount_chroot_fs build_iso_package_set install_live_runtime install_dracut_live_module); $(declare -p iso_packages); build_iso_package_set '$WORK_DIR/live-root'; install_live_runtime '$WORK_DIR/live-root'; install_dracut_live_module '$WORK_DIR/live-root'"

    mapfile -t boot_files < <(sudo env WORK_DIR="$WORK_DIR" BFS_ISO_KERNEL="${BFS_ISO_KERNEL:-lts}" bash -c "$(declare -f log die mount_chroot_fs umount_chroot_fs create_live_initramfs); create_live_initramfs '$WORK_DIR/live-root'" | tail -n2)
    ((${#boot_files[@]} == 2)) || die "Could not determine generated live kernel/initramfs"
    stage_iso "$WORK_DIR/live-root" "$base_archive" "${boot_files[0]}" "${boot_files[1]}"
}

main "$@"
