#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
fail=0
say_fail(){ printf 'RELEASE-AUDIT: %s\n' "$*" >&2; fail=1; }

depends_has() {
    local dir="$1" dep="$2"
    [ -f "$dir/depends" ] &&
        grep -Eq "(^|[[:space:]])${dep}([[:space:]]|$)" "$dir/depends"
}

bash scripts/bfs-ports-static-audit.sh || fail=1
bash -n bootstrap.sh || say_fail "bootstrap.sh syntax"
bash -n scripts/install-bfs-menu-current.sh || say_fail "current installer syntax"

# Full Bootstrap must remain a real one-action orchestration of Stages 1-5.
grep -q '^_run_full_bootstrap()' bootstrap.sh || say_fail "Full Bootstrap orchestration function missing"
grep -q 'for stage in 1 2 3 4 5' bootstrap.sh || say_fail "Full Bootstrap does not run Stages 1 through 5 in order"
grep -Fq 'Run Full Bootstrap (Stages 1 -> 2 -> 3 -> 4 -> 5)' bootstrap.sh || say_fail "Full Bootstrap menu entry missing"
grep -q 'full|full-bootstrap|all)' bootstrap.sh || say_fail "Full Bootstrap CLI dispatch missing"
grep -q -- '--yes-label "Launch installer"' bootstrap.sh || say_fail "Full Bootstrap final Launch installer action missing"
grep -q -- '--no-label "Done"' bootstrap.sh || say_fail "Full Bootstrap final Done action missing"
grep -q 'BFS_FULL_BOOTSTRAP="${BFS_FULL_BOOTSTRAP:-no}"' bootstrap.sh || say_fail "Full Bootstrap mode is not preserved through root-stage dispatch"

grep -q '^integrity_verification_settings_menu()' bootstrap.sh || say_fail "dedicated Bootstrap integrity-verification settings menu missing"
grep -Fq '3 "Integrity verification"' bootstrap.sh || say_fail "Integrity verification is not exposed as its own Bootstrap Settings category"

# The RC2 runtime installer has one authoritative entry point.  Do not
# require or select historical versioned snapshots at runtime.
[ -f scripts/install-bfs-menu-current.sh ] || say_fail "authoritative current installer missing"
[ -x scripts/install-bfs-menu-current.sh ] || say_fail "authoritative current installer is not executable"
grep -Fq 'install-bfs-menu-current.sh' bootstrap.sh || say_fail "bootstrap does not reference authoritative current installer"
grep -Fq 'install-bfs-menu-current.sh' scripts/bfs-build-iso.sh || say_fail "ISO live menu does not reference authoritative current installer"
! grep -Eq 'install-bfs-menu-v50-r[0-9]+' bootstrap.sh || say_fail "bootstrap still references a versioned installer at runtime"

# Base diagnostics and trust stack.
[ -f ports/core/traceroute/spkgbuild ] || say_fail "traceroute diagnostic port missing"
depends_has ports/core/make-ca p11-kit || say_fail "make-ca must depend on p11-kit"
! depends_has ports/opt/p11-kit make-ca || say_fail "p11-kit must not depend on make-ca"
depends_has ports/opt/p11-kit meson || say_fail "p11-kit must depend on meson"
depends_has ports/core/meson ninja || say_fail "meson must depend on ninja"
depends_has ports/core/meson python3-pip || say_fail "meson must depend on python3-pip"
python3 - <<'PY_ORDER' || say_fail "Stage-2 basepkg must build meson before p11-kit and p11-kit before make-ca"
from pathlib import Path
s=Path('bootstrap.sh').read_text()
start=s.index('basepkg="') + len('basepkg="')
end=s.index('"\nsourcedir=', start)
pkgs=[x.strip() for x in s[start:end].splitlines() if x.strip()]
assert pkgs.index('meson') < pkgs.index('p11-kit') < pkgs.index('make-ca')
PY_ORDER
[ -x ports/core/make-ca/post-install ] || [ -f ports/core/make-ca/post-install ] || say_fail "make-ca post-install missing"
grep -q 'update-pki.timer' ports/core/make-ca/post-install || say_fail "make-ca timer policy missing"

# Qt split and consumers.
grep -q -- '-skip qtwebengine' ports/opt/qt5/spkgbuild || say_fail "Qt5 WebEngine not split"
[ -f ports/opt/qtwebengine5/spkgbuild ] || say_fail "qtwebengine5 port missing"
[ -f ports/opt/qt6-webengine/spkgbuild ] || say_fail "qt6-webengine port missing"
grep -q 'rm -rf qtwebengine' ports/opt/qt6/spkgbuild || say_fail "Qt6 WebEngine not excluded from qt6"
depends_has ports/plasma/khelpcenter qt6-webengine || say_fail "known Qt6 WebEngine consumer khelpcenter missing dependency"

