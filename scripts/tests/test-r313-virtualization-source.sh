#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() { printf 'r313 virtualization source: FAIL: %s\n' "$*" >&2; exit 1; }
need_file() { [ -f "$1" ] || fail "missing $1"; }
need_fixed() { grep -Fq -- "$1" "$2" || fail "$2 missing: $1"; }

need_file ports/core/python3-pyparsing/Pkgfile
bash -n ports/core/python3-pyparsing/Pkgfile
need_fixed 'version=3.3.3' ports/core/python3-pyparsing/Pkgfile

for port in spice-protocol spice spice-gtk virt-viewer libtpms swtpm; do
    need_file "ports/opt/$port/Pkgfile"
    bash -n "ports/opt/$port/Pkgfile"
done

need_fixed 'version=0.14.5' ports/opt/spice-protocol/Pkgfile
need_fixed 'version=0.16.0' ports/opt/spice/Pkgfile
need_fixed 'version=0.42' ports/opt/spice-gtk/Pkgfile
need_fixed 'wayland-protocols' ports/opt/spice-gtk/Pkgfile
need_fixed 'python3-pyparsing' ports/opt/spice-gtk/Pkgfile
need_fixed 'version=11.0' ports/opt/virt-viewer/Pkgfile
need_fixed 'version=0.10.2' ports/opt/libtpms/Pkgfile
need_fixed 'version=0.10.2' ports/opt/swtpm/Pkgfile

# QEMU must expose SPICE server support while retaining VNC.
need_fixed 'spice spice-protocol' ports/opt/qemu/Pkgfile
need_fixed '--enable-spice' ports/opt/qemu/Pkgfile
need_fixed '--enable-vnc' ports/opt/qemu/Pkgfile

# virt-manager gets the complete client stack but stays VNC-default until live acceptance.
need_fixed 'spice-gtk' ports/opt/virt-manager/Pkgfile
need_fixed 'swtpm' ports/opt/virt-manager/Pkgfile
need_fixed 'virt-viewer' ports/opt/virt-manager/Pkgfile
need_fixed '-Ddefault-graphics=vnc' ports/opt/virt-manager/Pkgfile

# swtpm must be backed by the maintained libtpms package.
need_fixed 'libtpms' ports/opt/swtpm/Pkgfile

printf 'r313 virtualization source regression: PASS\n'
