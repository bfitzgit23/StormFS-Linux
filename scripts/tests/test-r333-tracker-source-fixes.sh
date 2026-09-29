#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
iso="$ROOT/scripts/bfs-build-iso.sh"
installer="$ROOT/scripts/install-bfs-menu-current.sh"

fail(){ echo "FAIL: $*" >&2; exit 1; }

grep -Fq "3) Shell" "$iso" || fail "live Shell menu entry missing"
! grep -Fq "Enable SSH for this boot" "$iso" || fail "stale SSH-enable menu entry remains"
! grep -Fq "bfs-live-enable-ssh" "$iso" || fail "stale SSH helper remains"
grep -Fq "sudo ssh-keygen -A" "$iso" || fail "manual SSH key generation guidance missing"
grep -Fq "parted" "$iso" || fail "parted missing from ISO package set"
grep -Fq "resume-full" "$iso" || fail "ISO bootstrap resume path missing"

grep -Fq "review_device_size" "$installer" || fail "swap/device review size helper missing"
grep -Fq '"swap" "$SWAP_DEV" "swap"' "$installer" || fail "swap review row missing"
grep -Fq "Finish returns directly to the calling shell/bootstrap" "$installer" || fail "Finish-to-shell source policy missing"

grep -Fq '# Depends on: linux-headers' "$ROOT/ports/core/glibc/Pkgfile" || fail "glibc header ordering dependency missing"
for p in cifs-utils rpcbind nfs-utils python3-sip python3-pyqt-builder python3-pyqt5; do
    test -f "$ROOT/ports/opt/$p/Pkgfile" || fail "missing new port: $p"
done
grep -Fq 'python3-pyqt5' "$ROOT/ports/compiz/fusion-icon/Pkgfile" || fail "Fusion Icon PyQt5 dependency missing"

# Numeric dispatch must remain direct and not fall through to the menu.
for n in 1 2 3 4 5; do
    grep -Eq "^[[:space:]]*$n\\|" "$ROOT/bootstrap.sh" || fail "bootstrap direct stage $n missing"
done

echo "PASS: r333 source-policy regression checks"
