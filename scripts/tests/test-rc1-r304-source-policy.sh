#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { printf 'r304 source policy: FAIL: %s\n' "$*" >&2; exit 1; }
need_file() { [ -f "$ROOT/$1" ] || fail "missing $1"; }
need_grep() { local pat="$1" f="$2"; grep -Eq -- "$pat" "$ROOT/$f" || fail "$f missing expected pattern: $pat"; }

need_file ports/core/genfstab/spkgbuild
need_grep '^version=31$' ports/core/genfstab/spkgbuild
need_grep 'gitlab\.archlinux\.org/archlinux/arch-install-scripts/-/archive/v\$version/arch-install-scripts-v\$version\.tar\.gz' ports/core/genfstab/spkgbuild
need_grep '(^|[[:space:]])genfstab([[:space:]]|$)' bootstrap.sh

need_file ports/iso/networkmanager-iso/spkgbuild
need_file ports/iso/lynx-iso/spkgbuild
need_grep 'networkmanager-iso' scripts/bfs-build-iso.sh
need_grep 'lynx-iso' scripts/bfs-build-iso.sh
need_grep 'wireless-regdb' scripts/bfs-build-iso.sh
need_grep '-Dnmtui=true' ports/iso/networkmanager-iso/spkgbuild
need_grep '-Dnmcli=true' ports/iso/networkmanager-iso/spkgbuild
need_grep '-Dwifi=true' ports/iso/networkmanager-iso/spkgbuild

need_file ports/plasma/spectacle/spkgbuild
need_grep '^spectacle$' ports/plasma/plasma-meta/depends
need_file ports/plasma/kquickimageeditor/spkgbuild
need_file ports/opt/tesseract/spkgbuild
need_file ports/opt/leptonica/spkgbuild

need_file ports/opt/chrony/spkgbuild
need_grep '^version=4\.9$' ports/opt/chrony/spkgbuild

need_file ports/opt/ministream/spkgbuild
need_grep '^version=4\.24\.0$' ports/opt/gtk4/spkgbuild
need_grep '^version=1\.10\.0$' ports/opt/libadwaita/spkgbuild
need_grep '^version=51\.0$' ports/gnome/gnome-meta/spkgbuild
need_grep '^version=51\.0$' ports/gnome/gnome-shell/spkgbuild
need_grep '^version=51\.0$' ports/gnome/mutter/spkgbuild
need_grep '^version=51\.0$' ports/gnome/gnome-control-center/spkgbuild
need_grep '^version=51\.0$' ports/gnome/gdm/spkgbuild
need_grep '^version=51\.0\.1$' ports/gnome/nautilus/spkgbuild

need_grep 'BFSOS-base-\$\{VERSION\}-\$\{ARCH\}\.tar\.zst' scripts/bfs-build-iso.sh
need_grep 'downloads\.sourceforge\.net/project/bfsos/BFSOS/base/latest' scripts/bfs-build-iso.sh
need_grep 'github\.com/bmadonnaster/BFSOS\.git' scripts/bfs-build-iso.sh
need_grep 'Xbcj x86' scripts/bfs-build-iso.sh
need_grep 'required_tools=.*wget' scripts/bfs-build-iso.sh

printf 'r304 source policy regression: PASS\n'
