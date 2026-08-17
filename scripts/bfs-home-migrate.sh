#!/usr/bin/env bash
#
# bfs-home-migrate-v7.sh
#
# Interactive BFS-Linux home-folder migration utility.
#
# Features:
#   1. Remove files supplied by /etc/skel from one or all home directories.
#   2. Back up one or all home directories with xz compression.
#   3. Restore a backup into /home or another home-root directory.
#   4. Optional verbose file listing and pv progress meter.
#
# Run as root:
#
#   sudo ./bfs-home-migrate.sh
#

set -Eeuo pipefail

PROGRAM_NAME="${0##*/}"
DEFAULT_HOME_ROOT="/home"

if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    INVOKING_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
    INVOKING_HOME="$HOME"
fi

[[ -n "$INVOKING_HOME" ]] || INVOKING_HOME="$HOME"

DEFAULT_ARCHIVE_DIR="$INVOKING_HOME/BFSOS/archives/home-folder-backup"
SKEL_DIR="/etc/skel"

TEMP_MOUNT=""
TEMP_LISTS=()
VERBOSE_TAR="no"
SHOW_PROGRESS="yes"
EXCLUDE_VOLATILE="yes"
EXCLUDE_GIT="no"
BACKUP_MODE="normal"
CUSTOM_EXCLUSION_LABELS=()
CUSTOM_EXCLUSION_PATTERNS=()
SSH_CONTROL_DIR=""
SSH_CONTROL_PATH=""

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

