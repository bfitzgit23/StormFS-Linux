#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fail() { echo "build-work backend regression: FAIL: $*" >&2; exit 1; }
conf="$ROOT/ports/core/pkgutils/pkgmk.conf"
wrap="$ROOT/ports/core/pkgutils/bfs-pkgmk"
qt="$ROOT/ports/opt/qt6/Pkgfile"
pkg="$ROOT/ports/core/pkgutils/Pkgfile"

grep -q 'PKGMK_DISK_WORK_ROOT=.*build-work-disk' "$conf" || fail 'disk root missing'
grep -q 'disk).*PKGMK_WORK_DIR=' "$conf" || fail 'disk backend selection missing'
grep -q 'BFS_PKG_BUILD_WORK' "$wrap" || fail 'wrapper does not select backend before pkgmk'
grep -q '^build_work=disk$' "$qt" || fail 'Qt6 is not marked disk-backed'
grep -q 'build-work-disk' "$pkg" || fail 'pkgutils does not create disk-backed root'
# The disk root must not sit under the tmpfs mount.
! grep -q 'PKGMK_DISK_WORK_ROOT="/var/cache/pkg/build-work/' "$conf" || fail 'disk root is beneath tmpfs'

echo 'build-work backend regression: PASS'
