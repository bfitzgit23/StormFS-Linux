# Chapter 1: Introduction

## 1.1 What is StormFS Linux

StormFS Linux is an x86_64 source-built Linux distribution maintained by the StormFS community. It uses an LFS/MLFS-style bootstrap to produce a complete, bootable Linux system entirely from source code.

### Core Design Principles

- **Source-built**: Every package in the base system is compiled from source on the build host, producing an optimized system tailored to x86_64.
- **CRUX-based packaging**: Uses CRUX `pkgutils` and `ports` for package builds, extended for StormFS build conventions.
- **Dependency-aware management**: `prt-get` handles dependency resolution and package installation.
- **Multilib support**: Full 32-bit and 64-bit library support, with 32-bit libraries installed under `/usr/lib32`.
- **systemd init**: Uses systemd as the default init system.
- **UEFI and BIOS**: Supports both legacy BIOS and UEFI boot paths.
- **Advanced storage**: Installer support for Btrfs subvolumes, LUKS, LVM, md RAID, and combinations thereof.

### What Makes StormFS Different

StormFS builds upon the Linux From Scratch methodology but diverges in several important ways:

1. **CRUX ports system** instead of hand-written build scripts
2. **prt-get** for dependency-aware package management
3. **systemd** as the native init system (rather than SysVinit)
4. **Multilib** as a first-class target (32-bit libraries under `/usr/lib32`)
5. **PyQt5 graphical installer** for deployment
6. **Live ISO** with LightDM, XFCE default desktop, and auto-login

## 1.2 Host System Requirements

The build host must be an x86_64 Linux system with sufficient resources to compile a complete toolchain and base system.

### Hardware Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| Architecture | x86_64 | x86_64 |
| RAM | 8 GB | 16 GB or more |
| Disk space | 50 GB free | 80 GB or more (SSD preferred) |
| CPU cores | 2 | 4 or more (compilation is CPU-bound) |

### Software Requirements

The host must have the following tools installed. The `version-check.sh` script in the repository will verify all requirements:

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| Bash | 3.2 | Shell interpreter |
| GCC | 5.4 | C/C++ compiler |
| G++ | 5.4 | C++ compiler |
| Binutils (ld) | 2.13.1 | Linker |
| Bison | 2.7 | Parser generator |
| Coreutils (sort) | 8.1 | Core utilities |
| Diffutils | 2.8.1 | File comparison |
| Findutils | 4.2.31 | File search |
| Gawk | 4.0.1 | Text processing |
| Grep | 2.5.1a | Pattern matching |
| Gzip | 1.3.12 | Compression |
| M4 | 1.4.10 | Macro processor |
| Make | 4.0 | Build automation |
| Patch | 2.5.4 | File patching |
| Perl | 5.8.8 | Scripting language |
| Python | 3.4 | Scripting language |
| Sed | 4.1.5 | Stream editor |
| Tar | 1.22 | Archiving |
| Texinfo | 5.0 | Documentation |
| XZ | 5.0.0 | Compression |
| pkg-config | any | Build configuration |
| libarchive (dev) | any | Archive library |
| bsdtar | any | Archive utility |
| GMP (dev) | any | Math library |
| MPFR (dev) | any | Multiple-precision floating-point |
| libtirpc (dev) | any | RPC library |
| autoreconf | any | Autotools reconfiguration |
| Linux kernel | 5.10+ | Kernel headers |

### Verifying Host Requirements

Run the version-check script from the repository root:

```sh
$ ./version-check.sh
```

A passing run will report `OK` for every tool and print `nproc` reports for available CPU cores.

### Recommended Host Distribution

The **Gentoo LiveGUI ISO** is the primary development and test environment. It provides all required tools out of the box. Any modern x86_64 Linux distribution with working compiler/build tools, sufficient disk space, and network access can also be used.

Debian/Ubuntu hosts will need additional packages:

```sh
# apt install build-essential libarchive-dev libarchive-tools \
    libgmp-dev libmpfr-dev libtirpc-dev autoconf
```

## 1.3 About This Book

This book is structured as a sequential build guide. Each chapter corresponds to a stage of the StormFS bootstrap process:

