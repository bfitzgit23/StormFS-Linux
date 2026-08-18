# Chapter 4: Building the Base System

This chapter describes building the complete StormFS base system inside a chroot environment using the temporary toolchain built in Chapter 3. This is the longest and most resource-intensive stage of the bootstrap.

> **Important:** This stage requires root privileges. The interactive menu uses `sudo` automatically.

## 4.1 Setting Up the Chroot Environment

### Prerequisites

Before starting Stage 2, verify that:

1. The toolchain archive exists (Stage 1 completed)
2. No existing rootfs markers indicate a previous build (`.bfs-stage2-complete`, `.bfs-stage3-complete`)
3. Running as root

### Mounting Virtual Filesystems

```sh
# The bootstrap mounts these automatically:
mount --bind /dev $LFS/dev
mount -t devpts devpts $LFS/dev/pts -o gid=5,mode=620
mount -t proc proc $LFS/proc
mount -t sysfs sysfs $LFS/sys
mount -t tmpfs tmpfs $LFS/run

# Bind-mount source/package/build directories
mount --bind "$PWD/sources" $LFS/var/cache/pkg/sources
mount --bind "$PWD/packages" $LFS/var/cache/pkg/packages
mount --bind "$PWD/build-work" $LFS/var/cache/pkg/build-work
```

### Chroot Environment Variables

Each chroot invocation uses a clean environment:

```sh
chroot "$LFS" \
    env -i \
    HOME=/root \
    TERM="${TERM:-dumb}" \
    LANG=C \
    LC_ALL=C \
    LANGUAGE=C \
    PATH=/bin:/usr/bin:/sbin:/usr/sbin:$TOOLS/bin \
    /bin/bash
```

During Stage 2, `$TOOLS/bin` is included in the chroot PATH so packages can use the temporary toolchain. During Stage 3 (rebuild), only the system PATH is used.

### systemd Bootstrap Configuration

Before systemd is built, temporary util-linux pkg-config files are needed because the final util-linux has not been installed yet:

```sh
mkdir -p $LFS/tmp/systemd-util-linux-pc

for pc in uuid blkid mount; do
    cp $LFS/tmp/lfs-tools/lib/pkgconfig/$pc.pc \
       $LFS/tmp/systemd-util-linux-pc/$pc.pc
done
```

A special `pkgmk.conf` for systemd is created:

```sh
cat > $LFS/tmp/pkgmk.systemd-bootstrap.conf << 'EOF'
export LANG=C
export LC_ALL=C
export LANGUAGE=C

export CFLAGS="-O2 -march=x86-64 -pipe"
export CXXFLAGS="${CFLAGS}"
export LDFLAGS="-L/usr/lib -Wl,-rpath-link,/usr/lib"

# Expose only the temporary util-linux libraries to systemd.
export PKG_CONFIG_PATH="/tmp/systemd-util-linux-pc:/usr/lib/pkgconfig:/usr/share/pkgconfig"
export PKG_CONFIG_LIBDIR="/tmp/systemd-util-linux-pc:/usr/lib/pkgconfig:/usr/share/pkgconfig"

export JOBS=$(nproc)
export MAKEFLAGS="-j $JOBS"

PKGMK_SOURCE_DIR="/var/cache/pkg/sources"
PKGMK_PACKAGE_DIR="/var/cache/pkg/packages"
PKGMK_WORK_DIR="/var/cache/pkg/build-work/pkgmk-$name"

. /var/lib/pkgmk/extension
EOF
```

## 4.2 Building Packages in Order

The base system is built by iterating over the `$basepkg` list. Each package is built inside a chroot using `pkgin -d` (the StormFS wrapper for pkgmk) or `prt-get`.

### Package Build Order

