#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

fail=0

report() {
    printf 'AUDIT: %s\n' "$*" >&2
    fail=1
}

while IFS= read -r -d '' pkgfile; do
    if ! bash -n "$pkgfile"; then
        report "shell syntax failed: $pkgfile"
    fi

done < <(find ports -mindepth 3 -maxdepth 3 -type f -name Pkgfile -print0)

while IFS=: read -r file line text; do
    report "bad JOBS default expansion: $file:$line: $text"
done < <(grep -Rns --include=Pkgfile '\${JOBS-1}' ports || true)

# BFSOS pkgmk's extension enters the extracted source directory before pkg_build().
# These source-dir forms therefore point at a nonexistent nested directory.
python3 - "$ROOT" <<'PY' || fail=1
from pathlib import Path
import sys
root = Path(sys.argv[1])
issues = []
for p in root.glob('ports/*/*/Pkgfile'):
    lines = p.read_text(errors='replace').splitlines()
    inside = False
    depth = 0
    for n, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith('pkg_build()'):
            inside = True
            depth = line.count('{') - line.count('}')
            continue
        if not inside:
            continue
        depth += line.count('{') - line.count('}')
        suspicious = (
            ('meson setup' in line and any(tok in line.split() for tok in ('$name-$version', '${name}-${version}'))) or
            ('cmake -S ' in line and any(tok in line.split() for tok in ('$name-$version', '${name}-${version}'))) or
            ('meson setup ../libsigc++-$version' in line)
        )
        if suspicious:
            issues.append((p.relative_to(root), n, stripped))
        if depth <= 0:
            inside = False
if issues:
    for p, n, line in issues:
        print(f'AUDIT: nested source-dir assumption in pkg_build: {p}:{n}: {line}', file=sys.stderr)
    raise SystemExit(1)
PY

# X.Org recipes must not depend on the old ambient $docdir variable.
while IFS=: read -r file line text; do
    report "ambient X.Org docdir variable: $file:$line: $text"
done < <(grep -Rns --include=Pkgfile '\$docdir' ports/xorg || true)

if grep -Rqs --include=Pkgfile './configure --prefix= *\$XORG_CONFIG' ports/xorg; then
    grep -Rns --include=Pkgfile './configure --prefix= *\$XORG_CONFIG' ports/xorg >&2 || true
    report "malformed XORG_CONFIG prefix invocation found"
fi

if [ -e ports/xorg/util-macros/pre-install ]; then
    report "obsolete util-macros pre-install still exists (used to create /usr/X11R6/usr collisions)"
fi

# libX11 directly requires the protocol headers as well as libxcb/xtrans.
if ! grep -Eq '^# Depends on:.*(^|[[:space:]])xorgproto([[:space:]]|$)' ports/xorg/libX11/Pkgfile; then
    report "libX11 dependency metadata is missing xorgproto"
fi

# All maintained 64-bit collections use the BFSOS pkg_build() extension.
# compat-32 is intentionally excluded until its separate multilib redesign.
while IFS=: read -r file line text; do
    report "legacy build() recipe remains in maintained 64-bit tree: $file:$line: $text"
done < <(grep -RnsE --include=Pkgfile '^[[:space:]]*build[[:space:]]*\([[:space:]]*\)[[:space:]]*\{' \
    ports/core ports/opt ports/xorg ports/plasma ports/contrib ports/gnome \
    ports/lxqt ports/xfce ports/compiz || true)

# Qt5 must not silently drag QtWebEngine; it is packaged separately.
if ! grep -q -- '-skip qtwebengine' ports/opt/qt5/Pkgfile; then
    report "qt5 does not explicitly skip qtwebengine"
fi
if [ ! -f ports/opt/qtwebengine5/Pkgfile ]; then
    report "qtwebengine5 split port is missing"
fi

# Plasma's default closure must include a display manager and the tested Qt6 Phonon VLC backend once.
if ! grep -Eq '^# Depends on:.*(^|[[:space:]])sddm([[:space:]]|$)' ports/plasma/plasma-meta/Pkgfile; then
    report "plasma-meta dependency metadata is missing sddm"
fi
phonon_count=$(grep '^# Depends on:' ports/plasma/plasma-meta/Pkgfile | grep -o 'phonon-backend-vlc' | wc -l)
if [ "$phonon_count" -ne 1 ]; then
    report "plasma-meta must contain phonon-backend-vlc exactly once (found $phonon_count)"
fi

