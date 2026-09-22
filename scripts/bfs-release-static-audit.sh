#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
fail=0
say_fail(){ printf 'RELEASE-AUDIT: %s\n' "$*" >&2; fail=1; }

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

# The RC1 runtime installer has one authoritative entry point.  Do not
# require or select historical versioned snapshots at runtime.
[ -f scripts/install-bfs-menu-current.sh ] || say_fail "authoritative current installer missing"
[ -x scripts/install-bfs-menu-current.sh ] || say_fail "authoritative current installer is not executable"
grep -Fq 'install-bfs-menu-current.sh' bootstrap.sh || say_fail "bootstrap does not reference authoritative current installer"
grep -Fq 'install-bfs-menu-current.sh' scripts/bfs-build-iso.sh || say_fail "ISO live menu does not reference authoritative current installer"
! grep -Eq 'install-bfs-menu-v50-r[0-9]+' bootstrap.sh || say_fail "bootstrap still references a versioned installer at runtime"

# Base diagnostics and trust stack.
[ -f ports/core/traceroute/Pkgfile ] || say_fail "traceroute diagnostic port missing"
grep -Eq '^# Depends on:.*(^|[[:space:]])p11-kit([[:space:]]|$)' ports/core/make-ca/Pkgfile || say_fail "make-ca must depend on p11-kit"
! grep -Eq '^# Depends on:.*(^|[[:space:]])make-ca([[:space:]]|$)' ports/opt/p11-kit/Pkgfile || say_fail "p11-kit must not depend on make-ca"
grep -Eq '^# Depends on:.*(^|[[:space:]])meson([[:space:]]|$)' ports/opt/p11-kit/Pkgfile || say_fail "p11-kit must depend on meson"
grep -Eq '^# Depends on:.*(^|[[:space:]])ninja([[:space:]]|$)' ports/core/meson/Pkgfile || say_fail "meson must depend on ninja"
grep -Eq '^# Depends on:.*(^|[[:space:]])python3-pip([[:space:]]|$)' ports/core/meson/Pkgfile || say_fail "meson must depend on python3-pip"
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
grep -q -- '-skip qtwebengine' ports/opt/qt5/Pkgfile || say_fail "Qt5 WebEngine not split"
[ -f ports/opt/qtwebengine5/Pkgfile ] || say_fail "qtwebengine5 port missing"
[ -f ports/opt/qt6-webengine/Pkgfile ] || say_fail "qt6-webengine port missing"
grep -q 'rm -rf qtwebengine' ports/opt/qt6/Pkgfile || say_fail "Qt6 WebEngine not excluded from qt6"
grep -q 'qt6-webengine' ports/plasma/khelpcenter/Pkgfile || say_fail "known Qt6 WebEngine consumer khelpcenter missing dependency"

# Plasma desktop baseline.
deps="$(grep '^# Depends on:' ports/plasma/plasma-meta/Pkgfile)"
for dep in sddm pipewire wireplumber phonon-backend-vlc xdg-desktop-portal-kde; do
  grep -qw "$dep" <<<"$deps" || say_fail "plasma-meta missing $dep"
done
[ "$(grep -o 'phonon-backend-vlc' <<<"$deps" | wc -l)" -eq 1 ] || say_fail "phonon-backend-vlc dependency duplicated"
! grep -qw consolekit ports/plasma/kscreenlocker/Pkgfile || say_fail "kscreenlocker still depends on ConsoleKit"

# Xfce and Compiz must each provide a one-command complete desktop/stack meta package.
[ -f ports/xfce/xfce4-meta/Pkgfile ] || say_fail "xfce4-meta complete desktop package missing"
xfce_deps="$(grep '^# Depends on:' ports/xfce/xfce4-meta/Pkgfile 2>/dev/null || true)"
for dep in xfce4-session xfce4-settings xfce4-panel xfdesktop xfwm4 xfce4-appfinder thunar thunar-volman tumbler xfce4-power-manager xfce4-apps-meta; do
  grep -qw "$dep" <<<"$xfce_deps" || say_fail "xfce4-meta missing $dep"
done
[ -f ports/compiz/compiz-meta/Pkgfile ] || say_fail "compiz-meta package missing"
compiz_deps="$(grep '^# Depends on:' ports/compiz/compiz-meta/Pkgfile 2>/dev/null || true)"
for dep in compiz compiz-bcop libcompizconfig compizconfig-python ccsm compiz-plugins-main compiz-plugins-extra compiz-plugins-experimental emerald emerald-themes fusion-icon; do
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
[ -f ports/lxqt/lxqt-meta/Pkgfile ] || say_fail "lxqt-meta complete desktop package missing"
lxqt_deps="$(grep '^# Depends on:' ports/lxqt/lxqt-meta/Pkgfile 2>/dev/null || true)"
for dep in lxqt-session lxqt-panel pcmanfm-qt lxqt-notificationd lxqt-wayland-session   lximage-qt lxqt-archiver pavucontrol-qt qps qtermwidget qterminal screengrab   xdg-desktop-portal-lxqt openbox obconf-qt breeze-icons desktop-file-utils   sddm pipewire wireplumber; do
  grep -qw "$dep" <<<"$lxqt_deps" || say_fail "lxqt-meta missing $dep"
done
# GNOME current BLFS chapter coverage and complete meta path.
for f in \
  ports/gnome/gweather-locations/Pkgfile \
  ports/gnome/loupe/Pkgfile \
  ports/gnome/showtime/Pkgfile \
  ports/opt/glycin/Pkgfile \
  ports/opt/blueprint-compiler/Pkgfile; do
  [ -f "$f" ] || say_fail "GNOME/BLFS coverage missing $f"
done

