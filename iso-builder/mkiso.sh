#!/bin/sh -e
#
# StormFS Linux ISO Builder
# Adapted from linuxliveiso (https://github.com/emmett1/linuxliveiso)
#

msg() {
	echo "-> $@"
}

die() {
	echo "ERROR: $*" >&2
	exit 1
}

unmount() {
	while true; do
		mountpoint -q "$1" || break
		umount "$1" 2>/dev/null
	done
}

# Check required host tools
for tool in mksquashfs xorriso; do
	command -v "$tool" >/dev/null 2>&1 || die "$tool not found"
done

if [ -z "$1" ]; then
	die "usage: $0 <rootfs dir>"
fi

if [ ! -d "$1" ]; then
	die "rootfs directory '$1' does not exist"
fi

ROOTFS="$(realpath "$1")"
ISONAME="stormfs-$(date +%Y%m%d)"
DISTRONAME="StormFS Linux"

# Excluded directories for squashfs
# Do NOT compress: home, tmp, dev, proc, sys, run, root, build
EXCLUDE_DIRS="$ROOTFS/home/*"
EXCLUDE_DIRS="$EXCLUDE_DIRS $ROOTFS/tmp/*"
EXCLUDE_DIRS="$EXCLUDE_DIRS $ROOTFS/dev/*"
EXCLUDE_DIRS="$EXCLUDE_DIRS $ROOTFS/proc/*"
EXCLUDE_DIRS="$EXCLUDE_DIRS $ROOTFS/sys/*"
EXCLUDE_DIRS="$EXCLUDE_DIRS $ROOTFS/run/*"
EXCLUDE_DIRS="$EXCLUDE_DIRS $ROOTFS/root/*"
EXCLUDE_DIRS="$EXCLUDE_DIRS $ROOTFS/build/*"

# Package cache exclusions
EXCLUDE_DIRS="$EXCLUDE_DIRS $ROOTFS/var/cache/*"
EXCLUDE_DIRS="$EXCLUDE_DIRS $ROOTFS/var/tmp/*"

# Build squashfs exclude arguments
SQUASHFS_EXCLUDE=""
for dir in $EXCLUDE_DIRS; do
	SQUASHFS_EXCLUDE="$SQUASHFS_EXCLUDE -e $dir"
done

# Detect distro info from os-release
if [ -f "$ROOTFS/usr/lib/os-release" ]; then
	. "$ROOTFS/usr/lib/os-release"
elif [ -f "$ROOTFS/etc/os-release" ]; then
	. "$ROOTFS/etc/os-release"
fi
DISTRONAME="${PRETTY_NAME:-StormFS Linux}"

# Detect kernel version
KERNELVER=""
for i in "$ROOTFS/boot/"*; do
	[ -f "$i" ] || continue
	case "$i" in
		*vmlinuz*|*vmlinux*|*bzImage*)
			KERNELVER="$(file "$i" | awk '{print $9}')"
			KERNELFILE="$i"
			break
			;;
	esac
done

if [ -z "$KERNELFILE" ]; then
	die "kernel file does not exist in $ROOTFS/boot/"
fi

# Verify kernel modules exist
if [ ! -d "$ROOTFS/usr/lib/modules/$KERNELVER" ] && \
   [ ! -d "$ROOTFS/lib/modules/$KERNELVER" ]; then
	die "kernel modules directory does not exist for $KERNELVER"
fi

# Locate GRUB EFI modules
GRUBEFIDIR=""
for dir in "$ROOTFS/usr/lib/grub/x86_64-efi" \
           "$ROOTFS/usr/lib64/grub/x86_64-efi" \
           "$ROOTFS/usr/share/grub/x86_64-efi"; do
	if [ -d "$dir" ]; then
		GRUBEFIDIR="$dir"
		break
	fi
done

if [ -z "$GRUBEFIDIR" ]; then
	die "grub-efi files not found on target system"
fi

# Overview
echo
echo "distro   : $DISTRONAME"
echo "output   : iso/$ISONAME.iso"
echo "kernel   : $KERNELFILE ($KERNELVER)"
echo "grub-efi : $GRUBEFIDIR"
echo

msg "preparing working dirs..."
rm -rf work/_live
mkdir -p work/_live/boot work/_live/isolinux work/_live/rootfs