1. **Chapter 2**: Prepare the host system (create directories, set environment variables)
2. **Chapter 3**: Build the temporary toolchain (compiler, linker, and essential tools)
3. **Chapter 4**: Build the base system inside the toolchain (131 packages)
4. **Chapter 5**: Rebuild the base system using the final toolchain (self-hosting validation)
5. **Chapter 6**: Verify the base system (filesystem checks, chroot tests, toolchain leakage)
6. **Chapter 7**: Create the rootfs archive (XZ compression, exclusions, verification)
7. **Chapter 8**: Basic system configuration (fstab, hostname, locale, timezone, shells)

### Conventions Used

- **`#`** prefix indicates a command that must be run as root
- **`$`** prefix indicates a command that can be run as a regular user
- Environment variables are shown in `UPPER_CASE`
- File paths are shown in `monospace`
- Package names match the port directory names under `ports/core/`
- Each package section lists: source URL, build commands, and key notes

### Important Notes

> **Warning:** The bootstrap process requires root access for Stages 2 through 5. The interactive menu (`./bootstrap.sh`) uses `sudo` automatically for stages that require privilege.

> **Note:** The temporary toolchain must be built as a regular user, never as root.

## 1.4 Build Environment Setup

### Cloning the Repository

```sh
$ git clone --recurse-submodules https://github.com/bfitzgit23/StormFS-Linux.git
$ cd StormFS-Linux
```

Or initialize submodules after cloning:

```sh
$ git submodule update --init --recursive
```

### Directory Layout

The StormFS repository has the following key structure:

```
StormFS-Linux/
├── bootstrap.sh              # Interactive bootstrap menu
├── VERSION                   # Release version
├── ports/                    # Package recipes
│   ├── core/                 # Release-critical base collection
│   │   ├── gcc/              # GCC port (with multilib bootstrap_build)
│   │   ├── glibc/            # Glibc port (with multilib)
│   │   ├── binutils/         # Binutils port (with pass1/pass2)
│   │   ├── linux-headers/    # Kernel headers
│   │   ├── pkgutils/         # CRUX package management
│   │   ├── aaa_filesystem/   # Base filesystem hierarchy
│   │   └── ...
│   ├── contrib/              # Community packages
│   ├── opt/                  # Optional/desktop packages
│   ├── xorg/                 # X.Org packages
│   └── ...
├── scripts/                  # Installer and maintenance scripts
├── files/                    # Bootstrap configuration files
├── archives/                 # Generated archives (not in git)
│   ├── toolchain/
│   └── base/
└── logs/                     # Build logs (not in git)
```

### Environment Variables

The bootstrap uses these key environment variables:

| Variable | Value | Purpose |
|----------|-------|---------|
| `LFS` | `/tmp/lfs-rootfs` | Root filesystem build directory |
| `TOOLS` | `/tmp/lfs-tools` | Temporary toolchain path |
| `LFS_TGT` | `x86_64-lfs-linux-gnu` | Cross-compiler target triplet |
| `LFS_TGT32` | `i686-lfs-linux-gnu` | 32-bit cross-compiler target |
| `BOOTSTRAP` | `1` | Signals bootstrap mode to ports |
| `PATCH` | `$PWD/sources/` | Patch file directory |
| `LANG` | `C` | Locale (deterministic builds) |
| `LC_ALL` | `C` | Locale override |

### Using the Interactive Menu

The recommended way to build StormFS is through the interactive bootstrap menu:

```sh
$ ./bootstrap.sh
```

This presents a menu with the following options:

1. Build temporary toolchain (required) — runs as regular user
2. Build base system with temporary toolchain (required) — runs as root
3. Rebuild base system with final toolchain (optional) — runs as root
4. Verify completed base system (required) — runs as root
5. Create/compress base rootfs archive (required) — runs as root
6. Restore newest base rootfs archive
7. Restore newest temporary toolchain archive
8. Chroot into StormFS rootfs (sudo/root)
9. Launch StormFS installer
10. Settings (theme, compiler options, ccache)
11. Quit

The normal release path is: **1 → 2 → 4 → 5**. Stage 3 is optional but recommended for release validation.

### Build Settings

The bootstrap settings menu allows configuration of:

- **Compiler jobs**: Auto-detected from `nproc` or manually specified
- **Optimization**: `portable` (`-O2 -march=x86-64 -pipe`), `native` (`-O2 -march=native -mtune=native -pipe`), or custom CFLAGS
- **ccache**: Enabled by default, placed at `/usr/lib/ccache` in PATH

These settings are saved to `.bfs-bootstrap-settings` and carried into the base system's `/etc/pkgmk.conf`.
