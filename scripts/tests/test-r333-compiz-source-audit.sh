#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
fail(){ echo "FAIL: $*" >&2; exit 1; }

for p in "$ROOT"/ports/compiz/*/spkgbuild; do
    bash -n "$p" || fail "syntax: ${p#$ROOT/}"
done

fusion="$ROOT/ports/compiz/fusion-icon/spkgbuild"
for dep in python3-pyqt5 mesa-demos xorg-apps compiz compizconfig-python ccsm emerald-decorator; do
    grep -Eq "^# Depends on:.*(^|[[:space:]])${dep}([[:space:]]|$)" "$fusion" || \
        grep -Fxq "$dep" "$(dirname "$fusion")/depends" || fail "fusion-icon dependency missing: $dep"
done

for p in python3-sip python3-pyqt-builder python3-pyqt5; do
    test -f "$ROOT/ports/opt/$p/spkgbuild" || fail "missing PyQt support port: $p"
    bash -n "$ROOT/ports/opt/$p/spkgbuild" || fail "syntax: ports/opt/$p/spkgbuild"
done

if grep -Rni '/usr/local' "$ROOT/ports/compiz" --include=spkgbuild --include='*.py' --include='*.desktop' >/tmp/bfs-r333-compiz-local.$$ 2>/dev/null; then
    cat /tmp/bfs-r333-compiz-local.$$
    rm -f /tmp/bfs-r333-compiz-local.$$
    fail "unexpected /usr/local reference in Compiz suite"
fi
rm -f /tmp/bfs-r333-compiz-local.$$

grep -Fq '/usr/share/bfsos/' "$ROOT/ports/compiz/compiz-meta/spkgbuild" || fail "compiz-meta payload marker is not in /usr/share/bfsos"
! grep -Fq '/usr/share/doc' "$ROOT/ports/compiz/compiz-meta/spkgbuild" || fail "compiz-meta still uses stripped /usr/share/doc payload"

compiz_recipe="$ROOT/ports/compiz/compiz/spkgbuild"
line_c0=$(grep -nF '"$SRC/c0c605dd.patch"' "$compiz_recipe" | cut -d: -f1)
line_9f=$(grep -nF '"$SRC/9f105a8b.patch"' "$compiz_recipe" | cut -d: -f1)
[ -n "$line_c0" ] && [ -n "$line_9f" ] || fail "Compiz patch order is not explicit"
[ "$line_c0" -lt "$line_9f" ] || fail "Compiz applies 9f105a8b before its c0c605dd prerequisite"

echo "PASS: r333 Compiz source/dependency audit"

# r355 follow-up: PyQt5.sip is a separate runtime extension package.
[[ -f "$ROOT/ports/opt/pyqt5-sip/spkgbuild" ]] || { echo "missing pyqt5-sip port" >&2; exit 1; }
grep -Eq '^version=12\.19\.0$' "$ROOT/ports/opt/pyqt5-sip/spkgbuild" || { echo "pyqt5-sip version drift" >&2; exit 1; }
grep -qx 'pyqt5-sip' "$ROOT/ports/opt/python3-pyqt5/depends" || { echo "python3-pyqt5 missing pyqt5-sip runtime dependency" >&2; exit 1; }
grep -qx 'pyqt5-sip' "$ROOT/ports/compiz/fusion-icon/depends" || { echo "fusion-icon missing pyqt5-sip dependency" >&2; exit 1; }
! grep -qx 'python3-pyqt5' "$ROOT/ports/opt/pyqt5-sip/depends" 2>/dev/null || { echo "pyqt5-sip dependency cycle detected" >&2; exit 1; }

pyqt5="$ROOT/ports/opt/python3-pyqt5/spkgbuild"
for dep in python3 python3-build python3-installer; do
    grep -qx "$dep" "$ROOT/ports/opt/python3-pyqt5/depends" || fail "python3-pyqt5 missing $dep dependency"
done
grep -Fq 'python3 -m build --wheel --no-isolation' "$pyqt5" || fail 'python3-pyqt5 does not build a wheel'
grep -Fq 'python3 -m installer --compile-bytecode 2 --destdir="$PKG" dist/*.whl' "$pyqt5" || fail 'python3-pyqt5 does not stage its wheel with installer'
if grep -Eq '^[[:space:]]*sip-install([[:space:]]|$)' "$pyqt5"; then
    fail 'python3-pyqt5 still uses sip-install without a staging root'
fi
echo "PASS: r333 PyQt5 wheel staging"
