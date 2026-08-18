# Chapter 8: Basic System Configuration

This chapter describes the essential system configuration files that must be present in the StormFS rootfs before it can be deployed to a target system. These files are installed by the `aaa_filesystem` port and can be customized after installation.

## 8.1 /etc/fstab

The filesystem table defines how partitions and filesystems are mounted at boot. StormFS uses UUID-based device identification for reliability.

### Template

```
# /etc/fstab: static file system information.
#
# <file system>  <mount point>  <type>  <options>              <dump>  <pass>
/dev/sda1        /              ext4    defaults               1       1
/dev/sda2        swap           swap    sw                     0       0
proc             /proc          proc    nosuid,nodev,noexec    0       0
sysfs            /sys           sysfs   nosuid,nodev,noexec    0       0
devpts           /dev/pts       devpts  gid=5,mode=620         0       0
tmpfs            /run           tmpfs   nosuid,nodev,mode=755  0       0
tmpfs            /dev/shm       tmpfs   nosuid,nodev           0       0
```

### UUID-Based Configuration

For production installations, use UUIDs instead of device names:

```sh
# Find the UUID of a partition
$ blkid /dev/sda1
/dev/sda1: UUID="a1b2c3d4-e5f6-7890-abcd-ef1234567890" TYPE="ext4"

# /etc/fstab with UUIDs:
UUID=a1b2c3d4-e5f6-7890-abcd-ef1234567890  /       ext4  defaults  1  1
UUID=e5f6-7890                              swap    swap  sw        0  0
```

### Virtual Filesystems

```
proc             /proc          proc    nosuid,nodev,noexec    0       0
sysfs            /sys           sysfs   nosuid,nodev,noexec    0       0
devpts           /dev/pts       devpts  gid=5,mode=620         0       0
tmpfs            /run           tmpfs   nosuid,nodev,mode=755  0       0
tmpfs            /dev/shm       tmpfs   nosuid,nodev           0       0
```

### Common Mount Options

| Option | Description |
|--------|-------------|
| `defaults` | Equivalent to `rw,suid,dev,exec,auto,nouser,async` |
| `nosuid` | Ignore SUID/SGID bits |
| `nodev` | Do not interpret character/block devices |
| `noexec` | Do not allow direct execution of binaries |
| `noatime` | Do not update access times |
| `discard` | Enable TRIM for SSDs |

## 8.2 /etc/hostname

The hostname file contains the system's network name.

### Template

```
stormfs
```

### Setting a Custom Hostname

```sh
# echo "myworkstation" > /etc/hostname
```

### Applying Without Reboot

```sh
# hostname $(cat /etc/hostname)
```

## 8.3 /etc/hosts

The hosts file maps IP addresses to hostnames for local resolution.

### Template

```
# Begin /etc/hosts

127.0.0.1       localhost
127.0.1.1       <hostname>
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters

# End /etc/hosts
```

Replace `<hostname>` with the value from `/etc/hostname`:

```sh
# sed -i "s/<hostname>/$(cat /etc/hostname)/" /etc/hosts
```

## 8.4 /etc/locale.conf and Locale Generation

The locale configuration file sets the default system locale.

### Template

```
# Begin /etc/locale.conf

LANG=C

# End /etc/locale.conf
```

### Available Locales

StormFS ships with a locale definition system based on glibc's locale data. The `/etc/locales` file lists all available locales:

```sh
# View available locales
$ cat /etc/locales
```

### Generating Locales

```sh
# Generate a specific locale
# localedef -i en_US -f UTF-8 en_US.UTF-8

# Set the default locale
# echo "LANG=en_US.UTF-8" > /etc/locale.conf
```

### Profile Scripts

The `aaa_filesystem` port installs locale-related profile scripts:

- `/etc/profile.d/locale.sh` — Sets locale environment variables
- `/etc/profile.d/i18n.sh` — Internationalization configuration

### Valid Locales

```
C, C.UTF-8, en_US, en_US.UTF-8, POSIX
```

## 8.5 /etc/vconsole.conf (Keymap)

The vconsole configuration sets the keyboard layout for the virtual console.

### Template

```
# Begin /etc/vconsole.conf

KEYMAP=us

# End /etc/vconsole.conf
```

### Available Keymaps

Keymap files are installed by the `kbd` package:

```sh
# List available keymaps
$ ls /usr/share/kbd/keymaps/

# Load a keymap
# loadkeys de-latin1
```

### Common Keymaps

| Keymap | Description |
|--------|-------------|
| `us` | US English (default) |
| `uk` | UK English |
| `de` | German |
| `fr` | French |
| `es` | Spanish |
| `it` | Italian |
| `br-abnt2` | Brazilian Portuguese |

### Setting the Keymap

```sh
# echo "KEYMAP=de-latin1" > /etc/vconsole.conf
```

## 8.6 /etc/timezone and /etc/localtime

Timezone configuration determines the system's time zone and daylight saving time rules.

