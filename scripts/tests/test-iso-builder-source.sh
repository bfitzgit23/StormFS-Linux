#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
iso="$ROOT/scripts/bfs-build-iso.sh"
boot="$ROOT/bootstrap.sh"
fail() { echo "ISO builder source regression: FAIL: $*" >&2; exit 1; }

[ -x "$iso" ] || fail 'scripts/bfs-build-iso.sh is missing or not executable'
bash -n "$iso" || fail 'ISO builder shell syntax failed'
bash -n "$boot" || fail 'bootstrap shell syntax failed'

grep -q 'Build BFSOS bootable ISO' "$boot" || fail 'bootstrap menu does not expose ISO builder'
grep -q 'iso|build-iso|create-iso' "$boot" || fail 'bootstrap CLI does not expose ISO builder'

for token in mksquashfs xorriso grub-mkrescue grub-platform:i386-pc grub-platform:x86_64-efi; do
    grep -q "$token" "$iso" || fail "ISO preflight is missing $token"
done
for pkg in networkmanager-iso openssh git sudo wget wpa_supplicant wireless-regdb gpm lynx-iso chrony cryptsetup lvm2 mdadm snapper grub grub-efi squashfs-tools libisoburn; do
    grep -q "\b$pkg\b" "$iso" || fail "ISO package set is missing $pkg"
done
for pkg in xfce4-meta compiz-meta lightdm lightdm-gtk-greeter chromium-bin firefox-bin fastfetch mousepad libreoffice-bin flameshot galculator vlc gparted mintstick \
    thunderbird-bin pidgin rustdesk engrampa thunar-volman thunar-archive-plugin thunar-media-tags-plugin \
    p7zip unzip unrar gvfs gnupg xfce4-docklike-plugin xfce4-weather-plugin xfce4-whiskermenu-plugin \
    xfce4-power-manager xfce4-pulseaudio-plugin pavucontrol; do
    grep -q "\b$pkg\b" "$iso" || fail "ISO desktop package set is missing $pkg"
done
for pkg in system-config-printer hplip-plugin hpcups gutenprint epson-inkjet-printer-escpr; do
    grep -Fq -- "$pkg" "$iso" || fail "ISO printing package set is missing $pkg"
done
[ -f "$ROOT/ports/opt/mintstick/spkgbuild" ] || fail 'mintstick port is missing'
for port in \
    compiz/compiz-meta opt/lightdm opt/lightdm-gtk-greeter opt/engrampa opt/pidgin opt/rustdesk opt/thunderbird-bin \
    opt/p7zip opt/unzip opt/unrar opt/gtk-layer-shell opt/gnupg opt/pavucontrol \
    gnome/gvfs xfce/thunar-volman xfce/thunar-archive-plugin xfce/thunar-media-tags-plugin \
    xfce/xfce4-docklike-plugin xfce/xfce4-power-manager \
    xfce/xfce4-pulseaudio-plugin xfce/xfce4-weather-plugin \
    xfce/xfce4-whiskermenu-plugin; do
    [ -f "$ROOT/ports/$port/spkgbuild" ] || fail "ISO package port is missing: $port"
done
for dep in python3-gnupg python3-pyparted python3-unidecode; do
    [ -f "$ROOT/ports/opt/$dep/spkgbuild" ] || fail "mintstick dependency port is missing: $dep"
done
! grep -Eq '(^|[[:space:]])chromium([[:space:]]|$)' "$iso" || \
    fail 'ISO still includes the source-built chromium package'
! grep -Eq '(^|[[:space:]])lxdm([[:space:]]|$)' "$iso" || \
    fail 'ISO package set still includes LXDM'
for pkg in calamares adw-gtk3 tela-icon-theme stormfs-theme lightdm-gtk-greeter oh-my-bash xinit xauth shadow; do
    grep -q "\b$pkg\b" "$iso" || fail "ISO installer/theme package set is missing $pkg"
done

[ -f "$ROOT/ports/iso/networkmanager-iso/spkgbuild" ] || fail 'networkmanager-iso port is missing'
[ -f "$ROOT/ports/iso/lynx-iso/spkgbuild" ] || fail 'lynx-iso port is missing'
grep -q -- '-Dwifi=true' "$ROOT/ports/iso/networkmanager-iso/spkgbuild" || fail 'ISO NetworkManager lost Wi-Fi support'
grep -q -- '-Dnmcli=true' "$ROOT/ports/iso/networkmanager-iso/spkgbuild" || fail 'ISO NetworkManager lost nmcli'
grep -q -- '-Dnmtui=true' "$ROOT/ports/iso/networkmanager-iso/spkgbuild" || fail 'ISO NetworkManager lost nmtui'
for nm_recipe in opt/networkmanager iso/networkmanager-iso; do
    nm_file="$ROOT/ports/$nm_recipe/spkgbuild"
    for nm_opt in session_tracking=no session_tracking_consolekit=true \
        suspend_resume=consolekit systemd_journal=false \
        systemdsystemunitdir=no systemdsystemgeneratordir=no; do
        grep -q -- "-D$nm_opt" "$nm_file" || fail "$nm_recipe is missing -D$nm_opt"
    done
