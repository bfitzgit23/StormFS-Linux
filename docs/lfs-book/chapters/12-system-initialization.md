# Chapter 12: System Initialization

This chapter uses **OpenRC** as the default init system and service manager for StormFS Linux. The systemd material later in this chapter is optional compatibility/reference material and must not be enabled when OpenRC is the selected init system.

## 12.1 OpenRC Default

OpenRC manages service dependencies and runlevels. It is not itself PID 1; pair it with the OpenRC init provided by the package and boot the system with the OpenRC init path.

### Installing OpenRC

Use the MLFS OpenRC build, or install the StormFS port:

```bash
# Port-based installation
prt-get install openrc openrc-init-scripts

# Source-based installation
cd /sources
wget https://github.com/OpenRC/openrc/archive/refs/tags/0.63.tar.gz
wget https://www.linuxfromscratch.org/glfs/view/dev/download/openrc/openrc-0.63-lock-1.patch
tar xf 0.63.tar.gz
cd openrc-0.63
patch -Np1 -i ../openrc-0.63-lock-1.patch
sed -i '/set -u/d' tools/meson_final.sh
mkdir build
cd build
meson setup --prefix=/usr \\
            --sysconfdir=/etc \\
            --buildtype=release \\
            -D uucp_group=root \\
            -D pam=false ..
ninja
ninja install
```

### Enable the OpenRC Base Services

```bash
# Create the standard runlevels if the package did not create them
mkdir -p /etc/runlevels/{boot,default,nonetwork,shutdown,sysinit}

# Add the core services needed by an installed system
rc-update add devfs sysinit
rc-update add dmesg sysinit
rc-update add mdev sysinit 2>/dev/null || true
rc-update add hwdrivers boot 2>/dev/null || true
rc-update add syslog boot 2>/dev/null || true
rc-update add networking boot

# Inspect and start the selected runlevel
rc-status
rc-service networking start
```

Set the kernel command line to use the OpenRC init supplied by the installation, and verify after reboot:

```bash
ps -p 1 -o comm=
rc-status
rc-update show
```

### OpenRC Equivalents for Common Services

The following services provide the OpenRC equivalents for the functions commonly supplied by systemd. Install only the services you need, then add them to the indicated runlevel.

| systemd function | OpenRC implementation | Typical runlevel |
|------------------|-----------------------|------------------|
| `systemd-journald` | `sysklogd` or `syslog-ng` | `boot` |
| `systemd-logind` | `ConsoleKit2` (or elogind from an external port tree) | D-Bus activated |

| `systemd-networkd` | `networking` with `dhcpcd`, or `NetworkManager` | `boot`/`default` |
| `systemd-resolved` | `openresolv` with `dhcpcd` or NetworkManager | `boot` |
| `systemd-udevd` | `eudev` with the `udev` and `udev-postmount` scripts | `sysinit` |
| `systemd-timesyncd` | `chronyd` | `boot` |
| `systemd-tmpfiles` | OpenRC `local.d`/`localmount` setup scripts | `boot` |
| `dbus.service` | `dbus` OpenRC service | `boot` |
| `getty@tty1.service` | `agetty` entries in `/etc/inittab` | PID 1/inittab |

For the services shipped by StormFS, enable the available OpenRC scripts as follows:

```bash
# Logging, device management, time, and message bus
prt-get install sysklogd eudev chrony dbus openrc-init-scripts
rc-update add syslog boot 2>/dev/null || rc-update add sysklogd boot 2>/dev/null || true
rc-update add udev sysinit
rc-update add udev-postmount sysinit
rc-update add chronyd boot
rc-update add dbus boot 2>/dev/null || true

# Session provider for desktop environments (D-Bus activated)
prt-get install consolekit2
rc-update add dbus boot 2>/dev/null || true
```

Desktop environments that expect the logind D-Bus API need a compatible session provider. This repository provides `consolekit2`; it is D-Bus activated rather than an OpenRC runlevel service. An external `elogind` port can be used instead when available, but do not enable a systemd service in the OpenRC profile.

### OpenRC Logging Instead of journald

