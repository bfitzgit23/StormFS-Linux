#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

# Package hooks may prepare accounts/configuration, but may not activate a
# display manager as an install/update side effect.
for hook in \
    ports/plasma/sddm/post-install \
    ports/plasma/plasma-login-manager/post-install
do
    if grep -Eq 'systemctl[[:space:]]+(enable|enable[[:space:]]+--now|start)[[:space:]]|bfs-display-manager[[:space:]]+(sddm|plasmalogin)' "$hook"; then
        echo "display-manager policy violation in $hook" >&2
        exit 1
    fi
done

selector=ports/plasma/plasma-login-manager/bfs-display-manager
grep -Fq "printf '%s' 'unselected'" "$selector"
grep -Fq 'systemctl enable --force "$unit"' "$selector"  # explicit admin action remains supported

grep -Fq 'no display manager explicitly selected' scripts/bfs-desktop-integration-check.sh

echo "display-manager activation policy regression: PASS"
