#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wrap="$ROOT/ports/core/pkgutils/bfs-pkgmk"
fail() { echo "pkgmk payload guard regression: FAIL: $*" >&2; exit 1; }
grep -q 'directory-only package archive' "$wrap" || fail 'directory-only rejection missing'
grep -Fq 'substr($0, length($0), 1) != "/"' "$wrap" || fail 'non-directory payload test missing'
if printf 'usr/\n' | awk 'substr($0,length($0),1)!="/"{found=1;exit} END{exit !found}'; then fail 'directory-only listing passed'; fi
printf 'usr/\nusr/bin/\nusr/bin/tool\n' | awk 'substr($0,length($0),1)!="/"{found=1;exit} END{exit !found}' || fail 'real payload listing failed'
echo 'pkgmk payload guard regression: PASS'