cleanup() {
    local file

    if [[ -n "$SSH_CONTROL_PATH" && -n "${SCP_HOST:-}" ]]; then
        ssh -o ControlPath="$SSH_CONTROL_PATH" -O exit "$SCP_HOST" \
            >/dev/null 2>&1 || true
    fi

    if [[ -n "$SSH_CONTROL_DIR" && -d "$SSH_CONTROL_DIR" ]]; then
        rm -rf -- "$SSH_CONTROL_DIR"
    fi

    for file in "${TEMP_LISTS[@]:-}"; do
        [[ -n "$file" ]] && rm -f -- "$file"
    done

    if [[ -n "$TEMP_MOUNT" && -d "$TEMP_MOUNT" ]]; then
        if mountpoint -q "$TEMP_MOUNT"; then
            umount "$TEMP_MOUNT" || warn "Could not unmount $TEMP_MOUNT"
        fi
        rmdir "$TEMP_MOUNT" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

require_commands() {
    local command_name
    local missing=0

    for command_name in "$@"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            printf 'Missing required command: %s\n' "$command_name" >&2
            missing=1
        fi
    done

    (( missing == 0 )) || die "Install the missing commands and try again."
}

require_root() {
    if (( EUID != 0 )); then
        die "Run this operation as root, for example: sudo ./$PROGRAM_NAME"
    fi
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local answer

    while true; do
        if [[ "$default" == "y" ]]; then
            read -r -p "$prompt [Y/n]: " answer
            answer="${answer:-y}"
        else
            read -r -p "$prompt [y/N]: " answer
            answer="${answer:-n}"
        fi

        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     echo "Please answer yes or no." ;;
        esac
    done
}

read_path_with_default() {
    local prompt="$1"
    local default="$2"
    local result

    read -r -p "$prompt [$default]: " result
    printf '%s\n' "${result:-$default}"
}

canonicalize_existing_dir() {
    local path="$1"
    [[ -d "$path" ]] || die "Directory does not exist: $path"
    realpath -- "$path"
}

normalize_directory_path() {
    local path="$1"

    [[ "$path" == /* ]] || path="/$path"

    while [[ "$path" != "/" && "$path" == */ ]]; do
        path="${path%/}"
    done

    printf '%s\n' "$path"
}

select_home_scope() {
    local home_root="$1"
    local choice
    local username
    local user_home

    echo
    echo "1) One user home folder"
    echo "2) All user home folders under $home_root"

    while true; do
        read -r -p "Choose [1-2]: " choice
        case "$choice" in
            1)
                read -r -p "Enter the user name or home-folder name: " username
                [[ -n "$username" ]] || {
                    echo "A user name is required."
                    continue
                }

                user_home="$home_root/$username"
                [[ -d "$user_home" ]] || {
                    echo "Home directory does not exist: $user_home"
                    continue
                }

                SELECTED_SCOPE="single"
                SELECTED_USER="$username"
                SELECTED_HOMES=("$user_home")
                return 0
                ;;
            2)
                mapfile -d '' SELECTED_HOMES < <(
                    find "$home_root" -mindepth 1 -maxdepth 1 -type d -print0 |
                    sort -z
                )

                if (( ${#SELECTED_HOMES[@]} == 0 )); then
                    echo "No home directories were found under $home_root."
                    continue
                fi

                SELECTED_SCOPE="all"
                SELECTED_USER=""
                return 0
                ;;
            *)
                echo "Please choose 1 or 2."
                ;;
        esac
    done
}

build_skel_relative_list() {
    local list_file

    [[ -d "$SKEL_DIR" ]] || die "$SKEL_DIR does not exist."

    list_file="$(mktemp)"
    TEMP_LISTS+=("$list_file")

    (
        cd "$SKEL_DIR"
        find . -mindepth 1 -print0 |
            while IFS= read -r -d '' item; do
                printf '%s\0' "${item#./}"
            done
    ) > "$list_file"

    printf '%s\n' "$list_file"
}

remove_skel_from_home() {
    local home_dir="$1"
    local skel_list="$2"
    local relative
    local target
    local removed=0

    while IFS= read -r -d '' relative; do
        target="$home_dir/$relative"

        if [[ -L "$target" || -f "$target" ]]; then
            rm -f -- "$target"
            printf 'Removed: %s\n' "$target"
            removed=1
        fi
    done < "$skel_list"

    while IFS= read -r -d '' relative; do
        target="$home_dir/$relative"

        if [[ -d "$target" && ! -L "$target" ]]; then
            rmdir -- "$target" 2>/dev/null && {
                printf 'Removed empty directory: %s\n' "$target"
                removed=1
            }
        fi
    done < <(
        tr '\0' '\n' < "$skel_list" |
        awk '{ print length, $0 }' |
        sort -rn |
        cut -d' ' -f2- |
        tr '\n' '\0'
    )

    if (( removed == 0 )); then
        printf 'No matching skel files found in %s\n' "$home_dir"
    fi
}

operation_remove_skel() {
    local home_root
    local skel_list
    local home_dir

    require_root
    require_commands find realpath sort awk cut

    home_root="$(read_path_with_default \
        "Location containing the user home folders" \
        "$DEFAULT_HOME_ROOT")"
    home_root="$(canonicalize_existing_dir "$home_root")"

    select_home_scope "$home_root"
    skel_list="$(build_skel_relative_list)"

    echo
    echo "The following home directories will be checked:"
    printf '  %s\n' "${SELECTED_HOMES[@]}"
    echo
    echo "Only paths also present under $SKEL_DIR will be removed."
    echo "Existing directories are removed only when empty."

    ask_yes_no "Continue removing matching skel files?" "n" || {
        echo "Cancelled."
        return
    }

    for home_dir in "${SELECTED_HOMES[@]}"; do
        echo
        echo "Processing $home_dir"
        remove_skel_from_home "$home_dir" "$skel_list"
    done

    echo
    echo "Skel-file removal completed."
}

directory_size_bytes() {
    local total=0
    local path
    local size

    for path in "$@"; do
        size="$(du -sb -- "$path" | awk '{print $1}')"
        total=$((total + size))
    done

    printf '%s\n' "$total"
}

human_size() {
    local bytes="$1"

    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec-i --suffix=B "$bytes"
    else
        printf '%s bytes\n' "$bytes"
    fi
}

available_bytes_local() {
    local path="$1"
    df -PB1 -- "$path" | awk 'NR == 2 {print $4}'
}

ensure_local_space() {
    local destination_dir="$1"
    local required_bytes="$2"
    local available_bytes
    local reserve_bytes

    available_bytes="$(available_bytes_local "$destination_dir")"
    reserve_bytes=$((required_bytes + required_bytes / 20 + 64 * 1024 * 1024))

    if (( available_bytes < reserve_bytes )); then
        printf 'Required conservative estimate: %s\n' \
            "$(human_size "$reserve_bytes")" >&2
        printf 'Available at destination:      %s\n' \
            "$(human_size "$available_bytes")" >&2
        die "Not enough free space at $destination_dir."
    fi
}

mount_device_destination() {
    local device="$1"
    local mount_dir

    require_root
    require_commands mount mountpoint umount

    [[ -b "$device" ]] || die "Not a block device: $device"

    mount_dir="$(mktemp -d /tmp/bfs-home-backup-mount.XXXXXX)"
    TEMP_MOUNT="$mount_dir"

    echo "Mounting $device at $mount_dir"
    mount "$device" "$mount_dir"
    MOUNTED_PATH="$mount_dir"
}

prompt_remote_directory() {
    local username
    local host
    local default_directory
    local directory

    while true; do
        read -r -p "Remote SSH username: " username
        [[ -n "$username" ]] || {
            echo "A username is required."
            continue
        }

        read -r -p "Remote hostname or IP address: " host
        [[ -n "$host" ]] || {
            echo "A hostname or IP address is required."
            continue
        }

        default_directory="/home/$username"
        directory="$(read_path_with_default \
            "Remote destination directory" \
            "$default_directory")"
        directory="$(normalize_directory_path "$directory")"

        SCP_HOST="$username@$host"
        SCP_PATH="$directory"
        BACKUP_DEST="$SCP_HOST:$SCP_PATH"
        return
    done
}

choose_backup_destination() {
    local choice
    local destination
    local device

    echo
    echo "Backup destination:"
    echo "1) Default BFS archive directory"
    echo "2) Local directory"
    echo "3) Block device mounted automatically"
    echo "4) Remote SSH destination (stream directly; no local temporary file)"

    while true; do
        read -r -p "Choose [1-4]: " choice
        case "$choice" in
            1)
                mkdir -p -- "$DEFAULT_ARCHIVE_DIR"
                BACKUP_DEST_TYPE="local"
                BACKUP_DEST="$(realpath -- "$DEFAULT_ARCHIVE_DIR")"
                return
                ;;
            2)
                read -r -p "Enter the destination directory: " destination
                [[ -n "$destination" ]] || {
                    echo "A destination is required."
                    continue
                }

                mkdir -p -- "$destination"
                BACKUP_DEST_TYPE="local"
                BACKUP_DEST="$(realpath -- "$destination")"
                return
                ;;
            3)
                read -r -p "Enter the device path, for example /dev/sdb1: " device
                [[ -n "$device" ]] || {
                    echo "A device path is required."
                    continue
                }

                mount_device_destination "$device"
                BACKUP_DEST_TYPE="local"
                BACKUP_DEST="$MOUNTED_PATH"
                return
                ;;
            4)
                prompt_remote_directory
                BACKUP_DEST_TYPE="scp"
                return
                ;;
            *)
                echo "Please choose 1, 2, 3, or 4."
                ;;
        esac
    done
}

