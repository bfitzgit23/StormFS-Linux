#!/usr/bin/env bash
#
# chroot.sh
#
# Mount or reuse a BFS Linux target at /mnt/bfs and enter its chroot.
# Intended location: ~/BFSOS/scripts/chroot.sh
#

set -Eeuo pipefail

TARGET="${BFS_TARGET:-/mnt/bfs}"
KEEP_VIRTUAL_MOUNTS="${BFS_KEEP_VIRTUAL_MOUNTS:-no}"

USED_DEVICES=()
AVAILABLE_PATHS=()
AVAILABLE_TYPES=()
AVAILABLE_SIZES=()
AVAILABLE_FSTYPES=()
AVAILABLE_LABELS=()
AVAILABLE_MOUNTPOINTS=()

ROOT_DEV=""
BOOT_DEV=""
EFI_DEV=""
SWAP_DEV=""
EXTRA_DEVICES=()
EXTRA_MOUNTPOINTS=()

VIRTUAL_MOUNTS=()
SWAP_ENABLED_BY_SCRIPT=""
BOOT_MODE="unknown"

log() { printf '\n==> %s\n' "$*"; }
warn() { printf '\nWARNING: %s\n' "$*" >&2; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

ask_yes_no() {
    local prompt="$1"
    local default="${2:-no}"
    local answer=""
    local suffix="[y/N]"

    [[ "$default" == yes ]] && suffix="[Y/n]"

    while true; do
        read -r -p "$prompt $suffix: " answer
        answer="${answer,,}"

        if [[ -z "$answer" ]]; then
            [[ "$default" == yes ]]
            return
        fi

        case "$answer" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

detect_boot_mode() {
    if [[ -d /sys/firmware/efi ]]; then
        BOOT_MODE="uefi"
    else
        BOOT_MODE="bios"
    fi
}

require_root() {
    [[ $EUID -eq 0 ]] || die "Run this script as root."
}

require_commands() {
    local command_name=""

    for command_name in \
        mount umount mountpoint findmnt lsblk swapon swapoff \
        chroot awk grep sort readlink mkdir
    do
        command -v "$command_name" >/dev/null 2>&1 ||
            die "Missing required command: $command_name"
    done
}

is_used_device() {
    local wanted="$1"
    local used=""

    for used in "${USED_DEVICES[@]}"; do
        [[ "$used" == "$wanted" ]] && return 0
    done

    return 1
}

get_available_partitions() {
    local path="" type="" size="" fstype="" label="" mountpoints=""

    AVAILABLE_PATHS=()
    AVAILABLE_TYPES=()
    AVAILABLE_SIZES=()
    AVAILABLE_FSTYPES=()
    AVAILABLE_LABELS=()
    AVAILABLE_MOUNTPOINTS=()

    while read -r path type size fstype label mountpoints; do
        case "$type" in
            part|lvm|crypt|raid*) ;;
            *) continue ;;
        esac

        is_used_device "$path" && continue

        AVAILABLE_PATHS+=("$path")
        AVAILABLE_TYPES+=("$type")
        AVAILABLE_SIZES+=("${size:--}")
        AVAILABLE_FSTYPES+=("${fstype:--}")
        AVAILABLE_LABELS+=("${label:--}")
        AVAILABLE_MOUNTPOINTS+=("${mountpoints:--}")
    done < <(
        lsblk -prno PATH,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS |
        awk '{
            p=$1; t=$2; s=$3; f=$4; l=$5;
            $1=$2=$3=$4=$5="";
            sub(/^ +/, "");
            print p,t,s,f,l,$0
        }'
    )
}

