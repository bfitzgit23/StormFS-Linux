#!/usr/bin/env bash
set -Eeuo pipefail

# BFSOS ISO builder - initial local-package/repository implementation.
# Source-complete implementation; boot/install acceptance still requires live VM testing.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION" 2>/dev/null || printf '0.9.0')"
ARCH="x86_64"
BUILD_DATE="$(date +%Y%m%d)"
GIT_COMMIT="$(git -C "$PROJECT_DIR" rev-parse --short=12 HEAD 2>/dev/null || printf 'unknown')"
ISO_LABEL="BFSOS_${VERSION//./_}_${ARCH}"
WORK_DIR="${BFS_ISO_WORK_DIR:-/var/tmp/bfsos-iso-${USER:-builder}}"
OUTPUT_DIR="${BFS_ISO_OUTPUT_DIR:-$HOME/BFSOS-ISO}"
ISO_NAME="BFSOS-${VERSION}-${ARCH}-${BUILD_DATE}-${GIT_COMMIT}.iso"
ISO_PATH="$OUTPUT_DIR/$ISO_NAME"
ASSUME_YES="${BFS_ISO_ASSUME_YES:-no}"
SKIP_BOOTSTRAP="${BFS_ISO_SKIP_BOOTSTRAP:-no}"

required_tools=(bash git sudo tar xz zstd rsync sha256sum find awk sed grep mount umount chroot mksquashfs xorriso grub-mkrescue mformat)
optional_tools=(qemu-system-x86_64)

declare -A tool_packages=(
    [git]=git [zstd]=zstd [rsync]=rsync [mksquashfs]=squashfs-tools
    [xorriso]=libisoburn [grub-mkrescue]=grub [mformat]=mtools [qemu-system-x86_64]=qemu
)

# Everything the current installer can select or require dynamically, plus
# the live-media services/tools. Dependencies are resolved by prt-get.
iso_packages=(
    linux-firmware dracut
    networkmanager openssh git sudo wget wpa_supplicant wireless_tools gpm lynx links
    cryptsetup lvm2 mdadm snapper pciutils
    dialog squashfs-tools grub grub-efi dosfstools mtools efibootmgr libisoburn syslinux
)

log() { printf '[BFSOS ISO] %s\n' "$*"; }
die() { printf '[BFSOS ISO] ERROR: %s\n' "$*" >&2; exit 1; }

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

confirm_rebuild() {
    [ "$ASSUME_YES" = yes ] && return 0
    printf '\nThe ISO builder will rebuild the complete BFSOS base before assembling media.\n'
    printf 'Continue? [y/N]: '
    read -r answer
    case "$answer" in y|Y|yes|YES|Yes) ;; *) exit 0 ;; esac
}

latest_base_archive() {
    find "$PROJECT_DIR/archives/base" -maxdepth 1 -type f \
        \( -name 'bfs-rootfs-*.tar.xz' -o -name 'bfs-rootfs-*.tar.zst' -o -name 'bfs-rootfs-*.tar.gz' \) \
        -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2-
}

