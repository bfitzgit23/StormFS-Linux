#!/bin/sh
#
# StormFS Linux Live Session Setup
# Executed inside initramfs before switch_root
#

LIVEUSER="stormfs"
PASSWORD="stormfs"

# Create live user
useradd -m -G users,wheel,audio,video -s /bin/bash "$LIVEUSER" 2>/dev/null || true

# Set passwords
echo "root:root" | chpasswd -c SHA512
echo "$LIVEUSER:$PASSWORD" | chpasswd -c SHA512

# Remove password expiry
passwd -d "$LIVEUSER" >/dev/null 2>&1 || true
passwd -d root >/dev/null 2>&1 || true

# Hostname
echo "stormfs-live" > /etc/hostname

# Timezone
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
echo "America/New_York" > /etc/timezone

# Keymap
echo "KEYMAP=us" > /etc/vconsole.conf

# Locale
if [ -f /etc/locale.gen ]; then
	grep -q "^en_US.UTF-8" /etc/locale.gen && \
		sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
fi
echo "LANG=en_US.UTF-8" > /etc/locale.conf
command -v locale-gen >/dev/null 2>&1 && locale-gen 2>/dev/null || true

# Enable systemd services
if [ -d /etc/systemd/system ]; then
	for svc in dbus NetworkManager lightdm; do
		if [ -d "/usr/lib/systemd/system/${svc}.service" ] || \
		   [ -f "/usr/lib/systemd/system/${svc}.service" ]; then
			systemctl enable "$svc" 2>/dev/null || true
			systemctl set-default graphical.target 2>/dev/null || true
		fi
	done
fi

# Configure LightDM autologin
mkdir -p /etc/lightdm
if [ -f /etc/lightdm/lightdm.conf ]; then
	sed -i 's/^#autologin-user=.*/autologin-user=stormfs/' /etc/lightdm/lightdm.conf
	sed -i 's/^autologin-user=.*/autologin-user=stormfs/' /etc/lightdm/lightdm.conf
	sed -i 's/^#autologin-user-timeout=.*/autologin-user-timeout=0/' /etc/lightdm/lightdm.conf
	sed -i 's/^autologin-user-timeout=.*/autologin-user-timeout=0/' /etc/lightdm/lightdm.conf
else
	cat > /etc/lightdm/lightdm.conf <<LDM
[Seat:*]
autologin-user=$LIVEUSER
autologin-user-timeout=0
user-session=xfce
greeter-session=lightdm-gtk-greeter

[Greeter]
user-list=false
LDM
fi

# Enable sudo for wheel group
if [ -f /etc/sudoers ]; then
	grep -q "^$LIVEUSER" /etc/sudoers || \
		echo "$LIVEUSER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi

# Create desktop shortcut for installer
if [ -d /home/$LIVEUSER/Desktop ]; then
	deskdir="/home/$LIVEUSER/Desktop"
elif [ -d /home/$LIVEUSER/桌面 ]; then
	deskdir="/home/$LIVEUSER/桌面"
else
	mkdir -p /home/$LIVEUSER/Desktop
	deskdir="/home/$LIVEUSER/Desktop"
fi

cat > "$deskdir/stormfs-installer.desktop" <<DESK
[Desktop Entry]
Name=StormFS Installer
Comment=Install StormFS Linux to disk
Exec=/usr/bin/stormfs-installer
Icon=system-software-install
Terminal=false
Type=Application
Categories=System;
DESK
chmod +x "$deskdir/stormfs-installer.desktop"

cat > "$deskdir/stormfs-portmanager.desktop" <<DESK2
[Desktop Entry]
Name=StormFS Port Manager
Comment=Manage packages and ports
Exec=/usr/bin/stormfs-portmanager
Icon=system-software-install
Terminal=false
Type=Application
Categories=System;
DESK2
chmod +x "$deskdir/stormfs-portmanager.desktop"

chown -R "$LIVEUSER:$LIVEUSER" /home/$LIVEUSER/Desktop 2>/dev/null || true

# Polkit: allow wheel group to use pkexec without password
if [ -d /etc/polkit-1/rules.d ]; then
	cat > /etc/polkit-1/rules.d/49-live.rules <<'POLKIT'
polkit.addAdminRule(function(action, subject) {
    return ["unix-group:wheel"];
});
polkit.addRule(function(action, subject) {
    if (subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
POLKIT
elif [ -d /etc/polkit-1/localauthority ]; then
	cat > /etc/polkit-1/localauthority/50-local.d/49-live.pkla <<PKLA
[Allow for wheel]
Identity=unix-group:wheel
Action=*
ResultActive=yes
PKLA
fi

# Ensure clean shutdown
[ -f /etc/fastboot ] && rm -f /etc/fastboot

# Set permissions
chmod 755 /root/live_script.sh 2>/dev/null || true

exit 0
