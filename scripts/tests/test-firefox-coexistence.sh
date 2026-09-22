#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fail() { echo "firefox coexistence regression: FAIL: $*" >&2; exit 1; }

normal="$ROOT/ports/opt/firefox/Pkgfile"
esr="$ROOT/ports/opt/firefox-esr/Pkgfile"
bin="$ROOT/ports/opt/firefox-bin/Pkgfile"

# Three distinct package/application roots and launchers.
grep -q 'MOZ_APP_REMOTINGNAME=firefox$' "$normal" || fail 'normal remoting identity missing'
grep -q 'MOZ_APP_PROFILE=firefox$' "$normal" || fail 'normal profile identity missing'
grep -q 'MOZ_APP_REMOTINGNAME=firefox-esr$' "$esr" || fail 'ESR remoting identity missing'
! grep -q 'MOZ_APP_PROFILE=firefox-esr$' "$esr" || fail 'ESR mozconfig must not set forbidden MOZ_APP_PROFILE'
grep -q '/usr/lib/firefox-esr' "$esr" || fail 'ESR application root is not separate'
grep -q 'Name=Firefox ESR' "$esr" || fail 'ESR visible identity is not Firefox ESR'

grep -q 'usr/lib/firefox-bin' "$bin" || fail 'binary application root is not separate'
grep -q 'usr/bin/firefox-bin' "$bin" || fail 'binary launcher is not separate'
grep -q 'firefox-bin.desktop' "$bin" || fail 'binary desktop filename is not separate'
grep -q 'Profile=firefox-bin' "$bin" || fail 'binary profile override is missing'
grep -q 'RemotingName=firefox-bin' "$bin" || fail 'binary remoting override is missing'
grep -q -- '-app /usr/lib/firefox-bin/browser/application.ini' "$ROOT/ports/opt/firefox-bin/firefox-bin" || fail 'binary launcher does not use package-owned app identity'
grep -q "s/\^Name=.*Name=Firefox BIN/" "$bin" || fail 'binary visible identity transform is not Firefox BIN'
grep -q '^Exec=firefox-bin %U$' "$ROOT/ports/opt/firefox-bin/firefox.desktop" || fail 'binary desktop launcher is wrong'
grep -q '^Icon=firefox-bin$' "$ROOT/ports/opt/firefox-bin/firefox.desktop" || fail 'binary desktop icon identity is wrong'

# The binary package must not reclaim normal Firefox-owned paths.
! grep -Eq 'PKG/usr/lib/firefox([^/-]|$)|PKG/usr/bin/firefox(["[:space:]]|$)|applications/firefox\.desktop|pixmaps/firefox\.png' "$bin" || fail 'firefox-bin still claims a normal Firefox path'

echo 'firefox coexistence regression: PASS'
