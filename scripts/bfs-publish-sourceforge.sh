#!/usr/bin/env bash
set -Eeuo pipefail

# BFSOS SourceForge publisher
#
# Automatically discovers:
#   - newest BFSOS ISO below:
#       $HOME/Downloads
#       $HOME/BFSOS-ISO
#       $HOME/iso-test
#       $HOME/BFSOS
#   - newest BFSOS base archive below:
#       $HOME/BFSOS/archive/base
#       $HOME/Downloads
#       $HOME/iso-test
#       $HOME/BFSOS
#
# ISO selection is based on modification time across all search roots.
# Only complete release sets (.iso + .sha256 + .build-info) are eligible.
# Downloads is searched first, but the newest complete set anywhere wins.
#
# Remote layout:
#   ISO:
#     /home/frs/project/bfsos/BFSOS/ISOS/<iso-version>/
#
#   Base:
#     /home/frs/project/bfsos/BFSOS/base/archive/<base-version>/
#     /home/frs/project/bfsos/BFSOS/base/latest/
#
# The ISO version is parsed from the ISO filename.
# The base version is read from /etc/os-release inside the base archive.
#
# SourceForge FRS uses an older restricted-shell rsync server that does not
# support --mkpath. The normal BFSOS parent directories (ISOS/ and base/) must
# already exist; rsync can create the final release/latest directory itself.
#
# Usage:
#   SF_USER=bmadonnaster ./bfs-publish-sourceforge.sh iso
#   SF_USER=bmadonnaster ./bfs-publish-sourceforge.sh base
#   SF_USER=bmadonnaster ./bfs-publish-sourceforge.sh all
#
# Preview without uploading:
#   SF_USER=bmadonnaster ./bfs-publish-sourceforge.sh --dry-run all
#
# Optional:
#   ARCH=x86_64
#   PUBLISH_DIR=$HOME/BFSOS-publish
#   SF_HOST=frs.sourceforge.net
#   SF_PROJECT=bfsos
#   SF_ROOT=/home/frs/project/bfsos/BFSOS
#
# Search-path overrides are colon-separated:
#   ISO_SEARCH_PATHS="$HOME/Downloads:$HOME/BFSOS-ISO:$HOME/iso-test:$HOME/BFSOS"
#   BASE_SEARCH_PATHS="$HOME/BFSOS/archive/base:$HOME/Downloads:$HOME/iso-test:$HOME/BFSOS"

MODE=""
DRY_RUN=no

while (($#)); do
    case "$1" in
        iso|base|all)
            MODE="$1"
            shift
            ;;
        --dry-run)
            DRY_RUN=yes
            shift
            ;;
        -h|--help)
            sed -n '1,55p' "$0"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

MODE="${MODE:-all}"
ARCH="${ARCH:-x86_64}"
PUBLISH_DIR="${PUBLISH_DIR:-$HOME/BFSOS-publish}"

ISO_SEARCH_PATHS="${ISO_SEARCH_PATHS:-$HOME/Downloads:$HOME/BFSOS-ISO:$HOME/iso-test:$HOME/BFSOS}"
BASE_SEARCH_PATHS="${BASE_SEARCH_PATHS:-$HOME/BFSOS/archive/base:$HOME/Downloads:$HOME/iso-test:$HOME/BFSOS}"

SF_USER="${SF_USER:-}"
SF_HOST="${SF_HOST:-frs.sourceforge.net}"
SF_PROJECT="${SF_PROJECT:-bfsos}"
SF_ROOT="${SF_ROOT:-/home/frs/project/$SF_PROJECT/BFSOS}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ACTIVE_RELEASE="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION" 2>/dev/null || true)"
[[ -n "$ACTIVE_RELEASE" ]] || { echo "ERROR: Could not read authoritative BFSOS VERSION from $PROJECT_DIR/VERSION" >&2; exit 1; }


die() {
    echo "ERROR: $*" >&2
    exit 1
}

log() {
    printf '[BFSOS publish] %s\n' "$*"
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

for cmd in rsync ssh sha256sum tar zstd xz gzip cp date awk grep find sort sed; do
    need "$cmd"
done

[[ -n "$SF_USER" ]] || die \
    "Set SF_USER to your SourceForge login, e.g. SF_USER=bmadonnaster $0 $MODE"

mkdir -p "$PUBLISH_DIR"

remote() {
    printf '%s@%s:%s' "$SF_USER" "$SF_HOST" "$1"
}

# Upload one or more source files in a single SSH/rsync session.
# Last argument is the remote destination path.
run_rsync_files() {
    local argc=$#
    (( argc >= 2 )) || die "run_rsync_files requires files plus destination"

    local dest="${!argc}"
    local -a srcs=("${@:1:argc-1}")

    if [[ "$DRY_RUN" == yes ]]; then
        log "DRY RUN upload mapping:"
        local src
        for src in "${srcs[@]}"; do
            log "  $src -> ${dest%/}/$(basename "$src")"
        done
        return 0
    fi

    rsync -avP --partial -e ssh -- "${srcs[@]}" "$dest/"
}

newest_matching_file() {
    local paths="$1"
    shift

    local -a patterns=("$@")
    local -a roots=()
    local root pattern
    local tmp
    local result=""

    IFS=':' read -r -a roots <<<"$paths"
    tmp="$(mktemp)"

    for root in "${roots[@]}"; do
        [[ -d "$root" ]] || continue
        for pattern in "${patterns[@]}"; do
            find "$root" -type f -name "$pattern" \
                -printf '%T@ %p\n' 2>/dev/null >>"$tmp" || true
        done
    done

    if [[ -s "$tmp" ]]; then
        result="$(
            sort -nr "$tmp" |
                sed -n '1p' |
                cut -d' ' -f2-
        )"
    fi

    rm -f -- "$tmp"

    [[ -n "$result" ]] || return 1
    printf '%s\n' "$result"
}

