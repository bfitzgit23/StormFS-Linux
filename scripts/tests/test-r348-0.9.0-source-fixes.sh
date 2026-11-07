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

[[ ! -e ports/opt/glib/.footprint ]] || fail 'generated final GLib footprint must not be committed for bootstrap pass'
grep -qx 'glib' ports/opt/gobject-introspection/depends || fail 'GI must depend on glib'
grep -qx 'gobject-introspection' ports/opt/polkit/depends || fail 'polkit must depend on GI'
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
