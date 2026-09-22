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
grep -q 'BFS_FULL_BOOTSTRAP_NO_INSTALL_PROMPT' "$boot" || fail 'ISO full-bootstrap handoff cannot suppress installer prompt'

for token in mksquashfs xorriso grub-mkrescue grub-platform:i386-pc grub-platform:x86_64-efi; do
    grep -q "$token" "$iso" || fail "ISO preflight is missing $token"
done
for pkg in linux linux-lts networkmanager openssh git sudo wget wpa_supplicant wireless_tools gpm lynx links cryptsetup lvm2 mdadm snapper grub grub-efi squashfs-tools libisoburn; do
    grep -q "\b$pkg\b" "$iso" || fail "ISO package set is missing $pkg"
done

grep -q 'BFSOS project tree shipped on the ISO' "$iso" || fail 'offline bundled-tree fallback is missing'
grep -q 'git pull --ff-only' "$iso" || fail 'safe online project refresh is missing'
grep -q 'passwd bfs' "$iso" || fail 'temporary bfs live-password prompt is missing'
grep -q 'ssh-keygen -A' "$iso" || fail 'runtime SSH host-key generation is missing'
grep -q 'systemctl start sshd.service' "$iso" || fail 'runtime SSH startup is missing'
grep -q 'NetworkManager.service' "$iso" || fail 'NetworkManager live default is missing'
grep -q 'rootfs.squashfs' "$iso" || fail 'SquashFS live-root staging is missing'
grep -q 'mount -t overlay overlay' "$iso" || fail 'writable overlay root is missing'
grep -q 'packages.sha256' "$iso" || fail 'ISO local package checksum manifest is missing'
grep -q 'packages.list' "$iso" || fail 'ISO local package list is missing'
grep -q 'base_archive' "$iso" || fail 'base archive is not staged into ISO logic'

echo 'ISO builder source regression: PASS'
