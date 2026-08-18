# Chapter 2: Preparing the Host System

This chapter describes the steps needed to prepare the host system for building StormFS Linux. These steps create the directory structure, set environment variables, and prepare the skeleton root filesystem that will be populated during the toolchain and base system builds.

> **Note:** Steps in this chapter that require root access are handled automatically by the bootstrap menu. If building manually, follow the indicated privilege requirements.

## 2.1 Creating the Tools Directory

The temporary toolchain is installed into `/tmp/lfs-tools`, which is a symlink pointing to `/tmp/lfs-rootfs/tmp/lfs-tools`. This layout allows the toolchain to reside physically inside the rootfs while remaining accessible via a short host-side path.

### Creating the Root Filesystem Directory

```sh
$ sudo mkdir -p /tmp/lfs-rootfs
```

### Creating the Tools Symlink

The bootstrap script creates this automatically, but the relationship is:

```
/tmp/lfs-tools → /tmp/lfs-rootfs/tmp/lfs-tools
```

```sh
$ mkdir -p /tmp/lfs-rootfs/tmp/lfs-tools
$ ln -s /tmp/lfs-rootfs/tmp/lfs-tools /tmp/lfs-tools
```

> **Important:** Do not use `rm -f` followed by `ln -sf` in sequence. If `/tmp/lfs-tools` already exists as a directory, `ln -sf` creates a nested symlink inside it rather than replacing it. Use `rm -rf` first if you need to recreate the symlink.

### Verifying the Symlink

```sh
$ ls -la /tmp/lfs-tools
lrwxrwxrwx 1 user user ... /tmp/lfs-tools -> /tmp/lfs-rootfs/tmp/lfs-tools

$ readlink -f /tmp/lfs-tools
/tmp/lfs-rootfs/tmp/lfs-tools
```

## 2.2 Setting Up Environment Variables

The following environment variables must be set for the entire build process. They are set by the bootstrap script, but can also be exported manually:

```sh
$ export LFS=/tmp/lfs-rootfs
$ export TOOLS=/tmp/lfs-tools
$ export PATH=$TOOLS/bin:$PATH
$ export LFS_TGT=x86_64-lfs-linux-gnu
$ export LFS_TGT32=i686-lfs-linux-gnu
```

### Variable Descriptions

| Variable | Value | Purpose |
|----------|-------|---------|
| `LFS` | `/tmp/lfs-rootfs` | Root of the target filesystem being built |
| `TOOLS` | `/tmp/lfs-tools` | Location of the temporary cross-compilation toolchain |
| `PATH` | `$TOOLS/bin:$PATH` | Ensures toolchain binaries are found first |
| `LFS_TGT` | `x86_64-lfs-linux-gnu` | Target triplet for 64-bit cross-compiler |
| `LFS_TGT32` | `i686-lfs-linux-gnu` | Target triplet for 32-bit cross-compiler |

### Locale Settings

For deterministic builds, the bootstrap enforces the POSIX C locale:

```sh
$ unset LC_CTYPE LC_COLLATE LC_MESSAGES LC_MONETARY LC_NUMERIC LC_TIME
$ export LANG=C
$ export LC_ALL=C
$ export LANGUAGE=C
```

### Build Flags

The default portable build flags are:

```sh
$ export MAKEFLAGS="-j$(nproc)"
$ export CFLAGS="-O2 -march=x86-64 -pipe"
$ export CXXFLAGS="$CFLAGS"
```

When using ccache:

```sh
$ export PATH="/usr/lib/ccache:$TOOLS/bin:$PATH"
```

## 2.3 Mounting Virtual Filesystems

Before entering a chroot or building the base system, certain virtual filesystems must be mounted inside the rootfs. The `mountfs` function in `bootstrap.sh` handles this:

```sh
# mount function (from bootstrap.sh)
mountfs() {
    umountfs

    mkdir -p "$LFS/dev" "$LFS/run" "$LFS/proc" "$LFS/sys"

    mount --bind /dev "$LFS/dev"

    mount -t devpts devpts \
        "$LFS/dev/pts" \
        -o gid=5,mode=620

    mount -t proc proc "$LFS/proc"
    mount -t sysfs sysfs "$LFS/sys"
    mount -t tmpfs tmpfs "$LFS/run"

    if [ -h "$LFS/dev/shm" ]; then
        mkdir -p "$LFS/$(readlink "$LFS/dev/shm")"
    fi
}
```

