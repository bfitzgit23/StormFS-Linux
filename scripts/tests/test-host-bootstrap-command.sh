#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
DOC="$ROOT/docs/COMMAND-LINE.md"
BOOT="$ROOT/bootstrap.sh"

fail() {
    echo "Noninteractive host bootstrap command regression: FAIL: $*" >&2
    exit 1
}

[ -f "$DOC" ] || fail "missing $DOC"
[ -f "$BOOT" ] || fail "missing $BOOT"
bash -n "$BOOT" || fail "bootstrap shell syntax failed"

# These are the bootstrap contract points the documented command relies on.
for token in \
    'BFS_STATE_DIR=' \
    'BFS_FULL_BOOTSTRAP_ASSUME_YES' \
    'BFS_FULL_BOOTSTRAP_NO_INSTALL_PROMPT' \
    'sudo -v' \
    '_run_full_bootstrap' \
    'full|full-bootstrap|all' \
    'read -r answer </dev/tty' \
    'Clean-start confirmation requires an interactive terminal' \
    'Stage 1 requires sudo' \
    'Could not clear the package directory'
do
    grep -Fq -- "$token" "$BOOT" || fail "bootstrap is missing contract token: $token"
done

command_block=$(
    awk '
        /<!-- noninteractive-host-bootstrap:start -->/ { capture=1; next }
        /<!-- noninteractive-host-bootstrap:end -->/ { capture=0; next }
        capture && /^```/ { next }
        capture { print }
    ' "$DOC"
)
[ -n "$command_block" ] || fail "documented host bootstrap command block is missing"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/bfs-host-bootstrap-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

mkdir -p "$WORK/bin" "$WORK/project" "$WORK/home"
printf '%s\n' "$command_block" > "$WORK/command.sh"

cat > "$WORK/bin/sudo" <<'EOF'
#!/bin/sh
printf 'sudo:%s\n' "$*" >> "$BFS_TEST_ORDER"
[ "${BFS_TEST_SUDO_FAIL:-no}" = yes ] && exit 1
exit 0
EOF

cat > "$WORK/project/bootstrap.sh" <<'EOF'
#!/bin/sh
printf 'bootstrap:%s\n' "$*" >> "$BFS_TEST_ORDER"
{
    printf 'args=%s\n' "$*"
    printf 'BFS_STATE_DIR=%s\n' "${BFS_STATE_DIR-}"
    printf 'BFS_FULL_BOOTSTRAP_ASSUME_YES=%s\n' "${BFS_FULL_BOOTSTRAP_ASSUME_YES-}"
    printf 'BFS_FULL_BOOTSTRAP_NO_INSTALL_PROMPT=%s\n' "${BFS_FULL_BOOTSTRAP_NO_INSTALL_PROMPT-}"
} > "$BFS_TEST_BOOTSTRAP_RECORD"
exit 0
EOF

chmod 0755 "$WORK/bin/sudo" "$WORK/project/bootstrap.sh"

PATH="$WORK/bin:$PATH"
HOME="$WORK/home"
XDG_CACHE_HOME=
BFS_TEST_ORDER="$WORK/order"
BFS_TEST_BOOTSTRAP_RECORD="$WORK/bootstrap-record"
export PATH HOME XDG_CACHE_HOME BFS_TEST_ORDER BFS_TEST_BOOTSTRAP_RECORD
unset BFS_STATE_DIR BFS_FULL_BOOTSTRAP_ASSUME_YES BFS_FULL_BOOTSTRAP_NO_INSTALL_PROMPT

(
    cd "$WORK/project"
    sh "$WORK/command.sh" </dev/null
)

# Pre-authentication must happen before the build starts.
[ "$(sed -n '1p' "$WORK/order")" = 'sudo:-v' ] \
    || fail "sudo -v was not the first shell action"
[ "$(sed -n '2p' "$WORK/order")" = 'bootstrap:full' ] \
    || fail "bootstrap was not invoked with full after sudo -v"

grep -Fqx -- 'args=full' "$WORK/bootstrap-record" \
    || fail "bootstrap did not receive the full argument"
grep -Fqx -- "BFS_STATE_DIR=$HOME/.cache/bfsos/bootstrap" "$WORK/bootstrap-record" \
    || fail "persistent BFS_STATE_DIR was not exported to bootstrap"
grep -Fqx -- 'BFS_FULL_BOOTSTRAP_ASSUME_YES=yes' "$WORK/bootstrap-record" \
    || fail "full-bootstrap confirmation was not suppressed"
grep -Fqx -- 'BFS_FULL_BOOTSTRAP_NO_INSTALL_PROMPT=yes' "$WORK/bootstrap-record" \
    || fail "installer handoff prompt was not suppressed"

# A failed sudo pre-authentication must stop before bootstrap starts.
: > "$WORK/order"
rm -f "$WORK/bootstrap-record"
if (cd "$WORK/project"; BFS_TEST_SUDO_FAIL=yes sh "$WORK/command.sh" </dev/null); then
    fail "documented command continued after sudo pre-authentication failure"
fi
[ "$(sed -n '1p' "$WORK/order")" = 'sudo:-v' ] \
    || fail "sudo pre-authentication was not attempted on the failure path"
[ ! -e "$WORK/bootstrap-record" ] \
    || fail "bootstrap ran after sudo pre-authentication failed"

echo 'Noninteractive host bootstrap command regression: PASS'