split_scp_destination() {
    local destination="$1"

    SCP_HOST="${destination%%:*}"
    SCP_PATH="${destination#*:}"
    SCP_PATH="$(normalize_directory_path "$SCP_PATH")"

    [[ -n "$SCP_HOST" && -n "$SCP_PATH" ]] ||
        die "Invalid SSH destination: $destination"
}

start_ssh_master() {
    SSH_CONTROL_DIR="$(mktemp -d /tmp/bfs-home-ssh.XXXXXX)"
    SSH_CONTROL_PATH="$SSH_CONTROL_DIR/control"

    ssh \
        -o ControlMaster=yes \
        -o ControlPersist=600 \
        -o ControlPath="$SSH_CONTROL_PATH" \
        -Nf \
        "$SCP_HOST"
}

remote_ssh() {
    ssh -o ControlPath="$SSH_CONTROL_PATH" "$SCP_HOST" "$@"
}

ensure_remote_space() {
    local destination="$1"
    local required_bytes="$2"
    local available_bytes
    local reserve_bytes

    split_scp_destination "$destination"

    available_bytes="$(
        remote_ssh \
            "mkdir -p -- $(printf '%q' "$SCP_PATH") &&
             df -PB1 -- $(printf '%q' "$SCP_PATH") |
             awk 'NR == 2 {print \$4}'"
    )"

    [[ "$available_bytes" =~ ^[0-9]+$ ]] ||
        die "Could not determine free space at $destination."

    reserve_bytes=$((required_bytes + required_bytes / 20 + 64 * 1024 * 1024))

    if (( available_bytes < reserve_bytes )); then
        printf 'Required conservative estimate: %s\n' \
            "$(human_size "$reserve_bytes")" >&2
        printf 'Available on remote machine:   %s\n' \
            "$(human_size "$available_bytes")" >&2
        die "Not enough free space at $destination."
    fi
}

create_tar_exclude_file() {
    local home_root="$1"
    local skel_list="$2"
    shift 2
    local homes=("$@")
    local exclude_file
    local home_dir
    local home_name
    local relative

    exclude_file="$(mktemp)"
    TEMP_LISTS+=("$exclude_file")

    for home_dir in "${homes[@]}"; do
        home_name="${home_dir##*/}"

        while IFS= read -r -d '' relative; do
            printf '%s\n' "$home_name/$relative"
        done < "$skel_list"
    done > "$exclude_file"

    printf '%s\n' "$exclude_file"
}

append_volatile_excludes() {
    local exclude_file="$1"
    shift
    local home_dir
    local home_name

    for home_dir in "$@"; do
        home_name="${home_dir##*/}"

        cat >> "$exclude_file" <<EOF
$home_name/.cache
$home_name/.cache/*
$home_name/.gvfs
$home_name/.gvfs/*
$home_name/.var/app/*/cache
$home_name/.var/app/*/cache/*
$home_name/.var/app/*/.cache
$home_name/.var/app/*/.cache/*
EOF
    done
}

append_git_excludes() {
    local exclude_file="$1"
    shift
    local home_dir
    local home_name

    for home_dir in "$@"; do
        home_name="${home_dir##*/}"
        printf '%s\n' "$home_name/**/.git" "$home_name/**/.git/**" >> "$exclude_file"
    done
}

normalize_tar_status() {
    local status="$1"

    case "$status" in
        0)
            return 0
            ;;
        1)
            warn "Some files changed while tar was reading them."
            warn "The archive will still be verified before it is finalized."
            return 0
            ;;
        *)
            return "$status"
            ;;
    esac
}

run_tar_command() {
    local home_root="$1"
    local exclude_file="$2"
    shift 2

    local -a tar_items=("$@")
    local -a tar_options=(
        --acls
        --xattrs
        --numeric-owner
        --one-file-system
        --wildcards
        --wildcards-match-slash
    )
    local status

    [[ "$VERBOSE_TAR" == "yes" ]] && tar_options+=(-v)
    [[ -n "$exclude_file" ]] && tar_options+=(--exclude-from="$exclude_file")

    set +e
    tar \
        "${tar_options[@]}" \
        -C "$home_root" \
        -cf - \
        "${tar_items[@]}"
    status=$?
    set -e

    normalize_tar_status "$status"
}

unique_archive_path() {
    local directory="$1"
    local base_name="$2"
    local path="$directory/$base_name"
    local counter=1
    local stem="${base_name%.tar.xz}"

    while [[ -e "$path" || -e "$path.partial" ]]; do
        path="$directory/${stem}-${counter}.tar.xz"
        ((counter++))
    done

    printf '%s\n' "$path"
}

add_custom_exclusion() {
    local label="$1"
    shift
    local pattern

    CUSTOM_EXCLUSION_LABELS+=("$label")
    for pattern in "$@"; do
        CUSTOM_EXCLUSION_PATTERNS+=("$pattern")
    done
}

