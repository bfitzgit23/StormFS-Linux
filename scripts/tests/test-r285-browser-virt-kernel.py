#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]

def text(rel): return (root / rel).read_text()

expected = {
    'ports/core/linux/Pkgfile': 'version=7.2.6',
    'ports/core/linux-api-headers/Pkgfile': 'version=7.2.6',
    'ports/core/linux-headers/Pkgfile': 'version=7.2.6',
    'ports/core/linux-lts/Pkgfile': 'version=6.18.52',
    'ports/opt/qemu/Pkgfile': 'version=11.1.1',
    'ports/opt/libvirt/Pkgfile': 'version=12.7.0',
    'ports/opt/libvirt-python/Pkgfile': 'version=12.7.0',
    'ports/opt/virt-manager/Pkgfile': 'version=5.1.0',
    'ports/opt/chromium/Pkgfile': 'version=153.0.8010.36',
}
for rel, needle in expected.items():
    assert needle in text(rel), (rel, needle)

for rel in ['ports/opt/qemu/Pkgfile','ports/opt/libvirt/Pkgfile','ports/opt/virt-manager/Pkgfile']:
    s=text(rel)
    assert 'build_opt=' in s
    assert '\npkg_build() {' not in s, f'{rel}: ordinary build should be extension-owned'

for rel in ['ports/opt/chromium/Pkgfile','ports/opt/gn/Pkgfile']:
    s=text(rel)
    assert 'Custom build required:' in s
    assert 'pkg_build()' in s

assert 'build_work=disk' in text('ports/opt/chromium/Pkgfile')
assert 'build_work=disk' in text('ports/opt/qemu/Pkgfile')
print('r285 browser/virtualization/kernel source regression: PASS')
