#!/bin/bash
# BFSOS maintained-tree upstream version audit v10.
# compat-32 is version-synchronized against native ports by multilibvercheck.sh.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAMP=$(date +%Y%m%d-%H%M%S)
LOG=${1:-"$ROOT/bfs-maintained-port-version-audit-$STAMP.log"}
TSV=${2:-"${LOG%.log}.tsv"}

export REPO="$ROOT/ports/core $ROOT/ports/opt $ROOT/ports/xorg $ROOT/ports/plasma $ROOT/ports/gnome $ROOT/ports/lxqt $ROOT/ports/xfce $ROOT/ports/compiz $ROOT/ports/contrib"

echo "BFSOS maintained-port online version audit v10"
echo "Trees: core opt xorg plasma gnome lxqt xfce compiz contrib"
echo "Excluded from online provider audit: compat-32 (checked against native counterparts separately)"
echo "Safety: read-only; checker is read-only; reviewed UPDATE rows can be applied with scripts/bfs-maintained-port-updater.py"
echo "Log: $LOG"
echo "TSV: $TSV"
echo

set +e
"$ROOT/scripts/checkupdate.sh" --jobs "${BFS_AUDIT_JOBS:-10}" --timeout "${BFS_AUDIT_TIMEOUT:-10}" --tsv "$TSV" 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}
set -e

echo
echo "Audit saved to: $LOG"
echo "Machine-readable results: $TSV"
echo "Only UPDATE rows are verified update candidates; UNVERIFIABLE rows require a provider override or manual upstream review."
exit "$status"
