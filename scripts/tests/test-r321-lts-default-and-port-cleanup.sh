#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

fail() { echo "r321 LTS/default cleanup regression: FAIL: $*" >&2; exit 1; }

lts_version="$(sed -n 's/^version=//p' ports/core/linux-lts/Pkgfile | head -n1)"
headers_version="$(sed -n 's/^version=//p' ports/core/linux-headers/Pkgfile | head -n1)"

[ -n "$lts_version" ] || fail "linux-lts version missing"
[ "$headers_version" = "$lts_version" ] || fail "linux-headers ($headers_version) is not aligned with linux-lts ($lts_version)"

grep -Fq 'KERNEL_PACKAGE="${BFS_KERNEL_PACKAGE:-linux-lts}"' scripts/install-bfs-menu-current.sh || \
    fail "installer does not default to linux-lts"
grep -Fq 'kernel_flavor="${BFS_ISO_KERNEL:-lts}"' scripts/bfs-build-iso.sh || \
    fail "ISO builder does not default to LTS"
grep -Fq 'source=(https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$version.tar.xz)' ports/core/linux-headers/Pkgfile || \
    fail "linux-headers is not sourced from the 6.x LTS tree"

mapfile -t backups < <(find ports -type f -name 'Pkgfile*' ! -name Pkgfile -print)
((${#backups[@]} == 0)) || {
    printf 'stale Pkgfile copies remain:\n%s\n' "${backups[*]}" >&2
    fail "ports tree contains stale Pkgfile copies"
}

echo "r321 LTS/default cleanup regression: PASS"
