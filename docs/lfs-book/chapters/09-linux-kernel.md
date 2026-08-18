# Chapter 09: Linux Kernel

The Linux kernel is the core of the StormFS Linux system. This chapter covers downloading, configuring, compiling, and installing the kernel along with the necessary boot setup.

## 9.1 Downloading the Kernel Source

Download the latest stable kernel from kernel.org:

```bash
cd /sources
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.10.6.tar.xz
```

Extract the archive:

```bash
tar -xf linux-6.10.6.tar.xz
cd linux-6.10.6
```

## 9.2 Kernel Configuration

There are three ways to configure the StormFS kernel. Choose the method that best suits your needs.

### Option A: Using the Provided .config

StormFS ships a pre-built configuration tuned for general-purpose use. Copy it into the source tree:

```bash
cp /sources/stormfs-kernel-config .config
make olddefconfig
```

The `make olddefconfig` target resolves any new symbols introduced by the kernel version by assigning them default values, while preserving your existing choices.

### Option B: Interactive Configuration with `menuconfig`

To review and modify the configuration interactively:

```bash
make menuconfig
```

This launches an ncurses-based menu system. Key areas to verify for StormFS:

- **General setup** → Local version: set to `-stormfs`
- **Enable loadable module support** → Module unloading: **Yes**
- **Enable loadable module support** → Module signature verification: your choice
- **Processor type and features** → Processor family: match your CPU
- **Device Drivers** → SCSI device support → SCSI disk support: **built-in**
- **Device Drivers** → NVMe Support → NVM Express block device: **built-in** (if applicable)
- **Device Drivers** → Network device support → Ethernet driver for your NIC
- **File systems** → <*> Second extended fs support
- **File systems** → <*> The Extended 4 (ext4) filesystem
- **File systems** → <*> Btrfs filesystem support
- **File systems** → <*> XFS filesystem support
- **File systems** → DOS/FAT/NT Filesystems → <*> Microsoft Windows Briefcase (FAT32) support
- **File systems** → DOS/FAT/NT Filesystems → <*> NTFS file system support
- **File systems** → Network File Systems → <*> NFS client support (if needed)
- **File systems** → FUSE filesystem support (if needed)
- **General setup** → cgroup support: enable as needed
- **Security** → choose your LSM (AppArmor, SELinux, or none)

Save the configuration and exit.

### Option C: Defconfig for Your Architecture

As a baseline, start from the architecture default:

```bash
make defconfig
make olddefconfig
```

Then customize with `make menuconfig` as described above.

## 9.3 Compiling the Kernel

Determine the number of parallel jobs based on your CPU cores:

```bash
NPROC=$(nproc)
make -j${NPROC}
```

This compiles the kernel image (`vmlinuz`), modules, and device tree blobs. On a modern 8-core system, expect approximately 10–20 minutes.

## 9.4 Installing the Kernel and Modules

### Install Modules

```bash
make modules_install
```

This copies compiled modules to `/lib/modules/<kernel-version>/`. For StormFS with kernel 6.10.6, the path will be `/lib/modules/6.10.6-stormfs/`.

### Install the Kernel Image

```bash
make install
```

This copies the kernel image and associated files to `/boot/`:

```
/boot/vmlinuz-6.10.6-stormfs
/boot/config-6.10.6-stormfs
/boot/System.map-6.10.6-stormfs
```

### Manual Installation (Alternative)

If `make install` does not place files where you need them:

```bash
cp arch/x86/boot/bzImage /boot/vmlinuz-6.10.6-stormfs
cp System.map /boot/System.map-6.10.6-stormfs
cp .config /boot/config-6.10.6-stormfs
```

## 9.5 Setting Up /boot

Verify that the kernel files are in place:

```bash
ls -la /boot/vmlinuz-6.10.6-stormfs
ls -la /boot/System.map-6.10.6-stormfs
ls -la /boot/config-6.10.6-stormfs
```

Set permissions and create a symlink for convenience:

```bash
chmod 644 /boot/vmlinuz-6.10.6-stormfs
chmod 644 /boot/config-6.10.6-stormfs
chmod 644 /boot/System.map-6.10.6-stormfs

ln -sf vmlinuz-6.10.6-stormfs /boot/vmlinuz
```

### Generating grub.cfg Entry (Preview)

For GRUB configuration, see [Chapter 10: Bootloader](chapter-10-bootloader.md). A minimal manual entry for testing:

```
menuentry "StormFS Linux 6.10.6" {
    linux /boot/vmlinuz-6.10.6-stormfs root=/dev/sda2 ro
    initrd /boot/initramfs-6.10.6-stormfs.img
}
```

## 9.6 Creating the Initial RAM Filesystem (initramfs)

