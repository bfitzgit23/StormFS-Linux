#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "r321 ISO/installer policy regression: FAIL: $*" >&2; exit 1; }

iso=scripts/bfs-build-iso.sh
inst=scripts/install-bfs-menu-current.sh

grep -Fq 'BASE_MODE="${BFS_ISO_BASE_MODE:-auto}"' "$iso" || fail "ISO builder is not local-first by default"
grep -Fq -- '--sourceforge-base' "$iso" || fail "explicit SourceForge mode missing"
grep -Fq -- '--local-base PATH' "$iso" || fail "explicit local-base path mode missing"
grep -Fq 'project_base_candidates' "$iso" || fail "local project-base discovery helper missing"
grep -Fq '*.tar.zst|*.tar.zst.tmp' "$iso" || fail "temporary .tar.zst validation support missing"
! grep -Fq 'bfs-live-enable-ssh' "$iso" || fail "obsolete live SSH enable helper is still present"
grep -Fq 'ssh-keygen -A' "$iso" || fail "manual live SSH instructions missing"
! grep -A20 "cat > \"\$root/usr/local/sbin/bfs-live-init\"" "$iso" | grep -Fq 'ssh-keygen -A' || \
    fail "live init still generates SSH host keys automatically"
grep -Fq 'rm -f "$root"/etc/ssh/ssh_host_*' "$iso" || fail "ISO build does not remove baked SSH host keys"

grep -Fq '(fd|sr|loop)[0-9]+$/' "$inst" || fail "installer does not filter floppy/optical/loop pseudo-disks"
grep -Fq '# Back from Ready to install returns to the main installer menu.' "$inst" || fail "review Back-loop fix missing"

echo "r321 ISO/installer policy regression: PASS"