### Manual Mount Commands

```sh
# Create mount point directories
# mkdir -p $LFS/{dev,proc,sys,run}

# Bind-mount /dev
# mount --bind /dev $LFS/dev

# Mount devpts
# mount -t devpts devpts $LFS/dev/pts -o gid=5,mode=620

# Mount proc
# mount -t proc proc $LFS/proc

# Mount sysfs
# mount -t sysfs sysfs $LFS/sys

# Mount tmpfs for /run
# mount -t tmpfs tmpfs $LFS/run
```

### Bind-Mounting Build Directories

During Stage 2 (base build), the bootstrap bind-mounts the host's source, package, and build-work directories into the chroot:

```sh
# Source directory
# mount --bind "$PWD/sources" $LFS/var/cache/pkg/sources

# Package output directory
# mount --bind "$PWD/packages" $LFS/var/cache/pkg/packages

# Build work directory (for large builds like GCC)
# mount --bind "$PWD/build-work" $LFS/var/cache/pkg/build-work
```

### Unmounting

The `umountfs` function unmounts all virtual filesystems in reverse order:

```sh
umountfs() {
    umount "$LFS/dev/pts"
    umount "$LFS/dev"
    umount "$LFS/run"
    umount "$LFS/proc"
    umount "$LFS/sys"
    umount "$LFS/$pkgmkwork"
    umount "$LFS/$pkgmkpkg"
    umount "$LFS/$pkgmksrc"
}
```

> **Important:** Always unmount virtual filesystems before archiving the rootfs. Archiving with active mounts produces an inconsistent and unusable archive.

## 2.4 Creating the Rootfs Skeleton

Before the first base system package is installed, a minimal directory skeleton must exist inside the rootfs. The bootstrap creates this when the package database (`/var/lib/pkg/db`) does not yet exist.

### Directory Structure

The skeleton follows a merged-/usr layout:

```sh
# Create base directories
# mkdir -pv $LFS/{etc,var}
# mkdir -pv $LFS/usr/{bin,lib,sbin}
# mkdir -pv $LFS/dev
```

### Symlinks for Merged-/usr

StormFS uses a merged-/usr layout where `/bin`, `/lib`, and `/sbin` are symlinks to their `/usr` counterparts:

```sh
# for i in bin lib sbin; do
#     ln -sv "usr/$i" "$LFS/$i"
# done
```

This produces:

```
/bin    -> usr/bin
/lib    -> usr/lib
/sbin   -> usr/sbin
```

### 64-bit Library Directory

```sh
# mkdir -pv $LFS/lib64
```

On x86_64, `lib64` is a symlink to `lib`:

```
/lib64 -> lib
```

### 32-bit Library Directories

StormFS supports x86_64 multilib with 32-bit libraries:

```sh
# mkdir -pv $LFS/usr/lib32
# ln -sv usr/lib32 $LFS/lib32
```

### Shell Symlink

```sh
# ln -svf bash $LFS/bin/sh
```

This creates `/bin/sh -> bash`.

### Mount Table Symlink

```sh
# ln -svf /proc/self/mounts $LFS/etc/mtab
```

### Toolchain Library Symlinks

Bootstrap the initial shared libraries from the toolchain:

```sh
# ln -svf \
#     $TOOLS/lib/libgcc_s.so \
#     $TOOLS/lib/libgcc_s.so.1 \
#     $LFS/usr/lib

# ln -svf \
#     $TOOLS/lib/libstdc++.a \
#     $TOOLS/lib/libstdc++.so \
#     $TOOLS/lib/libstdc++.so.6 \
#     $LFS/usr/lib
```

### Basic Command Symlinks

For the initial bootstrap, essential commands are symlinked from the toolchain:

```sh
# for i in bash cat chmod dd echo ln mkdir pwd rm stty; do
#     ln -svf "$TOOLS/bin/$i" "$LFS/usr/bin"
# done

# for i in env install perl printf touch; do
#     ln -svf "$TOOLS/bin/$i" "$LFS/usr/bin"
# done
```

## 2.5 Installing passwd and Group Files

The base system requires `/etc/passwd` and `/etc/group` files. These are taken from the `aaa_filesystem` port source:

### /etc/passwd

```sh
# cat ports/core/aaa_filesystem/passwd > $LFS/etc/passwd
```

Contents (from `ports/core/aaa_filesystem/passwd`):