Use a traditional syslog daemon and text logs in `/var/log`. With the StormFS `sysklogd` port:

```bash
prt-get install sysklogd
install -d -m 0755 /var/log

cat > /etc/init.d/syslog << 'EOF'
#!/sbin/openrc-run

description="System logger"
command="/usr/sbin/syslogd"
command_args="-F"
command_background=true
pidfile="/run/${RC_SVCNAME}.pid"

depend() {
    need localmount
}
EOF
chmod 755 /etc/init.d/syslog
rc-update add syslog boot
rc-service syslog start

# Follow the equivalent of journalctl -f
tail -f /var/log/messages

# Filter the equivalent of journalctl -p err
grep -iE 'err|crit|alert|emerg' /var/log/messages
```

Configure rotation with `logrotate` or a periodic cron job. `syslogd -F` can receive kernel and daemon messages, while individual services should log through syslog or their own files.

### OpenRC Session, Device, and Time Services

```bash
# Session management for graphical desktops
prt-get install consolekit2
rc-update add dbus boot 2>/dev/null || true

# Device events and post-mount triggers
rc-update add udev sysinit
rc-update add udev-postmount sysinit

# NTP synchronization, replacing systemd-timesyncd
prt-get install chrony
rc-update add chronyd boot
rc-service chronyd start

# Check the replacements
rc-service udev status
rc-service chronyd status
rc-status --all
```

For temporary-file setup, place idempotent commands in `/etc/local.d/boot.start` and make the file executable. This replaces the subset of `systemd-tmpfiles-setup.service` normally needed by local services:

```bash
install -d -m 0755 /etc/local.d
cat > /etc/local.d/boot.start << 'EOF'
#!/bin/sh
install -d -m 0755 /run/stormfs /var/log/stormfs
chown root:root /run/stormfs /var/log/stormfs
EOF
chmod 755 /etc/local.d/boot.start
rc-update add local default
```

### OpenRC Console Logins

OpenRC uses the kernel's init process together with `agetty`; it does not require a `getty@tty1.service` unit. Add the consoles you want to `/etc/inittab`:

```text
tty1::respawn:/sbin/agetty --noclear tty1  linux
tty2::respawn:/sbin/agetty tty2  linux
tty3::respawn:/sbin/agetty tty3  linux
```

After editing `inittab`, ask the init process to reload it:

```bash
init q
```

### OpenRC Replacement for systemd Service Files

Translate a long-running `.service` unit into an executable `/etc/init.d/` script. Dependencies replace `After=`/`Requires=`, `command_background` replaces a simple service supervisor, and `rc-update` replaces `[Install]` targets:

```bash
cat > /etc/init.d/stormfs-webapp << 'EOF'
#!/sbin/openrc-run

description="StormFS Web Application"
command="/opt/stormfs-webapp/bin/webapp"
command_args="--config /etc/stormfs/webapp.conf"
command_user="webapp:webapp"
command_background=true
pidfile="/run/${RC_SVCNAME}.pid"
output_log="/var/log/stormfs-webapp.log"
error_log="/var/log/stormfs-webapp.err"

depend() {
    need net
    use logger
    after firewall
}

start_pre() {
    checkpath --directory --owner webapp:webapp --mode 0750 /run/stormfs-webapp
}
EOF
chmod 755 /etc/init.d/stormfs-webapp
rc-update add stormfs-webapp default
rc-service stormfs-webapp start
```

### OpenRC Replacement for systemd Timers

OpenRC has no native timer-unit format. Use `cronie` for recurring jobs and an executable OpenRC service for a one-shot operation:

```bash
prt-get install cronie
rc-update add crond boot 2>/dev/null || true

cat > /etc/cron.d/stormfs-cleanup << 'EOF'
17 3 * * * root /usr/local/bin/stormfs-cleanup.sh
EOF
chmod 644 /etc/cron.d/stormfs-cleanup
```

The cron entry replaces `OnCalendar=daily`; put `Persistent`-style catch-up behavior in the cleanup script if the job must run after downtime.

### OpenRC Replacement for Socket Activation