### Finding the Timezone

```sh
# List available timezones
$ ls /usr/share/zoneinfo/

# Test a timezone
$ TZ=America/New_York date
```

### Setting the Timezone

```sh
# echo "America/New_York" > /etc/timezone

# Create the /etc/localtime symlink
# ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
```

### Common Timezones

| Timezone | Description |
|----------|-------------|
| `America/New_York` | US Eastern |
| `America/Chicago` | US Central |
| `America/Denver` | US Mountain |
| `America/Los_Angeles` | US Pacific |
| `Europe/London` | UK |
| `Europe/Berlin` | Germany |
| `Asia/Tokyo` | Japan |
| `UTC` | Coordinated Universal Time |

### Timezone Data

Timezone data is installed by the `tzdata` package. The `zic` compiler creates the binary timezone files:

```sh
# Recompile timezone data
# zic /usr/share/zoneinfo/posixrules
```

## 8.7 /etc/resolv.conf

The resolver configuration file specifies DNS servers for name resolution.

### Template

```
# Begin /etc/resolv.conf

nameserver 8.8.8.8
nameserver 8.8.4.4

# End /etc/resolv.conf
```

### Google DNS

```
nameserver 8.8.8.8
nameserver 8.8.4.4
```

### Cloudflare DNS

```
nameserver 1.1.1.1
nameserver 1.0.0.1
```

### OpenDNS

```
nameserver 208.67.222.222
nameserver 208.67.220.220
```

### Using systemd-resolved

If systemd-resolved is enabled, `/etc/resolv.conf` should be a symlink:

```sh
# ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
```

## 8.8 /etc/shells

The shells file lists valid login shells for the system.

### Template

```
# Begin /etc/shells

/bin/sh
/bin/bash

# End /etc/shells
```

### Adding Additional Shells

After installing additional shells (e.g., dash, zsh):

```sh
# echo "/bin/dash" >> /etc/shells
# echo "/bin/zsh" >> /etc/shells
```

### Checking Valid Shells

```sh
$ chsh -l
/bin/sh
/bin/bash
```

## 8.9 Console Fonts

Console fonts are configured through the kernel console driver and kbd utilities.

### Available Fonts

```sh
# List available console fonts
$ ls /usr/share/kbd/consolefonts/

# Common fonts
lat1-16.psfu       # ISO 8859-1 (Western European)
lat2-16.psfu       # ISO 8859-2 (Central European)
LatGrkCyr-12x22.psfu  # Latin, Greek, Cyrillic
eurlatgr.psfu      # Euro Latin Greek
```

### Setting the Console Font

```sh
# Load a font
# setfont LatGrkCyr-12x22

# Make persistent via /etc/vconsole.conf
# echo "FONT=LatGrkCyr-12x22" >> /etc/vconsole.conf
```

### framebuffer Console

For framebuffer consoles, fonts are loaded via the kernel:

```
# /etc/vconsole.conf
KEYMAP=us
FONT=LatGrkCyr-12x22
```

## 8.10 System Configuration Summary

The following configuration files are installed by the `aaa_filesystem` port:

| File | Purpose | Default |
|------|---------|---------|
| `/etc/fstab` | Filesystem mount table | UUID-based template |
| `/etc/hostname` | System hostname | `stormfs` |
| `/etc/hosts` | Local hostname resolution | `127.0.0.1 localhost` |
| `/etc/locale.conf` | Default locale | `LANG=C` |
| `/etc/resolv.conf` | DNS configuration | Google DNS |
| `/etc/shells` | Valid login shells | `/bin/sh`, `/bin/bash` |
| `/etc/passwd` | User account database | Root + system accounts |
| `/etc/group` | Group database | Standard system groups |
| `/etc/inputrc` | Readline configuration | Standard inputrc |
| `/etc/profile` | System-wide shell profile | Standard profile |
| `/etc/bashrc` | Bash system configuration | Standard bashrc |
| `/etc/bfs-release` | StormFS version | Current version |
| `/etc/os-release` | OS identification | StormFS metadata |

### Profile Directory

```
/etc/profile.d/
├── bash_completion.sh
├── dircolors.sh
├── extrapaths.sh
├── gawk.sh
├── i18n.sh
├── locale.sh
├── readline.sh
├── umask.sh
└── ...
```

### Default User Skeleton

```
/etc/skel/
├── .bash_profile
├── .bashrc
├── .profile
├── .bash_logout
└── .vimrc
```

### Generated Files

| File | Generator |
|------|-----------|
| `/etc/dircolors` | `dircolors -p` |
| `/etc/issue` | `aaa_filesystem` package |
| `/etc/bfs-release` | `aaa_filesystem` package |
| `/etc/lfs-release` | `aaa_filesystem` package (compatibility) |
| `/etc/os-release` | `aaa_filesystem` package |

These files complete the basic system configuration. For advanced configuration (systemd services, networking, desktop environments), see the StormFS BLFS guides.
