#!/usr/bin/env python3
from pathlib import Path
import re
root = Path(__file__).resolve().parents[2]

def text(rel): return (root / rel).read_text()

expected = {
    'ports/core/linux/spkgbuild': 'version=7.2.8',
    'ports/core/linux-headers/spkgbuild': 'version=7.3.1',
    'ports/core/linux-lts/spkgbuild': 'version=7.3.1',
    'ports/opt/qemu/spkgbuild': 'version=11.1.1',
    'ports/opt/libvirt/spkgbuild': 'version=12.7.0',
    'ports/opt/libvirt-python/spkgbuild': 'version=12.7.0',
    'ports/opt/virt-manager/spkgbuild': 'version=5.1.0',
    'ports/opt/chromium/spkgbuild': 'version=157.0.8103.38',
}
for rel, needle in expected.items():
    assert needle in text(rel), (rel, needle)

for rel in ['ports/opt/libvirt/spkgbuild','ports/opt/virt-manager/spkgbuild']:
    s=text(rel)
    assert 'build_opt=' in s
    # scratchpkg requires build(); ordinary ports must keep it extension-owned
    # (delegating to spkgbuild.helper) instead of hand-rolling configure steps.
    assert 'bfs_autobuild' in s, f'{rel}: ordinary build should be extension-owned'
    assert not re.search(r'(?m)^\s*(?:\./configure|meson setup|cmake -S)\b', s), rel

qemu=text('ports/opt/qemu/spkgbuild')
assert 'build_opt=' in qemu
assert 'Custom build required' not in qemu or 'configure' in qemu
assert "QEMU's ./configure wrapper" in qemu
assert '\nbuild() {' in qemu

for rel in ['ports/opt/chromium/spkgbuild','ports/opt/gn/spkgbuild']:
    s=text(rel)
    assert 'Custom build required:' in s
    assert 'build() {' in s

assert 'build_work=disk' in text('ports/opt/chromium/spkgbuild')
assert 'build_work=disk' in text('ports/opt/qemu/spkgbuild')
print('r285 browser/virtualization/kernel source regression: PASS')