show_available_partitions() {
    local index=0

    get_available_partitions

    printf '\nAvailable partitions not yet selected:\n'
    printf '  %-4s %-24s %-9s %-10s %-12s %-16s %s\n' \
        NUM DEVICE TYPE SIZE FSTYPE LABEL MOUNTPOINTS

    for ((index=0; index<${#AVAILABLE_PATHS[@]}; index++)); do
        printf '  %-4d %-24s %-9s %-10s %-12s %-16s %s\n' \
            "$((index + 1))" \
            "${AVAILABLE_PATHS[$index]}" \
            "${AVAILABLE_TYPES[$index]}" \
            "${AVAILABLE_SIZES[$index]}" \
            "${AVAILABLE_FSTYPES[$index]}" \
            "${AVAILABLE_LABELS[$index]}" \
            "${AVAILABLE_MOUNTPOINTS[$index]}"
    done

    printf '\n'
}

select_partition() {
    local variable="$1"
    local prompt="$2"
    local optional="${3:-no}"
    local answer=""
    local selected_index=0
    local selected_device=""

    while true; do
        show_available_partitions

        ((${#AVAILABLE_PATHS[@]} > 0)) ||
            die "No unselected partitions remain."

        if [[ "$optional" == yes ]]; then
            printf '  0) Skip\n'
            read -r -p "$prompt [0-${#AVAILABLE_PATHS[@]}]: " answer

            if [[ "${answer:-0}" == 0 ]]; then
                printf -v "$variable" ''
                return 0
            fi
        else
            read -r -p "$prompt [1-${#AVAILABLE_PATHS[@]}]: " answer
        fi

        [[ "$answer" =~ ^[0-9]+$ ]] || {
            warn "Enter a number from the list."
            continue
        }

        ((answer >= 1 && answer <= ${#AVAILABLE_PATHS[@]})) || {
            warn "Selection is outside the available range."
            continue
        }

        selected_index=$((answer - 1))
        selected_device="${AVAILABLE_PATHS[$selected_index]}"

        printf -v "$variable" '%s' "$selected_device"
        USED_DEVICES+=("$selected_device")

        printf 'Selected %s: %s\n' "$prompt" "$selected_device"
        return 0
    done
}

unmount_device_elsewhere() {
    local device="$1"
    local wanted_target="$2"
    local current_target=""

    while IFS= read -r current_target; do
        [[ -n "$current_target" ]] || continue
        [[ "$current_target" == "$wanted_target" ]] && continue

        warn "$device is mounted at $current_target; unmounting it."
        umount "$current_target" ||
            die "Could not unmount $device from $current_target"
    done < <(findmnt -rn -S "$device" -o TARGET 2>/dev/null | sort -r || true)
}

mount_selected_device() {
    local device="$1"
    local destination="$2"

    [[ -n "$device" ]] || return 0

    mkdir -p "$destination"

    if mountpoint -q "$destination"; then
        local mounted_source=""
        mounted_source="$(findmnt -rn -o SOURCE --target "$destination" 2>/dev/null || true)"

        [[ "$mounted_source" == "$device" ]] ||
            die "$destination is already mounted from $mounted_source, not $device."

        return 0
    fi

    unmount_device_elsewhere "$device" "$destination"

    log "Mounting $device at $destination"
    mount "$device" "$destination"
}

record_virtual_mount() {
    VIRTUAL_MOUNTS+=("$1")
}

mount_virtual_filesystems() {
    log "Mounting virtual filesystems"

    mkdir -p \
        "$TARGET/dev" \
        "$TARGET/proc" \
        "$TARGET/sys" \
        "$TARGET/run"

    if ! mountpoint -q "$TARGET/dev"; then
        mount --rbind /dev "$TARGET/dev"
        mount --make-rslave "$TARGET/dev"
        record_virtual_mount "$TARGET/dev"
    fi

    if ! mountpoint -q "$TARGET/proc"; then
        mount -t proc proc "$TARGET/proc"
        record_virtual_mount "$TARGET/proc"
    fi

    if ! mountpoint -q "$TARGET/sys"; then
        mount --rbind /sys "$TARGET/sys"
        mount --make-rslave "$TARGET/sys"
        record_virtual_mount "$TARGET/sys"
    fi

    if ! mountpoint -q "$TARGET/run"; then
        mount --rbind /run "$TARGET/run"
        mount --make-rslave "$TARGET/run"
        record_virtual_mount "$TARGET/run"
    fi

    # EFI variables are included by the recursive /sys bind when the live
    # environment was booted in UEFI mode.
}

cleanup_virtual_filesystems() {
    local index=0
    local destination=""

    [[ "$KEEP_VIRTUAL_MOUNTS" == yes ]] && return 0

    for ((index=${#VIRTUAL_MOUNTS[@]}-1; index>=0; index--)); do
        destination="${VIRTUAL_MOUNTS[$index]}"

        if mountpoint -q "$destination"; then
            umount -R "$destination" 2>/dev/null ||
                umount -l "$destination" 2>/dev/null ||
                warn "Could not fully unmount $destination"
        fi
    done
}

cleanup() {
    cleanup_virtual_filesystems

    if [[ -n "$SWAP_ENABLED_BY_SCRIPT" ]]; then
        swapoff "$SWAP_ENABLED_BY_SCRIPT" 2>/dev/null || true
    fi
}

trap cleanup EXIT

target_has_existing_layout() {
    findmnt -Rrn "$TARGET" 2>/dev/null | grep -q .
}

show_existing_layout() {
    log "Existing BFS mount layout"
    findmnt -R "$TARGET" || true

    if swapon --noheadings --show=NAME 2>/dev/null | grep -q .; then
        printf '\nActive swap:\n'
        swapon --show
    fi
}

validate_existing_root() {
    mountpoint -q "$TARGET" ||
        die "$TARGET exists but its root filesystem is not mounted."

    [[ -x "$TARGET/bin/bash" || -x "$TARGET/usr/bin/bash" ]] ||
        die "$TARGET does not look like a BFS root filesystem; bash is missing."
}

select_and_mount_layout() {
    local device=""
    local mountpoint=""

    select_partition ROOT_DEV "Root filesystem"
    mount_selected_device "$ROOT_DEV" "$TARGET"

    if ask_yes_no "Is a separate /boot filesystem being used?" no; then
        select_partition BOOT_DEV "Boot filesystem"
        mount_selected_device "$BOOT_DEV" "$TARGET/boot"
    fi

    printf '
Detected live-environment boot mode: %s
' "${BOOT_MODE^^}"
    if [[ "$BOOT_MODE" == bios ]]; then
        echo "Legacy BIOS mode detected; an EFI partition is usually not required."
    else
        echo "UEFI mode detected; mount an EFI System Partition if this BFS installation uses one."
    fi

    if ask_yes_no "Mount an EFI System Partition at /boot/efi?" no; then
        select_partition EFI_DEV "EFI System Partition"
        mount_selected_device "$EFI_DEV" "$TARGET/boot/efi"
    fi

    if ask_yes_no "Is swap being used?" no; then
        select_partition SWAP_DEV "Swap partition"

        if swapon --noheadings --show=NAME | grep -Fxq "$SWAP_DEV"; then
            echo "$SWAP_DEV is already active."
        else
            log "Enabling swap on $SWAP_DEV"
            swapon "$SWAP_DEV"
            SWAP_ENABLED_BY_SCRIPT="$SWAP_DEV"
        fi
    fi

    while ask_yes_no "Mount another filesystem such as /home, /var, or /srv?" no; do
        device=""
        mountpoint=""

        select_partition device "Additional filesystem"

        while true; do
            read -r -p "Mount point inside BFS, for example /var: " mountpoint

            if [[ "$mountpoint" == /* &&
                  "$mountpoint" != / &&
                  "$mountpoint" != /boot &&
                  "$mountpoint" != /boot/efi &&
                  "$mountpoint" != *'..'* ]]
            then
                break
            fi

            warn "Enter a safe absolute mount point such as /home, /var, or /srv."
        done

        EXTRA_DEVICES+=("$device")
        EXTRA_MOUNTPOINTS+=("$mountpoint")
        mount_selected_device "$device" "$TARGET$mountpoint"
    done
}

enter_chroot() {
    local shell_path="/bin/bash"
    local status=0

    [[ -x "$TARGET/bin/bash" ]] || shell_path="/usr/bin/bash"

    mount_virtual_filesystems

    log "Entering BFS chroot"
    printf 'Type exit to return to the live environment.\n\n'

    set +e
    chroot "$TARGET" /usr/bin/env -i \
        HOME=/root \
        TERM="${TERM:-linux}" \
        PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        LANG=C \
        LC_ALL=C \
        PS1='[BFS-CHROOT \u@\h \W]\$ ' \
        "$shell_path" --noprofile --norc
    status=$?
    set -e

    printf '\nExited BFS chroot'
    if ((status != 0)); then
        printf ' with status %d' "$status"
    fi
    printf '.\n'
}

main() {
    require_root
    require_commands
    detect_boot_mode

    mkdir -p "$TARGET"

    if target_has_existing_layout; then
        show_existing_layout
        validate_existing_root

        if ask_yes_no "Use the existing mounted BFS layout?" yes; then
            enter_chroot
            return 0
        fi

        die "Existing mounts must be unmounted manually before selecting a different layout."
    fi

    select_and_mount_layout
    validate_existing_root

    show_existing_layout
    enter_chroot
}

main "$@"
