# Chapter 17: Emerald Package Manager and mkinitramfs

StormFS uses **Emerald** as its package-management frontend while retaining the existing port tree and OpenRC profile. Emerald is a POSIX shell package manager from Vylen: `pkgbuild` builds `.epkg.tar.xz` packages, `pkgadd` installs them, `portsync` updates repositories, and `emerald` resolves dependencies and performs higher-level operations.

The initramfs tool for the OpenRC profile is **Vylen mkinitramfs**. It is a POSIX shell program with ordered hooks for base files, modules, encryption, udev, and live-media behavior. It does not require systemd and its default `init.in` mounts the early kernel filesystems before handing control to `/sbin/init`.

## 17.1 Install Emerald

Build and install the StormFS port after the base toolchain, OpenRC, and the existing pkgutils bootstrap are available:

```bash
cd /usr/ports/opt/emerald
pkgmk -d
pkgadd /var/spool/pkg/emerald-20260911-1.pkg.tar.xz
```

Once Emerald is installed, package operations use its native commands:

```bash
emerald install openrc openrc-init-scripts
emerald build openrc
pkgadd /var/cache/emerald/packages/openrc-<version>-<release>.epkg.tar.xz
```

Emerald installs the command suite under `/usr/bin`, including `emerald`, `pkgbuild`, `pkgadd`, `pkgbase`, `pkgdel`, `pkgrebuild`, `portcreate`, `portsync`, `revdep`, `updateconf`, and `xchroot`. Its database is under `/var/lib/emerald/db`, while sources, build work, and packages are cached beneath `/var/cache/emerald`.

> The current StormFS checkout still contains CRUX-compatible `Pkgfile` recipes. Emerald's native recipe filename is controlled by its `build_script` setting and defaults upstream to `build.eme`; keep the migration policy explicit and do not assume that every existing `Pkgfile` is immediately consumable by Emerald.

## 17.2 Configure repositories and defaults

Install the upstream example files, then review their values before enabling a repository:

```bash
install -Dm644 /etc/emerald.repo.example /etc/emerald.repo
install -Dm644 /etc/emerald.conf.example /etc/emerald.conf
install -d -m 0755 /usr/ports
```

The repository file is consumed by `portsync`. Keep StormFS custom ports in a separate local repository so syncing an upstream collection cannot overwrite them. The exact repository URLs and branch names are distribution policy; verify them against the current StormFS mirror before release.

The main paths configured by the port are:

| Path | Purpose |
|------|---------|
| `/etc/emerald.repo` | repository definitions for `portsync` |
| `/etc/emerald.conf` | compiler, cache, and package defaults |
| `/var/lib/emerald/db` | installed package database |
| `/var/lib/emerald/world` | explicitly requested packages |
| `/var/cache/emerald/sources` | downloaded source files |
| `/var/cache/emerald/work` | temporary build trees |
| `/var/cache/emerald/packages` | generated `.epkg.tar.xz` packages |
| `/usr/ports` | local and synchronized port trees |

Example OpenRC-oriented defaults:

```bash
cat > /etc/emerald.conf << 'EOF'
CFLAGS="-O2 -march=x86-64 -pipe"
CXXFLAGS="${CFLAGS}"
MAKEFLAGS="$(nproc)"
SOURCE_DIR="/var/cache/emerald/sources"
PACKAGE_DIR="/var/cache/emerald/packages"
WORK_DIR="/var/cache/emerald/work"
COMPRESSION_MODE="xz"
KEEP_LOCALE="yes"
KEEP_MAN="yes"
EOF
```

Synchronize and inspect the available ports:

```bash
portsync
emerald list
emerald info openrc
emerald deplist calamares
```

## 17.3 Emerald operations

```bash
# Build without installing
emerald build openrc

# Install with dependency resolution
emerald install openrc openrc-init-scripts

# Upgrade explicitly requested packages
emerald upgrade emerald openrc

# Upgrade the world set
emerald world
emerald sysup

# Inspect installed files and integrity
emerald files openrc
emerald integrity openrc

# Remove a package and inspect unused dependencies
emerald remove old-package
emerald orphan
```

`pkgbuild` also supports source preparation, checksums, package-file generation, and cleanup:

