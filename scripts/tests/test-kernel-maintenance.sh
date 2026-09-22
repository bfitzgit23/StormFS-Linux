#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HELPER="$ROOT/ports/core/bfs-kernel-maintenance/bfs-kernel-maintenance"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T"/{boot/grub,modules,src,etc/bfsos,etc/default,state,rollback,bin}

cat > "$T/bin/uname" <<'SH'
#!/bin/sh
[ "${1:-}" = -r ] && { printf '%s\n' "$BFS_TEST_UNAME"; exit 0; }
exec /usr/bin/uname "$@"
SH
cat > "$T/bin/grub-mkconfig" <<'SH'
#!/bin/sh
[ "${1:-}" = -o ] || exit 2
# The public LTS alias must be hidden during discovery or GRUB's Linux scanner
# can emit a second menu entry for the same versioned kernel image.
[ ! -L "$BFS_KERNEL_BOOT_ROOT/vmlinuz-lts" ] || {
    echo "vmlinuz-lts alias visible during grub-mkconfig" >&2
    exit 44
}
printf '# generated for %s\nmenuentry BFSOS {}\n' "$BFS_TEST_UNAME" > "$2"
SH
cat > "$T/bin/grub-script-check" <<'SH'
#!/bin/sh
[ -s "$1" ]
SH
chmod +x "$T/bin/"*

env_for() {
    export PATH="$T/bin:/usr/bin:/bin"
    export BFS_KERNEL_STATE_ROOT="$T/state"
    export BFS_KERNEL_ROLLBACK_ROOT="$T/rollback"
    export BFS_KERNEL_BOOT_ROOT="$T/boot"
    export BFS_KERNEL_MODULE_ROOT="$T/modules"
    export BFS_KERNEL_SOURCE_ROOT="$T/src"
    export BFS_KERNEL_ETC_ROOT="$T/etc"
    export BFS_KERNEL_GRUB_BOOT_PREFIX=/boot
    export BFS_TEST_UNAME=$1
}
install_fake() {
    local flavor=$1 kver=$2
    printf kernel > "$T/boot/vmlinuz-$kver"
    printf initramfs > "$T/boot/initramfs-$kver.img"
    printf map > "$T/boot/System.map-$kver"
    printf config > "$T/boot/config-$kver"
    mkdir -p "$T/modules/$kver" "$T/src/linux-$kver"
    printf module > "$T/modules/$kver/test.ko"
    printf source > "$T/src/linux-$kver/README"
    printf '%s\n' "$flavor" > "$T/etc/bfsos/kernel-flavor"
}
remove_fake() {
    local kver=$1
    rm -f "$T/boot/vmlinuz-$kver" "$T/boot/initramfs-$kver.img" "$T/boot/System.map-$kver" "$T/boot/config-$kver"
    rm -rf "$T/modules/$kver" "$T/src/linux-$kver"
}
assert_file() { [ -e "$1" ] || { echo "missing: $1" >&2; exit 1; }; }
assert_absent() { [ ! -e "$1" ] || { echo "unexpected: $1" >&2; exit 1; }; }

run_family() {
    local flavor=$1 old=$2 mid=$3 new=$4
    env_for "$old"
    install_fake "$flavor" "$old"
    mkdir -p "$T/state/$flavor"
    printf '%s\n' "$old" > "$T/state/$flavor/known-good"

    "$HELPER" pre-upgrade "$flavor"
    remove_fake "$old"             # simulate package replacement removing old files
    install_fake "$flavor" "$mid"
    "$HELPER" mark-pending "$flavor" "$mid"
    assert_file "$T/boot/vmlinuz-$old"  # staged rollback restored
    assert_file "$T/boot/vmlinuz-$mid"

    # A second update is forbidden until the pending kernel is actually booted.
    if "$HELPER" pre-upgrade "$flavor" >/dev/null 2>&1; then
        echo "second update unexpectedly accepted for $flavor" >&2
        exit 1
    fi

    env_for "$mid"
    "$HELPER" finalize-boot
    assert_file "$T/boot/vmlinuz-$old"
    assert_file "$T/boot/vmlinuz-$mid"

    "$HELPER" pre-upgrade "$flavor"
    remove_fake "$mid"
    install_fake "$flavor" "$new"
    "$HELPER" mark-pending "$flavor" "$new"
    env_for "$new"
    "$HELPER" finalize-boot
    assert_absent "$T/boot/vmlinuz-$old"
    assert_file "$T/boot/vmlinuz-$mid"
    assert_file "$T/boot/vmlinuz-$new"
    [ "$(cat "$T/state/$flavor/known-good")" = "$new" ]
    [ ! -e "$T/state/$flavor/pending" ]
}

