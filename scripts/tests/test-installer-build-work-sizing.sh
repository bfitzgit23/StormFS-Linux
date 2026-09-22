#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
INSTALLER="$ROOT/scripts/install-bfs-menu-v50-r72-tracker-maintenance.sh"

# Extract exactly the implementation under test without sourcing the full
# interactive/root installer.
func=$(awk '
  /^recommended_build_tmpfs_size\(\) \{/ {on=1}
  on {print}
  on && /^}$/ {exit}
' "$INSTALLER")
[ -n "$func" ] || { echo "unable to extract recommended_build_tmpfs_size" >&2; exit 1; }
eval "$func"

check() {
    local ram=$1 expected=$2 got
    physical_ram_gib() { printf "%s\n" "$ram"; }
    got=$(recommended_build_tmpfs_size)
    [ "$got" = "$expected" ] || {
        echo "RAM ${ram}GiB: expected $expected, got $got" >&2
        exit 1
    }
}

check 1 disabled
check 15 disabled
check 16 8G
check 31 8G
check 32 16G
check 47 16G
check 48 32G
check 61 32G
check 95 32G
check 96 64G
check 191 64G
check 192 96G
check 512 96G

grep -q 'Auto (recommended:' "$INSTALLER"
grep -q 'Disk-backed' "$INSTALLER"
grep -q 'Custom tmpfs size' "$INSTALLER"

echo "installer build-work sizing regression: PASS"
