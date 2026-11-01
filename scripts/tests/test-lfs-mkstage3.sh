#!/bin/bash
#
# test-lfs-mkstage3.sh - regression test for scripts/lfs-mkstage3.sh.
#
# The stage3 builder targets scratchpkg only: the pacman matrix (fake pacman
# binaries, /var/lib/pacman fixtures, .PKGINFO identity) was removed with the
# package-manager migration, so this suite checks the scratchpkg paths and the
# refusal paths that replaced it.
#
# Usage: bash scripts/tests/test-lfs-mkstage3.sh
# Exit status 0 means every assertion held.

set -uo pipefail

ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/lfs-mkstage3.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/bfs-stage3-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

PASS=0
SKIPPED=0
FAILED=0

pass() { PASS=$((PASS + 1)); printf '  ok    %s
' "$1"; }
skip() { SKIPPED=$((SKIPPED + 1)); printf '  SKIP  %s (%s)
' "$1" "$2"; }
fail() {
    FAILED=$((FAILED + 1))
    printf '  FAIL  %s
' "$1" >&2
    [ $# -gt 1 ] && printf '        %s
' "$2" >&2
}

run() { RUN_OUT=$(bash "$SCRIPT" "$@" 2>&1); RUN_STATUS=$?; }
expect_status() { if [ "$RUN_STATUS" -eq "$1" ]; then pass "$2"; else fail "$2" "status $RUN_STATUS: $(printf '%s' "$RUN_OUT" | head -3)"; fi; }
expect_grep() { if printf '%s' "$RUN_OUT" | grep -Fq -- "$1"; then pass "$2"; else fail "$2" "missing: $1"; fi; }

printf 'stage3 builder scratchpkg regression
'

[ -f "$SCRIPT" ] || { echo "missing $SCRIPT" >&2; exit 1; }
bash -n "$SCRIPT" && pass "builder parses" || fail "builder parses"

# The builder must not carry pacman support any more.
if grep -q 'pacman' "$SCRIPT"; then
    fail "builder carries no pacman support" "found pacman references"
else
    pass "builder carries no pacman support"
fi

# scratchpkg root fixture: a database directory is the detection signal.
SP_ROOT="$WORK/sp-root"
mkdir -p "$SP_ROOT"/{var/lib/scratchpkg/db,etc,usr/bin} "$WORK/pkgdir"

run --pkgmgr scratchpkg --rootfs "$SP_ROOT" --compress --dry-run
expect_status 0 "pack dry-run (scratchpkg) exits 0"
expect_grep "Package manager: scratchpkg" "explicit scratchpkg selection is reported"

run --pkgmgr scratchpkg --rootfs "$SP_ROOT" --compress --dry-run -o "$WORK/out.tar.xz"
expect_status 0 "pack dry-run with output name exits 0"

# Autodetection must find the scratchpkg database.
run --rootfs "$SP_ROOT" --compress --dry-run
expect_status 0 "autodetect scratchpkg exits 0"
expect_grep "scratchpkg (detected)" "autodetect reports scratchpkg"

# pacman is no longer a supported package manager.
run --pkgmgr pacman --rootfs "$SP_ROOT" --dry-run
if [ "$RUN_STATUS" -ne 0 ]; then
    pass "pacman is refused as an unknown package manager"
else
    fail "pacman is refused as an unknown package manager" "exit status 0"
fi

# A missing rootfs must be refused rather than packed.
run --pkgmgr scratchpkg --rootfs "$WORK/does-not-exist" --dry-run
if [ "$RUN_STATUS" -ne 0 ]; then
    pass "missing rootfs is refused"
else
    fail "missing rootfs is refused" "exit status 0"
fi

printf '
%d passed, %d skipped, %d failed
' "$PASS" "$SKIPPED" "$FAILED"
[ "$FAILED" -eq 0 ]
