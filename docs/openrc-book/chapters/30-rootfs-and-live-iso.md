# Chapter 30: Rootfs Archives and OpenRC Live ISO Images

This chapter describes how to turn an installed StormFS OpenRC system into a reproducible root filesystem and a bootable live ISO. It deliberately covers the image pipeline only; the graphical installer is maintained as a separate StormFS port and is not part of this BLFS book.

## 30.1 Build a clean rootfs tree

Build images from a disposable mount or staging directory, not from the host's running `/`. The tree must contain the OpenRC init path, service scripts, a kernel, and the package database needed for repair:

```bash
ROOTFS=/var/tmp/stormfs-rootfs
sudo rm -rf "$ROOTFS"
sudo mkdir -p "$ROOTFS"

# Restore a verified StormFS base archive.
sudo tar -xJpf archives/base/bfs-rootfs-*.tar.xz -C "$ROOTFS"

# Ensure the merged-/usr compatibility links exist.
sudo ln -sfn usr/bin "$ROOTFS/bin"
sudo ln -sfn usr/lib "$ROOTFS/lib"
sudo ln -sfn usr/sbin "$ROOTFS/sbin"
```

Do not copy active `/proc`, `/sys`, `/dev`, `/run`, or host-specific secrets into the image. Create empty mount points instead:

```bash
sudo mkdir -p "$ROOTFS"/{dev/pts,proc,sys,run,tmp}
sudo chmod 1777 "$ROOTFS/tmp"
sudo rm -rf "$ROOTFS"/var/cache/emerald/* "$ROOTFS"/tmp/*
```

Install the image profile and OpenRC service defaults inside the tree. Select one network manager and one display manager; do not enable mutually exclusive alternatives:

```bash
sudo install -d "$ROOTFS/etc/runlevels"/{sysinit,boot,default,shutdown,nonetwork}
sudo chroot "$ROOTFS" rc-update add udev sysinit 2>/dev/null || true
sudo chroot "$ROOTFS" rc-update add udev-postmount sysinit 2>/dev/null || true
sudo chroot "$ROOTFS" rc-update add dbus boot 2>/dev/null || true
sudo chroot "$ROOTFS" rc-update add syslog boot 2>/dev/null || true
sudo chroot "$ROOTFS" rc-update add networking boot 2>/dev/null || true
```

## 30.2 Validate the rootfs before archiving

Check ownership, permissions, OpenRC links, and the architecture of the essential binaries:

```bash
sudo chroot "$ROOTFS" /bin/sh -c '
  test -x /sbin/init
  test -x /sbin/openrc
  test -d /etc/init.d
  test -d /etc/runlevels/default
  test -x /usr/bin/emerald || true
  test -x /usr/bin/mkinitramfs || true
'
sudo file "$ROOTFS"/bin/sh "$ROOTFS"/sbin/init
sudo find "$ROOTFS/etc/init.d" -maxdepth 1 -type f -perm -0100 -print | sort
```

Remove machine identity and generated host state if this rootfs will be reused on multiple machines:

```bash
sudo rm -f "$ROOTFS/etc/machine-id" "$ROOTFS/var/lib/dbus/machine-id"
sudo rm -rf "$ROOTFS/var/log"/* "$ROOTFS/var/lib/emerald/cbuild"/*
```

Keep `/etc/fstab` generic. Hardware-specific mount UUIDs belong in the installed target, not in a portable live image.

## 30.3 Create a rootfs archive

Create a deterministic archive while preserving numeric ownership and permissions. Exclude virtual filesystems and build caches:

```bash
ARCHIVE=archives/base/stormfs-rootfs-$(date -u +%Y%m%d).tar.xz
sudo mkdir -p "${ARCHIVE%/*}"
sudo tar --sort=name --numeric-owner --xattrs --acls \
  --exclude='./dev/*' --exclude='./proc/*' --exclude='./sys/*' \
  --exclude='./run/*' --exclude='./tmp/*' --exclude='./var/cache/*' \
  -C "$ROOTFS" -cJf "$ARCHIVE" .

tar -tJf "$ARCHIVE" >/dev/null
```

