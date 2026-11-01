#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]

def text(rel):
    return (root / rel).read_text()

def deps(rel):
    return (root / rel / 'depends').read_text().split()

gn = text('ports/opt/gn/spkgbuild')
assert 'version=0.20260907' in gn
assert '5df47e556efde72cc576d8a3af23b58b614345bd' in gn

qemu = text('ports/opt/qemu/spkgbuild')
assert int(re.search(r'^release=(\d+)$', qemu, re.M).group(1)) >= 2
for needle in ['--disable-download', '--enable-tools', '--enable-guest-agent',
               '--enable-kvm', '--enable-linux-io-uring', '--enable-slirp',
               '--enable-cap-ng', '--enable-libusb', '--enable-usb-redir']:
    assert needle in qemu, needle
# QEMU is a documented exception: its supported feature interface is the
# upstream ./configure wrapper, so the package owns the configure invocation.
assert "QEMU's ./configure wrapper" in qemu
assert '\nbuild() {' in qemu
for required in ['--prefix=/usr', '--sysconfdir=/etc', '--localstatedir=/var']:
    assert required in qemu, f'qemu configure wrapper missing {required}'

libvirt = text('ports/opt/libvirt/spkgbuild')
assert int(re.search(r'^release=(\d+)$', libvirt, re.M).group(1)) >= 2
assert 'default-network.xml' in libvirt
assert '-Ddriver_qemu=enabled' in libvirt
assert '-Ddriver_network=enabled' in libvirt
assert 'networks/autostart/default.xml' in libvirt
xml = text('ports/opt/libvirt/default-network.xml')
for needle in ["<name>default</name>", "<forward mode='nat'/>", "bridge name='virbr0'", "192.168.122.1"]:
    assert needle in xml, needle

virt = text('ports/opt/virt-manager/spkgbuild')
assert int(re.search(r'^release=(\d+)$', virt, re.M).group(1)) >= 2
assert '-Ddefault-graphics=vnc' in virt
for dep in ['python3-argcomplete', 'libisoburn', 'gtk-vnc', 'libvirt-python']:
    assert dep in deps('ports/opt/virt-manager'), dep

uring = text('ports/opt/liburing/spkgbuild')
assert int(re.search(r'^release=(\d+)$', uring, re.M).group(1)) >= 2
assert 'build() {' in uring
assert "liburing's configure is intentionally minimal" in uring
assert '--prefix=/usr' in uring
assert '--libdir=/usr/lib' in uring

chromium = text('ports/opt/chromium/spkgbuild')
assert int(re.search(r'^release=(\d+)$', chromium, re.M).group(1)) >= 2
for needle in ['clang_base_path="/usr"', 'clang_use_chrome_plugins=false',
               'v8_symbol_level=0', 'ozone_platform_wayland=true',
               'ozone_platform_x11=true', 'chrome_crashpad_handler',
               'vk_swiftshader_icd.json', '$PKG/usr/bin/chromedriver']:
    assert needle in chromium, needle
for stale in ['use_system_libjpeg=', 'use_system_libpng=',
              'use_system_zlib=', 'use_system_openh264=', 'enable_nacl=',
              'enable_widevine=']:
    assert stale not in chromium, f'stale/fragile Chromium GN arg retained: {stale}'
chromium_deps = deps('ports/opt/chromium')
for dep in ['dav1d', 'desktop-file-utils', 'hicolor-icon-theme', 'libgcrypt',
            'libx11', 'libxcb', 'libxcomposite', 'libxdamage', 'libxext',
            'libxfixes', 'libxrandr', 'libxscrnsaver', 'xdg-utils', 'git',
            'gperf', 'pipewire', 'typescript']:
    assert dep in chromium_deps, dep

# Every hard dependency introduced/retained by these ports must resolve to a
# maintained BFSOS port identity.
ports = root / 'ports'
identities = {p.name for collection in ports.iterdir() if collection.is_dir()
              for p in collection.iterdir() if p.is_dir() and (p / 'spkgbuild').exists()}
for rel in ['ports/opt/qemu', 'ports/opt/libvirt', 'ports/opt/libvirt-python',
            'ports/opt/virt-manager', 'ports/opt/chromium']:
    declared = deps(rel)
    assert declared, f'{rel}: empty depends file'
    known = {i.lower() for i in identities}
    missing = [d for d in declared if d.lower() not in known]
    assert not missing, f'{rel}: unresolved dependencies: {missing}'

print('r286 browser/virtualization hardening regression: PASS')