| # | Package | Description |
|---|---------|-------------|
| 1 | aaa_filesystem | Base filesystem hierarchy and default configuration |
| 2 | linux-headers | Kernel API headers |
| 3 | man-pages | Linux man page documentation |
| 4 | glibc | GNU C Library (32-bit and 64-bit) |
| 5 | autoconf | Autoconf configuration generator |
| 6 | zlib | Compression library |
| 7 | bzip2 | Compression utility |
| 8 | xz | XZ compression |
| 9 | file | File type identification |
| 10 | ncurses | Terminal handling library |
| 11 | readline | Line editing library |
| 12 | m4 | GNU Macro Processor |
| 13 | bc | Arbitrary precision calculator |
| 14 | binutils | Linker, assembler, and tools |
| 15 | ninja | Build system |
| 16 | pkgconf | Package configuration tool |
| 17 | libxcrypt | Crypt library |
| 18 | gmp | GNU Multiple Precision Arithmetic |
| 19 | mpfr | Multiple-precision floating-point |
| 20 | mpc | Multiple-precision complex arithmetic |
| 21 | attr | Extended attribute support |
| 22 | acl | Access Control Lists |
| 23 | gcc | GNU Compiler Collection (C, C++, Obj-C, LTO) |
| 24 | libcap | Linux capabilities library |
| 25 | psmisc | Process management utilities |
| 26 | sed | Stream editor |
| 27 | tzdata | Time zone data |
| 28 | iana-etc | IANA protocol/port assignments |
| 29 | bison | GNU Parser Generator |
| 30 | flex | Lexical analyzer generator |
| 31 | pcre2 | Perl Compatible Regular Expressions |
| 32 | grep | Pattern matching |
| 33 | bash | GNU Bourne-Again Shell |
| 34 | libtool | Library building support |
| 35 | gdbm | GNU DBM database library |
| 36 | gperf | Perfect hash function generator |
| 37 | expat | XML parser library |
| 38 | inetutils | Network utilities |
| 39 | perl | Perl interpreter |
| 40 | perl-xml-parser | Perl XML parser module |
| 41 | intltool | Internationalization tool |
| 42 | automake | Automake build system |
| 43 | openssl | TLS/SSL library |
| 44 | ca-certificates | CA certificate bundle |
| 45 | curl | URL transfer tool |
| 46 | gettext | GNU internationalization library |
| 47 | elfutils | ELF object file utilities |
| 48 | libffi | Foreign Function Interface library |
| 49 | sqlite | SQL database engine |
| 50 | python3 | Python 3 interpreter |
| 51 | coreutils | Core GNU utilities |
| 52 | check | Unit testing framework |
| 53 | diffutils | File comparison tools |
| 54 | gawk | GNU Awk |
| 55 | findutils | Directory search tools |
| 56 | groff | Document formatting system |
| 57 | less | Pager |
| 58 | gzip | Compression |
| 59 | zstd | Zstandard compression |
| 60 | iptables | Packet filtering |
| 61 | libtirpc | Transport-independent RPC |
| 62 | iproute2 | Network configuration |
| 63 | kbd | Keyboard utilities |
| 64 | libpipeline | Pipeline library |
| 65 | make | Build automation |
| 66 | patch | File patching |
| 67 | man-db | Man page database |
| 68 | tar | Archiving |
| 69 | texinfo | Documentation system |
| 70 | python3-setuptools | Python setuptools |
| 71 | python3-pip | Python package installer |
| 72 | python3-flit-core | Python flit core |
| 73 | python3-packaging | Python packaging utilities |
| 74 | python3-installer | Python installer |
| 75 | python3-build | Python build frontend |
| 76 | python3-pyproject-hooks | Python pyproject hooks |
| 77 | python3-wheel | Python wheel format |
| 78 | libuv | Async I/O library |
| 79 | libarchive | Archive library |
| 80 | cmake | Cross-platform build system |
| 81 | fmt | Text formatting library |
| 82 | xxhash | Fast hash algorithm |
| 83 | ccache | Compiler cache |
| 84 | boost | Boost C++ libraries |
| 85 | meson | Build system |
| 86 | kmod | Kernel module utilities |
| 87 | linux-pam | Pluggable Authentication Modules |
| 88 | shadow | Shadow password utilities |
| 89 | libpng | PNG library |
| 90 | which | Command locator |
| 91 | freetype | Font rendering library |
| 92 | fuse | Filesystem in Userspace |
| 93 | grub | GRUB bootloader |
| 94 | popt | Option parsing library |
| 95 | mandoc | Mandoc formatter |
| 96 | efivar | EFI variable support |
| 97 | efibootmgr | EFI boot manager |
| 98 | grub-efi | GRUB EFI support |
| 99 | vim | Text editor |
| 100 | nano | Text editor |
| 101 | python3-markupsafe | HTML string escaping |
| 102 | python3-tomli | TOML parser |
| 103 | python3-pytz | Timezone database |
| 104 | python3-babel | Internationalization |
| 105 | python3-jinja2 | Template engine |
| 106 | systemd | System and service manager |
| 107 | util-linux | Linux utilities |
| 108 | dbus | D-Bus message bus |
| 109 | procps-ng | Process utilities |
| 110 | e2fsprogs | Ext2/3/4 filesystem tools |
| 111 | fakeroot | Root privilege simulation |
| 112 | pkgutils | CRUX package management |
| 113 | dialog | Dialog boxes for shell |
| 114 | prt-get | Dependency-aware package manager |
| 115 | httpup | HTTP-based ports update |
| 116 | ports | Ports tree management |
| 117 | prt-utils | Port management utilities |
| 118 | lzo | LZO compression library |
| 119 | btrfs-progs | Btrfs filesystem tools |
| 120 | dosfstools | FAT filesystem tools |
| 121 | exfatprogs | exFAT filesystem tools |
| 122 | f2fs-tools | F2FS filesystem tools |
| 123 | mdadm | Software RAID management |
| 124 | libaio | Asynchronous I/O library |
| 125 | lvm2 | Logical Volume Manager |
| 126 | inih | INI file parser |
| 127 | liburcu | Userspace RCU library |
| 128 | xfsprogs | XFS filesystem tools |
| 129 | openssh | SSH implementation |
| 130 | genfstab | fstab generator |
| 131 | signify | Signature verification |

