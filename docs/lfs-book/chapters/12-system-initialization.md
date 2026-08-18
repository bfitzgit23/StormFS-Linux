# Chapter 12: System Initialization

This chapter covers **systemd**, the init system and service manager used by StormFS Linux. An OpenRC alternative is also documented.

## 12.1 systemd Overview

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
tar -xf systemd-256.tar.xz
cd systemd-256

mkdir build && cd build

meson setup .. \
    --prefix=/usr \
    --sysconfdir=/etc \
    --localstatedir=/var \
    -Dblkid=true \
    -Dbuildtype=release \
    -Dfirstboot=false \
    -Dinstall-tests=false \
    -Dman=false \
    -Dmode=release \
    -Drootprefix= \
    -Dhomed=false \
    -Duserdb=false \
    -Dldconfig=false \
    -Dnss-systemd=false

ninja
ninja install

systemd-machine-id-setup
systemd-hwdb update
```

## 12.2 Essential systemd Units

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

## 12.3 Creating Custom Service Files

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

## 12.4 Service Management Commands

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

## 12.5 Runlevels and Targets

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

## 12.6 Boot Target Dependencies

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

## 12.7 Boot Optimization

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

## 12.8 OpenRC Alternative

For users who prefer a lightweight init system without systemd, StormFS provides OpenRC as an alternative.

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

### Installing OpenRC

```bash
cd /sources
tar -xf openrc-0.54.tar.xz
cd openrc-0.54

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

## 12.9 References

- [systemd Documentation](https://www.freedesktop.org/software/systemd/man/)
- [systemd.unit(5)](https://www.freedesktop.org/software/systemd/man/systemd.unit.html)
- [systemd.service(5)](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [Chapter 09: Linux Kernel](chapter-09-linux-kernel.md) — Kernel and modules
- [Chapter 13: Networking](chapter-13-networking.md) — Network configuration
- [Chapter 10: Bootloader](chapter-10-bootloader.md) — GRUB and boot