latest_iso() {
    local paths="$ISO_SEARCH_PATHS"
    local -a roots=()
    local root iso
    local tmp
    local result=""

    IFS=':' read -r -a roots <<<"$paths"
    tmp="$(mktemp)"

    for root in "${roots[@]}"; do
        [[ -d "$root" ]] || continue

        while IFS= read -r -d '' iso; do
            # An ISO is publishable only when its checksum and build-info travel
            # with it. This prevents a freshly copied ISO-only file in Downloads
            # from hiding a slightly older complete release set in BFSOS-ISO.
            [[ -s "${iso}.sha256" ]] || continue
            [[ -s "${iso}.build-info" ]] || continue

            find "$iso" -maxdepth 0 -printf '%T@ %p\n' >>"$tmp"
        done < <(find "$root" -type f -name 'BFSOS-*.iso' -print0 2>/dev/null)
    done

    if [[ -s "$tmp" ]]; then
        result="$(
            sort -nr "$tmp" |
                sed -n '1p' |
                cut -d' ' -f2-
        )"
    fi

    rm -f -- "$tmp"

    [[ -n "$result" ]] || return 1
    printf '%s\n' "$result"
}

latest_base() {
    # Release publishing is scoped to the authoritative project VERSION so an
    # older RC cannot win merely because its archive has a newer mtime.
    newest_matching_file "$BASE_SEARCH_PATHS" \
        "BFSOS-base-${ACTIVE_RELEASE}-${ARCH}.tar.zst" \
        "bfs-rootfs-${ACTIVE_RELEASE}-*.tar.xz" \
        "bfs-rootfs-${ACTIVE_RELEASE}-*.tar.zst" \
        "bfs-rootfs-${ACTIVE_RELEASE}-*.tar.gz"
}

iso_release_from_filename() {
    local iso="$1"
    local base
    base="$(basename "$iso")"

    if [[ "$base" =~ ^BFSOS-(.+)-${ARCH}-[0-9]{8}-[[:xdigit:]]+\.iso$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    die "Cannot determine BFSOS release from ISO filename: $base"
}

read_base_os_release() {
    local archive="$1"
    local member=""
    local text=""

    for member in ./etc/os-release etc/os-release; do
        case "$archive" in
            *.tar.xz)
                text="$(tar -xJOf "$archive" "$member" 2>/dev/null || true)"
                ;;
            *.tar.zst)
                text="$(tar --zstd -xOf "$archive" "$member" 2>/dev/null || true)"
                ;;
            *.tar.gz)
                text="$(tar -xzOf "$archive" "$member" 2>/dev/null || true)"
                ;;
            *)
                die "Unsupported base archive: $archive"
                ;;
        esac

        [[ -n "$text" ]] && break
    done

    [[ -n "$text" ]] || die "Could not read /etc/os-release from base archive: $archive"
    printf '%s\n' "$text"
}

base_release_from_archive() {
    local archive="$1"
    local osr version

    osr="$(read_base_os_release "$archive")"

    version="$(
        printf '%s\n' "$osr" |
        sed -n 's/^VERSION_ID=["'\'']\{0,1\}\([^"'\'']*\)["'\'']\{0,1\}$/\1/p' |
        sed -n '1p'
    )"

    if [[ -z "$version" ]]; then
        version="$(
            printf '%s\n' "$osr" |
            sed -n 's/^VERSION=["'\'']\{0,1\}\([^"'\'']*\)["'\'']\{0,1\}$/\1/p' |
            sed -n '1p'
        )"
    fi

    [[ -n "$version" ]] || die \
        "Could not determine base VERSION_ID/VERSION from /etc/os-release"

    # VERSION can occasionally contain descriptive text. Keep the folder safe.
    version="${version// /-}"
    version="${version//\//-}"

    printf '%s\n' "$version"
}

check_sha_file() {
    local file="$1"
    local sha="$file.sha256"

    [[ -s "$file" ]] || die "Missing file: $file"
    [[ -s "$sha" ]] || die "Missing checksum: $sha"

    (
        cd "$(dirname "$file")"
        sha256sum -c "$(basename "$sha")"
    )
}

