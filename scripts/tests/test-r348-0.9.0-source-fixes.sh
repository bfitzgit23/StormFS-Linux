#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

fail(){ echo "FAIL: $*" >&2; exit 1; }
pass(){ echo "PASS: $*"; }

[[ $(tr -d '[:space:]' < VERSION) == 0.9.0 ]] || fail 'VERSION is not 0.9.0'
grep -q 'bfs_version=0.9.0' ports/core/aaa_filesystem/spkgbuild || fail 'aaa_filesystem 0.9.0 identity missing'
pass '0.9.0 authoritative version and filesystem identity'

for f in bootstrap.sh bootstrap-clean-start.sh scripts/bfs-build-iso.sh scripts/install-bfs-menu-current.sh scripts/bfs-publish-sourceforge.sh; do
  bash -n "$f" || fail "$f syntax"
done
pass 'bootstrap/ISO/installer/publisher shell syntax'

openrc_recipe=ports/opt/openrc/spkgbuild
grep -Fq 'https://www.linuxfromscratch.org/glfs/view/dev/download/openrc/openrc-$version-lock-1.patch' "$openrc_recipe" || \
    fail 'OpenRC lock patch source missing'
grep -Fq 'for _bfs_patch in "$SRC"/*.patch "$SRC"/*.diff; do' "$openrc_recipe" || \
    fail 'OpenRC lock patch is not applied'
grep -Fq -- '-D uucp_group=root' "$openrc_recipe" || \
    fail 'OpenRC root lock group option missing'
grep -qx 'release=4' "$openrc_recipe" || fail 'OpenRC recipe release missing'
grep -Fq 'install -m 0644 "$SRC/inittab" "$PKG/etc/inittab"' "$openrc_recipe" || \
    fail 'OpenRC inittab is not installed from the source root'
line_openrc_patch=$(grep -n 'patch -t "${patch_opt:--p1}" -i "$_bfs_patch"' "$openrc_recipe" | cut -d: -f1)
line_openrc_meson=$(grep -n 'meson setup' "$openrc_recipe" | cut -d: -f1)
(( line_openrc_patch < line_openrc_meson )) || fail 'OpenRC lock patch must be applied before meson setup'
pass 'OpenRC lock patch and uucp_group option'

grep -qx 'release=3' ports/opt/bluez/spkgbuild || fail 'BlueZ OpenRC-only recipe release missing'
grep -Fq -- '--disable-systemd' ports/opt/bluez/spkgbuild || fail 'BlueZ still enables systemd integration'
grep -Fq 'rm -rf "$PKG/usr/lib/systemd" "$PKG/lib/systemd"' ports/opt/bluez/spkgbuild || \
    fail 'BlueZ does not strip packaged systemd units'
grep -Fq 'need dbus' ports/opt/openrc-init-scripts/bluetooth || \
    fail 'BlueZ OpenRC service does not require dbus'
grep -qx 'release=4' ports/opt/openrc-init-scripts/spkgbuild || \
    fail 'OpenRC service-script release missing'
pass 'BlueZ OpenRC-only build and service dependency'

grep -qx 'release=3' ports/opt/chrony/spkgbuild || fail 'Chrony OpenRC-only release missing'
! grep -Fq 'usr/lib/sysusers.d' ports/opt/chrony/spkgbuild || fail 'Chrony still packages systemd sysusers data'
! grep -Fq 'usr/lib/tmpfiles.d' ports/opt/chrony/spkgbuild || fail 'Chrony still packages systemd tmpfiles data'
grep -qx 'release=4' ports/opt/avahi/spkgbuild || fail 'Avahi OpenRC-only release missing'
grep -Fq -- '--with-systemdsystemunitdir=no' ports/opt/avahi/spkgbuild || \
    fail 'Avahi still installs systemd units'
grep -qx 'release=3' ports/opt/cups/spkgbuild || fail 'CUPS OpenRC-only release missing'
grep -Fq -- '--without-systemd' ports/opt/cups/spkgbuild || fail 'CUPS still enables systemd integration'
grep -Fq -- '--without-rcdir' ports/opt/cups/spkgbuild || fail 'CUPS still installs a SysV init script'
grep -qx 'release=3' ports/opt/smartmontools/spkgbuild || fail 'smartmontools OpenRC-only release missing'
grep -Fq -- '--with-libsystemd=no' ports/opt/smartmontools/spkgbuild || \
    fail 'smartmontools still links libsystemd'
