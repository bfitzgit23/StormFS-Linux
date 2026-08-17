#!/usr/bin/env bash
set -Eeuo pipefail

# BFS Linux installer
#
# Assumptions:
#   - Run from the Gentoo live environment as root.
#   - Partitions are already created and formatted.
#   - A completed BFS rootfs archive is available.
#
# This installer mounts the target, extracts BFS, writes the primary system
# configuration, installs selected packages, installs GRUB, enables services,
# and runs final sanity checks. It never partitions or formats disks.

TARGET="${BFS_TARGET:-/mnt/bfs}"
ARCHIVE="${BFS_ARCHIVE:-}"
ROOT_DEV="${BFS_ROOT_DEV:-}"
BOOT_DEV="${BFS_BOOT_DEV:-}"
EFI_DEV="${BFS_EFI_DEV:-}"
SWAP_DEV="${BFS_SWAP_DEV:-}"
HOME_DEV="${BFS_HOME_DEV:-}"
HOSTNAME="${BFS_HOSTNAME:-bfs}"
TIMEZONE="${BFS_TIMEZONE:-America/New_York}"
LOCALE="${BFS_LOCALE:-en_US.UTF-8}"
USERNAME="${BFS_USERNAME:-}"
BOOT_MODE="${BFS_BOOT_MODE:-}"
BOOT_DISK="${BFS_BOOT_DISK:-}"
NETWORK_IFACE="${BFS_NETWORK_IFACE:-}"

INSTALL_KERNEL="${BFS_INSTALL_KERNEL:-yes}"
INSTALL_OPENSSH="${BFS_INSTALL_OPENSSH:-yes}"
INSTALL_NETWORKMANAGER="${BFS_INSTALL_NETWORKMANAGER:-yes}"
INSTALL_DHCPCD="${BFS_INSTALL_DHCPCD:-yes}"
INSTALL_EXFAT="${BFS_INSTALL_EXFAT:-yes}"
INSTALL_XFS="${BFS_INSTALL_XFS:-yes}"
INSTALL_BTRFS="${BFS_INSTALL_BTRFS:-yes}"
INSTALL_LVM="${BFS_INSTALL_LVM:-yes}"
INSTALL_MDADM="${BFS_INSTALL_MDADM:-yes}"
INSTALL_CRYPTSETUP="${BFS_INSTALL_CRYPTSETUP:-no}"
KEEP_MOUNTS="${BFS_KEEP_MOUNTS:-no}"

MOUNTED_BY_SCRIPT=()
CHROOT_INSTALLER="/root/.bfs-install-chroot.sh"

