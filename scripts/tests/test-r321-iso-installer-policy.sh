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
# scratch isinstalled is a one-package status check and returns 1 for a
# missing package.  A pipefail pipeline over a whole closure aborts silently
# under set -e, before the package-upgrade error can be reported.
! grep -Fq 'scratch isinstalled $dependency_closure' "$inst" || \
    fail "installed-system dependency preflight still pipes a closure through isinstalled"
grep -Fq 'for dependency in $dependency_closure' "$inst" || \
    fail "installed-system dependency preflight does not check each package"
grep -Fq 'if ! scratch isinstalled "$dependency"' "$inst" || \
    fail "installed-system dependency preflight does not use isinstalled's status"
# Older base archives contain stale BFSOS recipes. Refresh Git and cpio from
# the checked-out tree before entering the chroot so installer-side recipe
# fixes apply without a base-archive rebuild.
grep -Fq 'for transitional_port in git cpio' "$inst" || \
    fail "installer does not refresh the Git/cpio provisioning recipes"
grep -Fq 'PROJECT_DIR/ports/opt/$transitional_port' "$inst" || \
    fail "installer recipe refresh is not sourced from the project tree"
! grep -Fq 'autoreconf -fi' ports/opt/cpio/spkgbuild || \
    fail "cpio still regenerates autotools files instead of using its shipped configure"
grep -Fq 'bfs_autobuild' ports/opt/cpio/spkgbuild || \
    fail "cpio recipe lost its build hook"
# Stage 2 builds autoconf before m4, so the installed autom4te records the
# temporary toolchain's m4. Repair that path for existing base archives and
# prevent it from being baked into new ones.
grep -Fq 's|/tmp/lfs-tools/bin/m4|/usr/bin/m4|g' "$inst" || \
    fail "installer does not repair autom4te's temporary-toolchain m4 path"
grep -Fq 's|/tmp/lfs-tools/bin/m4|/usr/bin/m4|g' ports/core/autoconf/spkgbuild || \
    fail "autoconf recipe bakes in the temporary-toolchain m4 path"
grep -Fq 'M4=/usr/bin/m4 ./bootstrap.sh' ports/core/rdfind/spkgbuild || \
    fail "rdfind bootstrap does not use the target m4"
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