custom_exclusion_selected() {
    local label="$1"
    local current

    for current in "${CUSTOM_EXCLUSION_LABELS[@]:-}"; do
        [[ "$current" == "$label" ]] && return 0
    done

    return 1
}

append_custom_excludes() {
    local exclude_file="$1"
    shift
    local home_dir
    local home_name
    local pattern

    for home_dir in "$@"; do
        home_name="${home_dir##*/}"

        for pattern in "${CUSTOM_EXCLUSION_PATTERNS[@]:-}"; do
            printf '%s\n' "$home_name/$pattern" >> "$exclude_file"
        done
    done
}

show_custom_exclusion_review() {
    local label

    echo
    echo "Selected exclusions:"

    if (( ${#CUSTOM_EXCLUSION_LABELS[@]} == 0 )); then
        echo "  None"
        return
    fi

    for label in "${CUSTOM_EXCLUSION_LABELS[@]}"; do
        echo "  - $label"
    done
}

configure_custom_exclusions() {
    local selections
    local selection
    local custom_pattern
    local done_selecting="no"
    local -a requested=()

    CUSTOM_EXCLUSION_LABELS=()
    CUSTOM_EXCLUSION_PATTERNS=()

    while [[ "$done_selecting" == "no" ]]; do
        echo
        echo "Custom backup exclusions"
        echo
        echo "1) Cache directories"
        echo "   .cache, thumbnails, Flatpak application caches"
        echo "2) Trash"
        echo "   .local/share/Trash"
        echo "3) Git metadata"
        echo "   .git directories"
        echo "4) Downloads folder"
        echo "5) Virtual machines"
        echo "   VirtualBox VMs, libvirt images"
        echo "6) Steam and game installations"
        echo "7) Common build output"
        echo "   build, pkg, src, packages"
        echo "8) node_modules"
        echo "9) Browser caches"
        echo "10) Add a custom path or tar pattern"
        echo "11) Review exclusions"
        echo "12) Clear all selections"
        echo "13) Continue backup"
        echo
        read -r -p "Choose one or more numbers separated by spaces: " selections

        read -r -a requested <<< "$selections"

        for selection in "${requested[@]}"; do
            case "$selection" in
                1)
                    if ! custom_exclusion_selected "Cache directories"; then
                        add_custom_exclusion "Cache directories" \
                            ".cache" ".cache/**" \
                            ".thumbnails" ".thumbnails/**" \
                            ".var/app/*/cache" ".var/app/*/cache/**" \
                            ".var/app/*/.cache" ".var/app/*/.cache/**"
                    fi
                    ;;
                2)
                    if ! custom_exclusion_selected "Trash"; then
                        add_custom_exclusion "Trash" \
                            ".local/share/Trash" ".local/share/Trash/**"
                    fi
                    ;;
                3)
                    if ! custom_exclusion_selected "Git metadata"; then
                        add_custom_exclusion "Git metadata" \
                            "**/.git" "**/.git/**"
                    fi
                    ;;
                4)
                    if ! custom_exclusion_selected "Downloads folder"; then
                        add_custom_exclusion "Downloads folder" \
                            "Downloads" "Downloads/**"
                    fi
                    ;;
                5)
                    if ! custom_exclusion_selected "Virtual machines"; then
                        add_custom_exclusion "Virtual machines" \
                            "VirtualBox VMs" "VirtualBox VMs/**" \
                            ".VirtualBox" ".VirtualBox/**" \
                            ".local/share/libvirt/images" \
                            ".local/share/libvirt/images/**"
                    fi
                    ;;
                6)
                    if ! custom_exclusion_selected "Steam and game installations"; then
                        add_custom_exclusion "Steam and game installations" \
                            ".steam" ".steam/**" \
                            ".local/share/Steam" ".local/share/Steam/**" \
                            ".var/app/com.valvesoftware.Steam" \
                            ".var/app/com.valvesoftware.Steam/**"
                    fi
                    ;;
                7)
                    if ! custom_exclusion_selected "Common build output"; then
                        add_custom_exclusion "Common build output" \
                            "**/build" "**/build/**" \
                            "**/pkg" "**/pkg/**" \
                            "**/src" "**/src/**" \
                            "**/packages" "**/packages/**"
                    fi
                    ;;
                8)
                    if ! custom_exclusion_selected "node_modules"; then
                        add_custom_exclusion "node_modules" \
                            "**/node_modules" "**/node_modules/**"
                    fi
                    ;;
                9)
                    if ! custom_exclusion_selected "Browser caches"; then
                        add_custom_exclusion "Browser caches" \
                            ".mozilla/firefox/*/cache2" \
                            ".mozilla/firefox/*/cache2/**" \
                            ".config/google-chrome/*/Cache" \
                            ".config/google-chrome/*/Cache/**" \
                            ".config/chromium/*/Cache" \
                            ".config/chromium/*/Cache/**" \
                            ".cache/mozilla" ".cache/mozilla/**" \
                            ".cache/google-chrome" ".cache/google-chrome/**" \
                            ".cache/chromium" ".cache/chromium/**"
                    fi
                    ;;
                10)
                    echo
                    echo "Enter a path or GNU tar exclusion pattern relative to each home folder."
                    echo "Examples:"
                    echo "  Videos"
                    echo "  BFSOS/archives"
                    echo "  **/*.iso"
                    read -r -p "Custom path or pattern: " custom_pattern

                    if [[ -z "$custom_pattern" ]]; then
                        echo "No custom pattern added."
                    elif [[ "$custom_pattern" == /* || "$custom_pattern" == ../* ]]; then
                        echo "Use a path relative to the home folder, not an absolute path."
                    else
                        custom_pattern="${custom_pattern#./}"
                        add_custom_exclusion "Custom: $custom_pattern" "$custom_pattern"
                    fi
                    ;;
                11) show_custom_exclusion_review ;;
                12)
                    CUSTOM_EXCLUSION_LABELS=()
                    CUSTOM_EXCLUSION_PATTERNS=()
                    echo "All custom exclusions were cleared."
                    ;;
                13) done_selecting="yes" ;;
                *) echo "Ignoring invalid selection: $selection" ;;
            esac
        done
    done

    show_custom_exclusion_review
}

select_backup_mode() {
    local choice

    echo
    echo "Backup mode:"
    echo "1) Full"
    echo "   Include everything."
    echo "2) Normal (recommended)"
    echo "   Exclude volatile cache and runtime files."
    echo "3) Compact"
    echo "   Exclude volatile files and Git metadata directories (.git)."
    echo "4) Custom"
    echo "   Choose exactly which categories or paths to exclude."

    while true; do
        read -r -p "Choose [1-4]: " choice
        case "$choice" in
            1)
                BACKUP_MODE="full"
                EXCLUDE_VOLATILE="no"
                EXCLUDE_GIT="no"
                return
                ;;
            2)
                BACKUP_MODE="normal"
                EXCLUDE_VOLATILE="yes"
                EXCLUDE_GIT="no"
                return
                ;;
            3)
                BACKUP_MODE="compact"
                EXCLUDE_VOLATILE="yes"
                EXCLUDE_GIT="yes"
                return
                ;;
            4)
                BACKUP_MODE="custom"
                EXCLUDE_VOLATILE="no"
                EXCLUDE_GIT="no"
                configure_custom_exclusions
                return
                ;;
            *) echo "Please choose 1, 2, 3, or 4." ;;
        esac
    done
}

configure_backup_display() {
    if ask_yes_no "Show each file as it is added to the archive?" "n"; then
        VERBOSE_TAR="yes"
    else
        VERBOSE_TAR="no"
    fi

    if command -v pv >/dev/null 2>&1; then
        if ask_yes_no "Show an overall progress meter?" "y"; then
            SHOW_PROGRESS="yes"
        else
            SHOW_PROGRESS="no"
        fi
    else
        SHOW_PROGRESS="no"
        warn "pv is not installed; the overall progress meter is unavailable."
        warn "Install the 'pv' package to enable it."
    fi
}

run_tar_stream() {
    local home_root="$1"
    local exclude_file="$2"
    local source_size="$3"
    shift 3

    local -a tar_items=("$@")

    if [[ "$SHOW_PROGRESS" == "yes" ]]; then
        run_tar_command \
            "$home_root" \
            "$exclude_file" \
            "${tar_items[@]}" |
        pv \
            --size "$source_size" \
            --timer \
            --eta \
            --rate \
            --bytes
    else
        run_tar_command \
            "$home_root" \
            "$exclude_file" \
            "${tar_items[@]}"
    fi
}

operation_backup() {
    local home_root
    local include_skel="yes"
    local skel_list=""
    local exclude_file=""
    local source_size
    local date_stamp
    local archive_name
    local archive_path
    local partial_archive
    local remote_archive
    local remote_temp
    local home_dir
    local start_epoch
    local end_epoch
    local elapsed
    local final_size
    local checksum
    local average_rate
    local -a tar_items=()

    require_root
    require_commands tar xz du df find realpath awk sort ssh scp sha256sum stat

    home_root="$(read_path_with_default \
        "Location containing the user home folders" \
        "$DEFAULT_HOME_ROOT")"
    home_root="$(canonicalize_existing_dir "$home_root")"

    select_home_scope "$home_root"

    if ask_yes_no "Include files supplied by $SKEL_DIR in the backup?" "y"; then
        include_skel="yes"
    else
        include_skel="no"
        skel_list="$(build_skel_relative_list)"
        exclude_file="$(create_tar_exclude_file \
            "$home_root" "$skel_list" "${SELECTED_HOMES[@]}")"
    fi

    select_backup_mode
    configure_backup_display

    if [[ "$EXCLUDE_VOLATILE" == "yes" ]]; then
        if [[ -z "$exclude_file" ]]; then
            exclude_file="$(mktemp)"
            TEMP_LISTS+=("$exclude_file")
        fi

        append_volatile_excludes "$exclude_file" "${SELECTED_HOMES[@]}"
    fi

    if [[ "$EXCLUDE_GIT" == "yes" ]]; then
        if [[ -z "$exclude_file" ]]; then
            exclude_file="$(mktemp)"
            TEMP_LISTS+=("$exclude_file")
        fi

        append_git_excludes "$exclude_file" "${SELECTED_HOMES[@]}"
    fi

    if [[ "$BACKUP_MODE" == "custom" && ${#CUSTOM_EXCLUSION_PATTERNS[@]} -gt 0 ]]; then
        if [[ -z "$exclude_file" ]]; then
            exclude_file="$(mktemp)"
            TEMP_LISTS+=("$exclude_file")
        fi

        append_custom_excludes "$exclude_file" "${SELECTED_HOMES[@]}"
    fi

    choose_backup_destination

    echo
    echo "Scanning selected home folder(s)..."
    source_size="$(directory_size_bytes "${SELECTED_HOMES[@]}")"
    echo "Uncompressed source size: $(human_size "$source_size")"

    if [[ "$BACKUP_DEST_TYPE" == "local" ]]; then
        ensure_local_space "$BACKUP_DEST" "$source_size"
    else
        split_scp_destination "$BACKUP_DEST"
        echo "Opening shared SSH connection..."
        start_ssh_master
        ensure_remote_space "$BACKUP_DEST" "$source_size"
    fi

    date_stamp="$(date '+%Y-%m-%d')"

    if [[ "$SELECTED_SCOPE" == "single" ]]; then
        archive_name="home-folder-backup-${SELECTED_USER}-${date_stamp}.tar.xz"
    else
        archive_name="home-folder-backup-${date_stamp}.tar.xz"
    fi

    for home_dir in "${SELECTED_HOMES[@]}"; do
        tar_items+=("${home_dir##*/}")
    done

    echo
    echo "Home root:          $home_root"
    echo "Included folders:"
    printf '  %s\n' "${SELECTED_HOMES[@]}"
    echo "Include skel files: $include_skel"
    echo "Backup mode:        $BACKUP_MODE"
    echo "Exclude volatile:   $EXCLUDE_VOLATILE"
    echo "Exclude .git:       $EXCLUDE_GIT"
    if [[ "$BACKUP_MODE" == "custom" ]]; then
        show_custom_exclusion_review
    fi
    echo "Verbose file list:  $VERBOSE_TAR"
    echo "Progress meter:     $SHOW_PROGRESS"
    echo "Archive name:       $archive_name"
    echo "Destination:        $BACKUP_DEST"
    echo
    echo "The archive stores paths relative to $home_root and preserves"
    echo "permissions, ownership, ACLs, extended attributes, and hard links."

    ask_yes_no "Create this backup?" "y" || {
        echo "Cancelled."
        return
    }

    start_epoch="$(date +%s)"

    if [[ "$BACKUP_DEST_TYPE" == "local" ]]; then
        archive_path="$(unique_archive_path "$BACKUP_DEST" "$archive_name")"
        partial_archive="$archive_path.partial"

        rm -f -- "$partial_archive"

        echo
        echo "Creating compressed archive:"
        echo "  $partial_archive"

        run_tar_stream \
            "$home_root" \
            "$exclude_file" \
            "$source_size" \
            "${tar_items[@]}" |
        xz -9e -T0 > "$partial_archive"

        echo
        echo "Verifying archive..."
        xz -t -- "$partial_archive"
        tar -tJf "$partial_archive" >/dev/null

        echo "Finalizing archive..."
        mv -- "$partial_archive" "$archive_path"

        end_epoch="$(date +%s)"
        elapsed=$((end_epoch - start_epoch))
        final_size="$(stat -c '%s' "$archive_path")"
        checksum="$(sha256sum "$archive_path" | awk '{print $1}')"
        average_rate=$((elapsed > 0 ? final_size / elapsed : final_size))

        echo
        echo "Backup completed successfully."
        echo
        echo "Archive:"
        echo "  $archive_path"
        echo
        echo "Original size:      $(human_size "$source_size")"
        echo "Compressed size:    $(human_size "$final_size")"
        echo "Elapsed time:       ${elapsed}s"
        echo "Average write rate: $(human_size "$average_rate")/s"
        echo "SHA256:"
        echo "  $checksum"
    else
        remote_ssh \
            "mkdir -p -- $(printf '%q' "$SCP_PATH")"

        remote_archive="$SCP_PATH/$archive_name"
        remote_temp="$remote_archive.partial"

        echo
        echo "Streaming archive directly to:"
        echo "  $SCP_HOST:$remote_temp"
        echo "No temporary local archive will be created."

        remote_ssh \
            "rm -f -- $(printf '%q' "$remote_temp")"

        run_tar_stream \
            "$home_root" \
            "$exclude_file" \
            "$source_size" \
            "${tar_items[@]}" |
        xz -9e -T0 |
        remote_ssh \
            "cat > $(printf '%q' "$remote_temp")"

        echo
        echo "Verifying and finalizing remote archive..."
        remote_ssh \
            "xz -t -- $(printf '%q' "$remote_temp") &&
             tar -tJf $(printf '%q' "$remote_temp") >/dev/null &&
             mv -- $(printf '%q' "$remote_temp") $(printf '%q' "$remote_archive")"

        end_epoch="$(date +%s)"
        elapsed=$((end_epoch - start_epoch))
        final_size="$(remote_ssh "stat -c '%s' $(printf '%q' "$remote_archive")")"
        checksum="$(remote_ssh "sha256sum $(printf '%q' "$remote_archive") | awk '{print \$1}'")"
        average_rate=$((elapsed > 0 ? final_size / elapsed : final_size))

        echo
        echo "Backup completed successfully."
        echo
        echo "Archive:"
        echo "  $SCP_HOST:$remote_archive"
        echo
        echo "Original size:      $(human_size "$source_size")"
        echo "Compressed size:    $(human_size "$final_size")"
        echo "Elapsed time:       ${elapsed}s"
        echo "Average transfer:   $(human_size "$average_rate")/s"
        echo "SHA256:"
        echo "  $checksum"
    fi
}

