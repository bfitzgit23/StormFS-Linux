#!/usr/bin/env bash
#
# git-update-BFSOS-v5.sh
#
# Locate ~/BFSOS, clean generated port metadata and httpup
# client-state files, regenerate bundled httpup REPO manifests, stage all
# changes, commit them with today's date, and push.
#
# Uses Codeberg SSH when it works and automatically falls back to HTTPS.
#

set -Eeuo pipefail

PROGRAM_NAME="${0##*/}"
PROJECT_NAME="BFSOS"
CODEBERG_HOST="codeberg.org"
CODEBERG_SSH_USER="git"
CODEBERG_KEY_NAME="id_ed25519_codeberg"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local answer=""

    while true; do
        if [[ "$default" == y ]]; then
            read -r -p "$prompt [Y/n]: " answer
            answer="${answer:-y}"
        else
            read -r -p "$prompt [y/N]: " answer
            answer="${answer:-n}"
        fi

        case "${answer,,}" in
            y|yes)
                return 0
                ;;
            n|no)
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

find_user_home() {
    if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
        getent passwd "$SUDO_USER" | cut -d: -f6
    else
        printf '%s\n' "$HOME"
    fi
}

require_commands() {
    local command_name=""
    local missing=0

    for command_name in "$@"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            printf 'Missing required command: %s\n' "$command_name" >&2
            missing=1
        fi
    done

    ((missing == 0)) ||
        die "Install the missing commands and try again."
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
    local private_key="$1"
    local output=""
    local status=0

    [[ -f "$private_key" ]] || return 1

    set +e
    output="$(
        ssh \
            -o BatchMode=yes \
            -o ConnectTimeout=15 \
            -o StrictHostKeyChecking=accept-new \
            -o IdentitiesOnly=yes \
            -i "$private_key" \
            -T "$CODEBERG_SSH_USER@$CODEBERG_HOST" 2>&1
    )"
    status=$?
    set -e

    if grep -qi "successfully authenticated" <<< "$output"; then
        echo "$output"
        return 0
    fi

    warn "Codeberg SSH authentication is unavailable."
    echo "$output"
    return "$status"
}

configure_origin_transport() {
    local private_key="$1"
    local remote_url=""
    local repo_path=""
    local ssh_url=""
    local https_url=""

    remote_url="$(git remote get-url origin 2>/dev/null)" ||
        die "This repository has no 'origin' remote."

    case "$remote_url" in
        git@codeberg.org:*)
            repo_path="${remote_url#git@codeberg.org:}"
            ;;
        ssh://git@codeberg.org/*)
            repo_path="${remote_url#ssh://git@codeberg.org/}"
            ;;
        https://codeberg.org/*)
            repo_path="${remote_url#https://codeberg.org/}"
            ;;
        http://codeberg.org/*)
            repo_path="${remote_url#http://codeberg.org/}"
            ;;
        *)
            die "The origin remote is not a recognized Codeberg URL: $remote_url"
            ;;
    esac

    repo_path="${repo_path#/}"
    [[ -n "$repo_path" ]] ||
        die "Could not determine the Codeberg repository path."

    ssh_url="git@codeberg.org:$repo_path"
    https_url="https://codeberg.org/$repo_path"

    if test_codeberg_ssh "$private_key"; then
        if [[ "$remote_url" != "$ssh_url" ]]; then
            echo "Switching origin to SSH:"
            echo "  $ssh_url"
            git remote set-url origin "$ssh_url"
        else
            echo "Origin already uses working Codeberg SSH."
        fi
    else
        if [[ "$remote_url" != "$https_url" ]]; then
            echo "Falling back to HTTPS:"
            echo "  $https_url"
            git remote set-url origin "$https_url"
        else
            echo "Origin already uses Codeberg HTTPS."
        fi
    fi
}

clean_httpup_client_state() {
    local ports_dir="$1"
    local removed=0
    local state_file=""

    [[ -d "$ports_dir" ]] || {
        warn "Bundled ports directory not found: $ports_dir"
        return 0
    }

    echo
    echo "Removing client-side httpup state files..."

    while IFS= read -r -d '' state_file; do
        echo "  Removing ${state_file#"$ports_dir"/}"
        rm -f -- "$state_file"
        removed=$((removed + 1))
    done < <(
        find "$ports_dir" \
            -type f \
            \( \
                -name '.httpup-repo.current' \
                -o -name '.httpup-urlinfo' \
            \) \
            -print0
    )

    echo "Removed $removed httpup client-state file(s)."
}

