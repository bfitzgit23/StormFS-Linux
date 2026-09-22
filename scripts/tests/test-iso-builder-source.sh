#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
iso="$ROOT/scripts/bfs-build-iso.sh"
boot="$ROOT/bootstrap.sh"
fail() { echo "ISO builder source regression: FAIL: $*" >&2; exit 1; }

[ -x "$iso" ] || fail 'scripts/bfs-build-iso.sh is missing or not executable'
bash -n "$iso" || fail 'ISO builder shell syntax failed'
bash -n "$boot" || fail 'bootstrap shell syntax failed'

grep -q 'Build BFSOS bootable ISO' "$boot" || fail 'bootstrap menu does not expose ISO builder'
grep -q 'iso|build-iso|create-iso' "$boot" || fail 'bootstrap CLI does not expose ISO builder'

for token in mksquashfs xorriso grub-mkrescue grub-platform:i386-pc grub-platform:x86_64-efi; do
    grep -q "$token" "$iso" || fail "ISO preflight is missing $token"
done
for pkg in networkmanager-iso openssh git sudo wget wpa_supplicant wireless-regdb gpm lynx-iso chrony cryptsetup lvm2 mdadm snapper grub grub-efi squashfs-tools libisoburn; do
    grep -q "\b$pkg\b" "$iso" || fail "ISO package set is missing $pkg"
done

[ -f "$ROOT/ports/iso/networkmanager-iso/Pkgfile" ] || fail 'networkmanager-iso port is missing'
[ -f "$ROOT/ports/iso/lynx-iso/Pkgfile" ] || fail 'lynx-iso port is missing'
grep -q -- '-Dwifi=true' "$ROOT/ports/iso/networkmanager-iso/Pkgfile" || fail 'ISO NetworkManager lost Wi-Fi support'
grep -q -- '-Dnmcli=true' "$ROOT/ports/iso/networkmanager-iso/Pkgfile" || fail 'ISO NetworkManager lost nmcli'
grep -q -- '-Dnmtui=true' "$ROOT/ports/iso/networkmanager-iso/Pkgfile" || fail 'ISO NetworkManager lost nmtui'

grep -q 'downloads.sourceforge.net/project/bfsos/BFSOS/base/latest' "$iso" || fail 'SourceForge base URL is missing'
grep -q 'BASE_SHA256_URL' "$iso" || fail 'SourceForge base checksum verification is missing'
grep -q 'verify_sha256_file' "$iso" || fail 'base SHA256 verifier is missing'
grep -q 'codeberg.org/bmadonnaster/BFSOS.git' "$iso" || fail 'canonical Codeberg Git URL is missing'
grep -q 'prepare_build_project' "$iso" || fail 'automatic clean Git checkout is missing'
grep -q 'GIT_COMMIT_FULL' "$iso" || fail 'full Git commit provenance is missing'
grep -q '/etc/bfs-build-info' "$iso" || fail 'embedded build provenance is missing'

grep -q 'git pull --ff-only' "$iso" || fail 'safe live online project refresh is missing'
grep -q 'passwd bfs' "$iso" || fail 'temporary bfs live-password prompt is missing'
grep -q 'ssh-keygen -A' "$iso" || fail 'runtime SSH host-key generation is missing'
grep -q 'systemctl start sshd.service' "$iso" || fail 'runtime SSH startup is missing'
grep -q 'NetworkManager.service' "$iso" || fail 'NetworkManager live default is missing'
grep -q 'rootfs.squashfs' "$iso" || fail 'SquashFS live-root staging is missing'
grep -q 'mount -t overlay overlay' "$iso" || fail 'writable overlay root is missing'

grep -q -- '-comp xz -b 1M -Xdict-size 100% -Xbcj x86' "$iso" || fail 'size-oriented SquashFS settings are missing'
grep -q 'audit_live_root' "$iso" || fail 'live-root archive audit is missing'
grep -q "Forbidden tar/package archives remain" "$iso" || fail 'forbidden-archive failure policy is missing'

# The new RC1 policy must not copy base/package tar archives onto release media.
if grep -Eq 'cp .*base_archive.*stage/bfsos|packages\.sha256|packages\.list|Preserve one copy of package archives' "$iso"; then
    fail 'old offline tar/package-archive staging policy is still present'
fi

echo 'ISO builder source regression: PASS'
