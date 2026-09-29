#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
iso=scripts/bfs-build-iso.sh
installer=scripts/install-bfs-menu-current.sh

fail() { printf 'r313 live/download policy: FAIL: %s\n' "$*" >&2; exit 1; }

grep -Fq 'downloads.sourceforge.net/project/bfsos/BFSOS/base/latest' "$iso" || fail 'ISO SourceForge base/latest endpoint missing'
grep -Fq 'downloads.sourceforge.net/project/bfsos/BFSOS/base/latest' "$installer" || fail 'installer SourceForge base/latest endpoint missing'
grep -Fq 'fetch_sourceforge_base base_archive' "$iso" || fail 'ISO fetch result handoff missing'
grep -Fq 'local -n result_ref="$1"' "$iso" || fail 'ISO named-result handoff missing'
grep -Fq 'BASE_ARCHIVE_RESULT="$archive"' "$installer" || fail 'installer verified archive handoff missing'
grep -Fq 'Base archive handoff failed' "$installer" || fail 'installer handoff guard missing'
grep -Fq 'BFSOS-base-${release}-x86_64.tar.zst' "$installer" || fail 'installer versioned base filename missing'
grep -Fq "script -qec './bootstrap.sh' /dev/null" "$iso" || fail 'live Bootstrap PTY wrapper missing'
grep -Fq "script -qec 'sudo ./scripts/install-bfs-menu-current.sh' /dev/null" "$iso" || fail 'live installer PTY wrapper missing'
grep -Fq 'ssh-keygen -A' "$iso" || fail 'manual SSH instructions missing'

bash -n "$iso"
bash -n "$installer"
echo 'r313 live/download policy regression: PASS'