grep -qw gweather-locations ports/gnome/libgweather/Pkgfile || say_fail "libgweather missing gweather-locations dependency"

[ -f ports/gnome/gnome-apps-meta/Pkgfile ] || say_fail "gnome-apps-meta missing"
gnome_apps_deps="$(grep '^# Depends on:' ports/gnome/gnome-apps-meta/Pkgfile 2>/dev/null || true)"
for dep in baobab brasero evince evolution file-roller gnome-calculator gnome-color-manager   gnome-connections gnome-disk-utility gnome-logs gnome-maps gnome-nettool   gnome-power-manager gnome-system-monitor gnome-terminal gnome-weather gucharmap   loupe seahorse showtime snapshot; do
  grep -qw "$dep" <<<"$gnome_apps_deps" || say_fail "gnome-apps-meta missing current BLFS app $dep"
done
! grep -qw eog <<<"$gnome_apps_deps" || say_fail "gnome-apps-meta still hard-depends on retired EOG"
! grep -qw gnome-screenshot <<<"$gnome_apps_deps" || say_fail "gnome-apps-meta still hard-depends on legacy gnome-screenshot"

[ -f ports/gnome/gnome-meta/Pkgfile ] || say_fail "gnome-meta complete desktop package missing"
gnome_deps="$(grep '^# Depends on:' ports/gnome/gnome-meta/Pkgfile 2>/dev/null || true)"
for dep in gdm gnome-session gnome-shell gnome-shell-extensions gnome-control-center   gnome-settings-daemon nautilus gnome-tweaks gnome-user-docs yelp dconf-editor   gnome-apps-meta xdg-desktop-portal-gnome pipewire wireplumber; do
  grep -qw "$dep" <<<"$gnome_deps" || say_fail "gnome-meta missing $dep"
done

# New hard dependencies added to installed packages must be discovered before update/sysup.
grep -q 'bfs_refresh_new_deps' ports/core/prt-get/Pkgfile || say_fail "prt-get missing new-dependency refresh"

# Mainline/LTS MD policy must agree: core built in, personalities modular.
for f in ports/core/linux/Pkgfile ports/core/linux-lts/Pkgfile; do
  grep -q 'scripts/config --enable MD' "$f" || say_fail "$f does not enable MD core"
  for sym in MD_LINEAR MD_RAID0 MD_RAID1 MD_RAID10 MD_RAID456; do
    grep -q "scripts/config --module $sym" "$f" || say_fail "$f does not make $sym modular"
  done
done

# Mainline/LTS kernel package policy: Zstd kernel image and every installed
# loadable module must be compressed as .ko.zst. Keep both the recipe and the
# saved baseline config aligned so this cannot be silently skipped again.
for f in ports/core/linux/Pkgfile ports/core/linux-lts/Pkgfile; do
  grep -q 'scripts/config --enable KERNEL_ZSTD' "$f" || say_fail "$f does not enable KERNEL_ZSTD"
  grep -q 'scripts/config --disable KERNEL_GZIP' "$f" || say_fail "$f does not disable KERNEL_GZIP"
  grep -q 'scripts/config --enable MODULE_COMPRESS_ZSTD' "$f" || say_fail "$f does not select Zstd module compression"
  grep -q 'scripts/config --enable MODULE_COMPRESS_ALL' "$f" || say_fail "$f does not compress all modules during modules_install"
  grep -Fq -- "-name '*.ko.zst'" "$f" || say_fail "$f lacks post-install .ko.zst verification"
  grep -Eq '^# Depends on:.*(^|[[:space:]])zstd([[:space:]]|$)' "$f" || say_fail "$f does not depend on zstd"
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
for prefix in /opt/qt6 /opt/kf6 /opt/qt5; do
  grep -Fq "$prefix" ports/core/pkgutils/pkgmk.conf || say_fail "pkgmk build environment missing $prefix"
done
grep -Fq 'PKGMK_SOURCE_DIR="$PKGMK_SOURCE_ROOT/$name"' ports/core/pkgutils/pkgmk.conf || say_fail "source cache is not package-namespaced"
grep -Fq 'PKGMK_SOURCE_ROOT="$sourcedir"' bootstrap.sh || say_fail "Stage-1 source-cache root does not reuse the authoritative source tree"
grep -Fq 'PKGMK_SOURCE_DIR="\$PKGMK_SOURCE_ROOT/\$name"' bootstrap.sh || say_fail "bootstrap generated pkgmk source cache is not package-namespaced"
grep -Fq '$sourcedir/pkgutils/pkgutils-5.40.12.tar.xz' bootstrap.sh || say_fail "initial pkgutils archive is outside its package namespace"
for fallback in \
  'https://download.savannah.gnu.org/releases/|https://mirror.fi.ossplanet.net/nongnu/' \
  'https://cdn.kernel.org/pub/|https://mirrors.edge.kernel.org/pub/'; do
  grep -Fq "$fallback" ports/core/pkgutils/pkgmk.conf || say_fail "installed pkgmk source fallback missing $fallback"
  grep -Fq "$fallback" bootstrap.sh || say_fail "bootstrap source fallback missing $fallback"
done

# Sysup must bring package tooling current first.
grep -q 'BFSOS sysup preflight' ports/core/prt-get/Pkgfile || say_fail "prt-get sysup pkgutils preflight missing"

# No duplicated hard dependency tokens anywhere in maintained Pkgfiles.
python3 - <<'PY' || fail=1
from pathlib import Path
from collections import Counter
bad=[]
for p in Path('ports').glob('*/*/Pkgfile'):
    for line in p.read_text(errors='replace').splitlines():
        if line.startswith('# Depends on:'):
            vals=line.split(':',1)[1].split(); dup=[x for x,c in Counter(vals).items() if c>1]
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