```bash
cd /usr/ports/stormfs/example
pkgbuild --gen-checksum
pkgbuild --pkgfiles
pkgbuild --skip-checksum       # local development only
```

Do not publish a port without a checked-in checksum file. Package upgrades preserve modified configuration as `.epkgnew`; review and merge those files manually.

## 17.4 Build and install mkinitramfs

The upstream Meson project installs its configuration below `/etc`, its executable tools below `/usr/bin`, and data below `/usr/share/mkinitramfs`:

```bash
cd /usr/ports/opt/mkinitramfs
pkgbuild --install
```

The package provides:

- `/usr/bin/mkinitramfs`
- `/usr/bin/lsmkinitramfs`
- `/etc/mkinitramfs.conf`
- `/usr/share/mkinitramfs/init.in`
- `/usr/share/mkinitramfs/hooks/`

A minimal OpenRC configuration is:

```bash
cat > /etc/mkinitramfs.conf << 'EOF'
INITFSCOMP=xz
HOOKS="base modules udev"
EOF
```

The upstream command-line interface uses `-k` for the kernel version, `-o` for the output, `-C` for compression, `-m` for extra modules, `-f` for extra files, and `-a` for extra hooks:

```bash
mkinitramfs \
  -k "$(uname -r)" \
  -C xz \
  -o /boot/initramfs-$(uname -r).img
lsmkinitramfs /boot/initramfs-$(uname -r).img | less
```

For encrypted LUKS/LVM storage, include modules and the matching hook available in the installed hook set:

```bash
mkinitramfs \
  -k "$(uname -r)" \
  -m dm_crypt,dm_mod \
  -a encrypt \
  -a udev \
  -C xz \
  -o /boot/initramfs-$(uname -r).img
```

The tool requires root because it reads kernel modules, firmware, and device metadata. Treat missing firmware warnings as actionable when the laptop's Wi-Fi, storage, or graphics device is needed during early boot.

## 17.5 OpenRC live-media hooks

For a live ISO, add a hook that locates the read-only SquashFS image, mounts it below `/newroot`, creates writable overlay storage, and lets `init.in` move `/proc`, `/sys`, `/dev`, and `/run` into the new root before handing off to OpenRC:

```bash
cat > /etc/mkinitramfs.conf << 'EOF'
INITFSCOMP=xz
HOOKS="base modules udev"
EOF
mkinitramfs \
  -k "$(uname -r)" \
  -a /usr/share/mkinitramfs/hooks/liveiso \
  -o /tmp/stormfs-live-initrd.img
```

The `liveiso` hook is a StormFS image-profile addition, not a universal upstream hook name. Verify that it exists before generating an image:

```bash
test -f /usr/share/mkinitramfs/hooks/liveiso
```

For reproducible media, keep the kernel, modules, initramfs, and SquashFS image from the same build profile and test both UEFI and BIOS boot paths in a VM. See the BLFS OpenRC book's rootfs/live-ISO chapter for the image assembly workflow.

## 17.6 OpenRC and multilib checks

Emerald and mkinitramfs are userspace tools; neither adds a systemd service. Verify the selected init path and the architecture of the generated tools:

```bash
ps -p 1 -o comm=
readlink -f /sbin/init
rc-status --all
command -v emerald pkgbuild pkgadd mkinitramfs
file /usr/bin/emerald /usr/bin/mkinitramfs
ls -l /etc/init.d /etc/runlevels
```

Keep the previous working initramfs until the new image has booted successfully. On a multilib build, ensure the image includes the libraries needed by the selected shell and early-boot binaries.

## 17.7 References

- [Emerald](https://gitlab.com/vylen/emerald)
- [mkinitramfs](https://gitlab.com/vylen/mkinitramfs)
- [Chapter 7: Creating the Rootfs Archive](chapter-07-creating-the-rootfs-archive.md)
- [Chapter 10: Bootloader](chapter-10-bootloader.md)
- [Chapter 12: System Initialization](chapter-12-system-initialization.md)
- [BLFS OpenRC rootfs and live ISO chapter](../../openrc-book/chapters/30-rootfs-and-live-iso.md)
