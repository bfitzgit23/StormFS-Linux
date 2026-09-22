#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

python3 - "$ROOT/ports/core/prt-get/Pkgfile" "$T/prt-get" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
start="cat > \"$PKG/usr/bin/prt-get\" <<'EOF_WRAPPER'\n"
a=s.index(start)+len(start)
b=s.index('\nEOF_WRAPPER\n',a)
w=s[a:b]
w=w.replace('real=/usr/libexec/prt-get.real', f'real={sys.argv[2]}.real')
Path(sys.argv[2]).write_text(w)
PY
chmod +x "$T/prt-get"
cat > "$T/prt-get.real" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$PRT_TEST_LOG"
case "${1:-}" in
  info) exit 0 ;;
  quickdep) echo newdep ;;
  isinst) echo 'Package newdep not installed' ;;
  quickdiff) printf '%s\n' "${PRT_TEST_QUICKDIFF:-demo}" ;;
  --help|-h) echo 'upstream help' ;;
esac
exit 0
SH
chmod +x "$T/prt-get.real"
export PRT_TEST_LOG="$T/log"
export PRT_TEST_QUICKDIFF=demo

: > "$PRT_TEST_LOG"
"$T/prt-get" update demo >/dev/null 2>&1
grep -q '^depinst newdep$' "$PRT_TEST_LOG"
grep -q '^update demo$' "$PRT_TEST_LOG"

: > "$PRT_TEST_LOG"
out=$("$T/prt-get" update --no-new-deps demo 2>&1)
! grep -q '^depinst ' "$PRT_TEST_LOG"
grep -q '^update demo$' "$PRT_TEST_LOG"
grep -q 'automatic installation of newly required dependencies is disabled' <<<"$out"
grep -q 'intentionally skipped new dependencies' <<<"$out"
grep -q '^  newdep$' <<<"$out"

: > "$PRT_TEST_LOG"
export PRT_TEST_QUICKDIFF=demo
"$T/prt-get" sysup --no-new-deps >/dev/null 2>&1
! grep -q '^update pkgutils$' "$PRT_TEST_LOG"
grep -q '^sysup$' "$PRT_TEST_LOG"
! grep -q '^depinst ' "$PRT_TEST_LOG"

: > "$PRT_TEST_LOG"
export PRT_TEST_QUICKDIFF='pkgutils
demo'
"$T/prt-get" sysup --no-new-deps >/dev/null 2>&1
grep -q '^update pkgutils$' "$PRT_TEST_LOG"
grep -q '^sysup$' "$PRT_TEST_LOG"
! grep -q '^depinst ' "$PRT_TEST_LOG"
export PRT_TEST_QUICKDIFF=demo

: > "$PRT_TEST_LOG"
"$T/prt-get" depinst demo >/dev/null 2>&1
grep -q '^depinst demo$' "$PRT_TEST_LOG"

"$T/prt-get" --help 2>&1 | grep -q -- '--no-new-deps'
echo "prt-get --no-new-deps regression: PASS"
