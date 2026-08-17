#!/usr/bin/env bash
set -Eeuo pipefail

# BFS Linux repository cleanup script
#
# Removes generated build content before committing/pushing.
#
# Behavior:
#   - packages/  -> always cleared
#   - sources/   -> always cleared
#   - archives/  -> asks first, default NO
#   - ports/*/work/ -> always removed
#   - generated package/editor/cache junk -> removed
#
# The script explicitly protects itself from deletion.

SCRIPT_PATH="$(realpath "$0")"
REPO_ROOT="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

cd "$REPO_ROOT"

echo
echo "Cleaning BFS repository:"
echo "  $REPO_ROOT"
echo

remove_path() {
    local path="$1"

    [[ -e "$path" || -L "$path" ]] || return 0

    if [[ "$(realpath -m "$path")" == "$SCRIPT_PATH" ]]; then
        echo "Skipping cleanup script: $path"
        return 0
    fi

    echo "Removing: $path"
    rm -rf -- "$path"
}

clear_directory() {
    local directory="$1"

    [[ -d "$directory" ]] || return 0

    echo "Clearing: $directory"

    find "$directory" -mindepth 1 -maxdepth 1 -print0 |
    while IFS= read -r -d '' path; do
        remove_path "$path"
    done
}

ask_clear_archives() {
    local answer=""

    [[ -d archives ]] || return 0

    echo
    echo "Saved BFS archives were found."
    echo
    echo "WARNING:"
    echo "  These archives may be needed after rebooting into a live environment."
    echo "  Deleting them may require rebuilding the toolchain and/or base rootfs."
    echo
    read -r -p "Delete saved BFS archives? [y/N]: " answer

    case "${answer,,}" in
        y|yes)
            clear_directory "archives"
            ;;
        *)
            echo "Keeping archives."
            ;;
    esac
}

echo "Removing generated package files..."
clear_directory "packages"

echo
echo "Removing downloaded source cache..."
clear_directory "sources"

ask_clear_archives

echo
echo "Removing port work directories..."

find ports -type d -name work -prune -print0 2>/dev/null |
while IFS= read -r -d '' path; do
    remove_path "$path"
done

echo
echo "Removing generated package files inside ports..."

find ports -type f \
    \( -name '*.pkg.tar.gz' \
       -o -name '*.pkg.tar.xz' \
       -o -name '*.pkg.tar.zst' \
       -o -name '*.rej' \
       -o -name '*.orig' \
       -o -name '*~' \) \
    -print0 2>/dev/null |
while IFS= read -r -d '' path; do
    remove_path "$path"
done

echo
echo "Removing Python cache files..."

find . \
    \( -type d -name '__pycache__' \
       -o -type f -name '*.pyc' \
       -o -type f -name '*.pyo' \) \
    -print0 2>/dev/null |
while IFS= read -r -d '' path; do
    remove_path "$path"
done

echo
echo "Removing editor and OS junk..."

find . -type f \
    \( -name '.DS_Store' \
       -o -name 'Thumbs.db' \
       -o -name '*.swp' \
       -o -name '*.swo' \) \
    -print0 2>/dev/null |
while IFS= read -r -d '' path; do
    remove_path "$path"
done

echo
echo "Cleanup complete."
echo