```
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/nologin
daemon:x:2:2:daemon:/dev/null:/usr/bin/nologin
sys:x:3:3:sys:/dev:/usr/bin/nologin
sync:x:4:65534:sync:/bin:/bin/sync
games:x:5:60:games:/usr/games:/usr/bin/nologin
man:x:6:13:man:/var/cache/man:/usr/bin/nologin
lp:x:7:7:lp:/var/spool/lpd:/usr/bin/nologin
mail:x:8:8:mail:/var/mail:/usr/bin/nologin
news:x:9:9:news:/var/spool/news:/usr/bin/nologin
uucp:x:10:10:uucp:/var/spool/uucp:/usr/bin/nologin
proxy:x:13:13:proxy:/bin:/usr/bin/nologin
www-data:x:33:33:www-data:/var/www:/usr/bin/nologin
backup:x:34:34:backup:/var/backups:/usr/bin/nologin
list:x:38:38:Mailing List Manager:/var/list:/usr/bin/nologin
irc:x:39:39:ircd:/var/run/ircd:/usr/bin/nologin
gnats:x:41:41:Gnats Bug-Reporting System (admin):/var/lib/gnats:/usr/bin/nologin
nobody:x:65534:65534:nobody:/nonexistent:/usr/bin/nologin
dbus:x:81:81:dbus:/var/lib/dbus:/usr/bin/nologin
systemd-journal-gateway:x:72:72:systemd Journal Gateway:/:/usr/bin/nologin
systemd-journal-remote:x:73:73:systemd Journal Remote:/:/usr/bin/nologin
systemd-journal-upload:x:74:74:systemd Journal Upload:/:/usr/bin/nologin
systemd-network:x:75:75:systemd Network Management:/:/usr/bin/nologin
systemd-resolve:x:76:76:systemd Resolver:/:/usr/bin/nologin
systemd-timesync:x:77:77:systemd Time Synchronization:/:/usr/bin/nologin
systemd-coredump:x:78:78:systemd Core Dumper:/:/usr/bin/nologin
systemd-oom:x:79:79:systemd Out Of Memory Daemon:/:/usr/bin/nologin
tss:x:82:82:TPM Software Stack:/var/lib/tpm:/usr/bin/nologin
polkitd:x:997:997:PolicyKit Daemon:/run/polkitd:/usr/bin/nologin
avahi:x:996:996:Avahi mDNS/DNS-SD Daemon:/var/run/avahi-daemon:/usr/bin/nologin
colord:x:995:995:Color management daemon:/var/lib/colord:/usr/bin/nologin
usbmux:x:994:994:usbmux daemon:/var/lib/usbmux:/usr/bin/nologin
lpq:x:993:993:printer spooling directory:/var/spool/lpd:/usr/bin/nologin
kvm:x:992:992:kvm:/dev/kvm:/usr/bin/nologin
renderer:x:991:991:Renderer Directory:/run/renderer:/usr/bin/nologin
rfkill:x:990:990:rfkill daemon:/run/rfkill:/usr/bin/nologin
ngplug:x:989:989:NetworkManager:/run/NetworkManager:/usr/bin/nologin
sshd:x:988:988:Privilege-separated SSH:/var/empty:/usr/bin/nologin
dnsmasq:x:987:987:dnsmasq daemon:/var/lib/misc:/usr/bin/nologin
ggated:x:986:986:GNUnet/ggated daemon:/var/run/gnunet:/usr/bin/nologin
messagebus:x:985:985:D-Bus message daemon user:/run/dbus:/usr/bin/nologin
root:x:0:0:root:/root:/bin/bash
```

### /etc/group

```sh
# cat ports/core/aaa_filesystem/group > $LFS/etc/group
```

Contents (from `ports/core/aaa_filesystem/group`):

```
root:x:0:
bin:x:1:bin
daemon:x:2:daemon
sys:x:3:sys
adm:x:4:
tty:x:5:
disk:x:6:
lp:x:7:
mail:x:8:
news:x:9:
uucp:x:10:
audio:x:29:
video:x:44:
dialout:x:20:
floppy:x:11:
cdrom:x:12:
tape:x:33:
audio:x:29:
video:x:44:
cdrom:x:12:
floppy:x:11:
tape:x:33:
dialout:x:20:
dbus:x:81:
systemd-journal:x:72:
systemd-network:x:75:
systemd-resolve:x:76:
systemd-timesync:x:77:
systemd-coredump:x:78:
systemd-oom:x:79:
tss:x:82:
polkitd:x:997:
avahi:x:996:
colord:x:995:
usbmux:x:994:
lpq:x:993:
kvm:x:992:
render:x:991:
rfkill:x:990:
nm-openconnect:x:989:
sshd:x:988:
dnsmasq:x:987:
ggated:x:986:
messagebus:x:985:
users:x:100:
nogroup:x:65534:
utmp:x:22:
utempter:x:35:
ssh:x:988:
```

