#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${BFSOS_REPO_ROOT:-$HOME/BFSOS}"
REMOTE_HTTPS="https://codeberg.org/bmadonnaster/BFSOS.git"
REMOTE_SSH="git@codeberg.org:bmadonnaster/BFSOS.git"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ -d "$REPO_ROOT/.git" ]] || die "$REPO_ROOT is not a Git checkout"
[[ -d "$REPO_ROOT/ports" ]] || die "$REPO_ROOT/ports is missing"
command -v git >/dev/null 2>&1 || die "git is not installed"

# BFSOS ports now synchronize through Git itself. REPO/.httpup state belongs
# only to legacy HttpUp publication and must not be regenerated for BFSOS.
find "$REPO_ROOT/ports" -type f \( -name '.httpup-repo.current' -o -name '.httpup-urlinfo' -o -name REPO \) -delete

remote="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
case "$remote" in
    git@codeberg.org:*|ssh://git@codeberg.org/*) desired="$REMOTE_SSH" ;;
    *) desired="$REMOTE_HTTPS" ;;
esac
[[ "$remote" == "$desired" ]] || git -C "$REPO_ROOT" remote set-url origin "$desired"

git -C "$REPO_ROOT" pull --ff-only

echo "BFSOS checkout is current. Maintainer workflow: edit ports, git add/commit, then git push."
