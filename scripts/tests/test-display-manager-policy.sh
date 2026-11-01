#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

# Package hooks may prepare accounts and configuration, but must not activate a
# display manager as an install or update side effect. Under OpenRC that means
# no runlevel enablement and no service start from a package hook.
for hook in     ports/plasma/sddm/post-install     ports/plasma/plasma-login-manager/post-install
do
    if grep -Eq 'rc-update[[:space:]]+add|rc-service[[:space:]]+[A-Za-z0-9_.-]+[[:space:]]+(start|restart)|bfs-display-manager[[:space:]]+(sddm|plasmalogin)' "$hook"; then
        echo "display-manager policy violation in $hook" >&2
        exit 1
    fi
done

selector=ports/plasma/plasma-login-manager/bfs-display-manager
grep -Fq 'unselected' "$selector"
grep -Fq 'rc-update add "$unit" default' "$selector"  # explicit admin action remains supported
if grep -Eq 'systemctl|/etc/systemd' "$selector"; then
    echo "display-manager selector still references systemd" >&2
    exit 1
fi

grep -Fq 'no display manager explicitly selected' scripts/bfs-desktop-integration-check.sh

echo 'display-manager policy: PASS'
