#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { printf 'r304 source policy: FAIL: %s\n' "$*" >&2; exit 1; }
need_file() { [ -f "$ROOT/$1" ] || fail "missing $1"; }
need_grep() { local pat="$1" f="$2"; grep -Eq -- "$pat" "$ROOT/$f" || fail "$f missing expected pattern: $pat"; }

need_file ports/core/genfstab/Pkgfile
need_grep '^version=31$' ports/core/genfstab/Pkgfile
need_grep 'gitlab\.archlinux\.org/archlinux/arch-install-scripts/-/archive/v\$version/arch-install-scripts-v\$version\.tar\.gz' ports/core/genfstab/Pkgfile
need_grep '(^|[[:space:]])genfstab([[:space:]]|$)' bootstrap.sh

need_file ports/iso/networkmanager-iso/Pkgfile
need_file ports/iso/lynx-iso/Pkgfile
need_grep 'networkmanager-iso' scripts/bfs-build-iso.sh
need_grep 'lynx-iso' scripts/bfs-build-iso.sh
need_grep 'wireless-regdb' scripts/bfs-build-iso.sh
need_grep '-Dnmtui=true' ports/iso/networkmanager-iso/Pkgfile
need_grep '-Dnmcli=true' ports/iso/networkmanager-iso/Pkgfile
need_grep '-Dwifi=true' ports/iso/networkmanager-iso/Pkgfile

need_file ports/plasma/spectacle/Pkgfile
need_grep 'spectacle' ports/plasma/plasma-meta/Pkgfile
need_file ports/plasma/kquickimageeditor/Pkgfile
need_file ports/opt/tesseract/Pkgfile
need_file ports/opt/leptonica/Pkgfile

need_file ports/opt/chrony/Pkgfile
need_grep '^version=4\.9$' ports/opt/chrony/Pkgfile

need_file ports/opt/ministream/Pkgfile
need_grep '^version=4\.24\.0$' ports/opt/gtk4/Pkgfile
need_grep '^version=1\.10\.0$' ports/opt/libadwaita/Pkgfile
need_grep '^version=51\.0$' ports/gnome/gnome-meta/Pkgfile
need_grep '^version=51\.0$' ports/gnome/gnome-shell/Pkgfile
need_grep '^version=51\.0$' ports/gnome/mutter/Pkgfile
need_grep '^version=51\.0$' ports/gnome/gnome-control-center/Pkgfile
need_grep '^version=51\.0$' ports/gnome/gdm/Pkgfile
need_grep '^version=51\.0\.1$' ports/gnome/nautilus/Pkgfile

need_grep 'BFSOS-base-\$\{ARCH\}\.tar\.zst' scripts/bfs-build-iso.sh
need_grep 'downloads\.sourceforge\.net/project/bfsos/BFSOS/base/latest' scripts/bfs-build-iso.sh
need_grep 'codeberg\.org/bmadonnaster/BFSOS\.git' scripts/bfs-build-iso.sh
need_grep 'Xbcj x86' scripts/bfs-build-iso.sh
need_grep 'required_tools=.*wget' scripts/bfs-build-iso.sh

printf 'r304 source policy regression: PASS\n'
