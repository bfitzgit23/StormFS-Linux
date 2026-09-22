#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ext="$ROOT/ports/core/pkgutils/extension"
gtk="$ROOT/ports/opt/gtk4/Pkgfile"

# GTK4 must remain on the generic Meson path; ordinary package builds must not
# invoke an upstream test runner directly from the port.
! grep -Eq '^[[:space:]]*pkg_build[[:space:]]*\(' "$gtk"
! grep -Eiq 'meson[[:space:]]+test|ninja[[:space:]]+test|ctest|make[[:space:]]+check' "$gtk"

grep -q '_bfs_meson_disable_supported_tests' "$ext"
grep -q 'PKGMK_RUN_TESTS:-no' "$ext"
grep -q 'meson test -C _meson_build --print-errorlogs' "$ext"

echo 'GTK4/Meson test policy regression: PASS'
