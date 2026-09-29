# BFSOS kernel baseline audit — r321

Date: 2026-09-23

## Policy after r321

- `linux-lts` 6.18.53 is the BFSOS default installed kernel.
- `linux` 7.2.7 remains the optional current/mainline kernel.
- `linux-headers` and `linux-api-headers` both follow the 6.18.53 LTS userspace API baseline.
- glibc 2.44 is release-bumped to 4 so the next clean toolchain/base cycle rebuilds against the LTS-aligned header policy.
- The installer defaults to `linux-lts`; the ISO builder already defaults to the LTS flavor.

## Configuration baseline

The current and LTS seed config files are byte-identical before version-specific `olddefconfig` reconciliation. Both Pkgfiles also carry the same BFSOS broad-hardware overrides where a seed symbol is intentionally forced at build time.

The r321 static regression audit checks effective configuration coverage for:

- EFI/ACPI/platform boot support;
- xHCI/EHCI/OHCI/UHCI and USB mass storage;
- NVMe, AHCI/SATA, SCSI, mdraid and device-mapper/LVM;
- ext4, XFS, Btrfs, F2FS and VFAT;
- HDA/HDMI/USB and modern SoC audio paths;
- cfg80211/mac80211/rfkill plus Intel, Realtek, Qualcomm/Atheros, MediaTek and Broadcom Wi-Fi families;
- Intel, Realtek, Broadcom and Aquantia/Marvell Ethernet families;
- UVC, Bluetooth and generic HID/input;
- DRM/KMS, simpledrm, AMDGPU, Intel and Nouveau/fallback console paths;
- KVM Intel/AMD, virtio and vhost;
- thermal, Type-C, MMC/card-reader and generic USB printer/serial support.

`scripts/tests/test-r321-kernel-hardware-baseline.py` passes for both maintained kernel recipes.

## Runtime acceptance still required

The static/config audit is not a substitute for a kernel build or boot test. Before the next release base is generated, build/install both 6.18.53 LTS and 7.2.7 current kernels on BFSOS, regenerate initramfs/GRUB, boot the default LTS kernel on bare metal, and re-check the existing RAID/mdadm compatibility path. Keep 7.2.7 available as an optional alternate boot entry.