### Package Build Commands

Each package is built with a chroot invocation:

```sh
chroot "$LFS" \
    env -i \
    HOME=/root \
    TERM="${TERM:-dumb}" \
    LANG=C \
    LC_ALL=C \
    LANGUAGE=C \
    PATH=/bin:/usr/bin:/sbin:/usr/sbin:$TOOLS/bin \
    pkgin -d "$i" -is -if -im -cf /tmp/pkgmk.conf
```

After building, the resulting package is installed with:

```sh
pkgadd -r "$LFS" -f "$(ls -1 packages/$i#* | tail -n1)"
```

For Stage 3 (rebuild), `prt-get` is used instead:

```sh
chroot "$LFS" \
    env -i \
    HOME=/root \
    TERM="${TERM:-dumb}" \
    LANG=C \
    LC_ALL=C \
    LANGUAGE=C \
    PATH=/bin:/usr/bin:/sbin:/usr/sbin \
    prt-get update -im -fr -if -fi "$i"
```

## 4.3 Special Handling

### glibc Post-Install Adjustment

After glibc is installed in Stage 2, a critical post-install script adjusts the GCC specs file and linker. This ensures the final compiler links against `/usr/lib` instead of the toolchain's `$TOOLS/lib`.

The script performs these steps:

1. **Locates the real ELF linker** (`ld.bfd` or `ld-new`) from the toolchain
2. **Saves a copy** of the real linker before renaming
3. **Replaces** `$TOOLS/bin/ld` with the real linker
4. **Adjusts GCC specs** to remove `$TOOLS` from search paths and set `/usr/lib/` as the startfile prefix
5. **Runs verification** — compiles a dummy C program and checks linker search paths

```sh
# Key GCC specs adjustment (from glibc post-install):
gcc -dumpspecs | sed \
    -e "s@$TOOLS@@g" \
    -e "/\*startfile_prefix_spec:/{n;s@.*@/usr/lib/ @}" \
    -e '/\*cpp:/{n;s@$@ -isystem /usr/include@}' \
    > "$(dirname "$(gcc --print-libgcc-file-name)")/specs"
```

This adjustment is what allows the final system to compile programs that link against `/usr/lib` instead of the temporary toolchain path.

### systemd Bootstrap

systemd requires util-linux pkg-config files before the final util-linux is installed. The bootstrap provides temporary copies from the toolchain:

```sh
# Temporary pkg-config files for systemd
for pc in uuid blkid mount; do
    cp $LFS/tmp/lfs-tools/lib/pkgconfig/$pc.pc \
       $LFS/tmp/systemd-util-linux-pc/$pc.pc
done
```

When building systemd during Stage 2, the special `pkgmk.systemd-bootstrap.conf` is used:

```sh
if [ "$i" = systemd ]; then
    pkgmk_conf=/tmp/pkgmk.systemd-bootstrap.conf
fi
```

### Force-Reinstall Packages

Certain packages are force-reinstalled even if already present in the database:

```sh
case $i in
    aaa_filesystem|gcc|bash|dash|perl|coreutils|pkgutils)
        _force=-f
        ;;
esac
```

### Logging

Each package build is logged to `logs/base/<package>-<timestamp>.log`. After Stage 2 completes, logs are copied into the rootfs:

```sh
$LFS/var/log/bfs/bfs-build/
```

## 4.4 Creating the Base Rootfs Archive

After Stage 2 (or Stage 3) completes and Stage 4 verification passes, the base rootfs archive is created. See Chapter 7 for the complete archiving process.

### Stage Markers

| Marker File | Meaning |
|-------------|---------|
| `$LFS/.bfs-stage2-complete` | Stage 2 (base build with toolchain) finished |
| `$LFS/.bfs-stage3-complete` | Stage 3 (rebuild with final toolchain) finished |
| `$LFS/.bfs-verified` | Stage 4 verification passed |
| `$LFS/.bfs-rootfs-restored` | Rootfs restored from archive |

## 4.5 Full Build Time Estimates

On a modern multi-core system (8+ cores, SSD), approximate build times are:

| Stage | Packages | Estimated Time |
|-------|----------|---------------|
| Stage 1 (toolchain) | 40 packages | 1–2 hours |
| Stage 2 (base) | 131 packages | 3–6 hours |
| Stage 3 (rebuild) | 131 packages | 3–6 hours |
| Stage 4 (verify) | — | 5–10 minutes |
| Stage 5 (archive) | — | 5–15 minutes |

GCC and glibc are the most time-consuming packages, accounting for roughly half the total build time.