# Package builds invoked through sudo/prt-get must get the /opt toolchain prefixes explicitly.
for required in /opt/qt6 /opt/kf6 /opt/qt5; do
    if ! grep -Fq "$required" ports/core/pkgutils/pkgmk.conf; then
        report "pkgmk.conf is missing build prefix $required"
    fi
done

# The trust-stack dependency direction is make-ca -> p11-kit, never p11-kit -> make-ca.
if grep -Eq '^# Depends on:.*(^|[[:space:]])make-ca([[:space:]]|$)' ports/opt/p11-kit/Pkgfile; then
    report "p11-kit incorrectly depends on make-ca"
fi
if ! grep -Eq '^# Depends on:.*(^|[[:space:]])p11-kit([[:space:]]|$)' ports/core/make-ca/Pkgfile; then
    report "make-ca dependency metadata is missing p11-kit"
fi
if ! grep -Eq '^# Depends on:.*(^|[[:space:]])meson([[:space:]]|$)' ports/opt/p11-kit/Pkgfile; then
    report "p11-kit dependency metadata is missing meson"
fi
if ! grep -Eq '^# Depends on:.*(^|[[:space:]])ninja([[:space:]]|$)' ports/core/meson/Pkgfile ||
   ! grep -Eq '^# Depends on:.*(^|[[:space:]])python3-pip([[:space:]]|$)' ports/core/meson/Pkgfile; then
    report "meson dependency metadata must include ninja and python3-pip"
fi

# r212 pre-bootstrap refresh guards.
check_version() {
    local file=$1 expected=$2 got
    got=$(sed -n 's/^version=//p' "$file" | head -n1)
    [ "$got" = "$expected" ] || report "$file version is $got; expected $expected"
}

check_version ports/core/linux/Pkgfile 7.2.6
check_version ports/core/linux-headers/Pkgfile 7.2.6
check_version ports/core/linux-api-headers/Pkgfile 7.2.6
check_version ports/core/linux-lts/Pkgfile 6.18.52
if grep -q 'debian_patch_base\|sources.debian.org/data/main/l/linux/6.18.9' ports/core/linux-lts/Pkgfile; then
    report "linux-lts still carries the obsolete cross-version Debian 6.18.9 patch bundle"
fi

for kpkg in linux linux-lts; do
    kfile="ports/core/$kpkg/Pkgfile"
    kcfg="ports/core/$kpkg/config"
    grep -q 'scripts/config --enable MODULE_COMPRESS_ALL' "$kfile" || report "$kpkg does not force CONFIG_MODULE_COMPRESS_ALL"
    grep -q 'scripts/config --enable MODULE_COMPRESS_ZSTD' "$kfile" || report "$kpkg does not force Zstd module compression"
    grep -Fq -- "-name '*.ko.zst'" "$kfile" || report "$kpkg does not verify .ko.zst output"
    grep -q '^CONFIG_MODULE_COMPRESS_ALL=y$' "$kcfg" || report "$kpkg saved config does not enable CONFIG_MODULE_COMPRESS_ALL"
    grep -q '^CONFIG_MODULE_COMPRESS_ZSTD=y$' "$kcfg" || report "$kpkg saved config does not select Zstd module compression"
done

