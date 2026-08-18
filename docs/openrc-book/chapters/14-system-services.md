# Chapter 14: System Services

## Overview

This chapter covers configuring various system services with OpenRC.

## Cron Service

### cronie

cronie provides cron functionality:

```bash
# Install cronie
prt-get install cronie

# Enable cronie
sudo rc-update add cronie boot

# Start cronie
sudo rc-service cronie start
```

### Adding Cron Jobs

```bash
# Edit user crontab
crontab -e

# Edit system crontab
sudo nano /etc/crontab
```

## Logging

### syslog-ng

syslog-ng provides system logging:

```bash
# Install syslog-ng
prt-get install syslog-ng

# Enable syslog-ng
sudo rc-update add syslog-ng boot

# Start syslog-ng
sudo rc-service syslog-ng start
```

### Configuration

Edit `/etc/syslog-ng/syslog-ng.conf`:

```bash
@version: 4.4

source s_sys {
    system();
    internal();
};

destination d_mesg { file("/var/log/messages"); };
destination d_auth { file("/var/log/auth.log"); };
destination d_syslog { file("/var/log/syslog"); };

log { source(s_sys); destination(d_mesg); };
log { source(s_sys); destination(d_auth); };
log { source(s_sys); destination(d_syslog); };
```

## SSH Server

### OpenSSH

```bash
# Install OpenSSH
prt-get install openssh

# Enable SSH
sudo rc-update add sshd default

# Start SSH
sudo rc-service sshd start
```

### Configuration

Edit `/etc/ssh/sshd_config`:

```bash
Port 22
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
```

## Power Management

### acpid

acpid handles power management events:

```bash
# Install acpid
prt-get install acpid

# Enable acpid
sudo rc-update add acpid boot

# Start acpid
sudo rc-service acpid start
```

### Configuration

Edit `/etc/acpi/actions/powerbtn.sh`:

```bash
#!/bin/bash
# Handle power button press
/sbin/poweroff
```

## Disk Monitoring

### smartd

smartd monitors disk health:

```bash
# Install smartmontools
prt-get install smartmontools

# Enable smartd
sudo rc-update add smartd default

# Start smartd
sudo rc-service smartd start
```

### Configuration

Edit `/etc/smartd.conf`:

```bash
# Monitor first disk
/dev/sda -a -o on -S on -n standby -s (S/../.././02|L/../../6/03) -m admin@example.com

# Monitor all disks
/dev/sd[a-z] -a -o on -S on -n standby -s (S/../.././02|L/../../6/03) -m admin@example.com
```

## Disk Management

### udisks2

udisks2 provides disk management:

```bash
# Install udisks2
prt-get install udisks2

# Enable udisks2
sudo rc-update add udisks2 default

# Start udisks2
sudo rc-service udisks2 start
```

## PolicyKit

### polkitd

polkitd provides authorization:

```bash
# Install polkit
prt-get install polkit

# Enable polkitd
sudo rc-update add polkitd default

# Start polkitd
sudo rc-service polkitd start
```

## Color Management

### colord

colord manages color profiles:

```bash
# Install colord
prt-get install colord

# Enable colord
sudo rc-update add colord default

# Start colord
sudo rc-service colord start
```

## Power Management

### upowerd

upowerd monitors power devices:

```bash
# Install upower
prt-get install upower

# Enable upowerd
sudo rc-update add upowerd default

# Start upowerd
sudo rc-service upowerd start
```

## Accounts Service

### accounts-daemon

accounts-daemon manages user accounts:

```bash
# Install accounts-service
prt-get install accountsservice

# Enable accounts-daemon
sudo rc-update add accounts-daemon default

# Start accounts-daemon
sudo rc-service accounts-daemon start
```

## Avahi (mDNS)

### avahi-daemon

avahi-daemon provides mDNS/DNS-SD:

```bash
# Install avahi
prt-get install avahi

# Enable avahi
sudo rc-update add avahi-daemon default
sudo rc-update add avahi-dnsconfd default

# Start avahi
sudo rc-service avahi-daemon start
sudo rc-service avahi-dnsconfd start
```

## Next Steps

After system services configuration, proceed to [Chapter 15: Troubleshooting](chapters/15-troubleshooting.md) for common issues.
