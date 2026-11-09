#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
COMPAT = ROOT / "ports/compat-32"
CONTRIB = ROOT / "ports/contrib"
pkgfiles = sorted(COMPAT.glob("*/spkgbuild"))
assert len(pkgfiles) >= 150, len(pkgfiles)

for p in pkgfiles:
    s = p.read_text(errors="replace")
    assert "-march=x86-64" not in s, p
    assert "linux-x86_64" not in s, p
    assert not re.search(r"(?m)^\s*meson\s+build\s+", s), p
    assert "--cross-file lib32" not in s, p
    cp = subprocess.run(["bash", "-n", str(p)], capture_output=True, text=True)
    assert cp.returncode == 0, (p, cp.stderr)

extension = (ROOT / "ports/core/bfs-spkgbuild-macros/helper.sh").read_text()
for needle in (
    'bfs_compat32()',
    'bfs_compat32_validate()',
    'bfs_autobuild()',
    'BFS_PKG_LIBDIR="/usr/lib32"',
    'BFS_PKG_LIBDIR_NAME="lib32"',
    'i686-pc-linux-gnu',
    'compat-32 payload contains files in native library directories',
):
    assert needle in extension, needle

for p in pkgfiles:
    s = p.read_text(errors="replace")
    # scratchpkg has no per-port architecture switch: every *-32 recipe must
    # opt in to the i686 build and validate its payload stayed out of the
    # native library directories.
    assert "bfs_compat32" in s, p
    assert "bfs_compat32_validate" in s, p

libxml2 = (COMPAT / "libxml2-32/spkgbuild").read_text()
assert "build_type=configure_build" in libxml2
flac = (COMPAT / "flac-32/spkgbuild").read_text()
assert "build_type=cmake_build" in flac
lcms2 = (COMPAT / "lcms2-32/spkgbuild").read_text()
assert "rm -rf $PKG/usr/{bin,include,share/man}" in lcms2
libffi = (COMPAT / "libffi-32/spkgbuild").read_text()
assert re.search(r"(?m)^release=3$", libffi)

scratchpkg = (ROOT / "ports/core/scratchpkg/spkgbuild").read_text()
assert re.search(r'(?m)^name=scratchpkg$', scratchpkg)
assert re.search(r'(?m)^release=\d+$', scratchpkg)
assert re.search(r'(?m)^build\(\) \{', scratchpkg)

gstreamer = (COMPAT / "gstreamer-32/spkgbuild").read_text()
assert "CRUX Linux" not in gstreamer
assert "_cross_file" not in gstreamer
gstbase = (COMPAT / "gst-plugins-base-32/spkgbuild").read_text()
assert re.search(r'build_opt\+=\([^)]*-Dgl_platform=\$', gstbase)
assert "CRUX Linux" not in gstbase

mpg = (COMPAT / "mpg123-32/depends").read_text().split()
assert "openal-32" in mpg
openssl = (COMPAT / "openssl11-32/spkgbuild").read_text()
assert "linux-x86" in openssl and "linux-x86_64" not in openssl
pipewire = (COMPAT / "pipewire-32/spkgbuild").read_text()
assert "xorg-libxcb-32" not in pipewire and "libxcb-32" in pipewire

wine = (CONTRIB / "wine-staging/spkgbuild").read_text()
for label, recipe in (("openssl11-32", openssl), ("wine-staging", wine)):
    source = re.search(r'(?m)^source="([^"]*)"$', recipe)
    assert source, label
    assert "\\" not in source.group(1).split(), label
assert '"$SRC/wine-staging-$version/staging/patchinstall.py"' in wine
assert '"$SRC/wine-$version/configure" $build_opt' in wine
steam = (CONTRIB / "steam/depends").read_text().split()
for dep in ("alsa-plugins-32", "fontconfig-32", "libx11-32", "libva-32", "vulkan-loader-32"):
    assert dep in steam, dep

print("compat-32/contrib build-contract regression: PASS")
