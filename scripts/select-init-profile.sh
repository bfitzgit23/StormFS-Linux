#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIG=${BFS_INIT_CONFIG:-$ROOT/.bfs-init-profile}
choice=${1:-}

if [ -z "$choice" ] && [ -t 0 ]; then
    printf '%s\n' 'Select BFSOS init system:'
    printf '%s\n' '  1) openrc   (default)' '  2) sysvinit'
    printf 'Choice [1-2]: '
    IFS= read -r choice
fi
case "$choice" in
    ''|1|openrc) choice=openrc ;;
    2|sysvinit|sysv) choice=sysvinit ;;
    *)
        printf 'Usage: %s [openrc|sysvinit]\n' "$0" >&2
        printf 'systemd has been removed from StormFS; OpenRC is the default.\n' >&2
        exit 2
        ;;
esac
printf 'BFS_INIT_SYSTEM=%s\n' "$choice" > "$CONFIG"
printf 'Selected init system: %s\nConfiguration: %s\n' "$choice" "$CONFIG"
