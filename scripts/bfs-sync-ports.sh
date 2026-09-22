#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
    USER_NAME="$SUDO_USER"
    USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
    USER_NAME="${USER:-root}"
    USER_HOME="$HOME"
fi

REPO_ROOT="$USER_HOME/BFSOS"
SRC_PORTS=/usr/ports
DST_PORTS="$REPO_ROOT/ports"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ -d "$REPO_ROOT" ]] || die "$REPO_ROOT not found"
[[ -d "$SRC_PORTS" ]] || die "$SRC_PORTS not found"
[[ -d "$DST_PORTS" ]] || die "$DST_PORTS not found"

echo "Synchronizing installed /usr/ports back into $DST_PORTS"
echo "BFSOS collections are Git-backed; HttpUp REPO metadata is not generated."

for collection in compat-32 compiz contrib core gnome iso lxqt opt plasma xfce xorg; do
    [[ -d "$SRC_PORTS/$collection" ]] || continue
    rm -rf "$DST_PORTS/$collection"
    cp -a "$SRC_PORTS/$collection" "$DST_PORTS/$collection"
done

find "$DST_PORTS" -type f \( -name '.httpup-repo.current' -o -name '.httpup-urlinfo' -o -name REPO \) -delete
chown -R "$USER_NAME:$(id -gn "$USER_NAME")" "$DST_PORTS"

echo "Done. Review with: cd $REPO_ROOT && git status"
