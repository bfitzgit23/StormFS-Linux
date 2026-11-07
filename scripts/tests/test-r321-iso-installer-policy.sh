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

# The scratchpkg migration removed the CRUX ports command.  Installation must
# use portsync and pull every Venom Linux collection, including s6-services.
! grep -Eq '^[[:space:]]*ports -u([[:space:]]|$)' "$inst" || fail "installer still invokes the removed ports tool"
! grep -Eq '^[[:space:]]*command -v ports([[:space:]]|$)' "$inst" || fail "installer still requires the removed ports command"
grep -Fq 'portsync -r' "$inst" || fail "installer does not synchronize ports with scratchpkg"
grep -Fq 'configure_venom_ports_repositories' "$inst" || fail "installer Venom repository setup missing"
grep -Fq 'ln -sfn ../venom-core/NEWS /usr/ports/main/NEWS' "$inst" || \
    fail "portnews news-directory compatibility link missing"
for repo in core extra nonfree multilib s6 kde-lxqt mate xfce s6-services; do
    grep -Fq "https://codeberg.org/venomlinux/$repo.git" "$inst" || fail "installer Venom repository missing: $repo"
    grep -Fq "https://codeberg.org/venomlinux/$repo.git" ports/core/scratchpkg/scratchpkg.repo || fail "default scratchpkg repository missing: $repo"
done

# The target is OpenRC-only.  Do not make a completed install depend on the
# systemd package just to create the machine ID required by D-Bus.
! grep -Eq '^[[:space:]]*systemd-machine-id-setup([[:space:]]|$)' "$inst" || fail "installer still invokes systemd-machine-id-setup"
grep -Fq 'ensure_machine_id() {' "$inst" || fail "portable machine-id generator missing"
grep -Fq 'dbus-uuidgen' "$inst" || fail "machine-id generator has no D-Bus fallback"
grep -Fq '/proc/sys/kernel/random/uuid' "$inst" || fail "machine-id generator has no kernel fallback"

echo "r321 ISO/installer policy regression: PASS"
