#!/usr/bin/env bash
#
# build-and-publish-repo.sh
#
# Full pipeline for stormfs-repo:
#   1. Build every PKGBUILD under pkgbuilds/ with makepkg -s
#   2. Install the resulting .pkg.tar.zst packages into a live LFS root using pacman
#   3. Copy the built packages into stormfs-repo/x86_64/
#   4. Rebuild the pacman database with repo-add
#   5. Commit and push the repo (and optionally the pkgbuilds) to GitHub
#
# This is intended to run on/against a live LFS root. It refuses to run against
# obvious host paths unless --force is passed.

set -euo pipefail

PROGRAM="${0##*/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

# ---- defaults -------------------------------------------------------

PKGBUILD_DIR="${PKGBUILD_DIR:-${REPO_ROOT}/pkgbuilds}"
REPO_DIR="${REPO_DIR:-${REPO_ROOT}/stormfs-repo/x86_64}"
STAGE3_CONF="${STAGE3_CONF:-${REPO_ROOT}/scripts/lfs-mkstage3.conf.example}"

LFS_ROOT="${LFS_ROOT:-/mnt/lfs}"

PACKAGE_LIST="${PACKAGE_LIST:-${PKGBUILD_DIR}/packages.lst}"

GITHUB_REPO="${GITHUB_REPO:-origin}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

DRY_RUN="no"
FORCE="no"
VERBOSE="no"
SKIP_INSTALL="no"
SKIP_PUSH="no"
PUSH_PKGBUILDS="no"
REPO_COMMIT_MSG="repo: refresh stormfs-repo/x86_64 packages"

# ---- helpers ---------------------------------------------------------

log() { printf '[%s] %s\n' "$PROGRAM" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$PROGRAM" "$*" >&2; }
die() { printf '[%s] ERROR: %s\n' "$PROGRAM" "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: build-and-publish-repo.sh [options]

Pipeline:
  1. Build packages from pkgbuilds/ (makepkg -s)
  2. Install packages into a live LFS root with pacman
  3. Copy built packages into stormfs-repo/x86_64
  4. Rebuild the pacman repo database (repo-add)
  5. Push the repo to GitHub (git push)

Defaults:
  PKGBUILD_DIR   = <repo>/pkgbuilds
  REPO_DIR       = <repo>/stormfs-repo/x86_64
  LFS_ROOT       = /mnt/lfs
  PACKAGE_LIST   = <pkgbuilds>/packages.lst  (optional; if absent, builds all dirs)
  GITHUB_REPO    = origin
  GITHUB_BRANCH  = main

Options:
  --pkgbuild-dir DIR     pkgbuilds directory
  --repo-dir DIR         pacman repo directory
  --lfs-root DIR         live LFS root to install into
  --package-list FILE    one pkgbuild subdirectory per line (optional)
  --stage3-conf FILE    lfs-mkstage3 config (documentation/reference only)
  --github-repo REMOTE   git remote to push to (default: origin)
  --github-branch BRANCH git branch to push (default: main)
  --dry-run              print commands, change nothing
  --force                allow non-obvious LFS_ROOT paths
  --verbose              print each command as it runs
  --skip-install         build packages and update repo, but do not install into LFS
  --skip-push            build/install/copy/repo-add, but do not push to GitHub
  --push-pkgbuilds       also commit+push pkgbuilds/ with the repo update
  -h, --help             this help
EOF
}

# ---- argument parsing ------------------------------------------------

while (($#)); do
    case "$1" in
        --pkgbuild-dir)  PKGBUILD_DIR="$2";     shift 2 ;;
        --repo-dir)      REPO_DIR="$2";         shift 2 ;;
        --lfs-root)      LFS_ROOT="$2";         shift 2 ;;
        --package-list)  PACKAGE_LIST="$2";     shift 2 ;;
        --stage3-conf)   STAGE3_CONF="$2";      shift 2 ;;
        --github-repo)   GITHUB_REPO="$2";      shift 2 ;;
        --github-branch) GITHUB_BRANCH="$2";    shift 2 ;;
        --dry-run)       DRY_RUN="yes";         shift ;;
        --force)         FORCE="yes";           shift ;;
        --verbose)       VERBOSE="yes";         shift ;;
        --skip-install)  SKIP_INSTALL="yes";    shift ;;
        --skip-push)     SKIP_PUSH="yes";       shift ;;
        --push-pkgbuilds)PUSH_PKGBUILDS="yes";  shift ;;
        -h|--help)       usage; exit 0 ;;
        *) die "Unknown option: $1 (try --help)" ;;
    esac
done

# ---- precondition checks --------------------------------------------

[[ -d "$PKGBUILD_DIR" ]] || die "pkgbuilds directory not found: $PKGBUILD_DIR"
[[ -d "$(dirname "$REPO_DIR")" ]] || die "repo parent directory not found: $(dirname "$REPO_DIR")"

# Safety check: refuse obvious non-LFS roots unless --force.
if [[ "$FORCE" != yes ]]; then
    case "$LFS_ROOT" in
        /|/tmp/*|/var/*|/home/*|~*|*-home*|*-Desktop*|*-Downloads*)
            die "Refusing unsafe LFS_ROOT='$LFS_ROOT' (use --force to override)"
            ;;
    esac
fi

for cmd in makepkg pacman repo-add git; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
done

# ---- package list ---------------------------------------------------

if [[ -f "$PACKAGE_LIST" ]]; then
    log "Using package list: $PACKAGE_LIST"
    mapfile -t PKG_DIRS < <(
        grep -v '^[[:space:]]*#' "$PACKAGE_LIST" |
            sed 's/[[:space:]]*#.*//' |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
            grep -v '^$'
    )