OpenRC does not provide native `.socket` units. Prefer making the daemon listen on its own socket and managing it with an OpenRC service. If a separate listener is required, use a socket-capable daemon such as `socat` and make the application service depend on it:

```bash
cat > /etc/init.d/mysocketapp << 'EOF'
#!/sbin/openrc-run

description="StormFS socket application"
command="/opt/myapp/bin/myapp"
command_args="--socket /run/stormfs/app.sock"
command_background=true
pidfile="/run/${RC_SVCNAME}.pid"

depend() {
    need localmount
    after logger
}

start_pre() {
    checkpath --directory --mode 0755 /run/stormfs
}
EOF
chmod 755 /etc/init.d/mysocketapp
rc-update add mysocketapp default
```

### OpenRC Runlevels Instead of systemd Targets

OpenRC runlevels replace the operational role of systemd targets:

| systemd target | OpenRC equivalent |
|----------------|-------------------|
| `rescue.target` | `single` or `nonetwork` |
| `multi-user.target` | `default` |
| `graphical.target` | `default` plus the display manager |
| `poweroff.target` | `shutdown` and `/sbin/poweroff` |
| `reboot.target` | `shutdown` and `/sbin/reboot` |

```bash
# Inspect and switch runlevels
rc-status --all
rc-update show
rc single
rc default

# Enable or disable a service in a runlevel
rc-update add sshd default
rc-update del sshd default
```

### OpenRC Boot Optimization

```bash
# /etc/rc.conf
RC_PARALLEL="YES"       # Start independent services in parallel
RC_VERBOSE="NO"         # Set YES while troubleshooting
RC_LOGGER="YES"         # Keep a boot log when supported by the logger

# Measure service startup without systemd-analyze
rc-status --servicelist
rc-status --all
rc-depend -a
```

Use `rc_parallel` only after dependencies are correct. A service that relies on ordering must declare `need`, `use`, `after`, or `before` in its init script.

## 12.2 Optional systemd Compatibility

systemd is the first process started by the kernel (PID 1) and is responsible for:

- Starting and managing system services
- Mounting filesystems
- Managing device hotplug
- Setting up logging (journald)
- Managing network (networkd/resolved)
- Handling power management and login sessions

### Installing systemd (from LFS)

systemd should already be installed during the LFS build. Verify:

```bash
systemctl --version
/lib/systemd/systemd --version
```

If rebuilding from source:

```bash
cd /sources
tar -xf systemd-261.2.tar.gz
cd systemd-261.2

mkdir -p build
cd build

meson setup .. \
    --prefix=/usr \
    --buildtype=release \
    -D default-dnssec=no \
    -D firstboot=false \
    -D install-tests=false \
    -D ldconfig=false \
    -D sysusers=false \
    -D rpmmacrosdir=no \
    -D homed=disabled \
    -D man=disabled \
    -D mode=release \
    -D pamconfdir=no \
    -D dev-kvm-mode=0660 \
    -D nobody-group=nogroup \
    -D sysupdate=disabled \
    -D ukify=disabled \
    -D docdir=/usr/share/doc/systemd-261.2

ninja
ninja install

systemd-machine-id-setup
systemd-hwdb update
```

## 12.3 Optional systemd Units

### systemd-journald (Logging)

The journal is systemd's logging system, replacing traditional syslog as the primary logging mechanism.

**Configuration:** `/etc/systemd/journald.conf`

```ini
[Journal]
Storage=persistent
SystemMaxUse=500M
MaxRetentionSec=1month
Compress=yes
ForwardToSyslog=yes
```

**Managing journald:**

```bash
# Restart journald
systemctl restart systemd-journald

# View all logs from current boot
journalctl -b

# View logs since last boot
journalctl -b -1

# Follow logs in real time
journalctl -f

# View logs for a specific unit
journalctl -u nginx.service

# View logs with priority filter
journalctl -p err

# View logs since a timestamp
journalctl --since "2026-08-17 10:00:00"
journalctl --since "1 hour ago"

# Disk usage
journalctl --disk-usage

# Vacuum old logs
journalctl --vacuum-size=200M
journalctl --vacuum-time=30d
```

