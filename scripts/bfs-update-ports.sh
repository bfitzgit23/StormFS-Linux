#!/usr/bin/env bash
#
# bfs-update-ports.sh
#
# Synchronize ~/BFSOS/ports with the BFS-Linux Codeberg repo.
# This script may be stored and run from any subfolder.
#

set -Eeuo pipefail

INSTALL_DIR="$HOME/BFSOS"
SOURCE_PORTS="$INSTALL_DIR/ports"

REPO_URL="git@codeberg.org:bmadonnaster/BFS-Linux.git"
REPO_DIR="$HOME/BFS-Linux"

PROGRAM_NAME="${0##*/}"
CODEBERG_HOST="codeberg.org"
CODEBERG_SSH_USER="git"
CODEBERG_KEY_NAME="id_ed25519_codeberg"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

get_local_hostname() {
    if command -v uname >/dev/null 2>&1; then
        uname -n 2>/dev/null && return
    fi

    if [[ -r /proc/sys/kernel/hostname ]]; then
        cat /proc/sys/kernel/hostname
        return
    fi

    echo unknown-host
}

find_httpup_repgen() {
    local candidate=""

    if command -v httpup-repgen >/dev/null 2>&1; then
        command -v httpup-repgen
        return 0
    fi

    for candidate in \
        /usr/bin/httpup-repgen \
        /usr/local/bin/httpup-repgen \
        /mnt/bfs/usr/bin/httpup-repgen
    do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

test_codeberg_ssh() {
    local ssh_dir="$HOME/.ssh"
    local priv="$ssh_dir/$CODEBERG_KEY_NAME"
    local test_file=""

    [[ -f "$priv" ]] || return 1

    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    test_file="$(mktemp /tmp/bfs-codeberg-test.XXXXXX)"

    ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=accept-new \
        -o IdentitiesOnly=yes \
        -i "$priv" \
        -T git@codeberg.org >"$test_file" 2>&1 || true

    if grep -qi "successfully authenticated" "$test_file"; then
        rm -f "$test_file"
        return 0
    fi

    echo "SSH authentication is unavailable:"
    cat "$test_file"
    rm -f "$test_file"
    return 1
}

cleanup_repo() {
    if [[ -d "$REPO_DIR" ]]; then
        echo "Removing temporary repository: $REPO_DIR"
        rm -rf -- "$REPO_DIR"
    fi
}

regenerate_repo_manifests() {
    local ports_dir="$1"
    local repgen="$2"
    local collection=""
    local generated=0

    echo "Regenerating httpup REPO manifests..."

    while IFS= read -r -d '' collection; do
        [[ -d "$collection" ]] || continue

        echo "  Generating $(basename "$collection")/REPO"
        (
            cd "$collection"
            "$repgen"
        ) || die "Failed to generate REPO in $collection"

        generated=$((generated + 1))
    done < <(
        find "$ports_dir" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -print0 |
        sort -z
    )

    ((generated > 0)) ||
        die "No port collection directories were found in $ports_dir."

    echo "Generated $generated REPO manifest(s)."
}

for c in git ssh grep find sort cp rm date mktemp basename; do
    command -v "$c" >/dev/null 2>&1 ||
        die "$c is not installed."
done

HTTPUP_REPGEN="$(find_httpup_repgen)" ||
    die "httpup-repgen was not found. Install httpup or make /mnt/bfs/usr/bin/httpup-repgen available."

SSH_KEY="$HOME/.ssh/$CODEBERG_KEY_NAME"
HTTPS_REPO_URL="https://codeberg.org/bmadonnaster/BFS-Linux.git"
SSH_REPO_URL="git@codeberg.org:bmadonnaster/BFS-Linux.git"
USE_SSH=no

if test_codeberg_ssh; then
    USE_SSH=yes
    REPO_URL="$SSH_REPO_URL"
    echo "Using authenticated SSH access to Codeberg."
else
    REPO_URL="$HTTPS_REPO_URL"
    echo "Falling back to HTTPS."
fi

if [[ -d "$REPO_DIR/.git" ]]; then
    existing_remote="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)"

    if [[ "$USE_SSH" == yes ]]; then
        if [[ "$existing_remote" != "$SSH_REPO_URL" ]]; then
            echo "Switching existing repository remote to SSH..."
            git -C "$REPO_DIR" remote set-url origin "$SSH_REPO_URL"
        fi
    else
        if [[ "$existing_remote" != "$HTTPS_REPO_URL" ]]; then
            echo "Switching existing repository remote to HTTPS..."
            git -C "$REPO_DIR" remote set-url origin "$HTTPS_REPO_URL"
        fi
    fi
fi

# 1. Verify ~/BFSOS exists.
[[ -d "$INSTALL_DIR" ]] ||
    die "$INSTALL_DIR does not exist."

[[ -d "$SOURCE_PORTS" ]] ||
    die "$SOURCE_PORTS does not exist."

# 2. Clone BFS-Linux into the current user's home directory,
#    or update it if it already exists.
if [[ -e "$REPO_DIR" && ! -d "$REPO_DIR/.git" ]]; then
    die "$REPO_DIR exists but is not a Git repository."
fi

if [[ -d "$REPO_DIR/.git" ]]; then
    echo "Updating existing repository: $REPO_DIR"
    git -C "$REPO_DIR" pull --ff-only
else
    echo "Cloning BFS-Linux into $REPO_DIR"
    git clone "$REPO_URL" "$REPO_DIR"
fi

# 3. Remove the repository's existing ports folder.
echo "Removing old ports folder..."
rm -rf -- "$REPO_DIR/ports"

# 4. Copy ports from ~/BFSOS.
echo "Copying $SOURCE_PORTS to $REPO_DIR/ports"
cp -a -- "$SOURCE_PORTS" "$REPO_DIR/ports"

# 5. Remove client-side httpup state files before generating REPO manifests.
#    Otherwise httpup-repgen records these local state files in REPO and
#    clients later try to download them from Codeberg.
echo "Removing client-side httpup state files..."
find "$REPO_DIR/ports" -type f \
    \( -name '.httpup-repo.current' -o -name '.httpup-urlinfo' \) \
    -delete

# 6. Regenerate every collection's server-side httpup REPO manifest only
#    after client-side state files have been removed.
regenerate_repo_manifests "$REPO_DIR/ports" "$HTTPUP_REPGEN"

# 7. Verify that no generated REPO manifest references client state.
if grep -RniE '(^|/)\.httpup-(repo\.current|urlinfo)$' \
    "$REPO_DIR/ports"/*/REPO 2>/dev/null
then
    die "A generated REPO manifest still contains client-side httpup state."
fi

# 8. Stage all changes.
git -C "$REPO_DIR" add --all

# Avoid creating an empty commit.
if git -C "$REPO_DIR" diff --cached --quiet; then
    echo "No ports changes were detected."
    cleanup_repo
    exit 0
fi

# 9. Commit with the current date.
COMMIT_MESSAGE="updated ports $(date '+%Y-%m-%d')"

echo "Creating commit: $COMMIT_MESSAGE"
git -C "$REPO_DIR" commit -m "$COMMIT_MESSAGE"

# 10. Push.
echo "Pushing changes to Codeberg..."
git -C "$REPO_DIR" push

# 11. Remove the temporary clone only after a successful push.
cleanup_repo

echo "BFS-Linux ports update completed successfully."
