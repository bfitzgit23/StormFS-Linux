#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
iso=scripts/bfs-build-iso.sh
installer=scripts/install-bfs-menu-current.sh

grep -Fq 'downloads.sourceforge.net/project/bfsos/BFSOS/base/latest' "$iso"
grep -Fq 'downloads.sourceforge.net/project/bfsos/BFSOS/base/latest' "$installer"
grep -Fq 'fetch_sourceforge_base base_archive' "$iso"
grep -Fq 'local -n result_ref="$1"' "$iso"
grep -Fq 'wget --show-progress --max-redirect=20' "$iso"
grep -Fq "script -qec './bootstrap.sh' /dev/null" "$iso"
grep -Fq "script -qec 'sudo ./scripts/install-bfs-menu-current.sh' /dev/null" "$iso"
grep -Fq 'Base archive handoff failed' "$installer"

echo 'r313 live/download policy regression: PASS'

# Exercise the installer Download -> result handoff without sourcing installer main.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/archive"
printf 'r313-base-fixture\n' > "$tmp/source.tar.zst"
sha256sum "$tmp/source.tar.zst" | awk '{print $1 "  BFSOS-base-x86_64.tar.zst"}' > "$tmp/source.tar.zst.sha256"
cat > "$tmp/bin/wget" <<'WGET'
#!/usr/bin/env bash
set -e
out=""
url="${!#}"
while (($#)); do
    case "$1" in
        -O) out="$2"; shift 2 ;;
        --ca-certificate=*) shift ;;
        *) shift ;;
    esac
done
case "$url" in
    *.sha256) cp "$R313_FIXTURE.sha256" "$out" ;;
    *) cp "$R313_FIXTURE" "$out" ;;
esac
WGET
chmod +x "$tmp/bin/wget"

R313_FIXTURE="$tmp/source.tar.zst"
export R313_FIXTURE
PATH="$tmp/bin:$PATH"
export PATH
BFS_INSTALL_BASE_URL='https://example.invalid/BFSOS-base-x86_64.tar.zst'
BFS_INSTALL_BASE_SHA256_URL='https://example.invalid/BFSOS-base-x86_64.tar.zst.sha256'
export BFS_INSTALL_BASE_URL BFS_INSTALL_BASE_SHA256_URL

# Import only the relevant function region.  It contains definitions, not main.
eval "$(sed -n '/^supported_base_archive() {/,/^configure_archive() {/p' "$installer" | sed '$d')"
dialog_message() { :; }
clear_screen() { :; }
themed_menu() { printf -v "$1" '%s' 1; }

BASE_ARCHIVE_RESULT=""
choose_missing_base_archive "$tmp/archive"
[ "$BASE_ARCHIVE_RESULT" = "$tmp/archive/BFSOS-base-x86_64.tar.zst" ] || {
    echo "r313: installer handoff returned unexpected path: $BASE_ARCHIVE_RESULT" >&2
    exit 1
}
supported_base_archive "$BASE_ARCHIVE_RESULT"

echo 'r313 installer Download -> selection handoff regression: PASS'
