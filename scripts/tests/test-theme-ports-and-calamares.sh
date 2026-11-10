#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
iso="$ROOT/scripts/bfs-build-iso.sh"
cal="$ROOT/ports/opt/calamares"
theme="$ROOT/ports/opt/stormfs-theme"
fail() { echo "Theme port/Calamares regression: FAIL: $*" >&2; exit 1; }

for port in adw-gtk3 tela-icon-theme oh-my-bash stormfs-theme lxdm stormfs-lxdm-theme lightdm lightdm-gtk-greeter; do
    file="$ROOT/ports/opt/$port/spkgbuild"
    [ -f "$file" ] || fail "ports/opt/$port/spkgbuild is missing"
    grep -q '^name=' "$file" || fail "$port has no package name"
    grep -q '^version=' "$file" || fail "$port has no version"
    grep -q '^source=' "$file" || fail "$port has no source"
done

grep -q '^name=stormfs-theme$' "$theme/spkgbuild" || fail 'theme pack package name changed'
grep -Fq 'cd "$SRC" || return 1' "$theme/spkgbuild" || \
    fail 'theme pack build does not enter the source cache'
! grep -Fq 'unzip -q StormFS-Recovered-Theme-Icons-Wallpapers-StormPkg.zip' "$theme/spkgbuild" || \
    fail 'theme pack tries to unpack the pkgbuild-extracted outer archive'
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
grep -q '/usr/bin/calamares' "$cal/shellprocess.conf" || fail 'cleanup has no binary-removal fallback'
grep -Fq 'forbidden_names: [ root, bfs ]' "$cal/users.conf" || fail 'live account name is not reserved'
grep -q 'userdel -r bfs' "$cal/shellprocess.conf" || fail 'cleanup does not delete the live user'
grep -q '90-bfs-live' "$cal/shellprocess.conf" || fail 'cleanup does not remove the live sudoers rule'
grep -q -- '--autologin bfs' "$cal/shellprocess.conf" || fail 'cleanup does not restore the target inittab'
[ -f "$cal/calamares.desktop" ] || fail 'Calamares launcher is missing'
grep -q 'calamares.desktop' "$cal/spkgbuild" || fail 'Calamares launcher is not installed'
grep -q 'stormfs-logo.png' "$cal/spkgbuild" || fail 'Calamares launcher icon is not installed'

broadcom="$ROOT/ports/opt/broadcom-wl"
[ -f "$broadcom/spkgbuild" ] || fail 'Broadcom wireless port is missing'
grep -q '^name=broadcom-wl$' "$broadcom/spkgbuild" || fail 'Broadcom package name changed'
grep -q '^version=6.30.223.271$' "$broadcom/spkgbuild" || fail 'Broadcom version changed'
grep -q '^release=5$' "$broadcom/spkgbuild" || fail 'Broadcom kernel-compatibility release is missing'
grep -Fq 'https://docs.broadcom.com/docs-and-downloads/docs/linux_sta/hybrid-v35_64-nodebug-pcoem-6_30_223_271.tar.gz' "$broadcom/spkgbuild" ||     fail 'Broadcom official source URL is missing'
! grep -q 'download.tuxfamily.org' "$broadcom/spkgbuild" || fail 'Broadcom source still uses TuxFamily'
grep -Fq 'patches/021-linux617.patch' "$broadcom/spkgbuild" || fail 'Broadcom 6.17 compatibility patch is not packaged'
grep -Fq 'patches/024-linux704.patch' "$broadcom/spkgbuild" || fail 'Broadcom 7.4 compatibility patch is not packaged'
grep -Fq 'patch -Np1 --batch --forward -i "$p"' "$broadcom/spkgbuild" || fail 'Broadcom patch application is missing'
[ "$(find "$broadcom/patches" -maxdepth 1 -name '*.patch' | wc -l)" -ge 26 ] || fail 'Broadcom compatibility patch series is incomplete'
grep -Fq 'ccflags-y' "$broadcom/patches/020-linux615.patch" || fail 'Broadcom kbuild EXTRA_CFLAGS fix is missing'
grep -Fq 'wl.o: override objtool-enabled =' "$broadcom/patches/020-linux615.patch" || fail 'Broadcom objtool link fix is missing'
grep -Fq 'kernel/drivers/net/wireless/wl.ko' "$broadcom/spkgbuild" || fail 'Broadcom module install path changed'
[ -f "$broadcom/post-install" ] || fail 'Broadcom post-install hook is missing'
grep -q 'depmod -a' "$broadcom/post-install" || fail 'Broadcom post-install does not rebuild module dependencies'

