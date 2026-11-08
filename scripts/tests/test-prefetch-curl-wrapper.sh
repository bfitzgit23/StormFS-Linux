#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPPER="$ROOT/files/bfs-prefetch-curl"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"

cat > "$tmp/bin/curl" <<'CURL'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$FAKE_CURL_ARGS"

dest=""
prev=""
for a in "$@"; do
    if [ "$prev" = "-o" ]; then dest="$a"; fi
    prev="$a"
done

case "${!#}" in
    *ftpmirror*|*mirrors.kernel.org*|*ftp.x.org*|*downloads.sourceforge.net*)
        status=0
        ;;
    *www.x.org*)
        status="${FAKE_CURL_WWW_STATUS:-0}"
        ;;
    *)
        status="${FAKE_CURL_STATUS:-0}"
        ;;
esac

if [ -n "$dest" ]; then
    printf 'fake-archive-data' >"$dest"
else
    printf 'fake-archive-data'
fi

exit "$status"
CURL

chmod +x "$tmp/bin/curl"

export PATH="$tmp/bin:$PATH"
export FAKE_CURL_ARGS="$tmp/args"

#
# 1. pkgmk-style redirected stdout must be allowed.
#
"$WRAPPER" \
    https://example.invalid/archive.tar.xz \
    >"$tmp/stdout" \
    2>"$tmp/stderr"

[[ "$(cat "$tmp/stdout")" == "fake-archive-data" ]] || {
    echo 'FAIL: redirected downloader stdout was not preserved' >&2
    exit 1
}

mapfile -t args <"$tmp/args"
[[ "${args[*]}" == *"https://example.invalid/archive.tar.xz"* ]] || {
    printf 'FAIL: redirected curl arguments were not preserved: %q\n' \
        "${args[*]}" >&2
    exit 1
}

#
# 2. Explicit curl output destination must still work.
#
rm -f "$tmp/args"

"$WRAPPER" \
    -L \
    -o "$tmp/archive.tar.xz" \
    https://example.invalid/archive.tar.xz \
    >/dev/null

mapfile -t args <"$tmp/args"
[[ "${args[*]}" == *"-o $tmp/archive.tar.xz https://example.invalid/archive.tar.xz"* ]] || {
    printf 'FAIL: curl arguments were not preserved: %q\n' \
        "${args[*]}" >&2
    exit 1
}

[[ -s "$tmp/archive.tar.xz" ]] || {
    echo 'FAIL: explicit output destination was not written' >&2
    exit 1
}

#
# 3. -o without a destination must be rejected by the wrapper.
#
set +e
"$WRAPPER" \
    https://example.invalid/archive.tar.xz \
    -o \
    >"$tmp/bad-output.stdout" \
    2>"$tmp/bad-output.stderr"
status=$?
set -e

[[ $status -eq 2 ]] || {
    echo "FAIL: missing -o destination returned $status" >&2
    exit 1
}

grep -q \
    'curl output option is missing its destination' \
    "$tmp/bad-output.stderr" || {
        echo 'FAIL: missing-output diagnostic was not emitted' >&2
        exit 1
    }

#
# 4. Transport failures mark a matching primary unhealthy.
#
health="$tmp/health"

export BFS_PREFETCH_HEALTH_FILE="$health"
export BFS_PREFETCH_SOURCE_PREFIXES='https://ftp.gnu.org/gnu/'
export BFS_PREFETCH_MIRROR_MAP=none
export FAKE_CURL_STATUS=28

set +e
"$WRAPPER" \
    -o "$tmp/a" \
    https://ftp.gnu.org/gnu/bash/bash.tar.xz \
    >/dev/null \
    2>"$tmp/transport.err"
status=$?
set -e

[[ $status -eq 28 ]] || {
    echo "FAIL: transport status changed: $status" >&2
    exit 1
}

grep -Fxq \
    'https://ftp.gnu.org/gnu/' \
    "$health" || {
        echo 'FAIL: unhealthy primary was not recorded' >&2
        exit 1
    }

#
# 5. A primary marked unhealthy must be skipped for the rest of the run when
#    no mirror is configured.
#
export FAKE_CURL_STATUS=0
rm -f "$tmp/args"

set +e
"$WRAPPER" \
    -o "$tmp/b" \
    https://ftp.gnu.org/gnu/coreutils/coreutils.tar.xz \
    >/dev/null \
    2>"$tmp/skip.err"
status=$?
set -e

[[ $status -eq 7 ]] || {
    echo "FAIL: unhealthy primary was not skipped: $status" >&2
    exit 1
}

[[ ! -e "$tmp/args" ]] || {
    echo 'FAIL: curl was invoked for cached unhealthy primary' >&2
    exit 1
}

#
# 6. With a mirror configured, an unhealthy primary is served from the mirror
#    instead of failing the download.
#
export BFS_PREFETCH_MIRROR_MAP='https://ftp.gnu.org/gnu/=https://ftpmirror.gnu.org/'
rm -f "$tmp/args"

"$WRAPPER" \
    -o "$tmp/c" \
    https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz \
    >/dev/null \
    2>"$tmp/mirror.err"

mapfile -t args <"$tmp/args"
[[ "${args[*]}" == *"https://ftpmirror.gnu.org/gmp/gmp-6.3.0.tar.xz"* ]] || {
    printf 'FAIL: mirror URL was not used: %q\n' "${args[*]}" >&2
    exit 1
}

grep -q 'using mirror' "$tmp/mirror.err" || {
    echo 'FAIL: mirror fallback was not reported' >&2
    exit 1
}

