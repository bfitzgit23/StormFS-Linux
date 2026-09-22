#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
qt5="$ROOT/ports/opt/qt5/Pkgfile"
qt6="$ROOT/ports/opt/qt6/Pkgfile"

grep -q '"$PKG/usr/bin/$file-qt5"' "$qt5"
grep -q '"$PKG/usr/bin/$file-qt6"' "$qt6"
grep -q '/opt/qt5/bin/$file' "$qt5"
grep -q '/opt/qt6/bin/$file' "$qt6"
# No generic /usr/bin/qmake ownership: side-by-side majors must stay explicit.
! grep -Eq '"?\$PKG/usr/bin/(qmake|moc|uic)"?([[:space:]]|$)' "$qt5" "$qt6"
# Prefix metadata is intentionally not mirrored wholesale into /usr.
! grep -Eq 'ln -sfn? .*/opt/qt[56]/(lib|include|share)[^ ]* .*/usr/(lib|include|share)' "$qt5" "$qt6"

echo 'Qt /opt compatibility-link regression: PASS'