validate_base_archive() {
    local archive="$1"
    local listing
    local required
    local alternate

    case "$archive" in
        *.tar.xz)  listing="$(tar -tJf "$archive")" ;;
        *.tar.zst) listing="$(tar --zstd -tf "$archive")" ;;
        *.tar.gz)  listing="$(tar -tzf "$archive")" ;;
        *) die "Unsupported base archive: $archive" ;;
    esac

    for required in \
        ./usr/bin/bash \
        ./usr/bin/pkgmk \
        ./etc/os-release \
        ./etc/passwd \
        ./etc/group \
        ./etc/shadow \
        ./etc/gshadow
    do
        alternate="${required#./}"
        if ! grep -Fxq -- "$required" <<<"$listing" &&
           ! grep -Fxq -- "$alternate" <<<"$listing"; then
            die "Base archive validation failed: missing $required"
        fi
    done
}

transcode_base_to_zstd() {
    local src="$1"
    local out="$2"
    local tmp="${out}.tmp"

    rm -f "$tmp"

    case "$src" in
        *.tar.zst)
            cp -f -- "$src" "$tmp"
            ;;
        *.tar.xz)
            log "Transcoding base xz -> zstd"
            xz -dc -- "$src" | zstd -T0 -19 -f -o "$tmp"
            ;;
        *.tar.gz)
            log "Transcoding base gzip -> zstd"
            gzip -dc -- "$src" | zstd -T0 -19 -f -o "$tmp"
            ;;
        *)
            die "Unsupported base compression: $src"
            ;;
    esac

    mv -f -- "$tmp" "$out"
}

publish_iso() {
    local iso iso_release iso_remote
    local sha info

    iso="$(latest_iso)" || die \
        "No complete BFSOS ISO set found below: $ISO_SEARCH_PATHS (need .iso + .sha256 + .build-info)"

    iso_release="$(iso_release_from_filename "$iso")"
    iso_remote="$SF_ROOT/ISOS/$iso_release"

    sha="${iso}.sha256"
    info="${iso}.build-info"

    check_sha_file "$iso"
    [[ -s "$info" ]] || die "Missing build-info: $info"

    log "Newest ISO selected by modification time:"
    log "  $iso"
    ls -lh "$iso" "$sha" "$info"
    log "Detected ISO release: $iso_release"

    log "Uploading ISO set to:"
    log "  $(remote "$iso_remote")"

    # One rsync connection for ISO + checksum + build-info.
    run_rsync_files \
        "$iso" \
        "$sha" \
        "$info" \
        "$(remote "$iso_remote")"

    log "ISO upload complete."
}

publish_base() {
    local src base_release base_remote latest_remote
    local public_name public public_sha digest

    src="$(latest_base)" || die \
        "No BFSOS base archive found below: $BASE_SEARCH_PATHS"

    base_release="$(base_release_from_archive "$src")"
    [[ "$base_release" == "$ACTIVE_RELEASE" ]] || die \
        "Selected base release '$base_release' does not match authoritative VERSION '$ACTIVE_RELEASE'"
    base_remote="$SF_ROOT/base/archive/$base_release"
    latest_remote="$SF_ROOT/base/latest"
    public_name="BFSOS-base-${base_release}-${ARCH}.tar.zst"
    public="$PUBLISH_DIR/$public_name"
    public_sha="$public.sha256"

    log "Newest base selected:"
    log "  $src"
    log "Detected base release: $base_release"
    log "Published filename: $public_name"

    validate_base_archive "$src"
    transcode_base_to_zstd "$src" "$public"

    log "Validating versioned public zstd base"
    validate_base_archive "$public"
    sha256sum "$public" >"$public_sha"
    digest="$(sha256sum "$public" | awk '{print $1}')"

    log "Prepared base artifact:"
    log "  local source : $src"
    log "  release      : $base_release"
    log "  public file  : $public"
    log "  sha256       : $digest"
    log "  release dest : $(remote "$base_remote/$public_name")"
    log "  latest dest  : $(remote "$latest_remote/$public_name")"
    ls -lh "$public" "$public_sha"

    # The exact same versioned payload and checksum live in both the immutable
    # release directory and the convenience base/latest directory. There is no
    # generic filename that can hide which release an installer is consuming.
    run_rsync_files "$public" "$public_sha" "$(remote "$base_remote")"
    run_rsync_files "$public" "$public_sha" "$(remote "$latest_remote")"

    log "Base upload complete."
}

log "SourceForge project: $SF_PROJECT"
log "FRS host:            $SF_HOST"
log "FRS root:            $SF_ROOT"
log "Mode:                $MODE"
log "Active release:      $ACTIVE_RELEASE"
log "ISO search paths:    $ISO_SEARCH_PATHS"
log "Base search paths:   $BASE_SEARCH_PATHS"

case "$MODE" in
    iso)
        publish_iso
        ;;
    base)
        publish_base
        ;;
    all)
        publish_base
        publish_iso
        ;;
esac

log "Finished successfully."