choose_restore_source() {
    local choice
    local source_path
    local device
    local remote_username
    local remote_host
    local remote_path
    local remote_size

    echo
    echo "Backup source:"
    echo "1) Default BFS archive directory"
    echo "2) Local directory or archive file"
    echo "3) Block device mounted automatically"
    echo "4) SSH stream from another machine (no local temporary file)"

    while true; do
        read -r -p "Choose [1-4]: " choice
        case "$choice" in
            1)
                [[ -d "$DEFAULT_ARCHIVE_DIR" ]] || {
                    echo "Default archive directory does not exist:"
                    echo "  $DEFAULT_ARCHIVE_DIR"
                    continue
                }

                RESTORE_SOURCE_TYPE="local"
                RESTORE_SOURCE="$DEFAULT_ARCHIVE_DIR"
                return
                ;;
            2)
                read -r -p "Enter the archive file or directory: " source_path
                [[ -e "$source_path" ]] || {
                    echo "Path does not exist: $source_path"
                    continue
                }

                RESTORE_SOURCE_TYPE="local"
                RESTORE_SOURCE="$(realpath -- "$source_path")"
                return
                ;;
            3)
                read -r -p "Enter the device path, for example /dev/sdb1: " device
                [[ -n "$device" ]] || {
                    echo "A device path is required."
                    continue
                }

                mount_device_destination "$device"
                RESTORE_SOURCE_TYPE="local"
                RESTORE_SOURCE="$MOUNTED_PATH"
                return
                ;;
            4)
                read -r -p "Remote SSH username: " remote_username
                read -r -p "Remote hostname or IP address: " remote_host
                read -r -p "Remote archive path: " remote_path

                [[ -n "$remote_username" && -n "$remote_host" && -n "$remote_path" ]] || {
                    echo "Username, host, and archive path are required."
                    continue
                }

                [[ "$remote_path" == *.tar.xz ]] || {
                    echo "Remote archive must end in .tar.xz"
                    continue
                }

                SCP_HOST="$remote_username@$remote_host"
                SCP_PATH="$remote_path"

                echo "Opening shared SSH connection..."
                start_ssh_master

                remote_size="$(
                    remote_ssh \
                        "test -f -- $(printf '%q' "$SCP_PATH") &&
                         stat -c '%s' -- $(printf '%q' "$SCP_PATH")"
                )"

                [[ "$remote_size" =~ ^[0-9]+$ ]] || {
                    echo "Remote archive does not exist or its size could not be determined:"
                    echo "  $SCP_HOST:$SCP_PATH"
                    continue
                }

                RESTORE_SOURCE_TYPE="ssh"
                RESTORE_SOURCE="$SCP_HOST:$SCP_PATH"
                REMOTE_ARCHIVE_SIZE="$remote_size"
                SELECTED_ARCHIVE="$RESTORE_SOURCE"

                echo "Remote archive detected:"
                echo "  $RESTORE_SOURCE"
                echo "No temporary local archive will be created."
                return
                ;;
            *)
                echo "Please choose 1, 2, 3, or 4."
                ;;
        esac
    done
}

