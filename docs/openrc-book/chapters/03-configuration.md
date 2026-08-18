# Chapter 3: Configuration

## Main Configuration

The main OpenRC configuration file is `/etc/rc.conf`. This file controls the overall behavior of OpenRC.

### Key Settings

```bash
# /etc/rc.conf

# Default runlevel
DEFAULT_RUNLEVEL=3

# Enable parallel starting of services
RC_PARALLEL="yes"

# Enable coloring of output
RC_COLORMAP="yes"

# Logger configuration
RC_LOGGER="yes"

# Shell for service scripts
OPENRC_SHELL=/bin/sh

# Cgroup configuration
RC_CGROUP_MODE="hybrid"

# Enable Unicode support
RC_UNICODE="yes"
```

## Service Configuration

Service-specific configuration is stored in `/etc/conf.d/` files. Each service can have its own configuration file.

### Example: NetworkManager

```bash
# /etc/conf.d/networkmanager

# Extra options for NetworkManager
NETWORKMANAGER_OPTS=""

# Wait for network before starting
RC_NEED="net"
```

### Example: LightDM

```bash
# /etc/conf.d/lightdm

# Display manager options
LIGHTDM_OPTS=""

# Runlevel for display manager
RC_RUNLEVEL="default"
```

## Environment Configuration

Environment variables can be set in `/etc/env.d/` files:

```bash
# /etc/env.d/00basic

PATH="/usr/local/bin:/usr/bin:/bin"
MANPATH="/usr/local/man:/usr/share/man"
```

After modifying environment files, run:

```bash
sudo env-update
```

## Boot Configuration

### /etc/conf.d/boot

```bash
# /etc/conf.d/boot

# Boot messages
RC_BOOTLOG="yes"

# Emergency shell on failure
RC_EMERGENCY="yes"
```

### /etc/conf.d/consolefont

```bash
# /etc/conf.d/consolefont

# Console font
CONSOLEFONT="Lat2-Terminus16"
CONSOLETRANSCODE=""
```

## Logging Configuration

OpenRC uses syslog for logging. Configure in `/etc/conf.d/syslog`:

```bash
# /etc/conf.d/syslog

# Syslog options
SYSLOGD_OPTS="-m 0 -s -b"
```

## Next Steps

After configuration, proceed to [Chapter 4: Runlevels](chapters/04-runlevels.md) to understand runlevel management.