clean_port_metadata() {
    local ports_dir="$1"
    local removed=0
    local metadata_file=""

    [[ -d "$ports_dir" ]] || {
        warn "Bundled ports directory not found: $ports_dir"
        return 0
    }

    echo
    echo "Removing port .footprint and .md5sum files..."

    while IFS= read -r -d '' metadata_file; do
        echo "  Removing ${metadata_file#"$ports_dir"/}"
        rm -f -- "$metadata_file"
        removed=$((removed + 1))
    done < <(
        find "$ports_dir" \
            -type f \
            \( \
                -name '.footprint' \
                -o -name '.md5sum' \
            \) \
            -print0
    )

    echo "Removed $removed port metadata file(s)."
}

regenerate_repo_manifests() {
    local ports_dir="$1"
    local repgen="$2"
    local collection=""
    local generated=0

    [[ -d "$ports_dir" ]] || {
        warn "Bundled ports directory not found: $ports_dir"
        return 0
    }

    echo
    echo "Regenerating bundled httpup REPO manifests..."

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

validate_repo_manifests() {
    local ports_dir="$1"
    local matches=""

    [[ -d "$ports_dir" ]] || return 0

    matches="$(
        grep -RniE '(^|/)\.httpup-(repo\.current|urlinfo)$' \
            "$ports_dir"/*/REPO 2>/dev/null || true
    )"

    if [[ -n "$matches" ]]; then
        printf '%s\n' "$matches" >&2
        die "A generated REPO manifest still contains client-side httpup state."
    fi

    echo "REPO manifest validation passed."
}

main() {
    local user_home=""
    local project_dir=""
    local ports_dir=""
    local ssh_dir=""
    local ssh_private_key=""
    local commit_date=""
    local commit_message=""
    local httpup_repgen=""

    require_commands \
        git \
        ssh \
        getent \
        grep \
        find \
        sort \
        basename \
        date \
        rm

    user_home="$(find_user_home)"
    [[ -n "$user_home" ]] ||
        die "Could not determine the current user's home directory."

    project_dir="$user_home/$PROJECT_NAME"
    ports_dir="$project_dir/ports"
    ssh_dir="$user_home/.ssh"
    ssh_private_key="$ssh_dir/$CODEBERG_KEY_NAME"

    echo "BFS Linux Git Update Utility"
    echo "============================"
    echo

    [[ -d "$project_dir" ]] ||
        die "Project directory not found: $project_dir"

    [[ -d "$project_dir/.git" ]] ||
        die "Not a Git repository: $project_dir"

    cd "$project_dir"

    echo "Repository:"
    echo "  $project_dir"

    configure_origin_transport "$ssh_private_key"

    if [[ -d "$ports_dir" ]]; then
        # Always clean generated/client-side files before staging.
        clean_httpup_client_state "$ports_dir"
        clean_port_metadata "$ports_dir"

        if httpup_repgen="$(find_httpup_repgen)"; then
            # Generate and validate fresh REPO manifests when the tool exists.
            regenerate_repo_manifests "$ports_dir" "$httpup_repgen"
            validate_repo_manifests "$ports_dir"
        else
            warn "httpup-repgen was not found."
            warn "Skipping REPO generation and continuing with the Git update."
        fi
    else
        warn "No bundled ports directory found; skipping REPO maintenance."
    fi

    echo
    echo "Checking repository status..."
    git status --short

    echo
    echo "Staging all new, modified, and deleted files..."
    git add -A

    if git diff --cached --quiet; then
        echo
        echo "Nothing to commit."
        echo "Checking whether an existing local commit needs to be pushed..."
        git push
        echo
        echo "Repository is up to date."
        exit 0
    fi

    commit_date="$(date '+%Y-%m-%d')"
    commit_message="Updated project $commit_date"

    echo
    echo "Commit message:"
    echo "  $commit_message"

    ask_yes_no "Commit and push these changes?" y || {
        echo "Cancelled. Changes remain staged."
        exit 0
    }

    git commit -m "$commit_message"

    echo
    echo "Pushing to Codeberg..."
    git push

    echo
    echo "BFS Linux project update completed successfully."
}

main "$@"