for spec in \
    libxfce4util:4.20.1 xfconf:4.20.0 libxfce4ui:4.20.2 exo:4.20.0 \
    garcon:4.20.0 libwnck:43.3 xfce4-dev-tools:4.20.0 libxfce4windowing:4.20.7 \
    xfce4-panel:4.20.8 thunar:4.20.9 thunar-volman:4.20.0 tumbler:4.20.2 \
    xfce4-appfinder:4.20.0 xfce4-power-manager:4.20.1 xfce4-settings:4.20.5 \
    xfdesktop:4.20.2 xfwm4:4.20.0 xfce4-session:4.20.4 parole:4.20.0 \
    xfce4-terminal:1.2.0 xfburn:0.8.0 ristretto:0.14.0 xfce4-notifyd:0.9.7 \
    xfce4-pulseaudio-plugin:0.5.1; do
    pkg=${spec%%:*}; ver=${spec#*:}
    check_version "ports/xfce/$pkg/Pkgfile" "$ver"
done

[ -f ports/xfce/xfce4-meta/Pkgfile ] || report "complete Xfce xfce4-meta package missing"
xfce_meta_deps=$(grep '^# Depends on:' ports/xfce/xfce4-meta/Pkgfile 2>/dev/null || true)
for dep in xfce4-session xfce4-settings xfce4-panel xfdesktop xfwm4 xfce4-appfinder thunar thunar-volman tumbler xfce4-power-manager xfce4-apps-meta; do
    grep -qw "$dep" <<<"$xfce_meta_deps" || report "xfce4-meta dependency metadata is missing $dep"
done

for pkg in compiz compiz-bcop libcompizconfig compizconfig-python ccsm compiz-plugins-main compiz-plugins-extra compiz-plugins-experimental emerald emerald-themes compiz-meta; do
    [ -f "ports/compiz/$pkg/Pkgfile" ] || { report "Compiz Reloaded component missing: $pkg"; continue; }
    check_version "ports/compiz/$pkg/Pkgfile" 0.8.18
done
compiz_meta_deps=$(grep '^# Depends on:' ports/compiz/compiz-meta/Pkgfile 2>/dev/null || true)
for dep in compiz compiz-bcop libcompizconfig compizconfig-python ccsm compiz-plugins-main compiz-plugins-extra compiz-plugins-experimental emerald emerald-themes fusion-icon; do
    grep -qw "$dep" <<<"$compiz_meta_deps" || report "compiz-meta dependency metadata is missing $dep"
done

check_version ports/compiz/fusion-icon/Pkgfile 0.2.4
check_version ports/xorg/glew/Pkgfile 2.3.1

# r223-r232 systemic package/desktop policy guards.
grep -q '_bfs_collect_build_opts' ports/core/pkgutils/extension || report "pkgutils generic extension lacks array-safe build_opt collection"
grep -Fq "\${build_opt//\$'\\n'/ }" ports/core/pkgutils/extension || report "pkgutils generic extension lacks multiline scalar build_opt normalization"
grep -q 'PKGMK_CMAKE_POLICY_VERSION_MINIMUM' ports/core/pkgutils/extension || report "pkgutils CMake policy compatibility default missing"
grep -q '_bfs_meson_disable_supported_tests' ports/core/pkgutils/extension || report "pkgutils Meson supported-test default logic missing"
grep -q '_bfs_configure_test_defaults' ports/core/pkgutils/extension || report "pkgutils Autotools supported-test default logic missing"
! grep -q 'vte\.sh\|vte\.csh' ports/core/aaa_filesystem/Pkgfile || report "aaa_filesystem still owns VTE profile scripts"
[ -f ports/opt/wireplumber/90-bfsos-audio.preset ] || report "BFSOS desktop-audio user preset missing"
for unit in pipewire.socket pipewire-pulse.socket wireplumber.service; do
    grep -q "^enable $unit$" ports/opt/wireplumber/90-bfsos-audio.preset || report "audio preset missing $unit"
done
[ -f ports/xfce/xfce4-panel/default.xml ] || report "Xfce default panel layout missing"
for plugin in notification-plugin power-manager-plugin pulseaudio systray; do
    grep -q "value=\"$plugin\"" ports/xfce/xfce4-panel/default.xml || report "Xfce default panel missing $plugin"
done
grep -q 'bfs_refresh_new_deps' ports/core/prt-get/Pkgfile || report "prt-get wrapper lacks newly-added dependency refresh"

# Bootstrap and installed pkgmk must agree on the package-namespaced source-cache layout.
grep -Fq 'PKGMK_SOURCE_ROOT="$sourcedir"' bootstrap.sh || report "Stage-1 bootstrap source-cache root is not explicit"
grep -Fq 'PKGMK_SOURCE_DIR="\$PKGMK_SOURCE_ROOT/\$name"' bootstrap.sh || report "bootstrap generated pkgmk configs are not package-namespaced"
grep -Fq '$sourcedir/pkgutils/pkgutils-5.40.12.tar.xz' bootstrap.sh || report "initial pkgutils source is not seeded into its package namespace"
for fallback in \
    'https://download.savannah.gnu.org/releases/|https://mirror.fi.ossplanet.net/nongnu/' \
    'https://cdn.kernel.org/pub/|https://mirrors.edge.kernel.org/pub/'; do
    grep -Fq "$fallback" ports/core/pkgutils/pkgmk.conf || report "installed pkgmk fallback missing $fallback"
    grep -Fq "$fallback" bootstrap.sh || report "bootstrap pkgmk fallback missing $fallback"
done

# Firefox rapid/ESR channels are tracked independently; binary and source rapid ports must match.
check_version ports/opt/firefox/Pkgfile 155.0.1
check_version ports/opt/firefox-bin/Pkgfile 155.0.1
check_version ports/opt/firefox-esr/Pkgfile 153.2.0esr

# Current LXQt stable baseline (2026-04 suite plus later point releases).
for spec in libfm-qt:2.4.0 liblxqt:2.4.0 libqtxdg:4.4.0 lxqt-about:2.4.0 lxqt-admin:2.4.0 \
    lxqt-build-tools:2.4.0 lxqt-config:2.4.0 lxqt-globalkeys:2.4.0 lxqt-menu-data:2.4.0 \
    lxqt-notificationd:2.4.0 lxqt-panel:2.4.1 lxqt-policykit:2.4.0 lxqt-powermanagement:2.4.0 \
    lxqt-qtplugin:2.4.0 lxqt-runner:2.4.0 lxqt-session:2.4.0 lxqt-sudo:2.4.0 lxqt-themes:2.4.0 \
    pcmanfm-qt:2.4.1 qterminal:2.4.0 qtermwidget:2.4.0 qtxdg-tools:4.4.0 xdg-desktop-portal-lxqt:1.4.0; do
    pkg=${spec%%:*}; ver=${spec#*:}; check_version "ports/lxqt/$pkg/Pkgfile" "$ver"
done
# BLFS Chapter 38 LXQt Applications: keep the complete application set present.
for pkg in lximage-qt lxqt-archiver lxqt-notificationd pavucontrol-qt qps qtermwidget qterminal screengrab; do
    [ -f "ports/lxqt/$pkg/Pkgfile" ] || report "BLFS LXQt application missing: $pkg"
done
[ -f ports/lxqt/lxqt-meta/Pkgfile ] || report "LXQt desktop component missing: lxqt-meta"
lxqt_meta_deps=$(grep '^# Depends on:' ports/lxqt/lxqt-meta/Pkgfile 2>/dev/null || true)
for dep in lxqt-session lxqt-panel pcmanfm-qt lxqt-notificationd lxqt-wayland-session     lximage-qt lxqt-archiver pavucontrol-qt qps qtermwidget qterminal screengrab     xdg-desktop-portal-lxqt openbox obconf-qt breeze-icons desktop-file-utils     sddm pipewire wireplumber; do
    grep -qw "$dep" <<<"$lxqt_meta_deps" || report "lxqt-meta dependency metadata is missing $dep"
done
# BLFS requires liblxqt for these two applications; keep the dependency explicit.
for pkg in lxqt-archiver pavucontrol-qt; do
    grep '^# Depends on:' "ports/lxqt/$pkg/Pkgfile" | grep -qw liblxqt || report "$pkg is missing required liblxqt dependency"
done

# Duplicate package identities across maintained collections are never silent.
python3 - "$ROOT" <<'PY_DUP' || fail=1
from pathlib import Path
from collections import defaultdict
import sys
root=Path(sys.argv[1]); found=defaultdict(list)
for p in root.glob('ports/*/*/Pkgfile'):
    for line in p.read_text(errors='replace').splitlines():
        if line.startswith('name='):
            found[line.split('=',1)[1].strip()].append(p.relative_to(root)); break
bad={k:v for k,v in found.items() if len(v)>1}
if bad:
    for name,paths in sorted(bad.items()):
        print(f"AUDIT: duplicate package identity {name}: " + ', '.join(map(str,paths)), file=sys.stderr)
    raise SystemExit(1)
PY_DUP

if grep -Rqs --include=Pkgfile -E 'launchpad\.net/compiz|version=0\.9\.|libwnck2|gtk2' ports/compiz; then
    grep -Rns --include=Pkgfile -E 'launchpad\.net/compiz|version=0\.9\.|libwnck2|gtk2' ports/compiz >&2 || true
    report "Compiz collection still contains 0.9/Launchpad/GTK2-era metadata"
fi

check_version ports/xorg/xscreensaver/Pkgfile 6.15
if ! grep -q 'bsod' ports/xorg/xscreensaver/Pkgfile; then
    report "XScreenSaver recipe does not disable the bsod fake-security saver from default random rotation"
fi
check_version ports/opt/avahi/Pkgfile 0.9-rc5
check_version ports/opt/xdg-dbus-proxy/Pkgfile 0.1.8
[ -f ports/core/python3-vcs-versioning/Pkgfile ] || report "python3-vcs-versioning port missing"
if ! grep -Eq '^# Depends on:.*(^|[[:space:]])rustc([[:space:]]|$)' ports/opt/corrosion/Pkgfile; then
    report "corrosion dependency metadata must use rustc"
fi
if [ -e ports/compiz/cython3/.checksums ] || [ -e ports/compiz/cython3/.pkgfiles ]; then
    report "stale cython3 generated metadata remains after the version refresh"
fi

if [ "$fail" -ne 0 ]; then
    printf 'BFSOS ports static audit: FAILED\n' >&2
    exit 1
fi

printf 'BFSOS ports static audit: PASSED\n'
