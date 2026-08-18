# Chapter 10: Bootloader (GRUB)

This chapter covers installing and configuring the GRand Unified Bootloader (GRUB) for StormFS Linux, supporting both legacy BIOS and modern UEFI systems.

## 10.1 Prerequisites

Ensure the following packages are installed before proceeding:

- **grub** (2.12 or later)
- **os-prober** (for dual-boot detection, optional)
- **efibootmgr** (required for UEFI installations)

Verify installation:

```bash
grub-install --version
efibootmgr --version 2>/dev/null || echo "efibootmgr not installed"
```

### Installing GRUB from Source (BLFS)

If GRUB was not included in your base LFS build:

```bash
cd /sources
tar -xf grub-2.12.tar.xz
cd grub-2.12

# Disable-Werror is needed for some compiler versions
./configure --prefix=/usr          \
            --sbinddir=/sbin       \
            --sysconfdir=/etc      \
            --disable-werror       \
            --with-bootdir=/boot   \
            --disable-grub-mount   \
            --disable-device-mapper \
            EMACS=false

make
make install
mv -v /etc/bash_completion.d/grub /usr/share/bash-completion/completions
```

### Installing EFI Boot Manager

```bash
cd /sources
tar -xf efibootmgr-18.tar.xz
cd efibootmgr-18

make
make install
```

## 10.2 Installing GRUB for BIOS (Legacy Boot)

For systems booting via traditional BIOS or CSM (Compatibility Support Module):

```bash
grub-install --target=i386-pc /dev/sda
```

Replace `/dev/sda` with the disk where the BIOS boot partition resides. This writes the GRUB boot image to the MBR gap (sectors after the MBR but before the first partition) or to the BIOS boot partition.

### Verifying BIOS Installation

```bash
ls -la /boot/grub/i386-pc/core.img
ls -la /boot/grub/i386-pc/*.mod | head -5
```

### BIOS Partition Layout

For BIOS boot, ensure your partition table includes an **BIOS boot partition** (type ef02) if using GPT, or leave space before the first partition if using MBR:

| Partition | Type | Size | Mount Point |
|-----------|------|------|-------------|
| /dev/sda1 | BIOS Boot (GPT) or reserved (MBR) | 1 MB | — |
| /dev/sda2 | Linux (ext4) | Remaining | / |
| /dev/sda3 | Linux swap | 2–4× RAM | — |

## 10.3 Installing GRUB for UEFI

For systems booting via UEFI firmware:

### Create the EFI System Partition (if not present)

```bash
# If creating from an existing partition:
mkfs.fat -F32 /dev/sda1
mkdir -p /boot/efi
mount /dev/sda1 /boot/efi
```

### Install GRUB for UEFI

```bash
grub-install --target=x86_64-efi   \
             --efi-directory=/boot/efi \
             --bootloader-id=StormFS   \
             --recheck
```

Options explained:

| Option | Purpose |
|--------|---------|
| `--target=x86_64-efi` | Build for 64-bit UEFI firmware |
| `--efi-directory=/boot/efi` | Location of the EFI System Partition mount |
| `--bootloader-id=StormFS` | Name of the EFI boot entry and directory under `/boot/efi/EFI/` |
| `--recheck` | Remove device maps for the target disk |

For 32-bit UEFI (rare):

```bash
grub-install --target=i386-efi \
             --efi-directory=/boot/efi \
             --bootloader-id=StormFS
```

### Verify UEFI Installation

```bash
ls -la /boot/efi/EFI/StormFS/
ls -la /boot/efi/EFI/StormFS/grubx64.efi

# Check EFI boot entries
efibootmgr -v
```

### EFI Partition Layout

| Partition | Type | Size | Filesystem | Mount Point |
|-----------|------|------|------------|-------------|
| /dev/sda1 | EFI System Partition (ESP) | 512 MB | FAT32 | /boot/efi |
| /dev/sda2 | Linux filesystem | Remaining | ext4 | / |
| /dev/sda3 | Linux swap | 2–4× RAM | swap | — |

## 10.4 Creating /boot/grub/grub.cfg

Generate the initial configuration:

```bash
grub-mkconfig -o /boot/grub/grub.cfg
```

### Understanding grub.cfg

The generated file sources snippets from `/etc/default/grub` and `/etc/grub.d/`. Key variables in `/etc/default/grub`:

```bash
# /etc/default/grub

GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_TIMEOUT_STYLE=menu
GRUB_DISTRIBUTOR="StormFS Linux"
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3"
GRUB_CMDLINE_LINUX=""
GRUB_INITRD=/boot/initramfs-*.img
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
```

