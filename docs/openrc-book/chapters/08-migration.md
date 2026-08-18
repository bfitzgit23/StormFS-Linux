# Chapter 8: Migration from Systemd

## Overview

This chapter covers migrating a system from systemd to OpenRC.

## Pre-Migration Checklist

Before migrating:

1. **Backup your system**
2. **Document current services**
3. **Check for systemd-specific dependencies**
4. **Test in a chroot first**

### Document Current Services

```bash
# List enabled services
systemctl list-unit-files --state=enabled

# List running services
systemctl list-units --type=service --state=running
```

## Migration Steps

### Step 1: Install OpenRC

```bash
# Install OpenRC
prt-get install openrc

# Install init scripts
prt-get install openrc-init-scripts
```

### Step 2: Create Runlevel Directories

```bash
sudo mkdir -p /etc/runlevels/{sysinit,boot,default,nonetwork,single}
```

### Step 3: Map Systemd Services to OpenRC

| Systemd Service | OpenRC Service | Notes |
|-----------------|----------------|-------|
| systemd-networkd | networkmanager | Use NetworkManager instead |
| systemd-resolved | resolvconf | Use resolvconf for DNS |
| systemd-journald | syslog | Use syslog-ng or rsyslog |
| systemd-logind | elogind | Install elogind for session management |
| systemd-udevd | udev | Use eudev |

### Step 4: Enable Services

```bash
# Map systemd services to OpenRC
sudo rc-update add dbus boot
sudo rc-update add udev sysinit
sudo rc-update add udev-postmount sysinit
sudo rc-update add cronie boot
sudo rc-update add chronyd boot
sudo rc-update add alsa boot
sudo rc-update add acpid boot
sudo rc-update add NetworkManager default
sudo rc-update add lightdm default
sudo rc-update add bluetooth default
sudo rc-update add sshd default
```

### Step 5: Remove Systemd

**WARNING**: Only do this after confirming OpenRC works!

```bash
# Remove systemd (careful!)
prt-get remove systemd

# Remove systemd-related packages
prt-get remove systemd-libs
```

## Common Issues

### Issue 1: Missing Dependencies

Some packages may depend on systemd. Check with:

```bash
prt-get depends <package>
```

### Issue 2: D-Bus Services

D-Bus services may not work without systemd. Install elogind:

```bash
prt-get install elogind
```

### Issue 3: Logging

Systemd uses journald. Switch to syslog:

```bash
prt-get install syslog-ng
sudo rc-update add syslog-ng boot
```

## Testing Migration

### Test in Chroot

```bash
# Create chroot environment
mkdir /tmp/test-system
# ... setup chroot ...

# Install OpenRC in chroot
chroot /tmp/test-system prt-get install openrc

# Test services
chroot /tmp/test-system rc-update add NetworkManager default
```

### Test Boot

1. Keep systemd as fallback
2. Install OpenRC alongside systemd
3. Test boot with OpenRC
4. Remove systemd only after confirming everything works

## Rollback Plan

If migration fails:

1. Boot from live media
2. Reinstall systemd
3. Restore service configuration

## Next Steps

After migration, proceed to [Chapter 9: Networking](chapters/09-networking.md) to configure networking.