### systemd-logind (Session Management)

Manages user logins, sessions, seats, and power management.

**Configuration:** `/etc/systemd/logind.conf`

```ini
[Login]
HandleSuspendKey=suspend
HandleHibernateKey=hibernate
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=suspend
KillUserProcesses=yes
KillOnlyUsers=root
IdleAction=ignore
IdleActionSec=infinity
RuntimeDirectorySize=10%
UserTasksMax=33%
```

**Commands:**

```bash
# List active sessions
loginctl list-sessions

# List active users
loginctl list-users

# Show session details
loginctl show-session <session-id>

# Enable lingering for a user (start services at boot without login)
loginctl enable-linger username

# Disable lingering
loginctl disable-linger username
```

### systemd-networkd (Networking)

Lightweight network management daemon.

**Configuration:** `/etc/systemd/networkd.conf`

```ini
[Network]
DHCP=no
```

See [Chapter 13: Networking](chapter-13-networking.md) for detailed configuration.

### systemd-resolved (DNS Resolution)

Handles DNS resolution with caching and DNSSEC support.

**Configuration:** `/etc/systemd/resolved.conf`

```ini
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=9.9.9.9 1.0.0.1
Domains=~.
DNSSEC=allow-downgrade
DNSOverTLS=opportunistic
Cache=yes
DNSStubListener=yes
```

**Commands:**

```bash
# Check DNS status
resolvectl status

# Query a specific domain
resolvectl query example.com

# Flush DNS cache
resolvectl flush-caches
```

### Other Essential Units

| Unit | Purpose |
|------|---------|
| `systemd-udevd.service` | Device management and hotplug |
| `systemd-timesyncd.service` | NTP time synchronization |
| `systemd-tmpfiles-setup.service` | Temporary file management |
| `systemd-hwdb-update.service` | Hardware database updates |
| `dbus.service` | D-Bus message bus (required by most services) |
| `getty@tty1.service` | Virtual console login |

## 12.4 Optional systemd Service Files

### Service File Structure

Service files live in `/etc/systemd/system/` (for admin-created units) or `/usr/lib/systemd/system/` (for package-provided units).

### Example: A Custom Web Application

Create `/etc/systemd/system/stormfs-webapp.service`:

```ini
[Unit]
Description=StormFS Web Application
Documentation=https://docs.stormfs.org/webapp
After=network.target
Wants=network-online.target
Requires=network-online.target
After=network-online.target

[Service]
Type=simple
User=webapp
Group=webapp
WorkingDirectory=/opt/stormfs-webapp
ExecStart=/opt/stormfs-webapp/bin/webapp --config /etc/stormfs/webapp.conf
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=3

# Environment
EnvironmentFile=-/etc/default/stormfs-webapp
Environment=STORMFS_ENV=production

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/lib/stormfs-webapp /var/log/stormfs-webapp
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
RestrictNamespaces=yes
MemoryDenyWriteExecute=yes
LockPersonality=yes
SystemCallArchitectures=native

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096
CPUQuota=200%
MemoryMax=2G
TasksMax=4096

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=stormfs-webapp

[Install]
WantedBy=multi-user.target
```

### Example: A Periodic Cleanup Timer

**Timer unit:** `/etc/stormfs-cleanup.timer`

```ini
[Unit]
Description=StormFS Daily Cleanup Timer
Requires=stormfs-cleanup.service

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1800
AccuracySec=1min

[Install]
WantedBy=timers.target
```

**Service unit:** `/etc/stormfs-cleanup.service`

```ini
[Unit]
Description=StormFS Daily Cleanup

[Service]
Type=oneshot
ExecStart=/usr/local/bin/stormfs-cleanup.sh
Nice=19
IOSchedulingClass=idle
```

### Example: A Socket-Activated Service

**Socket unit:** `/etc/systemd/system/mysocketapp.socket`

```ini
[Unit]
Description=StormFS Socket-Activated App

[Socket]
ListenStream=/run/stormfs/app.sock
Accept=no
SocketUser=webapp
SocketGroup=webapp
SocketMode=0660

[Install]
WantedBy=sockets.target
```

