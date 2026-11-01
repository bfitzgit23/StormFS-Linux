#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() { printf 'r313 virtualization source: FAIL: %s\n' "$*" >&2; exit 1; }
need_file() { [ -f "$1" ] || fail "missing $1"; }
need_fixed() { grep -Fq -- "$1" "$2" || fail "$2 missing: $1"; }

need_file ports/core/python3-pyparsing/spkgbuild
bash -n ports/core/python3-pyparsing/spkgbuild
need_fixed 'version=3.3.3' ports/core/python3-pyparsing/spkgbuild

for port in spice-protocol spice spice-gtk virt-viewer libtpms swtpm; do
    need_file "ports/opt/$port/spkgbuild"
    bash -n "ports/opt/$port/spkgbuild"
done

need_fixed 'version=0.14.5' ports/opt/spice-protocol/spkgbuild
need_fixed 'version=0.16.0' ports/opt/spice/spkgbuild
need_fixed 'version=0.42' ports/opt/spice-gtk/spkgbuild
need_fixed 'wayland-protocols' ports/opt/spice-gtk/depends
need_fixed 'python3-pyparsing' ports/opt/spice-gtk/depends
need_fixed 'version=11.0' ports/opt/virt-viewer/spkgbuild
need_fixed 'version=0.10.2' ports/opt/libtpms/spkgbuild
need_fixed 'version=0.10.2' ports/opt/swtpm/spkgbuild

# QEMU must expose SPICE server support while retaining VNC.
need_fixed 'spice' ports/opt/qemu/depends
need_fixed 'spice-protocol' ports/opt/qemu/depends
need_fixed '--enable-spice' ports/opt/qemu/spkgbuild
need_fixed '--enable-vnc' ports/opt/qemu/spkgbuild

# virt-manager gets the complete client stack but stays VNC-default until live acceptance.
need_fixed 'spice-gtk' ports/opt/virt-manager/depends
need_fixed 'swtpm' ports/opt/virt-manager/depends
need_fixed 'virt-viewer' ports/opt/virt-manager/depends
need_fixed '-Ddefault-graphics=vnc' ports/opt/virt-manager/spkgbuild

# swtpm must be backed by the maintained libtpms package.
need_fixed 'libtpms' ports/opt/swtpm/depends

printf 'r313 virtualization source regression: PASS\n'