| Variable | Purpose |
|----------|---------|
| `GRUB_DEFAULT` | Default menu entry (0 = first, or `saved` for last-used) |
| `GRUB_TIMEOUT` | Seconds to wait before auto-booting (0 = immediate, -1 = wait forever) |
| `GRUB_TIMEOUT_STYLE` | `menu` (show menu) or `hidden` (press key to show) |
| `GRUB_CMDLINE_LINUX_DEFAULT` | Parameters for all entries (default mode) |
| `GRUB_CMDLINE_LINUX` | Additional parameters always applied |

### Custom Menu Entries

To add a manual entry, create `/etc/grub.d/40_custom`:

```bash
#!/bin/sh
exec tail -n +3 $0

menuentry "StormFS Linux (recovery mode)" {
    linux /boot/vmlinuz-6.10.6-stormfs root=/dev/sda2 ro single
    initrd /boot/initramfs-6.10.6-stormfs.img
}

menuentry "StormFS Linux (verbose boot)" {
    linux /boot/vmlinuz-6.10.6-stormfs root=/dev/sda2 ro loglevel=5
    initrd /boot/initramfs-6.10.6-stormfs.img
}

menuentry "Memtest86+" {
    linux16 /boot/memtest86+.bin
}
```

Make it executable and regenerate:

```bash
chmod 755 /etc/grub.d/40_custom
grub-mkconfig -o /boot/grub/grub.cfg
```

### Dual-Boot Detection

If **os-prober** is installed and you want to detect other operating systems:

```bash
# Enable os-prober (disabled by default for security)
cat >> /etc/default/grub << 'EOF'
GRUB_DISABLE_OS_PROBER=false
EOF

grub-mkconfig -o /boot/grub/grub.cfg
```

## 10.5 GRUB Theme Configuration (StormFS-grub-theme)

StormFS ships a custom GRUB theme for a polished boot experience.

### Installing the Theme

```bash
# From the StormFS ports or manually:
cd /sources
tar -xf StormFS-grub-theme.tar.xz
cp -r StormFS-grub-theme /boot/grub/themes/StormFS
```

### Theme Directory Structure

```
/boot/grub/themes/StormFS/
├── background.png          # 1920×1080 background image
├── logo.png                # StormFS logo
├── theme.txt               # Theme definition
└── fonts/
    └── DejaVuSans-Bold-14.pf2
```

### theme.txt

```txt
# StormFS GRUB Theme

desktop-image: "background.png"
desktop-color: "#1a1a2e"
terminal-font: "DejaVuSans-Bold 14"

+ boot-menu {
    left = 20%
    top = 30%
    width = 60%
    height = 50%

    + item {
        left = 25%
        width = 50%
        height = 20%
        font = "DejaVuSans-Bold 18"
        color = "#e0e0e0"
        selected-color = "#ffffff"
        selected-bg-color = "#16213e"
        selected-stroke-color = "#0f3460"
    }

    + label {
        top = 2%
        left = 25%
        width = 50%
        height = 15%
        font = "DejaVuSans-Bold 24"
        color = "#e94560"
        text = "StormFS Linux"
    }

    + label {
        bottom = 2%
        left = 25%
        width = 50%
        height = 8%
        font = "DejaVuSans 10"
        color = "#888888"
        text = "Press 'e' to edit, 'c' for command line"
    }
}
```

### Enabling the Theme

Edit `/etc/default/grub`:

```bash
GRUB_THEME="/boot/grub/themes/StormFS/theme.txt"
GRUB_GFXMODE=1920x1080
GRUB_GFXPAYLOAD_LINUX=keep
```

Regenerate:

```bash
grub-mkconfig -o /boot/grub/grub.cfg
```

### Generating Fonts

GRUB requires pre-rendered `.pf2` fonts:

```bash
grub-mkfont -s 14 -o /boot/grub/themes/StormFS/fonts/DejaVuSans-Bold-14.pf2 \
    /usr/share/fonts/dejavu/DejaVuSans-Bold.ttf
```

## 10.6 UEFI Secure Boot Considerations

### Enabling Secure Boot

Secure Boot requires signed bootloaders and kernel images. StormFS can work with Secure Boot using the following approach:

#### Option A: Use a Shim Loader (Recommended)

The Microsoft-signed shim bootloader (`shimx64.efi`) chains to a MOK-signed GRUB:

```bash
# Install shim and MOK utilities
# (from BLFS or distro package)

# Enroll the StormFS signing key
mokutil --import /path/to/StormFS-MOK.der

# Reboot and complete enrollment in the MOK Manager
# Then install shim as the primary bootloader:
cp /usr/lib/shim/shimx64.efi.signed.latest /boot/efi/EFI/StormFS/shimx64.efi
```

#### Option B: Sign Everything Yourself