! grep -Fq 'systemctl' ports/opt/accountsservice/post-install || \
    fail 'AccountsService still calls systemctl from post-install'
grep -qx 'release=3' ports/opt/accountsservice/spkgbuild || fail 'AccountsService release missing'
grep -qx 'release=3' ports/opt/upower/spkgbuild || fail 'UPower release missing'
grep -Fq 'systemdsystemunitdir=no' ports/opt/upower/spkgbuild || fail 'UPower still installs systemd units'
grep -qx 'release=3' ports/opt/udisks/spkgbuild || fail 'UDisks release missing'
grep -Fq 'with-tmpfilesdir=no' ports/opt/udisks/spkgbuild || fail 'UDisks still packages systemd tmpfiles'
grep -qx 'release=4' ports/opt/lightdm/spkgbuild || fail 'LightDM ConsoleKit release missing'
grep -Fq 'pam_ck_connector' ports/opt/lightdm/spkgbuild || fail 'LightDM still references pam_systemd'
grep -qx 'release=5' ports/plasma/sddm/spkgbuild || fail 'SDDM OpenRC-only release missing'
grep -Fq 'NO_SYSTEMD=ON' ports/plasma/sddm/spkgbuild || fail 'SDDM still builds systemd support'
! grep -Fq 'pam_systemd' ports/plasma/sddm/post-install || fail 'SDDM PAM policy still references pam_systemd'
grep -qx 'release=5' ports/core/linux-pam/spkgbuild || fail 'Linux-PAM ConsoleKit release missing'
grep -Fq 'pam_ck_connector' ports/core/linux-pam/system-session || \
    fail 'system-session still references pam_systemd'
grep -Fq 'systemd=disabled' ports/opt/wireplumber/spkgbuild || fail 'WirePlumber still enables systemd units'
grep -Fq 'smartd' ports/opt/openrc-init-scripts/spkgbuild || fail 'OpenRC service package omits smartd'
[ -x ports/opt/openrc-init-scripts/smartd ] || fail 'openrc-init-scripts is missing smartd'
grep -Fq 'command_args="-n"' ports/opt/openrc-init-scripts/smartd || \
    fail 'smartd wrapper does not keep smartd in the foreground'
grep -Fq 'prt-get install smartmontools openrc-init-scripts' docs/openrc-book/chapters/14-system-services.md || \
    fail 'smartd documentation omits the OpenRC service package'
pass 'system service packages install OpenRC/ConsoleKit integration only'

