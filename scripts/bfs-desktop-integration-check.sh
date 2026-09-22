#!/bin/sh
# BFSOS Plasma/PipeWire integration sanity check.
# Non-destructive: reports session, unit, and audio integration state.

set -u

fail=0
ok()   { printf 'OK:   %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*"; }
bad()  { printf 'FAIL: %s\n' "$*"; fail=1; }

echo "== PAM / logind =="
if grep -Eq '^[[:space:]]*session[[:space:]]+.*pam_systemd\.so' /etc/pam.d/system-session 2>/dev/null; then
    ok "/etc/pam.d/system-session includes pam_systemd"
else
    bad "/etc/pam.d/system-session does not include pam_systemd"
fi

uid="$(id -u)"
if [ -d "/run/user/$uid" ]; then
    ok "/run/user/$uid exists"
else
    bad "/run/user/$uid missing"
fi

echo
echo "== Plasma systemd user units =="
for unit in \
    plasma-workspace.target \
    plasma-workspace-x11.target \
    plasma-kactivitymanagerd.service \
    plasma-kscreen.service
do
    if systemctl --user cat "$unit" >/dev/null 2>&1; then
        ok "$unit visible"
    else
        bad "$unit missing from systemd user unit path"
    fi
done

if [ -d /opt/kf6/lib/systemd ]; then
    warn "/opt/kf6/lib/systemd still exists; new packages should stage KF6 systemd units in /usr/lib/systemd"
else
    ok "no live /opt/kf6/lib/systemd integration tree"
fi

echo
echo "== PipeWire audio =="
for unit in pipewire.socket pipewire-pulse.socket wireplumber.service; do
    if systemctl --user is-active "$unit" >/dev/null 2>&1; then
        ok "$unit active"
    else
        warn "$unit not active"
    fi
done

if pgrep -x pulseaudio >/dev/null 2>&1; then
    bad "standalone PulseAudio daemon is running"
else
    ok "standalone PulseAudio daemon is not running"
fi

if command -v pactl >/dev/null 2>&1; then
    server="$(pactl info 2>/dev/null | sed -n 's/^Server Name:[[:space:]]*//p' | head -1)"
    case "$server" in
        *PipeWire*) ok "Pulse protocol served by $server" ;;
        "") bad "pactl cannot connect to the Pulse protocol socket" ;;
        *) bad "Pulse protocol is served by legacy server: $server" ;;
    esac
else
    warn "pactl not installed"
fi

if command -v wpctl >/dev/null 2>&1; then
    if wpctl status 2>/dev/null | grep -q 'Audio'; then
        ok "wpctl sees PipeWire audio graph"
    else
        bad "wpctl does not report an audio graph"
    fi
else
    warn "wpctl not installed"
fi

if command -v speaker-test >/dev/null 2>&1; then
    ok "speaker-test available (alsa-utils)"
else
    warn "speaker-test missing (install/check alsa-utils)"
fi

echo
echo "== Display manager / screen locker =="
if command -v sddm >/dev/null 2>&1; then
    ok "sddm executable present"
else
    bad "sddm executable missing"
fi
enabled_dms=0
for dm_unit in sddm.service plasmalogin.service gdm.service lightdm.service; do
    if systemctl is-enabled "$dm_unit" >/dev/null 2>&1; then
        ok "$dm_unit explicitly enabled"
        enabled_dms=$((enabled_dms + 1))
    fi
done
case "$enabled_dms" in
    0) warn "no display manager explicitly selected (valid BFSOS console/TTY state)" ;;
    1) : ;;
    *) bad "multiple display managers are enabled; BFSOS policy requires one explicit selection" ;;
esac

locker=""
for candidate in /opt/kf6/libexec/kscreenlocker_greet /opt/kf6/bin/kscreenlocker_greet /usr/libexec/kscreenlocker_greet /usr/bin/kscreenlocker_greet; do
    if [ -x "$candidate" ]; then locker="$candidate"; break; fi
done
if [ -n "$locker" ]; then
    ok "kscreenlocker_greet present: $locker"
    if ldd "$locker" 2>/dev/null | grep -q 'not found'; then
        bad "kscreenlocker_greet has unresolved shared libraries"
    else
        ok "kscreenlocker_greet shared libraries resolve"
    fi
else
    bad "kscreenlocker_greet executable missing"
fi

for pamfile in /etc/pam.d/kde /etc/pam.d/kscreensaver; do
    if [ -e "$pamfile" ]; then
        ok "$pamfile present"
    else
        warn "$pamfile not present (verify package/session policy)"
    fi
done

echo
echo "== Phonon / VLC Qt6 =="
phonon_vlc="/opt/kf6/lib/plugins/phonon4qt6_backend/phonon_vlc_qt6.so"
if [ -f "$phonon_vlc" ]; then
    ok "Qt6 Phonon VLC backend present"
    if ldd "$phonon_vlc" 2>/dev/null | grep -q 'not found'; then
        bad "Qt6 Phonon VLC backend has unresolved libraries"
    else
        ok "Qt6 Phonon VLC backend libraries resolve"
    fi
    if ldd "$phonon_vlc" 2>/dev/null | grep -q 'libQt6Core'; then
        ok "Phonon VLC backend links to Qt6"
    else
        bad "Phonon VLC backend does not link to Qt6"
    fi
else
    bad "Qt6 Phonon VLC backend missing"
fi

vlc_qt="/usr/lib/vlc/plugins/gui/libqt_plugin.so"
if [ -f "$vlc_qt" ]; then
    if ldd "$vlc_qt" 2>/dev/null | grep -q 'libQt6Core'; then
        ok "VLC GUI plugin links to Qt6"
    else
        bad "VLC GUI plugin is not linked to Qt6"
    fi
else
    bad "VLC Qt GUI plugin missing"
fi

if systemctl is-active rtkit-daemon.service >/dev/null 2>&1; then
    ok "rtkit-daemon.service active"
else
    warn "rtkit-daemon.service not active; PipeWire may run without realtime priority"
fi

exit "$fail"