else
    log "No package list found at $PACKAGE_LIST; building all pkgbuilds subdirectories"
    mapfile -t PKG_DIRS < <(
        for d in "$PKGBUILD_DIR"/*/; do
            [ -d "$d" ] || continue
            bn="${d%/}"
            bn="${bn##*/}"
            [ -f "$d/PKGBUILD" ] && printf '%s\n' "$bn"
        done | sort
    )
fi

if ((${#PKG_DIRS[@]} == 0)); then
    die "No packages to build (no pkgbuilds subdirectories with a PKGBUILD)"
fi

log "Packages to build (${:#PKG_DIRS[@]}): ${PKG_DIRS[*]}"

# ---- build -----------------------------------------------------------

run() {
    if [[ "$VERBOSE" == yes ]]; then
        printf '  + %s\n' "$*"
    fi
    if [[ "$DRY_RUN" == yes ]]; then
        return 0
    fi
    "$@"
}

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

log "Build dir: $BUILD_DIR"
mkdir -p "$REPO_DIR"

FAILED=()
BUILT_PACKAGES=()

for pkgdir in "${PKG_DIRS[@]}"; do
    src="$PKGBUILD_DIR/$pkgdir"
    [[ -f "$src/PKGBUILD" ]] || { warn "No PKGBUILD in $src; skipping"; continue; }

    log "Building package: $pkgdir"
    run bash -c "
        set -euo pipefail
        cd '$src'
        export PKGDEST='$BUILD_DIR'
        export PKGEXT='.pkg.tar.zst'
        makepkg -s --noconfirm --holdver
    " || { warn "Build failed for $pkgdir"; FAILED+=("$pkgdir"); continue; }

    pkgfile="$(find "$BUILD_DIR" -maxdepth 1 -name "${pkgdir}-"*.pkg.tar.zst -print -quit)"
    if [[ -z "$pkgfile" ]]; then
        warn "No package file produced for $pkgdir in $BUILD_DIR"
        FAILED+=("$pkgdir")
        continue
    fi

    BUILT_PACKAGES+=("$pkgfile")
    log "Built: $pkgfile"
done

if ((${#FAILED[@]} > 0)); then
    warn "Build failures: ${FAILED[*]}"
fi

if ((${#BUILT_PACKAGES[@]} == 0)); then
    die "No packages were built; aborting before install/repo steps"
fi

# ---- install into LFS root ------------------------------------------

if [[ "$SKIP_INSTALL" == yes ]]; then
    log "Skipping installation into LFS root (--skip-install)"
else
    log "Installing packages into LFS root: $LFS_ROOT"

    # Ensure the package cache used by pacman contains the built packages.
    PKG_CACHE="$BUILD_DIR/pacman-cache"
    mkdir -p "$PKG_CACHE"
    cp -f "${BUILT_PACKAGES[@]}" "$PKG_CACHE/"

    run pacman --root "$LFS_ROOT" \
        --dbpath "$LFS_ROOT/var/lib/pacman" \
        --cachedir "$PKG_CACHE" \
        --config "${LFS_ROOT}/etc/pacman.conf" \
        --noconfirm \
        -U "${BUILT_PACKAGES[@]}" || die "pacman install into LFS root failed"

    log "Installed packages into LFS root"
fi

# ---- copy to repo ---------------------------------------------------

log "Copying built packages into repo: $REPO_DIR"
run cp -f "${BUILT_PACKAGES[@]}" "$REPO_DIR/"

# ---- repo database --------------------------------------------------

log "Rebuilding pacman repo database: $REPO_DIR"
run repo-add "$REPO_DIR/stormfs-repo.db.tar.zst" "$REPO_DIR"/*.pkg.tar.zst || \
    die "repo-add failed"

log "Repo database updated: $REPO_DIR/stormfs-repo.db.tar.zst"

# ---- optional push to GitHub ----------------------------------------

if [[ "$SKIP_PUSH" == yes ]]; then
    log "Skipping GitHub push (--skip-push)"
else
    log "Pushing repo to GitHub: $GITHUB_REPO/$GITHUB_BRANCH"

    git -C "$REPO_ROOT" add "$REPO_DIR"

    if [[ "$PUSH_PKGBUILDS" == yes ]]; then
        git -C "$REPO_ROOT" add "$PKGBUILD_DIR"
    fi

    if git -C "$REPO_ROOT" diff --cached --quiet; then
        warn "Nothing to commit in repo; skipping push"
    else
        git -C "$REPO_ROOT" commit -m "$REPO_COMMIT_MSG"

        if [[ "$DRY_RUN" == yes ]]; then
            log "DRY RUN: would push to $GITHUB_REPO $GITHUB_BRANCH"
        else
            git -C "$REPO_ROOT" push "$GITHUB_REPO" "$GITHUB_BRANCH" || \
                die "git push failed (check remote/credentials/branch)"
        fi
    fi

    log "GitHub push complete"
fi

log "Pipeline complete"
log "  Built packages : ${BUILT_PACKAGES[*]:-none}"
log "  Repo dir       : $REPO_DIR"
log "  LFS root       : $LFS_ROOT"
log "  Failed builds  : ${FAILED[*]:-none}"