grep -Fq 'local_start' "$cal/shellprocess.conf" || fail 'Calamares cleanup does not handle local_start'
grep -Fq 'local.bfsos-disabled' "$cal/shellprocess.conf" || fail 'Calamares cleanup does not disable the legacy local hook'
grep -Fq 'remove_deprecated_local_start_hook' "$ROOT/scripts/install-bfs-menu-current.sh" ||     fail 'menu installer has no local_start cleanup'
grep -Fq 'local.bfsos-disabled' "$ROOT/scripts/install-bfs-menu-current.sh" ||     fail 'menu installer does not disable the legacy local hook'
grep -Fq 'local.bfsos-disabled' "$ROOT/iso-builder/liverootfs/root/post-install.sh" || fail 'legacy post-install path does not disable the local hook'

lxdm_theme="$ROOT/ports/opt/stormfs-lxdm-theme"
for file in lxdm.conf gtkrc greeter.ui index.theme background.jpg login.svg; do
    [ -f "$lxdm_theme/$file" ] || fail "LXDM theme file is missing: $file"
done
grep -q '^theme=StormFS$' "$lxdm_theme/lxdm.conf" || fail 'LXDM greeter theme is not StormFS'
grep -q '^gtk_theme=Clearlooks$' "$lxdm_theme/lxdm.conf" || fail 'LXDM GTK2 widget theme is not configured'
grep -q '^bg=/usr/share/lxdm/themes/StormFS/background.jpg$' "$lxdm_theme/lxdm.conf" || fail 'LXDM theme background is not configured'
grep -q '^session=/usr/bin/startxfce4$' "$lxdm_theme/lxdm.conf" || fail 'LXDM does not start Xfce'
grep -q '^Name=StormFS$' "$lxdm_theme/index.theme" || fail 'LXDM theme is not named StormFS'
grep -q 'background.jpg' "$lxdm_theme/gtkrc" || fail 'LXDM GTK2 theme does not use the StormFS background'
grep -q 'login.svg' "$lxdm_theme/greeter.ui" || fail 'LXDM greeter does not use the StormFS wordmark'
[ -f "$ROOT/ports/opt/openrc-init-scripts/lxdm" ] || fail 'OpenRC LXDM service is missing'
grep -qx 'openrc-init-scripts' "$ROOT/ports/opt/lxdm/depends" || fail 'lxdm does not depend on the OpenRC service package'
grep -q '^name=lxdm$' "$ROOT/ports/opt/lxdm/spkgbuild" || fail 'LXDM port name changed'
grep -Fq -- '--with-systemdsystemunitdir=no' "$ROOT/ports/opt/lxdm/spkgbuild" || fail 'LXDM still enables systemd units'
! grep -q 'pam_systemd' "$ROOT/ports/opt/lxdm/bfs-lxdm.pam" || fail 'LXDM PAM stack references pam_systemd'
grep -q '/etc/lightdm/lightdm.conf' "$iso" || fail 'live LightDM configuration is missing'

for pkg in calamares adw-gtk3 tela-icon-theme stormfs-theme lightdm lightdm-gtk-greeter oh-my-bash xinit xauth shadow; do
    grep -q "\b$pkg\b" "$iso" || fail "ISO package set is missing $pkg"
done
! grep -Fq '    startx' "$iso" || fail 'live session still starts startx'
grep -q 'autologin-user=bfs' "$iso" || fail 'live LightDM autologin is not configured'
grep -q 'autologin-user-timeout=0' "$iso" || fail 'live LightDM autologin timeout is not configured'
grep -q 'rc-update add dbus default' "$iso" || fail 'live D-Bus service is not enabled'
grep -q 'rc-update add lightdm default' "$iso" || fail 'live LightDM service is not enabled'
grep -q 'need localmount dbus' "$ROOT/ports/opt/openrc-init-scripts/lightdm" || \
	fail 'LightDM does not require the D-Bus service'
grep -q '/etc/lightdm/lightdm.conf' "$cal/shellprocess.conf" || fail 'installer does not clear live LightDM autologin'
grep -q 'exec startxfce4' "$iso" || fail 'live session does not start XFCE'
grep -q 'autostart/calamares.desktop' "$iso" || fail 'live session does not install a Calamares autostart entry'
grep -q 'sudo -n calamares' "$iso" || fail 'Calamares autostart is not non-interactive'
grep -q 'env_keep' "$iso" || fail 'live sudoers does not preserve the graphical environment'

sh -n "$ROOT/ports/opt/oh-my-bash/profile.sh" || fail 'oh-my-bash profile hook has invalid shell syntax'

echo 'Theme port/Calamares regression: PASS'