**Service unit:** `/etc/systemd/system/mysocketapp.service`

```ini
[Unit]
Description=StormFS Socket-Activated App Service
Requires=mysocketapp.socket

[Service]
Type=simple
User=webapp
ExecStart=/opt/myapp/bin/myapp --socket
```

## 12.5 Optional systemd Service Management Commands

### Starting and Stopping Services

```bash
# Start a service
systemctl start nginx.service

# Stop a service
systemctl stop nginx.service

# Restart a service
systemctl restart nginx.service

# Reload configuration without stopping
systemctl reload nginx.service

# Reload if running, otherwise do nothing
systemctl reload-or-restart nginx.service
```

### Enabling and Disabling Services

```bash
# Enable at boot
systemctl enable nginx.service

# Enable and start immediately
systemctl enable --now nginx.service

# Disable at boot
systemctl disable nginx.service

# Disable and stop immediately
systemctl disable --now nginx.service

# Re-enable (useful after modifying unit files)
systemctl reenable nginx.service

# Mask a service (prevent it from being started)
systemctl mask nginx.service

# Unmask a service
systemctl unmask nginx.service
```

### Checking Status

```bash
# Check service status
systemctl status nginx.service

# Check if active
systemctl is-active nginx.service

# Check if enabled
systemctl is-enabled nginx.service

# Check if failed
systemctl is-failed nginx.service

# List all running services
systemctl list-units --type=service --state=running

# List all enabled services
systemctl list-unit-files --type=service --state=enabled

# List all failed services
systemctl --failed
```

### Viewing Logs

```bash
# View service logs
journalctl -u nginx.service

# Follow service logs
journalctl -u nginx.service -f

# View since last boot
journalctl -u nginx.service -b

# View with detailed output
journalctl -u nginx.service -o verbose
```

### Systemd Paths and Targets

```bash
# List all unit files
systemctl list-unit-files

# List specific types
systemctl list-unit-files --type=service
systemctl list-unit-files --type=target
systemctl list-unit-files --type=timer

# Show unit dependencies
systemctl list-dependencies multi-user.target

# Show unit details
systemctl show nginx.service
```

## 12.6 Optional systemd Runlevels and Targets

systemd replaces traditional runlevels with **targets**. Each target represents a specific system state.

### Target Mapping

| Traditional Runlevel | systemd Target | Description |
|---------------------|----------------|-------------|
| 0 | `poweroff.target` | Shutdown |
| 1 | `rescue.target` | Single-user mode |
| 2 | `multi-user.target` | Multi-user, no GUI (Debian) |
| 3 | `multi-user.target` | Multi-user, no GUI |
| 4 | (custom) | User-defined |
| 5 | `graphical.target` | Multi-user with GUI |
| 6 | `reboot.target` | Reboot |

### Switching Targets

```bash
# Switch to rescue mode
systemctl isolate rescue.target

# Switch to graphical mode
systemctl isolate graphical.target

# Set default target
systemctl set-default multi-user.target
systemctl set-default graphical.target

# View default target
systemctl get-default
```

### Creating a Custom Target

Create `/etc/systemd/system/stormfs-custom.target`:

```ini
[Unit]
Description=StormFS Custom Target
Requires=basic.target
After=basic.target
AllowIsolate=yes

[Install]
WantedBy=multi-user.target
```

Create a service that starts in this target:

```ini
[Unit]
Description=StormFS Custom Service
PartOf=stormfs-custom.target
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/stormfs-custom-setup.sh

[Install]
WantedBy=stormfs-custom.target
```

Enable and use:

```bash
systemctl enable stormfs-custom.target
systemctl isolate stormfs-custom.target
```

## 12.7 Optional systemd Boot Target Dependencies

Understanding the boot sequence:

```
default.target
  └── multi-user.target
        ├── basic.target
        │     ├── sysinit.target
        │     │     ├── systemd-tmpfiles-setup.service
        │     │     └── ...
        │     ├── sockets.target
        │     ├── network.target
        │     └── ...
        ├── getty@tty1.service
        ├── sshd.service (if enabled)
        └── ...
```

