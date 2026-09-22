#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${BFSOS_REPO_ROOT:-$HOME/BFSOS}"
REMOTE_HTTPS="https://codeberg.org/bmadonnaster/BFSOS.git"
REMOTE_SSH="git@codeberg.org:bmadonnaster/BFSOS.git"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

[[ -d "$REPO_ROOT/.git" ]] || die "$REPO_ROOT is not a Git checkout"
command -v git >/dev/null 2>&1 || die "git is not installed"

# BFSOS-owned collections are transported by Git now. Remove only obsolete
# generated HttpUp state from the project tree; third-party user configs under
# /etc/ports are outside this maintainer checkout and are not touched here.
if [[ -d "$REPO_ROOT/ports" ]]; then
    # Development-tree hygiene: generated verification metadata is deliberately
    # removed before committing. pkgmk will regenerate it when verification is
    # enabled for release/testing workflows.
    find "$REPO_ROOT/ports" -type f \
        \( -name '.httpup-repo.current' -o -name '.httpup-urlinfo' -o -name REPO \
           -o -name '.md5sum' -o -name '.md5sums' \
           -o -name '.footprint' -o -name '.footprints' \
           -o -name '.signature' -o -name '.signatures' \) \
        -delete
fi

remote="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
case "$remote" in
    git@codeberg.org:*|ssh://git@codeberg.org/*) desired="$REMOTE_SSH" ;;
    *) desired="$REMOTE_HTTPS" ;;
esac
if [[ -z "$remote" ]]; then
    git -C "$REPO_ROOT" remote add origin "$desired"
elif [[ "$remote" != "$desired" ]]; then
    git -C "$REPO_ROOT" remote set-url origin "$desired"
fi

# Do not merge remote changes implicitly over local edits.
if ! git -C "$REPO_ROOT" diff --quiet || ! git -C "$REPO_ROOT" diff --cached --quiet; then
    warn "Local tracked changes are present; skipping pull before commit."
else
    git -C "$REPO_ROOT" pull --ff-only || die "git pull --ff-only failed"
fi

git -C "$REPO_ROOT" add --all
if git -C "$REPO_ROOT" diff --cached --quiet; then
    echo "No BFSOS changes to commit."
    exit 0
fi

message="${1:-updated BFSOS $(date '+%Y-%m-%d')}"
git -C "$REPO_ROOT" commit -m "$message"
git -C "$REPO_ROOT" push

echo "BFSOS update pushed successfully."
