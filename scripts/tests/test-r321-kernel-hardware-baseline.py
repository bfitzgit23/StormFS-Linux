#!/usr/bin/env python3
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
configs=[ROOT/'ports/core/linux/config', ROOT/'ports/core/linux-lts/config']
required={
 'boot/platform':['CONFIG_64BIT','CONFIG_X86_64','CONFIG_EFI','CONFIG_EFI_STUB','CONFIG_BLK_DEV_INITRD','CONFIG_DEVTMPFS'],
 'usb-host':['CONFIG_USB_XHCI_HCD','CONFIG_USB_EHCI_HCD','CONFIG_USB_OHCI_HCD','CONFIG_USB_UHCI_HCD','CONFIG_USB_STORAGE'],
 'storage':['CONFIG_BLK_DEV_NVME','CONFIG_SATA_AHCI','CONFIG_SCSI','CONFIG_BLK_DEV_SD','CONFIG_MD','CONFIG_BLK_DEV_DM'],
 'filesystems':['CONFIG_EXT4_FS','CONFIG_XFS_FS','CONFIG_BTRFS_FS','CONFIG_F2FS_FS','CONFIG_VFAT_FS'],
 'audio':['CONFIG_SND_HDA_INTEL','CONFIG_SND_HDA_CODEC_HDMI','CONFIG_SND_USB_AUDIO','CONFIG_SND_SOC'],
 'wifi-core':['CONFIG_CFG80211','CONFIG_MAC80211','CONFIG_RFKILL'],
 'wifi-drivers':['CONFIG_IWLWIFI','CONFIG_RTW88','CONFIG_RTW89','CONFIG_ATH10K','CONFIG_ATH11K','CONFIG_ATH12K','CONFIG_MT76_CORE','CONFIG_BRCMFMAC'],
 'ethernet':['CONFIG_R8169','CONFIG_E1000E','CONFIG_IGB','CONFIG_IGC','CONFIG_TIGON3','CONFIG_BNXT','CONFIG_AQTION'],
 'camera-bluetooth-input':['CONFIG_USB_VIDEO_CLASS','CONFIG_BT','CONFIG_BT_HCIBTUSB','CONFIG_HID_GENERIC','CONFIG_HID_MULTITOUCH'],
 'graphics':['CONFIG_DRM','CONFIG_DRM_SIMPLEDRM','CONFIG_DRM_AMDGPU','CONFIG_DRM_I915','CONFIG_DRM_NOUVEAU','CONFIG_FRAMEBUFFER_CONSOLE'],
 'virtualization':['CONFIG_KVM','CONFIG_KVM_INTEL','CONFIG_KVM_AMD','CONFIG_VIRTIO_PCI','CONFIG_VIRTIO_BLK','CONFIG_VIRTIO_NET','CONFIG_VHOST_NET'],
 'laptop-platform':['CONFIG_ACPI','CONFIG_THERMAL','CONFIG_TYPEC','CONFIG_MMC','CONFIG_MMC_SDHCI'],
 'peripherals':['CONFIG_USB_PRINTER','CONFIG_USB_SERIAL'],
}

def load(p):
    vals={}
    for line in p.read_text().splitlines():
        if line.startswith('CONFIG_') and '=' in line:
            k,v=line.split('=',1); vals[k]=v
        elif line.startswith('# CONFIG_') and line.endswith(' is not set'):
            vals[line.split()[1]]='n'
    return vals

bad=[]
for p in configs:
    vals=load(p)
    recipe=(p.parent/'Pkgfile').read_text(errors='replace')
    for cat,syms in required.items():
        for sym in syms:
            enabled = vals.get(sym) in {'y','m'}
            # Kernel recipes deliberately override a few seed-config values
            # with scripts/config before olddefconfig/build.
            if not enabled and f'scripts/config --enable {sym.removeprefix("CONFIG_")}' in recipe:
                enabled=True
            if not enabled:
                bad.append(f'{p.relative_to(ROOT)}: {cat}: {sym}={vals.get(sym,"missing")}')
if configs[0].read_bytes()!=configs[1].read_bytes():
    bad.append('linux and linux-lts baseline config files have drifted; review intentional differences')
if bad:
    print('FAIL: BFSOS broad kernel baseline')
    print('\n'.join('  '+x for x in bad))
    raise SystemExit(1)
print('PASS: BFSOS current/LTS configs share the broad generic hardware baseline')
for cat,syms in required.items(): print(f'  {cat}: {len(syms)} required symbols present as y/m')
