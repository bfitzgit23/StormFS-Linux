#!/bin/bash
# BFSOS r243 runtime verification. Read-only: this script does not update,
# enable, disable, remove, or regenerate anything.
set -u

section() { printf '\n===== %s =====\n' "$*"; }
run() { echo "+ $*"; "$@" 2>&1 || echo "[status $?]"; }

section "System"
run uname -a
run cat /etc/os-release

section "Kernel selection and rollback state"
run ls -lah /boot
run sh -c 'for p in /boot/vmlinuz-lts /usr/src/linux /usr/src/linux-lts; do [ -e "$p" ] || [ -L "$p" ] || continue; printf "%s -> %s\n" "$p" "$(readlink -f "$p" 2>/dev/null || true)"; done'
run sh -c 'find /var/lib/bfsos/kernel-state -maxdepth 3 -type f -print -exec sh -c '\''printf "  "; cat "$1"'\'' _ {} \; 2>/dev/null || true'
run sh -c 'find /var/lib/bfsos/kernel-rollback -maxdepth 3 -type f -o -type d 2>/dev/null | sort || true'
if command -v grub-script-check >/dev/null 2>&1 && [ -f /boot/grub/grub.cfg ]; then
    run grub-script-check /boot/grub/grub.cfg
fi
run sh -c 'grep -E "^[[:space:]]*GRUB_TOP_LEVEL=" /etc/default/grub 2>/dev/null || true'

section "Build-work policy"
run sh -c 'grep MemTotal /proc/meminfo; findmnt /var/cache/pkg/build-work 2>/dev/null || true; df -h /var/cache/pkg/build-work 2>/dev/null || true'

section "prt-get no-new-deps"
run sh -c 'prt-get --help 2>&1 | grep -A8 -B2 -- "--no-new-deps" || true'

section "sudoers"
if command -v visudo >/dev/null 2>&1; then
    [ -f /etc/sudoers.d/kf6 ] && run visudo -cf /etc/sudoers.d/kf6
    [ -f /etc/sudoers.d/xorg ] && run visudo -cf /etc/sudoers.d/xorg
    run visudo -c
else
    echo "visudo not installed"
fi
run sh -c 'sudo -n true >/dev/null 2>&1 && sudo -n env | grep -E "^(KF6_PREFIX|QT6DIR|QT5DIR|CMAKE_PREFIX_PATH|PKG_CONFIG_PATH|XORG_PREFIX|XORG_CONFIG)=" || true'

section "PipeWire / WirePlumber"
run systemctl --user status pipewire.service pipewire.socket pipewire-pulse.service pipewire-pulse.socket wireplumber.service --no-pager
run sh -c 'pgrep -a -f "pipewire|wireplumber|pulseaudio" || true'
command -v pactl >/dev/null 2>&1 && run pactl info
command -v wpctl >/dev/null 2>&1 && run wpctl status

section "Display manager"
run systemctl status display-manager --no-pager
run sh -c 'systemctl is-enabled sddm.service 2>/dev/null || true'
run sh -c 'systemctl is-enabled plasmalogin.service 2>/dev/null || true'
if command -v bfs-display-manager >/dev/null 2>&1; then
    run bfs-display-manager status
fi

section "Failed units"
run systemctl --failed --no-pager
run systemctl --user --failed --no-pager

printf '\nRuntime check complete. Paste or upload the complete output for tracker closeout.\n'
