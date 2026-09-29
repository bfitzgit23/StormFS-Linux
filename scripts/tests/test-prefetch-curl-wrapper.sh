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
printf 'fake-archive-data'
exit "${FAKE_CURL_STATUS:-0}"
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
# 5. A primary marked unhealthy must be skipped for the rest of the run.
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

echo 'prefetch curl wrapper regression: PASS'
