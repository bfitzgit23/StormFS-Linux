#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ext="$ROOT/ports/core/bfs-spkgbuild-macros/helper.sh"
gtk="$ROOT/ports/opt/gtk4/spkgbuild"

# GTK4 must remain on the generic Meson path; ordinary package builds must not
# invoke an upstream test runner directly from the port.
! grep -Eq '^[[:space:]]*pkg_build[[:space:]]*\(' "$gtk"
! grep -Eiq 'meson[[:space:]]+test|ninja[[:space:]]+test|ctest|make[[:space:]]+check' "$gtk"

grep -q '_bfs_opt=disabled' "$ext"
grep -q 'SPKG_RUN_TESTS:-no' "$ext"
grep -q 'meson test -C _meson_build --print-errorlogs' "$ext"

echo 'GTK4/Meson test policy regression: PASS'
