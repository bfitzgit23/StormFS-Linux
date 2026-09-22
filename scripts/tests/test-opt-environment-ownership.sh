#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

base=ports/core/aaa_filesystem/Pkgfile
for f in bfs-opt.sh kf6.sh; do
    grep -Fq "$f" "$base" || { echo "aaa_filesystem missing $f" >&2; exit 1; }
done
for retired in qt5.sh qt6.sh rustc.sh; do
    ! grep -Eq "(^|[[:space:]])${retired}([[:space:]]|$)" "$base" || {
        echo "aaa_filesystem must not claim legacy leaf-owned $retired during migration" >&2
        exit 1
    }
done
for prefix in /opt/qt5 /opt/qt6 /opt/rustc; do
    grep -Fq "$prefix" ports/core/aaa_filesystem/bfs-opt.sh || { echo "bfs-opt.sh missing $prefix" >&2; exit 1; }
done
grep -Fq '60-bfsos-opt.conf' "$base"
grep -Fq '/opt/kf6/bin:/opt/qt6/bin' ports/core/aaa_filesystem/60-bfsos-opt.conf
grep -Fq 'XDG_DATA_DIRS=/usr/local/share:/usr/share:/opt/kf6/share' ports/core/aaa_filesystem/60-bfsos-opt.conf

for leaf in ports/opt/qt5/Pkgfile ports/opt/qt6/Pkgfile ports/opt/rustc/Pkgfile; do
    if grep -Eq '\$PKG/etc/profile\.d|\$PKG/etc/profile.d' "$leaf"; then
        echo "leaf package still owns canonical profile.d content: $leaf" >&2
        exit 1
    fi
done
for hook in ports/opt/qt6/pre-install ports/opt/qt6/post-install ports/plasma/plasma-wayland-protocols/post-install; do
    if grep -Eq '(/etc/profile\.d/(qt5|qt6|kf6|rustc)\.sh|cat[[:space:]].*profile\.d)' "$hook"; then
        echo "hook still rewrites canonical profile environment: $hook" >&2
        exit 1
    fi
done

# The login-shell layer must not duplicate KF6 in the hard-coded initial PATH.
! grep -Eq '^export PATH=.*opt/kf6' ports/core/aaa_filesystem/profile

echo "canonical /opt environment ownership regression: PASS"