```bash
# Generate a Machine Owner Key (MOK)
openssl req -new -x509 -newkey rsa:2048 \
    -keyout /var/lib/shim-signed/MOK.priv \
    -outform DER -out /var/lib/shim-signed/MOK.der \
    -days 36500 -subj "/CN=StormFS MOK Key" \
    -nodes

# Sign the GRUB EFI binary
sbsign --key /var/lib/shim-signed/MOK.priv \
       --cert /var/lib/shim-signed/MOK.pem \
       --output /boot/efi/EFI/StormFS/grubx64.efi.signed \
       /boot/efi/EFI/StormFS/grubx64.efi

# Sign the kernel
sbsign --key /var/lib/shim-signed/MOK.priv \
       --cert /var/lib/shim-signed/MOK.pem \
       --output /boot/vmlinuz-6.10.6-stormfs.signed \
       /boot/vmlinuz-6.10.6-stormfs

# Enroll the key
mokutil --import /var/lib/shim-signed/MOK.der
```

#### Disabling Secure Boot (Simplest)

If you do not need Secure Boot, disable it in your UEFI firmware settings (BIOS setup). This is the simplest approach during initial setup.

### Checking Secure Boot Status

```bash
mokutil --sb-state
# or
od -An -t u1 /sys/firmware/efi/esrt/entries/*/fw_class 2>/dev/null
```

## 10.7 Fallback Boot Entries

Fallback entries ensure the system can boot even if the primary kernel or initramfs is corrupted.

### Automatic Fallback with GRUB_SUBMENU

In `/etc/default/grub`:

```bash
GRUB_DEFAULT=saved
GRUB_SAVEDEFAULT=true
GRUB_TIMEOUT=5
```

### Creating a Manual Fallback Entry

Add to `/etc/grub.d/40_custom`:

```bash
#!/bin/sh
exec tail -n +3 $0

menuentry "StormFS Linux — Fallback (previous kernel)" {
    set root='hd0,msdos2'
    linux /boot/vmlinuz-6.10.5-stormfs root=/dev/sda2 ro
    initrd /boot/initramfs-6.10.5-stormfs.img
}

menuentry "StormFS Linux — Recovery Shell" {
    linux /boot/vmlinuz-6.10.6-stormfs root=/dev/sda2 ro init=/bin/bash
    initrd /boot/initramfs-6.10.6-stormfs.img
}
```

### Automatic Fallback via dracut

dracut can keep a previous kernel's initramfs as fallback. Install the `dtc` dracut module and configure:

```bash
cat > /etc/dracut.conf.d/fallback.conf << 'EOF'
# Keep previous initramfs as fallback
# dracut will maintain /boot/initramfs-<old>.img on kernel updates
EOF
```

### Keeping Previous Kernels

When installing a new kernel, do not immediately remove the old one:

```bash
# Instead of removing:
mv /boot/vmlinuz-6.10.5-stormfs /boot/vmlinuz-6.10.5-stormfs.old
mv /boot/initramfs-6.10.5-stormfs.img /boot/initramfs-6.10.5-stormfs.img.old
mv /boot/System.map-6.10.5-stormfs /boot/System.map-6.10.5-stormfs.old
```

## 10.8 Finalizing GRUB

After all configuration is complete:

```bash
# Regenerate the final grub.cfg
grub-mkconfig -o /boot/grub/grub.cfg

# Verify the output
grep -i "menuentry" /boot/grub/grub.cfg
```

For BIOS systems, verify the MBR:

```bash
dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -i grub
```

For UEFI systems, verify the EFI entry:

```bash
efibootmgr -v
```

## 10.9 Troubleshooting

### GRUB Rescue Shell

If GRUB drops to a `grub>` prompt:

```bash
# Find the boot partition
set root=(hd0,msdos2)
set prefix=(hd0,msdos2)/boot/grub

# Load the normal module
insmod normal
normal
```

### GRUB Rescue Shell (UEFI)

```bash
set root=(hd0,gpt1)
set prefix=(hd0,gpt1)/EFI/StormFS
insmod normal
normal
```

### The GRUB Prompt (No rescue mode)

If you see `GRUB _` with no commands, the configuration is missing:

```bash
set root=(hd0,msdos2)
linux /boot/vmlinuz-6.10.6-stormfs root=/dev/sda2 ro
initrd /boot/initramfs-6.10.6-stormfs.img
boot
```

## 10.10 References

- [GRUB Manual](https://www.gnu.org/software/grub/manual/grub/)
- [EFI Booting on the Arch Wiki](https://wiki.archlinux.org/title/EFI_system_partition)
- [Secure Boot on the Arch Wiki](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot)
- [Chapter 09: Linux Kernel](chapter-09-linux-kernel.md) — Kernel installation
- [Chapter 12: System Initialization](chapter-12-system-initialization.md) — systemd and init
