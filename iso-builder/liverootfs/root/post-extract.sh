#!/bin/sh
#
# StormFS Linux Post-Extract Script
# Called right after squashfs is extracted to disk, before post-install.
#
# Environment variables:
#   $LIVEROOTFS - path to the live rootfs overlay on the medium
#   $ROOT       - path to the installed system root
#

# Copy overlay customization files from the live medium
if [ -d "$LIVEROOTFS" ]; then
	for i in $(find "$LIVEROOTFS" -type f 2>/dev/null | sed "s,$LIVEROOTFS,,"); do
		case "$i" in
			*stormfs-installer*|*live_script.sh|*fstab|*issue|*post-install.sh|*post-extract.sh|*live-chroot)
				continue
				;;
		esac
		install -D "$LIVEROOTFS/$i" "$ROOT/$i" 2>/dev/null || true
	done
fi

exit 0
