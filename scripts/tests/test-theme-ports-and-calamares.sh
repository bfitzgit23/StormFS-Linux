#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
iso="$ROOT/scripts/bfs-build-iso.sh"
cal="$ROOT/ports/opt/calamares"
fail() { echo "Theme port/Calamares regression: FAIL: $*" >&2; exit 1; }

for port in adw-gtk3 tela-icon-theme oh-my-bash stormfs-theme; do
    file="$ROOT/ports/opt/$port/spkgbuild"
    [ -f "$file" ] || fail "ports/opt/$port/spkgbuild is missing"
    grep -q '^name=' "$file" || fail "$port has no package name"
    grep -q '^version=' "$file" || fail "$port has no version"
    grep -q '^source=' "$file" || fail "$port has no source"
done

grep -q '^name=stormfs-theme$' "$ROOT/ports/opt/stormfs-theme/spkgbuild" || \
    fail 'theme pack package name changed'
grep -q 'StormFS-Theme-Icons-v3.zip' "$ROOT/ports/opt/stormfs-theme/spkgbuild" || \
    fail 'StormFS theme pack no longer installs the GTK/icon theme'
grep -q 'stormd_wallpapers.zip' "$ROOT/ports/opt/stormfs-theme/spkgbuild" || \
    fail 'StormFS theme pack no longer installs the wallpapers'

grep -q -- '-DWITH_MODULE_SERVICES_OPENRC=ON' "$cal/spkgbuild" || \
    fail 'Calamares does not build the services-openrc module used by its sequence'
! grep -q -- '-DWITH_MODULE_SERVICES_OPENRC=OFF' "$cal/spkgbuild" || \
    fail 'Calamares still disables the services-openrc module'
if grep -q '^  - services-openrc$' "$cal/settings.conf"; then
    [ -f "$cal/services-openrc.conf" ] || fail 'services-openrc module has no configuration'
else
    fail 'Calamares sequence no longer runs services-openrc'
fi
[ -f "$cal/calamares.desktop" ] || fail 'Calamares launcher is missing'
grep -q 'calamares.desktop' "$cal/spkgbuild" || fail 'Calamares launcher is not installed'
grep -q 'stormfs-logo.png' "$cal/spkgbuild" || fail 'Calamares launcher icon is not installed'

for conf in "$ROOT/ports/opt/lightdm-gtk-greeter/greeter.conf" \
            "$ROOT/iso-builder/liverootfs/etc/lightdm/lightdm-gtk-greeter.conf"; do
    [ -f "$conf" ] || fail "greeter configuration is missing: $conf"
    grep -q '^theme-name=adw-gtk3-dark$' "$conf" || fail "greeter theme is not adw-gtk3-dark: $conf"
    grep -q '^icon-theme-name=Tela$' "$conf" || fail "greeter icon theme is not Tela: $conf"
    ! grep -q 'Numix\|Tela-circle-dark' "$conf" || fail "greeter still references an uninstalled theme: $conf"
done

for pkg in calamares adw-gtk3 tela-icon-theme stormfs-theme oh-my-bash; do
    grep -q "\b$pkg\b" "$iso" || fail "ISO package set is missing $pkg"
done

sh -n "$ROOT/ports/opt/oh-my-bash/profile.sh" || fail 'oh-my-bash profile hook has invalid shell syntax'

echo 'Theme port/Calamares regression: PASS'
