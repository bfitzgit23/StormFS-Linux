#!/usr/bin/env bash
#
# generate-config.sh
#
# Generate ports/core/linux/config from the running system's kernel config.
# Run this manually from the Linux port directory before building the kernel.
#

set -Eeuo pipefail

PORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$PORT_DIR/config"
BACKUP_FILE="$PORT_DIR/config.backup"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

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

require_commands() {
    local command_name=""

    for command_name in cp gzip grep sed uname; do
        command -v "$command_name" >/dev/null 2>&1 ||
            die "Missing required command: $command_name"
    done
}

find_host_config() {
    local host_release=""
    local candidate=""

    host_release="$(uname -r)"

    if [[ -r /proc/config.gz ]]; then
        printf '%s\n' /proc/config.gz
        return 0
    fi

    for candidate in \
        "/boot/config-$host_release" \
        "/usr/lib/modules/$host_release/build/.config" \
        "/lib/modules/$host_release/build/.config"
    do
        if [[ -r "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

copy_host_config() {
    local source_config="$1"
    local destination="$2"

    case "$source_config" in
        *.gz)
            gzip -dc "$source_config" > "$destination"
            ;;
        *)
            cp "$source_config" "$destination"
            ;;
    esac
}

force_bfs_identity() {
    local config="$1"

    sed -i \
        -e '/^CONFIG_LOCALVERSION=/d' \
        -e '/^CONFIG_LOCALVERSION_AUTO=/d' \
        -e '/^# CONFIG_LOCALVERSION_AUTO is not set$/d' \
        "$config"

    cat >> "$config" <<'EOF'

CONFIG_LOCALVERSION="-BFS-Linux"
# CONFIG_LOCALVERSION_AUTO is not set
EOF
}

main() {
    local host_config=""
    local host_release=""

    require_commands

    host_release="$(uname -r)"
    host_config="$(find_host_config)" ||
        die "No kernel configuration was found for the running kernel: $host_release"

    echo "BFS Linux kernel config generator"
    echo "================================="
    echo
    echo "Running kernel: $host_release"
    echo "Source config:  $host_config"
    echo "Destination:    $CONFIG_FILE"
    echo

    if [[ -f "$CONFIG_FILE" ]]; then
        if ! ask_yes_no "Replace the existing BFS kernel config?" no; then
            echo "Existing config left unchanged."
            exit 0
        fi

        cp "$CONFIG_FILE" "$BACKUP_FILE"
        echo "Backup created:"
        echo "  $BACKUP_FILE"
        echo
    fi

    copy_host_config "$host_config" "$CONFIG_FILE"
    force_bfs_identity "$CONFIG_FILE"

    grep -q '^CONFIG_LOCALVERSION="-BFS-Linux"$' "$CONFIG_FILE" ||
        die "Failed to set CONFIG_LOCALVERSION."

    grep -q '^# CONFIG_LOCALVERSION_AUTO is not set$' "$CONFIG_FILE" ||
        die "Failed to disable CONFIG_LOCALVERSION_AUTO."

    echo "Generated BFS kernel configuration:"
    echo "  $CONFIG_FILE"
    echo
    echo "The config contains the running system's hardware support."
    echo "The Pkgfile will run olddefconfig and enforce the required"
    echo "BFS/LFS kernel options during the next build."
    echo
    echo "Next steps:"
    echo "  rm -f \"$PORT_DIR/.md5sum\" \"$PORT_DIR/.footprint\""
    echo "  cd \"$PORT_DIR\""
    echo "  pkgmk -d"
    echo "  pkgmk -i"
}

main "$@"