run_full_bootstrap() {
    if [ "$SKIP_BOOTSTRAP" = yes ]; then
        log "BFS_ISO_SKIP_BOOTSTRAP=yes: using newest existing verified base archive"
        return 0
    fi
    log "Rebuilding complete BFSOS base (bootstrap stages 1 -> 5)"
    BFS_FULL_BOOTSTRAP_ASSUME_YES=yes \
    BFS_FULL_BOOTSTRAP_NO_INSTALL_PROMPT=yes \
    BFS_ISO_BUILD=yes \
        "$PROJECT_DIR/bootstrap.sh" full
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
    cp -a "$PROJECT_DIR/ports/." "$root/usr/ports/"
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
    mkdir -p "$root/home/bfs/BFSOS"
    rsync -a --delete \
        --exclude '/iso-work/' \
        --exclude '/iso-output/' \
        "$PROJECT_DIR/" "$root/home/bfs/BFSOS/"

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
        chown -R bfs:bfs /home/bfs
    '
    cat > "$root/etc/sudoers.d/90-bfs-live" <<'EOS'
# Live-media account. Password is set interactively at each boot.
bfs ALL=(ALL:ALL) ALL
EOS
    chmod 0440 "$root/etc/sudoers.d/90-bfs-live"

    cat > "$root/usr/local/sbin/bfs-live-init" <<'EOS'
#!/usr/bin/env bash
set -u
exec </dev/tty1 >/dev/tty1 2>&1
printf '\nBFSOS live environment\n======================\n'
printf 'Set the temporary password for the bfs live account.\n'
printf 'This password applies only to this live session.\n\n'
until passwd bfs; do
    printf '\nPassword setup failed; please try again.\n'
done

if command -v nm-online >/dev/null 2>&1 && nm-online -q --timeout=12; then
    printf '\nNetwork is available. Refreshing the bundled BFSOS project tree...\n'
    if [ -d /home/bfs/BFSOS/.git ]; then
        su - bfs -c 'cd ~/BFSOS && if git diff --quiet && git diff --cached --quiet; then git pull --ff-only || true; else echo "Local BFSOS tree has changes; automatic pull skipped."; fi'
    fi
else
    printf '\nNo network detected; using the BFSOS project tree shipped on the ISO.\n'
fi

ssh-keygen -A
systemctl start sshd.service 2>/dev/null || systemctl start ssh.service 2>/dev/null || true
printf '\nLive initialization complete. Log in as bfs.\n'
EOS
    chmod 0755 "$root/usr/local/sbin/bfs-live-init"

    cat > "$root/etc/systemd/system/bfs-live-init.service" <<'EOS'
[Unit]
Description=BFSOS live-session initialization
After=NetworkManager.service
Before=getty@tty1.service sshd.service ssh.service
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
    printf '  1) Bootstrap BFSOS\n  2) Run BFSOS installer\n  3) Shell\n  4) Quit menu\n\nChoice: '
    read -r choice
    case "$choice" in
        1) cd "$PROJECT" && ./bootstrap.sh ;;
        2) cd "$PROJECT" && sudo ./scripts/install-bfs-menu-current.sh ;;
        3) printf 'Type exit to return to the BFSOS live menu.\n'; bash ;;
        4) exit 0 ;;
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
    chroot "$root" /bin/bash -lc '
        mkdir -p /etc/systemd/system/multi-user.target.wants
        ln -sfn /etc/systemd/system/bfs-live-init.service /etc/systemd/system/multi-user.target.wants/bfs-live-init.service
        if [ -e /usr/lib/systemd/system/NetworkManager.service ]; then
            ln -sfn /usr/lib/systemd/system/NetworkManager.service /etc/systemd/system/multi-user.target.wants/NetworkManager.service
        fi
        systemctl disable sshd.service ssh.service 2>/dev/null || true
    ' || true
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
    inst_multiple mount umount mkdir blkid losetup
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
mkdir -p /run/bfs-media /run/bfs-root /run/bfs-overlay /sysroot
for dev in /dev/disk/by-label/$label /dev/sr0 /dev/sr1; do
    [ -e "$dev" ] || continue
    mount -o ro "$dev" /run/bfs-media 2>/dev/null && break
done
[ -r "/run/bfs-media$squash" ] || { warn "BFSOS live root not found: $squash"; return 1; }
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

