#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# BFS Linux - Sync Installed Ports Back to Git Repository
###############################################################################

if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    USER_NAME="$SUDO_USER"
    USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
    USER_NAME="${USER:-root}"
    USER_HOME="$HOME"
fi

REPO_ROOT="$USER_HOME/BFSOS"
SRC_PORTS="/usr/ports"
DST_PORTS="$REPO_ROOT/ports"
HTTPUP_REPGEN="/usr/bin/httpup-repgen"

echo "==========================================="
echo " BFS Linux Ports Synchronization Utility"
echo "==========================================="
echo

# Verify directories exist
[ -d "$REPO_ROOT" ] || {
    echo "ERROR: $REPO_ROOT not found."
    exit 1
}

[ -d "$SRC_PORTS" ] || {
    echo "ERROR: $SRC_PORTS not found."
    exit 1
}

[ -d "$DST_PORTS" ] || {
    echo "ERROR: $DST_PORTS not found."
    exit 1
}

[ -x "$HTTPUP_REPGEN" ] || {
    echo "ERROR: $HTTPUP_REPGEN not found."
    exit 1
}

echo "Repository: $REPO_ROOT"
echo

echo "Updating REPO files..."

find "$SRC_PORTS" -mindepth 1 -maxdepth 1 -type d | while read -r repo
do
    echo "  $(basename "$repo")"
    (
        cd "$repo"
        "$HTTPUP_REPGEN"
    )
done

echo
echo "Removing existing repository ports..."

find "$DST_PORTS" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

echo
echo "Copying updated ports..."

cp -a "$SRC_PORTS"/. "$DST_PORTS"/

echo
echo "Removing httpup state files..."

find "$DST_PORTS" -type f \
    \( -name '.httpup-repo.current' -o -name '.httpup-urlinfo' \) \
    -delete

echo
echo "Restoring ownership..."

chown -R "$USER_NAME:$(id -gn "$USER_NAME")" "$DST_PORTS"

echo
echo "Done."
echo
echo "Repository ports have been synchronized successfully."
echo
echo "Next steps:"
echo "  cd $REPO_ROOT"
echo "  git status"
echo "  ./scripts/git-update-bfsos.sh"