# Plasma desktop baseline.
deps="$(cat ports/plasma/plasma-meta/depends 2>/dev/null || true)"
for dep in sddm pipewire wireplumber phonon-backend-vlc xdg-desktop-portal-kde; do
  grep -qw "$dep" <<<"$deps" || say_fail "plasma-meta missing $dep"
done
[ "$(grep -o 'phonon-backend-vlc' ports/plasma/plasma-meta/depends 2>/dev/null | wc -l)" -eq 1 ] || say_fail "phonon-backend-vlc dependency duplicated"
! grep -qw consolekit ports/plasma/kscreenlocker/spkgbuild || say_fail "kscreenlocker still depends on ConsoleKit"

# Xfce and Compiz must each provide a one-command complete desktop/stack meta package.
[ -f ports/xfce/xfce4-meta/spkgbuild ] || say_fail "xfce4-meta complete desktop package missing"
xfce_deps="$(cat ports/xfce/xfce4-meta/depends 2>/dev/null || true)"
for dep in xfce4-session xfce4-settings xfce4-panel xfdesktop xfwm4 xfce4-appfinder thunar thunar-volman tumbler xfce4-power-manager xfce4-apps-meta; do
  grep -qw "$dep" <<<"$xfce_deps" || say_fail "xfce4-meta missing $dep"
done
[ -f ports/compiz/compiz-meta/spkgbuild ] || say_fail "compiz-meta package missing"
compiz_deps="$(cat ports/compiz/compiz-meta/depends 2>/dev/null || true)"
for dep in compiz compiz-bcop libcompizconfig compizconfig-python ccsm compiz-plugins-main compiz-plugins-extra compiz-plugins-experimental emerald-decorator emerald-themes fusion-icon; do
  grep -qw "$dep" <<<"$compiz_deps" || say_fail "compiz-meta missing $dep"
done

# Desktop activation/default layout and modern suite meta packages.
[ -f ports/opt/wireplumber/90-bfsos-audio.preset ] || say_fail "desktop audio systemd user preset missing"
for unit in pipewire.socket pipewire-pulse.socket wireplumber.service; do
  grep -q "^enable $unit$" ports/opt/wireplumber/90-bfsos-audio.preset || say_fail "audio preset missing $unit"
done
for plugin in notification-plugin power-manager-plugin pulseaudio systray; do
  grep -q "value=\"$plugin\"" ports/xfce/xfce4-panel/default.xml || say_fail "Xfce default panel missing $plugin"
done
[ -f ports/lxqt/lxqt-meta/spkgbuild ] || say_fail "lxqt-meta complete desktop package missing"
lxqt_deps="$(cat ports/lxqt/lxqt-meta/depends 2>/dev/null || true)"
for dep in lxqt-session lxqt-panel pcmanfm-qt lxqt-notificationd lxqt-wayland-session   lximage-qt lxqt-archiver pavucontrol-qt qps qtermwidget qterminal screengrab   xdg-desktop-portal-lxqt openbox obconf-qt breeze-icons desktop-file-utils   sddm pipewire wireplumber; do
  grep -qw "$dep" <<<"$lxqt_deps" || say_fail "lxqt-meta missing $dep"
done
# GNOME current BLFS chapter coverage and complete meta path.
for f in \
  ports/gnome/gweather-locations/spkgbuild \
  ports/gnome/loupe/spkgbuild \
  ports/gnome/showtime/spkgbuild \
  ports/opt/glycin/spkgbuild \
  ports/opt/blueprint-compiler/spkgbuild; do
  [ -f "$f" ] || say_fail "GNOME/BLFS coverage missing $f"
done

depends_has ports/gnome/libgweather gweather-locations || say_fail "libgweather missing gweather-locations dependency"

[ -f ports/gnome/gnome-apps-meta/spkgbuild ] || say_fail "gnome-apps-meta missing"
gnome_apps_deps="$(cat ports/gnome/gnome-apps-meta/depends 2>/dev/null || true)"
for dep in baobab brasero evince evolution file-roller gnome-calculator gnome-color-manager   gnome-connections gnome-disk-utility gnome-logs gnome-maps gnome-nettool   gnome-power-manager gnome-system-monitor gnome-terminal gnome-weather gucharmap   loupe seahorse showtime snapshot; do
  grep -qw "$dep" <<<"$gnome_apps_deps" || say_fail "gnome-apps-meta missing current BLFS app $dep"
done
! grep -qw eog <<<"$gnome_apps_deps" || say_fail "gnome-apps-meta still hard-depends on retired EOG"
! grep -qw gnome-screenshot <<<"$gnome_apps_deps" || say_fail "gnome-apps-meta still hard-depends on legacy gnome-screenshot"