Record the checksum beside the archive and retain the exact kernel, ports revision, and image profile used to produce it:

```bash
sha256sum "$ARCHIVE" | tee "$ARCHIVE.sha256"
printf '%s\n' "$(git rev-parse HEAD)" | sudo tee "${ARCHIVE%.tar.xz}.ports-revision"
```

## 30.4 Build the live initramfs

Install the StormFS `mkinitramfs` port into the rootfs or run it in a matching chroot. Its configuration is hook-based and does not require systemd:

```bash
sudo install -Dm644 /etc/mkinitramfs.conf "$ROOTFS/etc/mkinitramfs.conf"
sudo sed -i 's/^HOOKS=.*/HOOKS="base modules udev"/' "$ROOTFS/etc/mkinitramfs.conf"
sudo chroot "$ROOTFS" mkinitramfs \
  -k "$(basename "$(find "$ROOTFS/lib/modules" -mindepth 1 -maxdepth 1 -type d | head -n1)")" \
  -C xz \
  -o /boot/stormfs-live.initrd
```

The live hook should mount the read-only SquashFS image, create an overlay upper directory on writable media or tmpfs, mount `/proc`, `/sys`, `/dev`, and `/run`, and finally hand off to the OpenRC `/sbin/init`. Test encrypted and multilib storage paths separately; an initramfs that boots the installed system is not automatically a complete live initramfs.

## 30.5 Assemble the live filesystem

Use `mksquashfs` to compress the rootfs. Keep user homes, package caches, machine IDs, and virtual filesystems out of the portable image:

```bash
LIVE=var/tmp/stormfs-live
sudo rm -rf "$LIVE"
sudo mkdir -p "$LIVE"/{boot,EFI/BOOT}
sudo mksquashfs "$ROOTFS" "$LIVE/boot/rootfs.sfs" \
  -comp xz -b 1048576 -all-root -noappend \
  -e home/* root/.cache tmp/* dev/* proc/* sys/* run/* var/cache/*

sudo install -Dm644 "$ROOTFS/boot/vmlinuz-"* "$LIVE/boot/vmlinuz"
sudo install -Dm644 "$ROOTFS/boot/stormfs-live.initrd" "$LIVE/boot/initrd"
```

Create BIOS and UEFI boot configuration with the bootloader already supported by the StormFS image pipeline. At minimum, the kernel command line must identify the SquashFS image and select the live hook, for example:

```text
root=/dev/ram0 boot=live live.image=/boot/rootfs.sfs quiet
```

Use the exact parameter names implemented by the installed live hook; do not assume that a parameter from another distribution's live system is supported.

## 30.6 Produce and test the ISO

The repository's `iso-builder/mkiso.sh` can assemble a hybrid image when the rootfs has a kernel, matching modules, GRUB EFI files, `mksquashfs`, and `xorriso` available:

```bash
cd iso-builder
sudo ./mkiso.sh "$ROOTFS"
sha256sum iso/stormfs-*.iso
```

Test the result before writing it to removable media:

```bash
qemu-system-x86_64 -enable-kvm -m 4096 \
  -cdrom iso/stormfs-*.iso -boot d -serial stdio
```

Verify UEFI and legacy BIOS boot, networking, OpenRC runlevel state, graphics, shutdown, and persistence behavior. A live ISO should not silently modify installed disks; keep storage changes behind an explicit image or installation workflow.

## 30.7 Reproducibility and release checklist

Before publishing an image:

- Pin the rootfs archive, kernel, ports revision, and branding version.
- Verify every package checksum with Emerald and retain the package manifest.
- Check that `/sbin/init` resolves to the OpenRC init path.
- Confirm `/etc/init.d` scripts are executable and their runlevel links are intentional.
- Confirm no host `/proc`, `/sys`, `/dev`, `/run`, credentials, or machine IDs leaked into the image.
- Inspect the ISO in a VM before testing physical hardware.
- Publish SHA-256 checksums and the build log with the image.

For the base archive workflow, see the LFS book's rootfs chapter. For service ordering and OpenRC troubleshooting, use Chapters 4–9 and 14–16 of this book.