#
# 7. A transport failure on a live primary must be retried on the mirror in the
#    same invocation.
#
rm -f "$health" "$tmp/args" "$tmp/d"
export FAKE_CURL_STATUS=28

"$WRAPPER" \
    -o "$tmp/d" \
    https://ftp.gnu.org/gnu/bash/bash-5.3.tar.gz \
    >/dev/null \
    2>"$tmp/fallback.err"

[[ -s "$tmp/d" ]] || {
    echo 'FAIL: mirror fallback did not produce an output file' >&2
    exit 1
}

mapfile -t args <"$tmp/args"
[[ "${args[*]}" == *"https://ftpmirror.gnu.org/bash/bash-5.3.tar.gz"* ]] || {
    printf 'FAIL: mirror was not retried after a primary failure: %q\n' "${args[*]}" >&2
    exit 1
}

grep -Fxq 'https://ftp.gnu.org/gnu/' "$health" || {
    echo 'FAIL: failed primary was not recorded during mirror fallback' >&2
    exit 1
}

#
# 8. Non-transport failures are source specific and must not be mirrored.
#
rm -f "$health" "$tmp/args" "$tmp/e"
export FAKE_CURL_STATUS=22

set +e
"$WRAPPER" \
    -o "$tmp/e" \
    https://ftp.gnu.org/gnu/bash/bash-5.3.tar.gz \
    >/dev/null \
    2>"$tmp/http.err"
status=$?
set -e

[[ $status -eq 22 ]] || {
    echo "FAIL: HTTP failure status changed: $status" >&2
    exit 1
}

mapfile -t args <"$tmp/args"
[[ "${args[*]}" != *"ftpmirror"* ]] || {
    printf 'FAIL: HTTP failures must not be retried on a mirror: %q\n' "${args[*]}" >&2
    exit 1
}

[[ ! -e "$health" ]] || {
    echo 'FAIL: HTTP failure poisoned the origin for the rest of the run' >&2
    exit 1
}

#
# 9. The default mirror map must cover the X.Org origin with the CDN hosts.
#
unset BFS_PREFETCH_SOURCE_PREFIXES BFS_PREFETCH_MIRROR_MAP
rm -f "$health" "$tmp/args" "$tmp/x"
export FAKE_CURL_STATUS=28

set +e
"$WRAPPER" \
    -o "$tmp/x" \
    https://xorg.freedesktop.org/archive/individual/lib/libX11-1.8.13.tar.xz \
    >/dev/null \
    2>"$tmp/xorg.err"
status=$?
set -e

[[ $status -eq 0 ]] || {
    echo "FAIL: X.Org files were not recovered from a mirror: $status" >&2
    exit 1
}

[[ -s "$tmp/x" ]] || {
    echo 'FAIL: X.Org mirror fallback produced no output file' >&2
    exit 1
}

mapfile -t args <"$tmp/args"
[[ "${args[*]}" == *"https://www.x.org/releases/individual/lib/libX11-1.8.13.tar.xz"* ]] || {
    printf 'FAIL: X.Org mirror URL was not used: %q\n' "${args[*]}" >&2
    exit 1
}

grep -Fxq 'https://xorg.freedesktop.org/archive/individual/' "$health" || {
    echo 'FAIL: failed X.Org origin was not recorded' >&2
    exit 1
}

#
# 10. A failing www.x.org CDN host must fall back to ftp.x.org.
#
rm -f "$health" "$tmp/args" "$tmp/y"
export FAKE_CURL_STATUS=28
export FAKE_CURL_WWW_STATUS=28

"$WRAPPER" \
    -o "$tmp/y" \
    https://www.x.org/releases/individual/app/xauth-1.1.5.tar.xz \
    >/dev/null \
    2>"$tmp/xorg-cdn.err"

mapfile -t args <"$tmp/args"
[[ "${args[*]}" == *"https://ftp.x.org/pub/individual/app/xauth-1.1.5.tar.xz"* ]] || {
    printf 'FAIL: second X.Org mirror was not used: %q\n' "${args[*]}" >&2
    exit 1
}

unset FAKE_CURL_WWW_STATUS

#
# 11. The default map must recover the NuTyX Broadcom source from SourceForge.
#
unset BFS_PREFETCH_SOURCE_PREFIXES BFS_PREFETCH_MIRROR_MAP
rm -f "$health" "$tmp/args" "$tmp/broadcom"
export FAKE_CURL_STATUS=28

"$WRAPPER"     -o "$tmp/broadcom"     http://download.tuxfamily.org/nutyx/sources/broadcom-wl/broadcom-wl-6.30.223.271.tar.xz     >/dev/null     2>"$tmp/broadcom.err"

[[ -s "$tmp/broadcom" ]] || {
    echo 'FAIL: Broadcom source fallback produced no output file' >&2
    exit 1
}

mapfile -t args <"$tmp/args"
[[ "${args[*]}" == *"https://downloads.sourceforge.net/project/nutyx/files/broadcom-wl-6.30.223.271.tar.xz"* ]] || {
    printf 'FAIL: Broadcom SourceForge mirror URL was not used: %q
' "${args[*]}" >&2
    exit 1
}

grep -Fxq 'http://download.tuxfamily.org/nutyx/sources/broadcom-wl/' "$health" || {
    echo 'FAIL: failed Broadcom origin was not recorded' >&2
    exit 1
}

echo 'prefetch curl wrapper regression: PASS'