run_family linux 7.2.1-BFS-Linux 7.2.2-BFS-Linux 7.2.3-BFS-Linux
# Reset roots for an independent LTS sequence.
rm -rf "$T"/{boot,modules,src,state,rollback,etc}
mkdir -p "$T"/{boot/grub,modules,src,etc/bfsos,etc/default,state,rollback}
run_family linux-lts 6.18.47-BFS-LTS 6.18.48-BFS-LTS 6.18.49-BFS-LTS
[ -L "$T/boot/vmlinuz-lts" ]
[ "$(readlink "$T/boot/vmlinuz-lts")" = "vmlinuz-6.18.49-BFS-LTS" ]

# Failed-boot path: pending state and rollback files must survive.
env_for 6.18.49-BFS-LTS
"$HELPER" pre-upgrade linux-lts
install_fake linux-lts 6.18.50-BFS-LTS
"$HELPER" mark-pending linux-lts 6.18.50-BFS-LTS
"$HELPER" finalize-boot
assert_file "$T/boot/vmlinuz-6.18.49-BFS-LTS"
assert_file "$T/boot/vmlinuz-6.18.50-BFS-LTS"
[ "$(cat "$T/state/linux-lts/pending")" = 6.18.50-BFS-LTS ]

echo "kernel-maintenance regression: PASS"

# Per-kernel Linux 6.18 MD metadata compatibility policy: append the bypass
# only to matching BFS-LTS entries and only when the installed kernel exposes
# the backported parameter.
rm -rf "$T"/{boot,modules,src,state,rollback,etc}
mkdir -p "$T"/{boot/grub,modules,src,etc/bfsos,etc/default,state,rollback}
env_for 6.18.50-BFS-LTS
cat > "$T/bin/grub-mkconfig" <<'MOCK_GRUB'
#!/bin/sh
[ "${1:-}" = -o ] || exit 2
cat > "$2" <<EOF
menuentry 'BFS mainline' {
  linux /vmlinuz-7.2.4-BFS-Linux root=/dev/mapper/root ro rd.md.uuid=1111:2222
  initrd /initramfs-7.2.4-BFS-Linux.img
}
menuentry 'BFS LTS' {
  linux /vmlinuz-6.18.50-BFS-LTS root=/dev/mapper/root ro rd.md.uuid=1111:2222 rd.driver.pre=raid10
  initrd /initramfs-6.18.50-BFS-LTS.img
}
EOF
MOCK_GRUB
chmod +x "$T/bin/grub-mkconfig"
printf kernel > "$T/boot/vmlinuz-6.18.50-BFS-LTS"
mkdir -p "$T/modules/6.18.50-BFS-LTS"
printf '%s\n' 'md_mod.parm=check_new_feature:bool' > "$T/modules/6.18.50-BFS-LTS/modules.builtin.modinfo"
printf '%s\n' 'reason=md-v1.2-nonzero-reserved-padding' 'uuid=1111:2222' > "$T/etc/bfsos/md-compat.conf"
"$HELPER" regenerate-grub
grep -E 'vmlinuz-6\.18\.50-BFS-LTS.*md_mod\.check_new_feature=0' "$T/boot/grub/grub.cfg" >/dev/null
if grep -E 'vmlinuz-7\.2\.4-BFS-Linux.*md_mod\.check_new_feature=0' "$T/boot/grub/grub.cfg" >/dev/null; then
    echo "6.18 MD compatibility token leaked into mainline kernel" >&2
    exit 1
fi

# If the matching LTS build does not expose the parameter, regeneration must
# fail and preserve the previous known-good grub.cfg atomically.
printf '%s\n' 'known-good-config' > "$T/boot/grub/grub.cfg"
: > "$T/modules/6.18.50-BFS-LTS/modules.builtin.modinfo"
if "$HELPER" regenerate-grub >/dev/null 2>&1; then
    echo "MD compatibility generation unexpectedly accepted a kernel without the parameter" >&2
    exit 1
fi
[ "$(cat "$T/boot/grub/grub.cfg")" = 'known-good-config' ] || {
    echo "failed MD compatibility generation overwrote grub.cfg" >&2
    exit 1
}

echo "kernel-maintenance MD compatibility regression: PASS"