msg "copying liverootfs overlay..."
if [ -d liverootfs ]; then
	cp -ra liverootfs/* work/_live/rootfs/
	chown -R 0:0 work/_live/rootfs
fi

# Move splash image to isolinux dir if present
[ -f work/_live/rootfs/root/splash.png ] && {
	mv work/_live/rootfs/root/splash.png work/_live/isolinux
}

# Fetch mkinitramfs if not present
[ -f work/mkinitramfs ] || {
	msg "fetching mkinitramfs script..."
	curl -fLo work/mkinitramfs \
		https://raw.githubusercontent.com/venomlinux/mkinitramfs/master/mkinitramfs
}

# Fetch init script if not present
[ -f work/init.in ] || {
	msg "fetching init script..."
	curl -fLo work/init.in \
		https://raw.githubusercontent.com/venomlinux/mkinitramfs/master/init.in
}

# Fetch and extract syslinux for BIOS boot
if [ ! -f work/syslinux-6.03.tar.xz ]; then
	msg "fetching syslinux sources..."
	curl -fLo work/syslinux-6.03.tar.xz \
		https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.tar.xz
fi

rm -rf work/syslinux-6.03
tar xf work/syslinux-6.03.tar.xz -C work

# Unmount any stale mounts
for i in $(findmnt --list 2>/dev/null | awk '{print $1}' | grep "$ROOTFS" | sort -r); do
	[ "$i" = "$ROOTFS" ] && continue
	echo ">> unmounting $i"
	unmount "$i"
done

msg "copying syslinux files..."
cp work/syslinux-6.03/bios/core/isolinux.bin work/_live/isolinux
cp work/syslinux-6.03/bios/com32/chain/chain.c32 work/_live/isolinux
cp work/syslinux-6.03/bios/com32/elflink/ldlinux/ldlinux.c32 work/_live/isolinux
cp work/syslinux-6.03/bios/com32/libutil/libutil.c32 work/_live/isolinux
cp work/syslinux-6.03/bios/com32/lib/libcom32.c32 work/_live/isolinux
cp work/syslinux-6.03/bios/com32/menu/vesamenu.c32 work/_live/isolinux
cp work/syslinux-6.03/bios/com32/menu/menu.c32 work/_live/isolinux
cp work/syslinux-6.03/bios/com32/modules/reboot.c32 work/_live/isolinux
cp work/syslinux-6.03/bios/com32/modules/poweroff.c32 work/_live/isolinux

# Create squashfs of rootfs
msg "creating squashfs (this may take a while)..."
# shellcheck disable=SC2086
mksquashfs "$ROOTFS" work/_live/boot/rootfs.sfs \
	-b 1048576 \
	-comp xz \
	-noappend \
	$SQUASHFS_EXCLUDE \
	2>/dev/null

# Generate live initramfs
install -m755 work/mkinitramfs "$ROOTFS/tmp/mkinitramfs"
install -m755 work/init.in "$ROOTFS/tmp/init"
install -m644 files/liveiso.hook "$ROOTFS/tmp/liveiso.hook"
touch "$ROOTFS/tmp/mkinitramfs.conf"

msg "generating live initramfs..."
./live-chroot "$ROOTFS" /tmp/mkinitramfs \
	-c /tmp/mkinitramfs.conf \
	-k "$KERNELVER" \
	-i /tmp/init \
	-a /tmp/liveiso \
	-o /tmp/initrd

rm -f "$ROOTFS/tmp/mkinitramfs" "$ROOTFS/tmp/init" \
      "$ROOTFS/tmp/mkinitramfs.conf" "$ROOTFS/tmp/liveiso.hook"

cp "$KERNELFILE" work/_live/boot/vmlinuz
mv "$ROOTFS/tmp/initrd" work/_live/boot/initrd

# Setup UEFI boot
msg "setting up UEFI GRUB..."
mkdir -p work/_live/boot/grub/x86_64-efi work/_live/boot/grub/fonts

echo "set prefix=/boot/grub" > work/_live/boot/grub-early.cfg

cp -a "$GRUBEFIDIR"/*.mod work/_live/boot/grub/x86_64-efi/
cp -a "$GRUBEFIDIR"/*.lst work/_live/boot/grub/x86_64-efi/

# Copy unicode font
if [ -f "$ROOTFS/usr/share/grub/unicode.pf2" ]; then
	cp "$ROOTFS/usr/share/grub/unicode.pf2" work/_live/boot/grub/fonts/
elif [ -f files/unicode.pf2 ]; then
	cp files/unicode.pf2 work/_live/boot/grub/fonts/
fi

# Create GRUB EFI image
mkdir -p work/_live/efi/boot
grub-mkimage \
	-c work/_live/boot/grub-early.cfg \
	-o work/_live/efi/boot/bootx64.efi \
	-O x86_64-efi \
	-p "" \
	iso9660 normal search search_fs_file

# Create EFI boot image
modprobe loop 2>/dev/null || true
dd if=/dev/zero of=work/_live/boot/efiboot.img count=4096
mkdosfs -n STORM-FS-UEFI work/_live/boot/efiboot.img
mkdir -p work/_live/boot/efiboot
mount -o loop work/_live/boot/efiboot.img work/_live/boot/efiboot
mkdir -p work/_live/boot/efiboot/EFI/boot
cp work/_live/efi/boot/bootx64.efi work/_live/boot/efiboot/EFI/boot/
unmount work/_live/boot/efiboot
rm -rf work/_live/boot/efiboot

# Generate boot configs with distro name substitution
sed "s/@DISTRONAME@/$DISTRONAME/g" files/grub.cfg > work/_live/boot/grub/grub.cfg
sed "s/@DISTRONAME@/$DISTRONAME/g" files/isolinux.cfg > work/_live/isolinux/isolinux.cfg

# Create the hybrid ISO
mkdir -p iso
rm -f "iso/$ISONAME.iso"

msg "creating ISO image..."
xorriso -as mkisofs \
	-isohybrid-mbr work/syslinux-6.03/bios/mbr/isohdpfx.bin \
	-c isolinux/boot.cat \
	-b isolinux/isolinux.bin \
	  -no-emul-boot \
	  -boot-load-size 4 \
	  -boot-info-table \
	-eltorito-alt-boot \
	-e boot/efiboot.img \
	  -no-emul-boot \
	  -isohybrid-gpt-basdat \
	-volid STORMFS \
	-o "iso/$ISONAME.iso" work/_live

echo
echo "iso created : iso/$ISONAME.iso"
echo "iso size    : $(du -h "iso/$ISONAME.iso" | awk '{print $1}')"
echo