done
grep -q -- '-Dsystemdsystemgeneratordir=no' "$ROOT/ports/compat-32/libnm-32/spkgbuild" || \
    fail 'libnm-32 still requires a systemd generator directory'

grep -q 'downloads.sourceforge.net/project/bfsos/BFSOS/base/latest' "$iso" || fail 'SourceForge base URL is missing'
grep -q 'BASE_SHA256_URL' "$iso" || fail 'SourceForge base checksum verification is missing'
grep -q 'verify_sha256_file' "$iso" || fail 'base SHA256 verifier is missing'
for repo in core extra nonfree multilib s6 kde-lxqt mate xfce s6-services; do
    grep -q "https://codeberg.org/venomlinux/$repo.git" "$iso" ||
        fail "Venom Linux repository is missing: $repo"
done
grep -q 'VENOM_SUPPORT_REPOS' "$iso" || fail 'Venom support-repository handling is missing'
grep -q 's6-services' "$iso" || fail 's6-services support repository is missing'
grep -q 'prepare_build_project' "$iso" || fail 'automatic clean Git checkout is missing'
grep -q 'VENOM_PORTS_DIR' "$iso" || fail 'Venom ports staging directory is missing'
grep -q 'register_iso_port_collections' "$iso" || fail 'Venom collections are not registered with scratchpkg'
grep -q 'VENOM_PORTS_SOURCES' "$iso" || fail 'Venom ports provenance is missing'
grep -q 'GIT_COMMIT_FULL' "$iso" || fail 'full Git commit provenance is missing'
grep -q '/etc/bfs-build-info' "$iso" || fail 'embedded build provenance is missing'

grep -q 'git pull --ff-only' "$iso" || fail 'safe live online project refresh is missing'
grep -q 'GIT_TERMINAL_PROMPT=0' "$iso" || fail 'live project refresh can block on Git credentials'
grep -Fq "grep -qw 'bfs.live=1' /proc/cmdline" "$iso" || fail 'live init has no installed-system guard'
! grep -q '/usr/local/sbin/bfs-live-console-font || true' "$iso" || fail 'boot-time console-font prompt blocks local'
grep -q 'passwd bfs' "$iso" || fail 'temporary bfs live-password prompt is missing'
grep -q 'ssh-keygen -A' "$iso" || fail 'runtime SSH host-key generation is missing'
grep -q 'rc-service sshd' "$iso" || fail 'runtime SSH startup is missing'
grep -q 'rc-update add networkmanager default' "$iso" \
	|| fail 'NetworkManager live default is missing'
grep -q 'openrc-init-scripts' "$iso" || fail 'ISO package set does not install the OpenRC service scripts'
grep -q 'need networkmanager' "$iso" || fail 'live init does not depend on networkmanager'
! grep -q 'need NetworkManager' "$iso" || fail 'live init still uses the systemd-style NetworkManager name'
grep -q 'rootfs.squashfs' "$iso" || fail 'SquashFS live-root staging is missing'
grep -q 'autologin-user=bfs' "$iso" || fail 'live LightDM autologin is missing'
grep -q 'autologin-user-timeout=0' "$iso" || fail 'live LightDM autologin timeout is missing'
grep -q 'autologin-session=xfce' "$iso" || fail 'live LightDM autologin session is missing'
grep -q 'rc-update add dbus default' "$iso" || fail 'live D-Bus service is not enabled'
grep -q 'rc-update add consolekit default' "$iso" || fail 'live ConsoleKit service is not enabled'
grep -q 'rc-update add lightdm default' "$iso" || fail 'live LightDM service is not enabled'
grep -q 'chpasswd -c SHA512' "$iso" || fail 'live bfs fallback password is not set'
grep -q 'need localmount dbus' "$ROOT/ports/opt/openrc-init-scripts/lightdm" || \
	fail 'LightDM does not require the D-Bus service'
! grep -Fq '    startx' "$iso" || fail 'live session still starts startx'
grep -q 'mount -t overlay overlay' "$iso" || fail 'writable overlay root is missing'

grep -q -- '-comp xz -b 1M -Xdict-size 100% -Xbcj x86' "$iso" || fail 'size-oriented SquashFS settings are missing'
grep -q 'audit_live_root' "$iso" || fail 'live-root archive audit is missing'
grep -q "Forbidden tar/package archives remain" "$iso" || fail 'forbidden-archive failure policy is missing'

# The RC2 policy must not copy base/package tar archives onto release media.
if grep -Eq 'cp .*base_archive.*stage/bfsos|packages\.sha256|packages\.list|Preserve one copy of package archives' "$iso"; then
    fail 'old offline tar/package-archive staging policy is still present'
fi

echo 'ISO builder source regression: PASS'