StormFS uses **dracut** to generate the initramfs. The initramfs is required to mount the root filesystem and load essential modules before the real root is available.

### Installing dracut

If not already installed from the BLFS build:

```bash
cd /sources
tar -xf dracut-060.tar.xz
cd dracut-060

./configure --prefix=/usr \
            --sysconfdir=/etc \
            --sbinddir=/sbin \
            --libdir=/usr/lib \
            --hwdbdir=/usr/lib/udev/hwdb.d
make
make install
```

### Generating the initramfs

```bash
dracut --kver 6.10.6-stormfs /boot/initramfs-6.10.6-stormfs.img
```

For a more minimal initramfs (useful for simple setups):

```bash
dracut --kver 6.10.6-stormfs \
       --hostonly \
       --compress xz \
       /boot/initramfs-6.10.6-stormfs.img
```

For debugging boot issues, generate an initramfs with a shell:

```bash
dracut --kver 6.10.6-stormfs \
       --debug \
       --shell \
       /boot/initramfs-6.10.6-stormfs.img
```

### Regenerating after Module Changes

Any time you add or remove kernel modules (e.g., new hardware support, filesystem drivers), regenerate the initramfs:

```bash
dracut --force --kver 6.10.6-stormfs /boot/initramfs-6.10.6-stormfs.img
```

### Verify the initramfs

```bash
ls -lh /boot/initramfs-6.10.6-stormfs.img
```

Optionally inspect its contents:

```bash
mkdir /tmp/initramfs-check
cd /tmp/initramfs-check
/usr/lib/dracut/skipcpio /boot/initramfs-6.10.6-stormfs.img | zcat | cpio -idmv 2>/dev/null
ls -la
cd /
rm -rf /tmp/initramfs-check
```

## 9.7 Kernel Modules Configuration

### Loading Modules Manually

```bash
# Load a module
modprobe <module-name>

# List loaded modules
lsmod

# Show module information
modinfo <module-name>

# Remove a module
modprobe -r <module-name>
```

### Auto-loading Modules at Boot

Modules that should be loaded automatically at boot go in `/etc/modules-load.d/`:

```bash
cat > /etc/modules-load.d/networking.conf << 'EOF'
e1000e
EOF
```

### Blacklisting Modules

To prevent a module from loading automatically, create a blacklist file:

```bash
cat > /etc/modprobe.d/stormfs-blacklist.conf << 'EOF'
# Disable nouveau if using proprietary NVIDIA driver
blacklist nouveau

# Disable snd-pcsp (PC speaker audio)
blacklist snd_pcsp
EOF
```

### Module Options

To pass options to a module at load time:

```bash
cat > /etc/modprobe.d/stormfs-options.conf << 'EOF'
# Set iwlwifi power save to disabled
options iwlwifi power_save=0
EOF
```

## 9.8 Kernel Command-Line Parameters

Add kernel parameters in GRUB (see [Chapter 10](chapter-10-bootloader.md)) or via `/etc/default/grub`:

| Parameter | Purpose |
|-----------|---------|
| `root=/dev/sda2` | Specifies the root partition |
| `ro` | Mount root read-only initially |
| `rw` | Mount root read-write initially |
| `quiet` | Suppress most kernel messages |
| `loglevel=3` | Only show errors and warnings |
| `nvidia.modeset=1` | Enable NVIDIA kernel mode-setting |
| `pcie_aspm=force` | Force PCIe power management |
| `mitigations=off` | Disable Spectre/Meltdown mitigations (not recommended for production) |

Example in `/etc/default/grub`:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3"
GRUB_CMDLINE_LINUX="root=/dev/sda2 ro"
```

## 9.9 Troubleshooting

### Kernel Panics

If the system fails to boot with a kernel panic:

1. Reboot and select the GRUB recovery entry (see [Chapter 10](chapter-10-bootloader.md))
2. Add `init=/bin/bash` to the kernel command line to get a shell
3. Verify the initramfs contains necessary modules:
   ```bash
   dracut --force --kver 6.10.6-stormfs --regenerate-all /boot/initramfs-6.10.6-stormfs.img
   ```
4. Check that `/etc/fstab` entries match your partition layout

### Module Failures

```bash
dmesg | grep -i error
journalctl -b -p err
```

## 9.10 References

- [Linux Kernel Documentation](https://www.kernel.org/doc/html/latest/)
- [KernelNewbies](https://kernelnewbies.org/)
- [dracut Manual](https://man7.org/linux/man-pages/man8/dracut.8.html)
- [Chapter 10: Bootloader](chapter-10-bootloader.md) — GRUB configuration
- [Chapter 12: System Initialization](chapter-12-system-initialization.md) — systemd units
