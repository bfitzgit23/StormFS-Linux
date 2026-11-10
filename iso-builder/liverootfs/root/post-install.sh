#!/bin/sh
#
# StormFS Linux Post-Install Configuration
# Called by the installer to configure the final installed system.
#
# Environment variables:
#   $ROOT       - directory where system is installed
#   $HOSTNAME   - hostname
#   $TIMEZONE   - timezone (Region/City)
#   $KEYMAP     - keyboard layout
#   $USERNAME   - user's login name
#   $USER_PSWD  - user's password
#   $ROOT_PSWD  - root's password
#   $LOCALE     - locale (e.g. en_US)
#   $BOOTLOADER - disk to install GRUB (e.g. /dev/sda) or 'skip'
#   $EFI_SYSTEM - 1 if booting in UEFI mode
#

_run() {
	live-chroot "$ROOT" "$@"
}

# Hostname
echo "$HOSTNAME" > "$ROOT/etc/hostname"
cat > "$ROOT/etc/hosts" <<HOSTS
127.0.0.1   localhost
127.0.1.1   $HOSTNAME
::1         localhost
HOSTS

# Timezone
ln -sf "/usr/share/zoneinfo/$TIMEZONE" "$ROOT/etc/localtime"
echo "$TIMEZONE" > "$ROOT/etc/timezone"

# Keymap
cat > "$ROOT/etc/vconsole.conf" <<VCONF
KEYMAP=$KEYMAP
VCONF

# Locale
if [ -f "$ROOT/etc/locale.gen" ]; then
	grep -q "^#${LOCALE}.UTF-8" "$ROOT/etc/locale.gen" && \
		sed -i "s/^#${LOCALE}.UTF-8/${LOCALE}.UTF-8/" "$ROOT/etc/locale.gen"
fi
echo "LANG=${LOCALE}.UTF-8" > "$ROOT/etc/locale.conf"
_run locale-gen 2>/dev/null || true

# Root password
echo "root:$ROOT_PSWD" | chpasswd -R "$ROOT" -c SHA512

# Create user
_run useradd -m -G users,wheel,audio,video -s /bin/bash "$USERNAME" 2>/dev/null || true
echo "$USERNAME:$USER_PSWD" | chpasswd -R "$ROOT" -c SHA512

# Initramfs
_run dracut --force 2>/dev/null || _run mkinitramfs 2>/dev/null || true

# GRUB
if [ "$BOOTLOADER" != skip ]; then
	echo "GRUB_DISABLE_OS_PROBER=false" >> "$ROOT/etc/default/grub"

	if [ "$EFI_SYSTEM" = 1 ]; then
		_run grub-install \
			--target=x86_64-efi \
			--efi-directory=/boot/efi \
			--bootloader-id=StormFS \
			--recheck \
			"$BOOTLOADER"
	else
		_run grub-install \
			--target=i386-pc \
			--recheck \
			"$BOOTLOADER"
	fi
	_run grub-mkconfig -o /boot/grub/grub.cfg
fi

# Install oh-my-bash for user if available
if [ -d "$ROOT/home/$USERNAME/.oh-my-bash" ] || \
   [ -f "$ROOT/usr/bin/omb" ]; then
	su - "$USERNAME" -c 'bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)" --unattended' 2>/dev/null || true
fi

# Install StormFS GRUB theme if available
if [ -d "$ROOT/usr/share/grub/themes/stormfs" ]; then
 THEME_CONF="$ROOT/etc/default/grub"
 if ! grep -q "GRUB_THEME=" "$THEME_CONF" 2>/dev/null; then
  echo 'GRUB_THEME="/usr/share/grub/themes/stormfs/theme.txt"' >> "$THEME_CONF"
 fi
fi

# Enable OpenRC services
# udev belongs in sysinit: it creates the /dev/input nodes that libinput
# enumerates, so without it keyboards, mice and touchpads do not work.
# Older openrc packages only create /etc/runlevels itself.
mkdir -p "$ROOT/etc/runlevels/sysinit"
_run rc-update add udev sysinit 2>/dev/null || true
_run rc-update add udev-postmount sysinit 2>/dev/null || true

for svc in dbus NetworkManager sshd; do
	if [ -f "$ROOT/usr/lib/systemd/system/${svc}.service" ] || \
	   [ -f "$ROOT/etc/systemd/system/${svc}.service" ]; then
		_run rc-update add "$svc" default 2>/dev/null || true
	fi
done

# Add user to sudoers
if [ -f "$ROOT/etc/sudoers" ]; then
	grep -q "^$USERNAME" "$ROOT/etc/sudoers" || \
		echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" >> "$ROOT/etc/sudoers"
fi

# Enable the LXDM display manager selected by the ISO.
_run rc-update add lxdm default 2>/dev/null || true

# Drop the live-only LXDM autologin before the installed system boots.
if [ -f "$ROOT/etc/lxdm/lxdm.conf" ]; then
	sed -i '/^autologin=bfs$/d' "$ROOT/etc/lxdm/lxdm.conf" || true
fi

# Cleanup: remove installer and live session artifacts
rm -f "$ROOT/usr/bin/stormfs-installer"
rm -f "$ROOT/root/live_script.sh"
rm -f "$ROOT/root/post-install.sh"
rm -f "$ROOT/root/post-extract.sh"
rm -f "$ROOT/root/splash.png"
# Keep the LXDM package configuration on the installed system.
rm -f "$ROOT/fastboot"

# Remove live desktop shortcuts (installer is only for live session)
for dir in Desktop 桌面; do
	rm -f "$ROOT/home/$USERNAME/$dir/stormfs-installer.desktop" 2>/dev/null || true
done

# Add port manager shortcut to installed system desktop
for dir in Desktop 桌面; do
	if [ -d "$ROOT/home/$USERNAME/$dir" ]; then
		cat > "$ROOT/home/$USERNAME/$dir/stormfs-portmanager.desktop" <<DESK
[Desktop Entry]
Name=StormFS Port Manager
Comment=Manage packages and ports
Exec=/usr/bin/stormfs-portmanager
Icon=system-software-install
Terminal=false
Type=Application
Categories=System;
DESK
		chmod +x "$ROOT/home/$USERNAME/$dir/stormfs-portmanager.desktop"
		chown -R "$USERNAME:$USERNAME" "$ROOT/home/$USERNAME/$dir" 2>/dev/null || true
	fi
done

exit 0