select_archive_file() {
    local source="$1"
    local -a archives=()
    local index

    if [[ -f "$source" ]]; then
        [[ "$source" == *.tar.xz ]] ||
            die "Selected file is not a .tar.xz archive: $source"
        SELECTED_ARCHIVE="$source"
        return
    fi

    mapfile -d '' archives < <(
        find "$source" -maxdepth 1 -type f \
            -name 'home-folder-backup-*.tar.xz' \
            -print0 |
        sort -z
    )

    case "${#archives[@]}" in
        0)
            die "No home-folder-backup-*.tar.xz files found in $source."
            ;;
        1)
            SELECTED_ARCHIVE="${archives[0]}"
            echo "Detected archive: $SELECTED_ARCHIVE"
            ;;
        *)
            echo
            echo "Available backups:"
            for index in "${!archives[@]}"; do
                printf '%d) %s\n' "$((index + 1))" "${archives[$index]}"
            done

            while true; do
                read -r -p "Choose an archive [1-${#archives[@]}]: " index

                if [[ "$index" =~ ^[0-9]+$ ]] &&
                   (( index >= 1 && index <= ${#archives[@]} )); then
                    SELECTED_ARCHIVE="${archives[$((index - 1))]}"
                    return
                fi

                echo "Invalid selection."
            done
            ;;
    esac
}

stream_selected_archive() {
    if [[ "$RESTORE_SOURCE_TYPE" == "ssh" ]]; then
        remote_ssh "cat -- $(printf '%q' "$SCP_PATH")"
    else
        cat -- "$SELECTED_ARCHIVE"
    fi
}

verify_archive_and_collect_top_levels() {
    local top_level_file="$1"
    local stream_status
    local tar_status
    local awk_status

    : > "$top_level_file"

    set +e
    stream_selected_archive |
        tar -tJf - |
        awk -F/ '
            function unsafe_path(path) {
                return (
                    path ~ /^\// ||
                    path ~ /^\.\.\// ||
                    path ~ /\/\.\.\// ||
                    path ~ /\/\.\.$/
                )
            }

            NF {
                if (unsafe_path($0)) {
                    printf "ERROR: Archive contains an unsafe path: %s\n", $0 > "/dev/stderr"
                    exit 2
                }

                if (!seen[$1]++ && top_count < 30) {
                    print "  " $1
                    top_count++
                }
            }
        ' > "$top_level_file"

    stream_status=${PIPESTATUS[0]}
    tar_status=${PIPESTATUS[1]}
    awk_status=${PIPESTATUS[2]}
    set -e

    if (( awk_status != 0 )); then
        rm -f -- "$top_level_file"
        die "Archive path validation failed."
    fi

    if (( stream_status != 0 )); then
        rm -f -- "$top_level_file"
        die "Could not read the selected archive."
    fi

    if (( tar_status != 0 )); then
        rm -f -- "$top_level_file"
        die "Archive integrity or tar readability test failed."
    fi

    if [[ ! -s "$top_level_file" ]]; then
        rm -f -- "$top_level_file"
        die "Archive contains no restorable entries."
    fi
}

operation_restore() {
    local restore_root
    local archive_size
    local existing_policy
    local verify_choice
    local verification_performed="no"
    local top_level_file=""
    local -a tar_options=()

    require_root
    require_commands tar xz df find realpath awk sort ssh scp

    choose_restore_source

    if [[ "$RESTORE_SOURCE_TYPE" == "local" ]]; then
        select_archive_file "$RESTORE_SOURCE"
    fi

    echo
    echo "Archive verification:"
    echo "1) Verify archive integrity before restoring (recommended)"
    echo "2) Skip integrity test and restore immediately"
    echo "3) Cancel"

    while true; do
        read -r -p "Choose [1-3]: " verify_choice
        case "$verify_choice" in
            1)
                echo "Testing archive integrity and validating paths..."
                top_level_file="$(mktemp)"
                TEMP_LISTS+=("$top_level_file")
                verify_archive_and_collect_top_levels \
                    "$SELECTED_ARCHIVE" \
                    "$top_level_file"
                verification_performed="yes"
                echo "Archive verification completed successfully."
                break
                ;;
            2)
                echo "Skipping archive integrity and path-safety tests."
                break
                ;;
            3)
                echo "Cancelled."
                return
                ;;
            *)
                echo "Please choose 1, 2, or 3."
                ;;
        esac
    done

    restore_root="$(read_path_with_default \
        "Restore home folders into" \
        "$DEFAULT_HOME_ROOT")"

    mkdir -p -- "$restore_root"
    restore_root="$(realpath -- "$restore_root")"

    if [[ "$RESTORE_SOURCE_TYPE" == "ssh" ]]; then
        archive_size="$REMOTE_ARCHIVE_SIZE"
    else
        archive_size="$(stat -c '%s' "$SELECTED_ARCHIVE")"
    fi
    ensure_local_space "$restore_root" "$archive_size"

    echo
    echo "Archive:      $SELECTED_ARCHIVE"
    echo "Restore root: $restore_root"
    echo
    echo "Top-level archive contents:"
    if [[ "$verification_performed" == "yes" ]]; then
        cat -- "$top_level_file"
    else
        echo "  Not inspected because archive verification was skipped."
    fi

    echo
    echo "Existing-file behavior:"
    echo "1) Overwrite existing files"
    echo "2) Keep existing files and restore only missing files"
    echo "3) Cancel"

    while true; do
        read -r -p "Choose [1-3]: " existing_policy
        case "$existing_policy" in
            1)
                break
                ;;
            2)
                tar_options+=(--skip-old-files)
                break
                ;;
            3)
                echo "Cancelled."
                return
                ;;
            *)
                echo "Please choose 1, 2, or 3."
                ;;
        esac
    done

    echo
    warn "Restoration can overwrite data under $restore_root."

    ask_yes_no "Proceed with restoration?" "n" || {
        echo "Cancelled."
        return
    }

    if [[ "$RESTORE_SOURCE_TYPE" == "ssh" ]]; then
        echo
        echo "Streaming archive directly from:"
        echo "  $RESTORE_SOURCE"
        echo "No temporary local archive will be created."

        stream_selected_archive |
            tar \
                --acls \
                --xattrs \
                --numeric-owner \
                --same-owner \
                --same-permissions \
                "${tar_options[@]}" \
                -C "$restore_root" \
                -xJf -
    else
        tar \
            --acls \
            --xattrs \
            --numeric-owner \
            --same-owner \
            --same-permissions \
            "${tar_options[@]}" \
            -C "$restore_root" \
            -xJf "$SELECTED_ARCHIVE"
    fi

    echo
    echo "Restore completed successfully into:"
    echo "  $restore_root"
}

show_menu() {
    echo
    echo "BFS-Linux Home Migration Utility"
    echo "================================"
    echo "1) Remove /etc/skel files from home folder(s)"
    echo "2) Back up home folder(s)"
    echo "3) Restore a home-folder backup"
    echo "4) Quit"
    echo
}

main() {
    local choice

    while true; do
        show_menu
        read -r -p "Choose [1-4]: " choice

        case "$choice" in
            1) operation_remove_skel ;;
            2) operation_backup ;;
            3) operation_restore ;;
            4)
                echo "Goodbye."
                exit 0
                ;;
            *)
                echo "Please choose 1, 2, 3, or 4."
                ;;
        esac
    done
}

main "$@"
