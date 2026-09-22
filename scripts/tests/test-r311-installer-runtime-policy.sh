#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

installer=scripts/install-bfs-menu-current.sh
chrony=ports/opt/chrony/Pkgfile
wget_port=ports/opt/wget/Pkgfile

# r310/r313: fetch helper uses a dedicated result channel, never stdout or nested namerefs.
grep -Fq 'fetch_sourceforge_base() {' "$installer"
grep -Fq 'BASE_ARCHIVE_RESULT="$archive"' "$installer"
grep -Fq 'selected="$BASE_ARCHIVE_RESULT"' "$installer"
if grep -Fq 'selected="$(fetch_sourceforge_base' "$installer"; then
    echo 'r313: installer still captures fetch stdout into selected' >&2
    exit 1
fi
if grep -Fq 'local -n result_ref="$1"' <(sed -n '/fetch_sourceforge_base()/,/^}/p' "$installer"); then
    echo 'r313: installer fetch still relies on nested nameref handoff' >&2
    exit 1
fi

# r309: no-local-archive path must require an explicit action.
grep -Fq 'choose_missing_base_archive() {' "$installer"
grep -Fq 'Download current BFSOS base from SourceForge' "$installer"
grep -Fq 'Browse for local base archive' "$installer"
grep -Fq '3 "Back"' "$installer"

# r308: archive/checksum phases and verification result must be user-visible.
grep -Fq 'BFSOS base download' "$installer"
grep -Fq 'Downloading SHA256 verification file' "$installer"
grep -Fq 'Base archive verified' "$installer"
grep -Fq 'SHA256 verification FAILED' "$installer"

# r307: use the runtime-proven chronyd invocation.
grep -Fq 'ExecStart=/usr/sbin/chronyd -n' "$chrony"
if grep -Fq 'ExecStart=/usr/bin/chronyd -F 2' "$chrony"; then
    echo 'r311: stale chronyd ExecStart remains' >&2
    exit 1
fi

# Live wget must have a deterministic distro CA bundle without --no-check-certificate.
grep -Fq '# Depends on: ca-certificates ' "$wget_port"
grep -Fq 'ca_certificate = /etc/pki/tls/certs/ca-bundle.crt' "$wget_port"

# r313: direct SourceForge mirror endpoint and verified handoff guard.
grep -Fq 'downloads.sourceforge.net/project/bfsos/BFSOS/base/latest' "$installer"
grep -Fq 'Base archive handoff failed' "$installer"

printf 'r311/r313 installer/runtime policy regression: PASS\n'