[[ ! -e ports/opt/glib/.footprint ]] || fail 'generated final GLib footprint must not be committed for bootstrap pass'
grep -qx 'glib' ports/opt/gobject-introspection/depends || fail 'GI must depend on glib'
grep -qx 'gobject-introspection' ports/opt/polkit/depends || fail 'polkit must depend on GI'
grep -qx 'consolekit' ports/opt/polkit/depends || fail 'polkit must depend on its ConsoleKit session provider'
grep -Fq 'session_tracking=ConsoleKit' ports/opt/polkit/spkgbuild || fail 'polkit still requests the libsystemd logind backend'
! grep -Fq 'session_tracking=logind' ports/opt/polkit/spkgbuild || fail 'polkit still requests the libsystemd logind backend'
grep -Fq 'release=5' ports/opt/polkit/spkgbuild || fail 'polkit ConsoleKit recipe release missing'
grep -Fq 'for polkit_port in opt/polkit opt/consolekit; do' scripts/install-bfs-menu-current.sh || fail 'installer does not refresh the Polkit/ConsoleKit recipes'
xorg_case_ports='
xorg/libxau libXau
xorg/libfs libFS
xorg/libice libICE
xorg/libsm libSM
xorg/libx11 libX11
xorg/libxaw libXaw
xorg/libxcomposite libXcomposite
xorg/libxcursor libXcursor
xorg/libxdamage libXdamage
xorg/libxdmcp libXdmcp
xorg/libxext libXext
xorg/libxfixes libXfixes
xorg/libxfont2 libXfont2
xorg/libxft libXft
xorg/libxi libXi
xorg/libxinerama libXinerama
xorg/libxmu libXmu
xorg/libxpm libXpm
xorg/libxpresent libXpresent
xorg/libxrandr libXrandr
xorg/libxrender libXrender
xorg/libxres libXres
xorg/libxscrnsaver libXScrnSaver
xorg/libxt libXt
xorg/libxtst libXtst
xorg/libxv libXv
xorg/libxvmc libXvMC
xorg/libxxf86dga libXxf86dga
xorg/libxxf86vm libXxf86vm
compat-32/libXau-32 libXau
compat-32/libSM-32 libSM
compat-32/libX11-32 libX11
compat-32/libXScrnSaver-32 libXScrnSaver
compat-32/libXcomposite-32 libXcomposite
compat-32/libXcursor-32 libXcursor
compat-32/libXdamage-32 libXdamage
compat-32/libXdmcp-32 libXdmcp
compat-32/libXext-32 libXext
compat-32/libXfixes-32 libXfixes
compat-32/libXft-32 libXft
compat-32/libXi-32 libXi
compat-32/libXinerama-32 libXinerama
compat-32/libXmu-32 libXmu
compat-32/libXrandr-32 libXrandr
compat-32/libXrender-32 libXrender
compat-32/libXt-32 libXt
compat-32/libXtst-32 libXtst
compat-32/libXv-32 libXv
compat-32/libXvMC-32 libXvMC
compat-32/libXxf86vm-32 libXxf86vm
compat-32/libice-32 libICE
'
while read -r xorg_case_port xorg_case_archive; do
    [[ -n "$xorg_case_port" ]] || continue
    grep -Fq "/$xorg_case_archive-\$version.tar.xz" "ports/$xorg_case_port/spkgbuild" || \
        fail "$xorg_case_port does not use the case-correct $xorg_case_archive archive"
    xorg_case_lower=$(printf '%s' "$xorg_case_archive" | tr '[:upper:]' '[:lower:]')
    if [[ "$xorg_case_lower" != "$xorg_case_archive" ]]; then
        ! grep -Fq "/$xorg_case_lower-\$version.tar.xz" "ports/$xorg_case_port/spkgbuild" || \
            fail "$xorg_case_port still requests the missing lowercase archive"
    fi
    grep -Fq "$xorg_case_port" scripts/install-bfs-menu-current.sh || \
        fail "installer does not refresh $xorg_case_port"
done <<< "$xorg_case_ports"
pass 'native and compat-32 X.Org CamelCase archive names and installer refresh'
line_func=$(grep -n '^ensure_glib_introspection_ready()' scripts/install-bfs-menu-current.sh | cut -d: -f1)
line_sysup=$(grep -n 'mandatory package upgrade (scratch sysup -y)' scripts/install-bfs-menu-current.sh | cut -d: -f1)
(( line_func < line_sysup )) || fail 'GI preflight must be defined before mandatory sysup'
grep -q 'rm -f "$glib_footprint"' scripts/install-bfs-menu-current.sh || fail 'bootstrap GLib footprint cleanup missing'
! grep -Fq 'scratch quickdiff' scripts/install-bfs-menu-current.sh || fail 'retired scratch quickdiff command remains'
! grep -Fq 'scratch quickdep' scripts/install-bfs-menu-current.sh || fail 'retired scratch quickdep command remains'
grep -Fq 'scratch outdate' scripts/install-bfs-menu-current.sh || fail 'installer does not query scratch outdated ports'
grep -Fq 'scratch deplist -q' scripts/install-bfs-menu-current.sh || fail 'installer does not query scratch dependency closure'
grep -Fq "closure=\"\${closure//\$'\\n'/ }\"" scripts/install-bfs-menu-current.sh || fail 'GLib preflight does not normalize newline-separated package lists'
grep -Fq 'scratch install -f -r -y glib' scripts/install-bfs-menu-current.sh || fail 'GLib introspection rebuild command is invalid'
! grep -Fq 'scratch -fr update glib' scripts/install-bfs-menu-current.sh || fail 'invalid scratch option order remains'
grep -Fq 'ensure_glib_introspection_ready "$outdated_packages $dependency_closure"' scripts/install-bfs-menu-current.sh || fail 'installed GLib preflight omits outdated package names'
line_glib_check=$(grep -n 'ensure_glib_introspection_ready "$outdated_packages $dependency_closure"' scripts/install-bfs-menu-current.sh | cut -d: -f1)
line_glib_closure=$(grep -n 'if \[\[ -n "$dependency_closure" \]\]; then' scripts/install-bfs-menu-current.sh | cut -d: -f1 | tail -n1)
(( line_glib_check < line_glib_closure )) || fail 'GLib preflight is gated behind a nonempty dependency closure'
! grep -Fq 'pkgbuild -d' scripts/bfs-build-iso.sh || fail 'ISO GLib rebuild uses an invalid pkgbuild option'
grep -Fq 'pkgbuild -f' scripts/bfs-build-iso.sh || fail 'ISO GLib rebuild command is missing'
grep -Fq 'glib#*.pkg.tar.*' scripts/bfs-build-iso.sh || fail 'ISO GLib package lookup assumes zstd packaging'
! grep -Fq 'glib#*.pkg.tar.zst' scripts/bfs-build-iso.sh || fail 'ISO GLib package lookup still assumes zstd packaging'
pass 'GLib/GI/Polkit bootstrap ordering and scratch command policy'

