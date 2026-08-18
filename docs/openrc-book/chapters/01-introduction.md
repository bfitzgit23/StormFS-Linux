# Chapter 1: Introduction to OpenRC

## What is OpenRC?

OpenRC is a dependency-based init system that can be used with Linux distributions. It is developed by the Gentoo project and provides a fast, flexible, and reliable way to manage system services.

### Key Features

- **Dependency-based**: Services are started and stopped based on their dependencies
- **BSD-style init scripts**: Uses shell scripts for service management
- **Fast**: Minimal overhead and quick boot times
- **Flexible**: Supports multiple runlevels and service configurations
- **Portable**: Works with any Linux distribution
- **No PID 1**: OpenRC does not replace the init process (PID 1)

### Comparison with Systemd

| Feature | OpenRC | Systemd |
|---------|--------|---------|
| Init System | Yes (not PID 1) | Yes (PID 1) |
| Service Management | init scripts | Unit files |
| Dependency Management | Yes | Yes |
| Parallel Starting | Yes | Yes |
| Logging | syslog | journald |
| Resource Control | cgroups (via cgroupfs) | cgroups (native) |
| Hardware Management | udev/eudev | udev (built-in) |

## OpenRC Architecture

### Core Components

1. **openrc**: The main service management script
2. **rc**: The init script that manages runlevels
3. **service**: The service management command
4. **runlevel**: The runlevel management command

### Directory Structure

```
/etc/
├── init.d/           # Service scripts
├── conf.d/           # Service configuration files
├── runlevels/        # Runlevel directories
│   ├── boot/
│   ├── default/
│   ├── nonetwork/
│   ├── single/
│   └── sysinit/
└── rc.conf           # Main configuration file
```

## Basic Concepts

### Services

A service is a daemon or background process that OpenRC can manage. Services are defined by init scripts in `/etc/init.d/`.

### Runlevels

A runlevel is a group of services that are started or stopped together. Common runlevels include:

- **sysinit**: System initialization (udev, etc.)
- **boot**: Basic system services
- **default**: Normal operating mode
- **single**: Single-user mode
- **nonetwork**: Services that don't need networking

### Dependencies

Services can depend on other services. For example, NetworkManager depends on dbus. OpenRC ensures dependencies are started before the services that need them.

### Need/Use/Break/After

- **need**: Service requires this dependency to be started
- **use**: Service can use this dependency if available
- **break**: Service conflicts with this dependency
- **after**: Service should start after this dependency

## History

OpenRC was originally developed as part of the Gentoo Linux project. It was extracted from Gentoo's baselayout package to provide a standalone init system that could be used by other distributions.

## Further Reading

- [OpenRC Documentation](https://github.com/OpenRC/openrc/blob/master/README.md)
- [Gentoo OpenRC Guide](https://wiki.gentoo.org/wiki/OpenRC)
- [OpenRC Man Pages](https://github.com/OpenRC/openrc/tree/master/man)