View the dependency tree:

```bash
systemctl list-dependencies multi-user.target
```

## 12.8 Optional systemd Boot Optimization

### Measuring Boot Time

```bash
# View boot time breakdown
systemd-analyze

# View critical chain (slowest path)
systemd-analyze critical-chain

# View specific unit timing
systemd-analyze blame | head -20

# Generate SVG visualization
systemd-analyze plot > boot-analysis.svg
```

### Common Optimizations

```bash
# Disable unnecessary services
systemctl disable NetworkManager-wait-online.service
systemctl disable systemd-networkd-wait-online.service

# Disable systemd-resolved if using static /etc/resolv.conf
systemctl disable systemd-resolved

# Reduce journald storage
sed -i 's/^#SystemMaxUse=.*/SystemMaxUse=200M/' /etc/systemd/journald.conf
```

## 12.9 OpenRC Reference

For detailed OpenRC service and runlevel reference, use this section together with the dedicated BLFS OpenRC book. OpenRC is the default path for this book; the systemd sections above are optional.

### Key Differences

| Feature | systemd | OpenRC |
|---------|---------|--------|
| Init system | PID 1 manager | init + rc script runner |
| Service files | .service units | init.d scripts |
| Dependencies | declarative | declarative |
| Socket activation | yes | no (not built-in) |
| Resource control | cgroups v2 | limited |
| Boot speed | faster (parallel) | fast (parallel with zsh) |
| Resource usage | higher | minimal |

### OpenRC Source Reference

```bash
cd /sources
tar -xf openrc-0.63.tar.gz
cd openrc-0.63

./configure --prefix=/usr           \
            --sysconfdir=/etc/openrc \
            --libdir=/usr/lib/openrc \
            --sbindir=/sbin          \
            --enable-agent-support   \
            --disable-examples-only

make
make install
```

### Basic OpenRC Commands

```bash
# Start/stop/restart services
rc-service nginx start
rc-service nginx stop
rc-service nginx restart

# Enable/disable at boot
rc-update add nginx default
rc-update del nginx

# View running services
rc-status

# View dependency graph
rc-depend -c

# View service info
rc-update show
```

### OpenRC Service Script Structure

```bash
#!/sbin/openrc-run

name="myapp"
description="StormFS My Application"

command="/opt/myapp/bin/myapp"
command_args="--config /etc/myapp.conf"
command_user="myapp:myapp"
command_background=true
pidfile="/run/${RC_SVCNAME}.pid"

depend() {
    need net
    after firewall
    before nginx
}

start_pre() {
    # Create runtime directory
    install -d -m 0755 -o myapp -g myapp /run/myapp
}

stop() {
    ebegin "Stopping ${RC_SVCNAME}"
    start-stop-daemon --stop --pidfile "${pidfile}"
    eend $?
}
```

### OpenRC Configuration

**Global settings:** `/etc/openrc/rc.conf`

```bash
# Key settings
RC_NOCOLOR="no"
RC_VERBOSE="yes"
RC_DEFAULT_OPTS="--quiet"
```

**Runlevel configuration:** `/etc/runlevels/`

```
/etc/runlevels/
├── boot/
├── default/
├── nonetwork/
├── pyre-box/
├── shutdown/
└── sysinit/
```

### OpenRC Resources

- [OpenRC User Guide](https://github.com/OpenRC/openrc/blob/master/README.md)
- [Arch Wiki: OpenRC](https://wiki.archlinux.org/title/OpenRC)
- [CRUX Handbook: init](https://crux.nu/Handbook#init)

## 12.10 References

- [systemd Documentation](https://www.freedesktop.org/software/systemd/man/)
- [systemd.unit(5)](https://www.freedesktop.org/software/systemd/man/systemd.unit.html)
- [systemd.service(5)](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [Chapter 09: Linux Kernel](chapter-09-linux-kernel.md) — Kernel and modules
- [Chapter 13: Networking](chapter-13-networking.md) — Network configuration
- [Chapter 10: Bootloader](chapter-10-bootloader.md) — GRUB and boot