stage_iso() {
    local root="$1" base_archive="$2" kernel="$3" initrd="$4"
    local stage="$WORK_DIR/iso-tree"
    local pkgdir="$stage/bfsos/packages/$ARCH"
    rm -rf "$stage"
    mkdir -p "$stage/boot/grub" "$stage/bfsos" "$pkgdir"

    # Preserve one copy of package archives outside the squashfs for offline installs.
    if [ -d "$root/var/cache/pkg/packages" ]; then
        sudo cp -a "$root/var/cache/pkg/packages/." "$pkgdir/"
    fi

    # Do not ship downloaded package sources, duplicate package archives,
    # or temporary package build trees inside the compressed live root.
    # Keep /usr/src intact; removing it saved little space and can be useful
    # for development/debugging on the live media.
    log "Cleaning package/build caches from live root before squashfs creation"
    sudo rm -rf "$root/var/cache/pkg/sources/"*
    sudo rm -rf "$root/var/cache/pkg/packages/"*
    sudo rm -rf "$root/var/cache/pkg/build-work/"*
    sudo rm -rf "$root/var/cache/pkg/build-work-disk/"*

    sudo cp "$root/boot/$kernel" "$stage/bfsos/vmlinuz"
    sudo cp "$root/boot/$initrd" "$stage/bfsos/initramfs.img"
    sudo mksquashfs "$root" "$stage/bfsos/rootfs.squashfs" -comp xz -noappend -wildcards \
        -e 'tmp/*'
    cp "$base_archive" "$stage/bfsos/$(basename "$base_archive")"
    sudo chown -R "$(id -u):$(id -g)" "$stage"

    if compgen -G "$pkgdir/*.pkg.tar.*" >/dev/null; then
        (cd "$pkgdir" && sha256sum *.pkg.tar.* > packages.sha256)
    else
        : > "$pkgdir/packages.sha256"
    fi

    cat > "$stage/bfsos/build-info" <<EOF_INFO
BFSOS_VERSION=$VERSION
ARCH=$ARCH
BUILD_DATE=$BUILD_DATE
GIT_COMMIT=$GIT_COMMIT
BASE_ARCHIVE=$(basename "$base_archive")
EOF_INFO
    (cd "$stage/bfsos" && find packages -type f -name '*.pkg.tar.*' -printf '%P\n' | sort > packages.list)

    cat > "$stage/boot/grub/grub.cfg" <<EOF_GRUB
set default=0
set timeout=5
menuentry "BFSOS $VERSION Live / Installer" {
    linux /bfsos/vmlinuz root=bfs-live bfs.live=1 bfs.live.label=$ISO_LABEL bfs.live.squash=/bfsos/rootfs.squashfs rw
    initrd /bfsos/initramfs.img
}
EOF_GRUB

    mkdir -p "$OUTPUT_DIR"
    rm -f "$ISO_PATH" "$ISO_PATH.sha256"
    log "Mastering hybrid GRUB ISO: $ISO_PATH"
    grub-mkrescue \
        -o "$ISO_PATH" \
        -iso-level 3 \
        -volid "$ISO_LABEL" \
        "$stage"
    sha256sum "$ISO_PATH" > "$ISO_PATH.sha256"
    log "ISO complete: $ISO_PATH"
    log "Checksum: $ISO_PATH.sha256"
}

main() {
    [ "$(id -u)" -ne 0 ] || die "Run the ISO creator as a regular user; it uses sudo when root access is required."
    preflight
    confirm_rebuild
    run_full_bootstrap
    base_archive="$(latest_base_archive)"
    [ -n "$base_archive" ] && [ -s "$base_archive" ] || die "No base archive was produced"

    case "$WORK_DIR" in
        /var/tmp/bfsos-iso-*)
            ;;
        *)
            die "Refusing to remove unsafe ISO work directory: $WORK_DIR"
            ;;
    esac

    if [ -d "$WORK_DIR/live-root" ]; then
        sudo bash -c "$(declare -f umount_chroot_fs); umount_chroot_fs '$WORK_DIR/live-root'" || true
    fi

    sudo rm -rf -- "$WORK_DIR"
    mkdir -p "$WORK_DIR"
    sudo mkdir -p "$WORK_DIR/live-root"
    sudo chown root:root "$WORK_DIR/live-root"
    log "Extracting verified base into isolated ISO live root"
    sudo bash -c "$(declare -f extract_archive); extract_archive '$base_archive' '$WORK_DIR/live-root'"
    sudo cp -a "$PROJECT_DIR/ports" "$WORK_DIR/live-root/usr/ports"

    # Remaining rootfs operations are deliberately performed as root while the
    # top-level builder itself remains a regular-user bootstrap operation.
    sudo env PROJECT_DIR="$PROJECT_DIR" WORK_DIR="$WORK_DIR" BFS_ISO_KERNEL="${BFS_ISO_KERNEL:-lts}" bash -c "$(declare -f log die mount_chroot_fs umount_chroot_fs build_iso_package_set install_live_runtime install_dracut_live_module); $(declare -p iso_packages); build_iso_package_set '$WORK_DIR/live-root'; install_live_runtime '$WORK_DIR/live-root'; install_dracut_live_module '$WORK_DIR/live-root'"

    mapfile -t boot_files < <(sudo env WORK_DIR="$WORK_DIR" BFS_ISO_KERNEL="${BFS_ISO_KERNEL:-lts}" bash -c "$(declare -f log die mount_chroot_fs umount_chroot_fs create_live_initramfs); create_live_initramfs '$WORK_DIR/live-root'" | tail -n2)
    ((${#boot_files[@]} == 2)) || die "Could not determine generated live kernel/initramfs"
    stage_iso "$WORK_DIR/live-root" "$base_archive" "${boot_files[0]}" "${boot_files[1]}"
}

main "$@"
