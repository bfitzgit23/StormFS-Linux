#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

echo "== maintained Pkgfile shell syntax =="
find ports/{core,opt,xorg,plasma,gnome,lxqt,xfce,compiz,contrib,compat-32} -mindepth 2 -maxdepth 2 -name Pkgfile -print0 | xargs -0 -n1 bash -n

echo "== maintained tree static audit =="
./scripts/bfs-ports-static-audit.sh

echo "== release static audit =="
./scripts/bfs-release-static-audit.sh

echo "== kernel maintenance regression =="
./scripts/tests/test-kernel-maintenance.sh

echo "== prt-get regression =="
./scripts/tests/test-prt-get-no-new-deps.sh

echo "== installer build-work sizing regression =="
./scripts/tests/test-installer-build-work-sizing.sh

echo "== installer pre-RC password/MD policy regression =="
python3 ./scripts/tests/test-installer-pre-rc-policy.py

echo "== display-manager activation policy regression =="
./scripts/tests/test-display-manager-policy.sh

echo "== canonical /opt environment ownership regression =="
./scripts/tests/test-opt-environment-ownership.sh

echo "== Qt /opt compatibility-link regression =="
./scripts/tests/test-qt-opt-compat-links.sh

echo "== CA trust source/install policy regression =="
./scripts/tests/test-ca-trust-source-policy.sh

echo "== XFCE default-profile regression =="
./scripts/tests/test-xfce-default-profile.sh

echo "== checkupdate v10 + updater regression =="
python3 ./scripts/tests/test-checkupdate-v2.py
python3 ./scripts/tests/test-maintained-port-updater.py

echo "== GTK4/Meson test policy regression =="
./scripts/tests/test-gtk4-test-policy.sh

echo "== compat-32 synchronization regression =="
python3 ./scripts/tests/test-compat32-sync.py

echo "== source companion regression =="
python3 "$ROOT/scripts/tests/test-source-companions.py"

echo "== r283 maintained-package sweep regression =="
python3 ./scripts/tests/test-package-sweep-r283.py

echo "BFSOS r243 source tests: PASS"

printf "\n== Firefox coexistence regression ==\n"
"$ROOT/scripts/tests/test-firefox-coexistence.sh"

printf "\n== build-work backend regression ==\n"
"$ROOT/scripts/tests/test-build-work-backend.sh"

printf "\n== pkgmk payload guard regression ==\n"
"$ROOT/scripts/tests/test-pkgmk-payload-guard.sh"

echo
echo '== ISO builder source regression =='
"$ROOT/scripts/tests/test-iso-builder-source.sh"