grep -q 'No usable partitions found; returning to the previous storage menu' scripts/install-bfs-menu-current.sh || fail 'blank-disk recovery missing'
grep -q 'mount -t btrfs "$device" "$temp_mount"' scripts/install-bfs-menu-current.sh || fail 'explicit Btrfs mount missing'
grep -q 'for mount_attempt in 1 2 3 4 5' scripts/install-bfs-menu-current.sh || fail 'Btrfs retry loop missing'
pass 'blank-disk and Btrfs recovery source fixes'

grep -q 'BFSOS-base-${release}-x86_64.tar.zst' scripts/install-bfs-menu-current.sh || fail 'installer versioned base default missing'
grep -q 'BFSOS-base-${VERSION}-${ARCH}.tar.zst' scripts/bfs-build-iso.sh || fail 'ISO versioned base default missing'
grep -q 'BFSOS-base-${base_release}-${ARCH}.tar.zst' scripts/bfs-publish-sourceforge.sh || fail 'publisher versioned base name missing'
grep -q 'checkout -B "$GIT_REF" "origin/$GIT_REF"' scripts/bfs-build-iso.sh || fail 'ISO tracking-branch checkout missing'
pass 'versioned base identity and live branch checkout source fixes'

grep -q "bfs-toolchain-\${BFS_VERSION}-\${BUILD_DATE}.tar.zst" bootstrap.sh || fail 'versioned zstd toolchain archive missing'
grep -q "bfs-rootfs-\${BFS_VERSION}-\${BUILD_DATE}.tar.zst" bootstrap.sh || fail 'versioned zstd base archive missing'
grep -q '_prefetch_bootstrap_sources /tmp/bootstrap.conf' bootstrap.sh || fail 'bootstrap source prefetch call missing'
pass 'bootstrap prefetch and zstd artifact source fixes'

./scripts/bfs-xorg-audit.py >/tmp/bfs-r348-xorg-audit.out || { cat /tmp/bfs-r348-xorg-audit.out; fail 'X.Org static audit'; }
grep -q '^version=26.2.3$' ports/xorg/mesa/spkgbuild || fail 'Mesa 26.2.3 update missing'
grep -q '^version=1.0.6$' ports/xorg/xorg-font-alias/spkgbuild || fail 'font-alias 1.0.6 update missing'
pass '180-port X.Org static audit and verified updates'

grep -q 'base_remote="$SF_ROOT/base/archive/$base_release"' scripts/bfs-publish-sourceforge.sh || fail 'publisher archive layout missing'
grep -q 'ACTIVE_RELEASE=.*VERSION' scripts/bfs-publish-sourceforge.sh || fail 'publisher authoritative release scoping missing'
grep -q 'Clear previous install state and start fresh' scripts/install-bfs-menu-current.sh || fail 'installer fresh-start recovery option missing'
grep -q 'wipefs -a "$device"' scripts/install-bfs-menu-current.sh || fail 'destructive format signature cleanup missing'
grep -q '_cleanup_completed_bootstrap_state' bootstrap.sh || fail 'successful-bootstrap tmp cleanup missing'
grep -q 'pkgbuild -o' bootstrap.sh || fail 'scratchpkg prefetch path missing'
grep -q 'chown -R bfs:bfs /home/bfs/BFSOS' scripts/bfs-build-iso.sh || fail 'live checkout bfs ownership normalization missing'
grep -q '^version=7.2.8$' ports/core/linux/spkgbuild || fail 'current kernel 7.2.8 update missing'
grep -q '^version=7.3.1$' ports/core/linux-lts/spkgbuild || fail 'default kernel 7.3.1 update missing'
pass 'r341-r347 release hardening source fixes'

echo 'r348 0.9.0 source regression checks passed.' 