log() { printf '\n==> %s\n' "$*"; }
warn() { printf '\nWARNING: %s\n' "$*" >&2; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

ask() {
        local variable="$1" prompt="$2" default="${3:-}" answer=""
        [[ -n "${!variable:-}" ]] && return 0
        if [[ -n "$default" ]]; then
                read -r -p "$prompt [$default]: " answer
                printf -v "$variable" '%s' "${answer:-$default}"
        else
                read -r -p "$prompt: " answer
                printf -v "$variable" '%s' "$answer"
        fi
}

ask_optional() {
        local variable="$1" prompt="$2" answer=""
        [[ -n "${!variable:-}" ]] && return 0
        read -r -p "$prompt [leave blank to skip]: " answer
        printf -v "$variable" '%s' "$answer"
}

ask_yes_no() {
        local variable="$1" prompt="$2" default="${3:-no}" answer="" suffix="[y/N]"
        [[ "$default" == "yes" ]] && suffix="[Y/n]"
        read -r -p "$prompt $suffix: " answer
        answer="${answer,,}"
        if [[ -z "$answer" ]]; then
                printf -v "$variable" '%s' "$default"
        elif [[ "$answer" == "y" || "$answer" == "yes" ]]; then
                printf -v "$variable" '%s' yes
        else
                printf -v "$variable" '%s' no
        fi
}

confirm() {
        local answer=""
        read -r -p "$1 [y/N]: " answer
        [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

require_root() { [[ $EUID -eq 0 ]] || die "Run this installer as root."; }

require_commands() {
        local command
        for command in mount umount mountpoint findmnt tar chroot blkid sed awk grep install readlink; do
                command -v "$command" >/dev/null 2>&1 || die "Missing host command: $command"
        done
}

record_mount() { MOUNTED_BY_SCRIPT+=("$1"); }

mount_device() {
        local device="$1" destination="$2"
        [[ -n "$device" ]] || return 0
        mkdir -p "$destination"
        if mountpoint -q "$destination"; then
                log "$destination is already mounted."
                return 0
        fi
        mount "$device" "$destination"
        record_mount "$destination"
}

mount_virtual_filesystems() {
        log "Mounting virtual filesystems"
        mkdir -p "$TARGET"/{dev,dev/pts,proc,sys,run}

        if ! mountpoint -q "$TARGET/dev"; then
                mount --bind /dev "$TARGET/dev"
                record_mount "$TARGET/dev"
        fi
        if ! mountpoint -q "$TARGET/dev/pts"; then
                mount -t devpts devpts "$TARGET/dev/pts" -o gid=5,mode=620
                record_mount "$TARGET/dev/pts"
        fi
        if ! mountpoint -q "$TARGET/proc"; then
                mount -t proc proc "$TARGET/proc"
                record_mount "$TARGET/proc"
        fi
        if ! mountpoint -q "$TARGET/sys"; then
                mount -t sysfs sysfs "$TARGET/sys"
                record_mount "$TARGET/sys"
        fi
        if ! mountpoint -q "$TARGET/run"; then
                mount -t tmpfs tmpfs "$TARGET/run"
                record_mount "$TARGET/run"
        fi

        if [[ -L "$TARGET/dev/shm" ]]; then
                mkdir -p "$TARGET/$(readlink "$TARGET/dev/shm")"
        else
                mkdir -p "$TARGET/dev/shm"
        fi

        if [[ "$BOOT_MODE" == uefi && -d /sys/firmware/efi/efivars ]]; then
                mkdir -p "$TARGET/sys/firmware/efi/efivars"
                if ! mountpoint -q "$TARGET/sys/firmware/efi/efivars"; then
                        mount --bind /sys/firmware/efi/efivars "$TARGET/sys/firmware/efi/efivars"
                        record_mount "$TARGET/sys/firmware/efi/efivars"
                fi
        fi
}

cleanup() {
        local index destination
        rm -f "$TARGET$CHROOT_INSTALLER" 2>/dev/null || true
        [[ "$KEEP_MOUNTS" == yes ]] && return 0
        for ((index=${#MOUNTED_BY_SCRIPT[@]}-1; index>=0; index--)); do
                destination="${MOUNTED_BY_SCRIPT[$index]}"
                mountpoint -q "$destination" && umount "$destination" 2>/dev/null || true
        done
}

trap cleanup EXIT
trap 'die "Installation stopped near line $LINENO."' ERR

collect_settings() {
        ask ROOT_DEV "Root filesystem device"
        ask_optional BOOT_DEV "Separate /boot device"
        ask_optional EFI_DEV "EFI system partition"
        ask_optional SWAP_DEV "Swap device"
        ask_optional HOME_DEV "Separate /home device"
        ask ARCHIVE "Path to BFS rootfs archive"
        ask HOSTNAME "Hostname" "$HOSTNAME"
        ask TIMEZONE "Timezone" "$TIMEZONE"
        ask LOCALE "Locale" "$LOCALE"
        ask USERNAME "Regular username"

        if [[ -z "$BOOT_MODE" ]]; then
                if [[ -n "$EFI_DEV" || -d /sys/firmware/efi ]]; then BOOT_MODE=uefi; else BOOT_MODE=bios; fi
        fi
        [[ "$BOOT_MODE" == bios ]] && ask BOOT_DISK "Whole disk for BIOS GRUB, for example /dev/sda"

        if [[ -z "$NETWORK_IFACE" ]]; then
                NETWORK_IFACE="$(find /sys/class/net -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | grep -v '^lo$' | head -n1 || true)"
        fi
        ask NETWORK_IFACE "Network interface" "${NETWORK_IFACE:-ether0}"

        ask_yes_no INSTALL_KERNEL "Install Linux from ports?" "$INSTALL_KERNEL"
        ask_yes_no INSTALL_OPENSSH "Install and enable OpenSSH?" "$INSTALL_OPENSSH"
        ask_yes_no INSTALL_NETWORKMANAGER "Install and enable NetworkManager?" "$INSTALL_NETWORKMANAGER"
        ask_yes_no INSTALL_DHCPCD "Install dhcpcd?" "$INSTALL_DHCPCD"
        ask_yes_no INSTALL_EXFAT "Install exFAT support?" "$INSTALL_EXFAT"
        ask_yes_no INSTALL_XFS "Install XFS support?" "$INSTALL_XFS"
        ask_yes_no INSTALL_BTRFS "Install Btrfs support?" "$INSTALL_BTRFS"
        ask_yes_no INSTALL_LVM "Install LVM support?" "$INSTALL_LVM"
        ask_yes_no INSTALL_MDADM "Install software RAID support?" "$INSTALL_MDADM"
        ask_yes_no INSTALL_CRYPTSETUP "Install optional LUKS tools?" "$INSTALL_CRYPTSETUP"
}

validate_settings() {
        [[ -b "$ROOT_DEV" ]] || die "Root device does not exist: $ROOT_DEV"
        [[ -f "$ARCHIVE" ]] || die "Rootfs archive does not exist: $ARCHIVE"
        [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid username: $USERNAME"
        local device
        for device in "$BOOT_DEV" "$EFI_DEV" "$SWAP_DEV" "$HOME_DEV"; do
                [[ -z "$device" || -b "$device" ]] || die "Device does not exist: $device"
        done
        [[ "$BOOT_MODE" == uefi || "$BOOT_MODE" == bios ]] || die "Boot mode must be uefi or bios."
        [[ "$BOOT_MODE" != uefi || -n "$EFI_DEV" ]] || die "UEFI requires an EFI partition."
        [[ "$BOOT_MODE" != bios || -b "$BOOT_DISK" ]] || die "BIOS requires a whole-disk GRUB target."
}

show_summary() {
        cat <<SUMMARY

BFS installation summary
------------------------
Target:              $TARGET
Archive:             $ARCHIVE
Root:                $ROOT_DEV
Boot:                ${BOOT_DEV:-inside root}
EFI:                 ${EFI_DEV:-not used}
Swap:                ${SWAP_DEV:-not configured}
Home:                ${HOME_DEV:-inside root}
Hostname:            $HOSTNAME
Timezone:            $TIMEZONE
Locale:              $LOCALE
Username:            $USERNAME
Boot mode:           $BOOT_MODE
GRUB disk:           ${BOOT_DISK:-not applicable}
Network interface:   $NETWORK_IFACE
Kernel:              $INSTALL_KERNEL
OpenSSH:             $INSTALL_OPENSSH
NetworkManager:      $INSTALL_NETWORKMANAGER
Dhcpcd:              $INSTALL_DHCPCD
exFAT:               $INSTALL_EXFAT
XFS:                 $INSTALL_XFS
Btrfs:               $INSTALL_BTRFS
LVM:                 $INSTALL_LVM
RAID:                $INSTALL_MDADM
LUKS:                $INSTALL_CRYPTSETUP

No disk will be partitioned or formatted.
SUMMARY
        confirm "Continue?" || die "Installation cancelled."
}

mount_target_filesystems() {
        log "Mounting target filesystems"
        mkdir -p "$TARGET"
        mount_device "$ROOT_DEV" "$TARGET"
        [[ -z "$BOOT_DEV" ]] || mount_device "$BOOT_DEV" "$TARGET/boot"
        [[ "$BOOT_MODE" != uefi ]] || mount_device "$EFI_DEV" "$TARGET/boot/efi"
        [[ -z "$HOME_DEV" ]] || mount_device "$HOME_DEV" "$TARGET/home"
        [[ -z "$SWAP_DEV" ]] || swapon "$SWAP_DEV" 2>/dev/null || true
}

extract_rootfs() {
        log "Extracting BFS root filesystem"
        if [[ -n "$(find "$TARGET" -mindepth 1 -maxdepth 1 ! -name boot ! -name home -print -quit)" ]]; then
                warn "$TARGET is not empty."
                confirm "Extract into it anyway?" || die "Installation cancelled."
        fi
        tar --xattrs --acls --numeric-owner -xpf "$ARCHIVE" -C "$TARGET"
}

generate_fstab() {
        local fstab="$TARGET/etc/fstab" source destination fstype options relative uuid pass
        log "Generating /etc/fstab"
        mkdir -p "$TARGET/etc"

        if command -v genfstab >/dev/null 2>&1; then
                genfstab -U "$TARGET" > "$fstab"
                return
        fi

        : > "$fstab"
        while read -r source destination fstype options; do
                [[ "$destination" == "$TARGET"* ]] || continue
                relative="${destination#"$TARGET"}"
                [[ -n "$relative" ]] || relative=/
                uuid="$(blkid -s UUID -o value "$source" 2>/dev/null || true)"
                [[ -n "$uuid" ]] || continue
                pass=2; [[ "$relative" == / ]] && pass=1
                printf 'UUID=%s %s %s %s 0 %s\n' "$uuid" "$relative" "$fstype" "$options" "$pass" >> "$fstab"
        done < <(findmnt -Rrn -o SOURCE,TARGET,FSTYPE,OPTIONS "$TARGET")

        if [[ -n "$SWAP_DEV" ]]; then
                uuid="$(blkid -s UUID -o value "$SWAP_DEV" 2>/dev/null || true)"
                if [[ -n "$uuid" ]]; then
                        printf 'UUID=%s none swap defaults 0 0\n' "$uuid" >> "$fstab"
                else
                        printf '%s none swap defaults 0 0\n' "$SWAP_DEV" >> "$fstab"
                fi
        fi
}

build_package_list() {
        local packages=()
        [[ "$INSTALL_KERNEL" == yes ]] && packages+=(linux)
        [[ "$INSTALL_OPENSSH" == yes ]] && packages+=(openssh)
        [[ "$INSTALL_NETWORKMANAGER" == yes ]] && packages+=(networkmanager)
        [[ "$INSTALL_DHCPCD" == yes ]] && packages+=(dhcpcd)
        [[ "$INSTALL_EXFAT" == yes ]] && packages+=(exfatprogs)
        [[ "$INSTALL_XFS" == yes ]] && packages+=(xfsprogs)
        [[ "$INSTALL_BTRFS" == yes ]] && packages+=(btrfs-progs)
        [[ "$INSTALL_LVM" == yes ]] && packages+=(lvm2)
        [[ "$INSTALL_MDADM" == yes ]] && packages+=(mdadm)
        [[ "$INSTALL_CRYPTSETUP" == yes ]] && packages+=(cryptsetup)
        printf '%s ' "${packages[@]}"
}

write_chroot_installer() {
        local package_list
        package_list="$(build_package_list)"
        log "Preparing chroot configuration"
        install -d -m 0755 "$TARGET/root"

        cat > "$TARGET$CHROOT_INSTALLER" <<'CHROOT'
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH=/usr/bin:/usr/sbin:/bin:/sbin
export LANG=C LC_ALL=C LANGUAGE=C

HOSTNAME_VALUE="__HOSTNAME__"
TIMEZONE_VALUE="__TIMEZONE__"
LOCALE_VALUE="__LOCALE__"
USERNAME_VALUE="__USERNAME__"
BOOT_MODE_VALUE="__BOOT_MODE__"
BOOT_DISK_VALUE="__BOOT_DISK__"
NETWORK_IFACE_VALUE="__NETWORK_IFACE__"
PACKAGE_LIST_VALUE="__PACKAGE_LIST__"
INSTALL_OPENSSH_VALUE="__INSTALL_OPENSSH__"
INSTALL_NETWORKMANAGER_VALUE="__INSTALL_NETWORKMANAGER__"
INSTALL_DHCPCD_VALUE="__INSTALL_DHCPCD__"
INSTALL_LVM_VALUE="__INSTALL_LVM__"
INSTALL_MDADM_VALUE="__INSTALL_MDADM__"
INSTALL_CRYPTSETUP_VALUE="__INSTALL_CRYPTSETUP__"

log() { printf '\n==> %s\n' "$*"; }

log "Setting hostname and timezone"
printf '%s\n' "$HOSTNAME_VALUE" > /etc/hostname
[[ -e "/usr/share/zoneinfo/$TIMEZONE_VALUE" ]] || { echo "Missing timezone: $TIMEZONE_VALUE" >&2; exit 1; }
ln -sfn "/usr/share/zoneinfo/$TIMEZONE_VALUE" /etc/localtime

log "Configuring locale"
mkdir -p /etc
if [[ -f /etc/locales ]]; then
        grep -qxF "$LOCALE_VALUE UTF-8" /etc/locales || printf '%s UTF-8\n' "$LOCALE_VALUE" >> /etc/locales
else
        printf '%s UTF-8\n' "$LOCALE_VALUE" > /etc/locales
fi
if command -v genlocales >/dev/null 2>&1; then genlocales; elif command -v locale-gen >/dev/null 2>&1; then locale-gen; fi
printf 'LANG=%s\n' "$LOCALE_VALUE" > /etc/locale.conf

log "Writing hosts and console configuration"
cat > /etc/hosts <<EOF_HOSTS
127.0.0.1 localhost
127.0.1.1 $HOSTNAME_VALUE
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF_HOSTS
printf 'FONT=Lat2-Terminus16\n' > /etc/vconsole.conf

cat > /etc/inputrc <<'EOF_INPUTRC'
set horizontal-scroll-mode Off
set meta-flag On
set input-meta On
set convert-meta Off
set output-meta On
set bell-style none
"\eOd": backward-word
"\eOc": forward-word
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[5~": beginning-of-history
"\e[6~": end-of-history
"\e[3~": delete-char
"\e[2~": quoted-insert
"\eOH": beginning-of-line
"\eOF": end-of-line
"\e[H": beginning-of-line
"\e[F": end-of-line
EOF_INPUTRC

log "Configuring systemd"
systemd-machine-id-setup
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/noclear.conf <<'EOF_GETTY'
[Service]
TTYVTDisallocate=no
EOF_GETTY
mkdir -p /etc/systemd/coredump.conf.d
cat > /etc/systemd/coredump.conf.d/maxuse.conf <<'EOF_CORE'
[Coredump]
MaxUse=5G
EOF_CORE

mkdir -p /etc/systemd/network
cat > /etc/systemd/network/10-bfs-dhcp.network <<EOF_NETWORK
[Match]
Name=$NETWORK_IFACE_VALUE

[Network]
DHCP=ipv4

[DHCPv4]
UseDomains=true
EOF_NETWORK

log "Creating user"
if ! id "$USERNAME_VALUE" >/dev/null 2>&1; then
        useradd -m -G users,wheel,audio,video -s /bin/bash "$USERNAME_VALUE"
fi
printf '\nSet password for %s:\n' "$USERNAME_VALUE"
passwd "$USERNAME_VALUE"
printf '\nSet root password:\n'
passwd root

if command -v ports >/dev/null 2>&1; then
        log "Synchronizing ports"
        ports -u
fi

if [[ -n "$PACKAGE_LIST_VALUE" ]]; then
        command -v prt-get >/dev/null 2>&1 || { echo "prt-get is missing" >&2; exit 1; }
        log "Installing selected packages"
        # shellcheck disable=SC2086
        prt-get depinst $PACKAGE_LIST_VALUE
fi

command -v ssh-keygen >/dev/null 2>&1 && ssh-keygen -A
ldconfig
systemctl preset-all || true

if [[ "$INSTALL_NETWORKMANAGER_VALUE" == yes ]] && systemctl list-unit-files NetworkManager.service >/dev/null 2>&1; then
        systemctl enable NetworkManager.service
        systemctl disable systemd-networkd.service 2>/dev/null || true
        systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true
elif systemctl list-unit-files systemd-networkd.service >/dev/null 2>&1; then
        systemctl enable systemd-networkd.service
        systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true
fi

if systemctl list-unit-files systemd-resolved.service >/dev/null 2>&1; then
        systemctl enable systemd-resolved.service
        ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
fi

if [[ "$INSTALL_DHCPCD_VALUE" == yes && "$INSTALL_NETWORKMANAGER_VALUE" != yes ]] && systemctl list-unit-files dhcpcd.service >/dev/null 2>&1; then
        systemctl enable dhcpcd.service
fi

if [[ "$INSTALL_OPENSSH_VALUE" == yes ]]; then
        if systemctl list-unit-files sshd.service >/dev/null 2>&1; then
                systemctl enable sshd.service
        elif systemctl list-unit-files ssh.service >/dev/null 2>&1; then
                systemctl enable ssh.service
        else
                echo "WARNING: No OpenSSH service unit was found." >&2
        fi
fi

if [[ "$INSTALL_LVM_VALUE" == yes ]]; then
        if [[ ! -f /etc/lvm/lvm.conf ]] && command -v lvmconfig >/dev/null 2>&1; then
                mkdir -p /etc/lvm
                lvmconfig --type full --withcomments > /etc/lvm/lvm.conf
        fi
        systemctl enable lvm2-monitor.service 2>/dev/null || true
fi

if [[ "$INSTALL_MDADM_VALUE" == yes ]] && command -v mdadm >/dev/null 2>&1; then
        mdadm --detail --scan > /etc/mdadm.conf || true
fi

if [[ "$INSTALL_CRYPTSETUP_VALUE" == yes ]]; then
        mkdir -p /etc/cryptsetup-keys.d
        chmod 0700 /etc/cryptsetup-keys.d
fi

log "Installing GRUB"
mkdir -p /boot/grub
if [[ "$BOOT_MODE_VALUE" == uefi ]]; then
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=BFS-GRUB
else
        grub-install "$BOOT_DISK_VALUE"
fi
grub-mkconfig -o /boot/grub/grub.cfg

log "Running final checks"
for command in bash sh env sed grep awk find tar gzip xz make gcc g++ ld ar nm strip readelf mount umount ls cp mv rm chmod chown pkgmk pkgadd pkginfo; do
        command -v "$command" >/dev/null 2>&1 || printf 'MISSING COMMAND: %s\n' "$command" >&2
done

cat > /tmp/bfs-test.c <<'EOF_TEST'
#include <stdio.h>
int main(void) { puts("BFS compiler test passed"); return 0; }
EOF_TEST
gcc /tmp/bfs-test.c -o /tmp/bfs-test
/tmp/bfs-test
if gcc -dumpspecs | grep -q '/tmp/lfs-tools'; then
        echo "ERROR: GCC still references /tmp/lfs-tools." >&2
        exit 1
fi
rm -f /tmp/bfs-test /tmp/bfs-test.c

pkginfo -i | sort > /root/base-system.manifest
find /usr/lib/systemd/system /etc/systemd/system -type f -o -type l 2>/dev/null | sort > /root/systemd-units.manifest
ldconfig -p > /root/ldconfig.manifest

log "BFS installation finished successfully"
CHROOT

        sed -i \
                -e "s|__HOSTNAME__|$(printf '%s' "$HOSTNAME" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__TIMEZONE__|$(printf '%s' "$TIMEZONE" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__LOCALE__|$(printf '%s' "$LOCALE" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__USERNAME__|$(printf '%s' "$USERNAME" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__BOOT_MODE__|$BOOT_MODE|g" \
                -e "s|__BOOT_DISK__|$(printf '%s' "$BOOT_DISK" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__NETWORK_IFACE__|$(printf '%s' "$NETWORK_IFACE" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__PACKAGE_LIST__|$(printf '%s' "$package_list" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__INSTALL_OPENSSH__|$INSTALL_OPENSSH|g" \
                -e "s|__INSTALL_NETWORKMANAGER__|$INSTALL_NETWORKMANAGER|g" \
                -e "s|__INSTALL_DHCPCD__|$INSTALL_DHCPCD|g" \
                -e "s|__INSTALL_LVM__|$INSTALL_LVM|g" \
                -e "s|__INSTALL_MDADM__|$INSTALL_MDADM|g" \
                -e "s|__INSTALL_CRYPTSETUP__|$INSTALL_CRYPTSETUP|g" \
                "$TARGET$CHROOT_INSTALLER"
        chmod 0700 "$TARGET$CHROOT_INSTALLER"
}

run_chroot_installer() {
        log "Entering BFS chroot"
        chroot "$TARGET" /usr/bin/env -i \
                HOME=/root \
                TERM="${TERM:-linux}" \
                PATH=/usr/bin:/usr/sbin:/bin:/sbin \
                LANG=C \
                LC_ALL=C \
                /bin/bash "$CHROOT_INSTALLER"
}

main() {
        require_root
        require_commands
        collect_settings
        validate_settings
        show_summary
        mount_target_filesystems
        extract_rootfs
        generate_fstab
        mount_virtual_filesystems
        write_chroot_installer
        run_chroot_installer

        log "Installation complete"
        cat <<DONE

Review before rebooting:

    $TARGET/etc/fstab
    $TARGET/etc/hostname
    $TARGET/etc/locale.conf
    $TARGET/boot/grub/grub.cfg

Saved validation manifests:

    $TARGET/root/base-system.manifest
    $TARGET/root/systemd-units.manifest
    $TARGET/root/ldconfig.manifest
DONE
}

main "$@"