[ -f ports/gnome/gnome-meta/spkgbuild ] || say_fail "gnome-meta complete desktop package missing"
gnome_deps="$(cat ports/gnome/gnome-meta/depends 2>/dev/null || true)"
for dep in gdm gnome-session gnome-shell gnome-shell-extensions gnome-control-center   gnome-settings-daemon nautilus gnome-tweaks gnome-user-docs yelp dconf-editor   gnome-apps-meta xdg-desktop-portal-gnome pipewire wireplumber; do
  grep -qw "$dep" <<<"$gnome_deps" || say_fail "gnome-meta missing $dep"
done

# Mainline/LTS MD policy must agree: core built in, personalities modular.
for f in ports/core/linux/spkgbuild ports/core/linux-lts/spkgbuild; do
  grep -q 'scripts/config --enable MD' "$f" || say_fail "$f does not enable MD core"
  for sym in MD_LINEAR MD_RAID0 MD_RAID1 MD_RAID10 MD_RAID456; do
    grep -q "scripts/config --module $sym" "$f" || say_fail "$f does not make $sym modular"
  done
done

# Mainline/LTS kernel package policy: Zstd kernel image and every installed
# loadable module must be compressed as .ko.zst. Keep both the recipe and the
# saved baseline config aligned so this cannot be silently skipped again.
for f in ports/core/linux/spkgbuild ports/core/linux-lts/spkgbuild; do
  grep -q 'scripts/config --enable KERNEL_ZSTD' "$f" || say_fail "$f does not enable KERNEL_ZSTD"
  grep -q 'scripts/config --disable KERNEL_GZIP' "$f" || say_fail "$f does not disable KERNEL_GZIP"
  grep -q 'scripts/config --enable MODULE_COMPRESS_ZSTD' "$f" || say_fail "$f does not select Zstd module compression"
  grep -q 'scripts/config --enable MODULE_COMPRESS_ALL' "$f" || say_fail "$f does not compress all modules during modules_install"
  grep -Fq -- "-name '*.ko.zst'" "$f" || say_fail "$f lacks post-install .ko.zst verification"
  depends_has "${f%/spkgbuild}" zstd || say_fail "$f does not depend on zstd"
done
for cfg in ports/core/linux/config ports/core/linux-lts/config; do
  grep -q '^CONFIG_KERNEL_ZSTD=y$' "$cfg" || say_fail "$cfg does not select KERNEL_ZSTD"
  grep -q '^# CONFIG_KERNEL_GZIP is not set$' "$cfg" || say_fail "$cfg still selects kernel Gzip"
  grep -q '^CONFIG_MODULE_COMPRESS=y$' "$cfg" || say_fail "$cfg does not enable module compression"
  grep -q '^CONFIG_MODULE_COMPRESS_ZSTD=y$' "$cfg" || say_fail "$cfg does not select Zstd module compression"
  grep -q '^CONFIG_MODULE_COMPRESS_ALL=y$' "$cfg" || say_fail "$cfg does not automatically compress all installed modules"
  grep -q '^# CONFIG_MODULE_COMPRESS_XZ is not set$' "$cfg" || say_fail "$cfg still selects XZ module compression"
done

grep -q 'state=y' scripts/install-bfs-menu-current.sh || say_fail "initramfs verifier does not recognize built-in support"
grep -q 'state=m' scripts/install-bfs-menu-current.sh || say_fail "initramfs verifier does not recognize modular support"

# Global package-build environment and source-cache identity.
for prefix in /opt/qt6 /opt/kf6; do
  grep -Fq "$prefix" ports/core/scratchpkg/scratchpkg.conf || say_fail "scratchpkg build environment missing $prefix"
done
grep -Fq 'SOURCE_DIR="$sourcedir"' bootstrap.sh || say_fail "Stage-1 source-cache root does not reuse the authoritative source tree"
grep -Fq 'sourcedir="$PWD/sources"' bootstrap.sh || say_fail "Stage-1 source-cache directory is not explicit"
grep -Fq 'SOURCE_DIR="/$spkgsrc"' bootstrap.sh || say_fail "bootstrap generated scratchpkg source cache is not package-namespaced"

# No duplicated hard dependency tokens anywhere in maintained spkgbuilds.
python3 - <<'PY' || fail=1
from pathlib import Path
from collections import Counter
bad=[]
for p in Path('ports').glob('*/*/depends'):
    vals=p.read_text(errors='replace').split(); dup=[x for x,c in Counter(vals).items() if c>1]
    if dup: bad.append((p,dup))
if bad:
    for p,d in bad: print(f'RELEASE-AUDIT: duplicate dependencies in {p}: {", ".join(d)}')
    raise SystemExit(1)
PY

if [ "$fail" -ne 0 ]; then
  echo 'BFSOS release static audit: FAILED' >&2
  exit 1
fi

echo 'BFSOS release static audit: PASSED'
