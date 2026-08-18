# Chapter 4: Runlevels

## Understanding Runlevels

Runlevels define groups of services that are started or stopped together. OpenRC uses runlevels to manage different system states.

## Default Runlevels

### sysinit

The sysinit runlevel contains services needed for basic system initialization:

- udev (device manager)
- udev-postmount (post-mount triggers)

```bash
# List sysinit services
ls /etc/runlevels/sysinit/
```

### boot

The boot runlevel contains services needed during system boot:

- dbus (message bus)
- cronie (cron daemon)
- chronyd (NTP client)
- acpid (power management)
- alsa (sound state)
- sysctl (kernel parameters)

```bash
# List boot services
ls /etc/runlevels/boot/
```

### default

The default runlevel contains services for normal operation:

- networkmanager (network management)
- lightdm (display manager)
- bluetooth (Bluetooth support)
- sshd (SSH server)
- smartd (disk monitoring)
- udisks2 (disk management)

```bash
# List default services
ls /etc/runlevels/default/
```

### single

The single runlevel is for single-user mode:

- udev
- udev-postmount

### nonetwork

The nonetwork runlevel is for recovery without networking:

- udev
- udev-postmount
- dbus

## Managing Runlevels

### Listing Runlevels

```bash
# List all runlevels
ls /etc/runlevels/

# List services in a runlevel
ls /etc/runlevels/default/
```

### Adding Services to Runlevels

```bash
# Add a service to a runlevel
sudo rc-update add networkmanager default

# Add multiple services
sudo rc-update add lightdm default
sudo rc-update add bluetooth default
```

### Removing Services from Runlevels

```bash
# Remove a service from a runlevel
sudo rc-update delete networkmanager default

# Remove multiple services
sudo rc-update delete lightdm default
sudo rc-update delete bluetooth default
```

## Switching Runlevels

### Changing Runlevel

```bash
# Switch to a different runlevel
sudo rc default        # Switch to default runlevel
sudo rc single         # Switch to single-user mode
sudo rc nonetwork      # Switch to nonetwork runlevel
```

### Booting to a Specific Runlevel

Add to kernel command line in GRUB:

```
# Boot to single-user mode
single

# Boot to specific runlevel
3

# Boot to nonetwork runlevel
nonetwork
```

## Creating Custom Runlevels

### Example: Custom GUI Runlevel

```bash
# Create the runlevel directory
sudo mkdir -p /etc/runlevels/gui

# Add services
sudo rc-update add xorg gui
sudo rc-update add lightdm gui
sudo rc-update add networkmanager gui
```

### Example: Server Runlevel

```bash
# Create the runlevel directory
sudo mkdir -p /etc/runlevels/server

# Add services
sudo rc-update add sshd server
sudo rc-update add httpd server
sudo rc-update add mysqld server
```

## Runlevel Dependencies

Services can specify which runlevel they belong to using the `runlevel` function in their init scripts:

```bash
#!/sbin/openrc-run

depend() {
    need dbus
    after xdm
    runlevel default
    runlevel !single
    runlevel !nonetwork
}
```

## Next Steps

After understanding runlevels, proceed to [Chapter 5: Service Management](chapters/05-service-management.md) to learn how to manage services.
