#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
iso="$ROOT/scripts/bfs-build-iso.sh"
cal="$ROOT/ports/opt/calamares"
theme="$ROOT/ports/opt/stormfs-theme"
fail() { echo "Theme port/Calamares regression: FAIL: $*" >&2; exit 1; }

for port in adw-gtk3 tela-icon-theme oh-my-bash stormfs-theme; do
    file="$ROOT/ports/opt/$port/spkgbuild"
    [ -f "$file" ] || fail "ports/opt/$port/spkgbuild is missing"
    grep -q '^name=' "$file" || fail "$port has no package name"
    grep -q '^version=' "$file" || fail "$port has no version"
    grep -q '^source=' "$file" || fail "$port has no source"
done

grep -q '^name=stormfs-theme$' "$theme/spkgbuild" || fail 'theme pack package name changed'
grep -q 'StormFS-Theme-Icons-v3.zip' "$theme/spkgbuild" || \
    fail 'StormFS theme pack no longer installs the GTK/icon theme'
grep -q 'stormd_wallpapers.zip' "$theme/spkgbuild" || \
    fail 'StormFS theme pack no longer installs the wallpapers'
grep -q 'xfce-xsettings.xml' "$theme/spkgbuild" || fail 'StormFS XFCE defaults are not installed'
grep -q 'gtk-settings.ini' "$theme/spkgbuild" || fail 'StormFS GTK defaults are not installed'
[ -f "$theme/xfce-xsettings.xml" ] || fail 'StormFS xsettings file is missing'
[ -f "$theme/xfce-xfwm4.xml" ] || fail 'StormFS xfwm4 defaults file is missing'
[ -f "$theme/gtk-settings.ini" ] || fail 'StormFS GTK defaults file is missing'
grep -q 'value="StormFS"' "$theme/xfce-xsettings.xml" || fail 'XFCE GTK theme is not StormFS'
grep -q 'value="StormFS-Icons"' "$theme/xfce-xsettings.xml" || fail 'XFCE icon theme is not StormFS-Icons'
grep -q 'value="StormFS"' "$theme/xfce-xfwm4.xml" || fail 'XFWM4 theme is not StormFS'
grep -q '^gtk-theme-name=StormFS$' "$theme/gtk-settings.ini" || fail 'GTK theme is not StormFS'
grep -q '^gtk-icon-theme-name=StormFS-Icons$' "$theme/gtk-settings.ini" || fail 'GTK icon theme is not StormFS-Icons'

grep -q -- '-DWITH_MODULE_SERVICES_OPENRC=ON' "$cal/spkgbuild" || \
    fail 'Calamares does not build the services-openrc module used by its sequence'
! grep -q -- '-DWITH_MODULE_SERVICES_OPENRC=OFF' "$cal/spkgbuild" || \
    fail 'Calamares still disables the services-openrc module'
grep -q -- '-DWITH_MODULE_SHELLPROCESS=ON' "$cal/spkgbuild" || \
    fail 'Calamares does not build the shellprocess cleanup module'
if grep -q '^  - services-openrc$' "$cal/settings.conf"; then
    [ -f "$cal/services-openrc.conf" ] || fail 'services-openrc module has no configuration'
else
    fail 'Calamares sequence no longer runs services-openrc'
fi
grep -q '^  - shellprocess$' "$cal/settings.conf" || fail 'Calamares sequence has no cleanup job'
[ -f "$cal/shellprocess.conf" ] || fail 'Calamares cleanup configuration is missing'
grep -q 'scratch remove -y calamares' "$cal/shellprocess.conf" || fail 'cleanup does not uninstall Calamares'
grep -q 'userdel -r bfs' "$cal/shellprocess.conf" || fail 'cleanup does not delete the live user'
grep -q '90-bfs-live' "$cal/shellprocess.conf" || fail 'cleanup does not remove the live sudoers rule'
grep -q -- '--autologin bfs' "$cal/shellprocess.conf" || fail 'cleanup does not restore the target inittab'
[ -f "$cal/calamares.desktop" ] || fail 'Calamares launcher is missing'
grep -q 'calamares.desktop' "$cal/spkgbuild" || fail 'Calamares launcher is not installed'
grep -q 'stormfs-logo.png' "$cal/spkgbuild" || fail 'Calamares launcher icon is not installed'

for conf in "$ROOT/ports/opt/lightdm-gtk-greeter/greeter.conf" \
            "$ROOT/iso-builder/liverootfs/etc/lightdm/lightdm-gtk-greeter.conf"; do
    [ -f "$conf" ] || fail "greeter configuration is missing: $conf"
    grep -q '^theme-name=StormFS$' "$conf" || fail "greeter theme is not StormFS: $conf"
    grep -q '^icon-theme-name=StormFS-Icons$' "$conf" || fail "greeter icon theme is not StormFS-Icons: $conf"
    ! grep -q 'Numix\|Tela-circle-dark' "$conf" || fail "greeter still references an uninstalled theme: $conf"
done

for pkg in calamares adw-gtk3 tela-icon-theme stormfs-theme oh-my-bash xinit xauth shadow; do
    grep -q "\b$pkg\b" "$iso" || fail "ISO package set is missing $pkg"
done
grep -q 'startx' "$iso" || fail 'live session does not start X'
grep -q 'exec startxfce4' "$iso" || fail 'live session does not start XFCE'
grep -q 'autostart/calamares.desktop' "$iso" || fail 'live session does not install a Calamares autostart entry'
grep -q 'sudo -n calamares' "$iso" || fail 'Calamares autostart is not non-interactive'
grep -q 'env_keep' "$iso" || fail 'live sudoers does not preserve the graphical environment'

sh -n "$ROOT/ports/opt/oh-my-bash/profile.sh" || fail 'oh-my-bash profile hook has invalid shell syntax'

echo 'Theme port/Calamares regression: PASS'