## 2.6 Initializing the Package Database

The CRUX-based package system uses a flat-file database at `/var/lib/pkg/db` to track installed packages:

```sh
# mkdir -p $LFS/var/lib/pkg
# touch $LFS/var/lib/pkg/db
```

### Package Cache Directories

```sh
# mkdir -p $LFS/var/cache/pkg/packages
# mkdir -p $LFS/var/cache/pkg/sources
# mkdir -p $LFS/var/cache/pkg/build-work
```

### pkgutils Extension

The StormFS build system extends CRUX pkgutils with a custom extension file:

```sh
# mkdir -p $LFS/var/lib/pkgmk
# cp ports/core/pkgutils/extension $LFS/var/lib/pkgmk
```

### pkgmk.conf for the Chroot

A minimal `pkgmk.conf` is written into the chroot for package builds:

```sh
cat > $LFS/tmp/pkgmk.conf << 'EOF'
export LANG=C
export LC_ALL=C
export LANGUAGE=C

export CPPFLAGS="-I/usr/include"
export CFLAGS="$CFLAGS"
export CXXFLAGS="${CFLAGS}"
export LDFLAGS="-L/usr/lib -Wl,-rpath-link,/usr/lib"
export LIBRARY_PATH="/usr/lib"

export PKG_CONFIG_PATH="/usr/lib/pkgconfig:/usr/share/pkgconfig"
export PKG_CONFIG_LIBDIR="/usr/lib/pkgconfig:/usr/share/pkgconfig"

export JOBS=$(nproc)
export MAKEFLAGS="-j $JOBS"

PKGMK_SOURCE_DIR="/var/cache/pkg/sources"
PKGMK_PACKAGE_DIR="/var/cache/pkg/packages"
PKGMK_WORK_DIR="/var/cache/pkg/build-work/pkgmk-$name"

. /var/lib/pkgmk/extension
EOF
```

### Ports Tree Copy

The entire ports tree is copied into the rootfs so packages can be built inside chroot:

```sh
# cp -r ports/ $LFS/usr/
```

### pkgin Stub

A `pkgin` wrapper script is placed in the toolchain for use during the base build:

```sh
# cp files/pkgin $LFS/tmp/lfs-tools/bin/pkgin
# chmod +x $LFS/tmp/lfs-tools/bin/pkgin
```

## 2.7 Complete Skeleton Summary

After completing all steps in this chapter, the rootfs should contain:

```
/tmp/lfs-rootfs/
├── bin -> usr/bin
├── dev/
├── etc/
│   ├── mtab -> /proc/self/mounts
│   ├── passwd
│   └── group
├── lib -> usr/lib
├── lib32 -> usr/lib32
├── lib64 -> lib
├── proc/                (mounted later)
├── run/                 (mounted later)
├── sbin -> usr/sbin
├── sys/                 (mounted later)
├── tmp/
│   └── pkgmk.conf
├── usr/
│   ├── bin/
│   │   ├── bash -> $TOOLS/bin/bash
│   │   ├── cat -> $TOOLS/bin/cat
│   │   └── ... (other symlinks)
│   ├── lib/
│   │   ├── libgcc_s.so -> $TOOLS/lib/libgcc_s.so
│   │   ├── libgcc_s.so.1 -> $TOOLS/lib/libgcc_s.so.1
│   │   ├── libstdc++.a -> $TOOLS/lib/libstdc++.a
│   │   ├── libstdc++.so -> $TOOLS/lib/libstdc++.so
│   │   └── libstdc++.so.6 -> $TOOLS/lib/libstdc++.so.6
│   ├── lib32/
│   └── ports/           (copy of host ports tree)
├── var/
│   ├── cache/pkg/
│   │   ├── packages/
│   │   ├── sources/
│   │   └── build-work/
│   └── lib/
│       └── pkg/
│           └── db       (empty)
└── tmp/
    └── lfs-tools/
        └── bin/
            └── pkgin
```

This skeleton is ready for Stage 2: building the base system with the temporary toolchain.
