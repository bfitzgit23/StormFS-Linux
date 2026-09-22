#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
COMPAT = ROOT / "ports/compat-32"
CONTRIB = ROOT / "ports/contrib"
pkgfiles = sorted(COMPAT.glob("*/Pkgfile"))
assert len(pkgfiles) == 170, len(pkgfiles)

for p in pkgfiles:
    s = p.read_text(errors="replace")
    assert "-march=x86-64" not in s, p
    assert "linux-x86_64" not in s, p
    assert not re.search(r"(?m)^\s*meson\s+build\s+", s), p
    assert "--cross-file lib32" not in s, p
    cp = subprocess.run(["bash", "-n", str(p)], capture_output=True, text=True)
    assert cp.returncode == 0, (p, cp.stderr)

extension = (ROOT / "ports/core/pkgutils/extension").read_text()
for needle in (
    'BFS_PKG_EXTENSION_API=2',
    'BFS_PKG_LIBDIR=/usr/lib32',
    '-DCMAKE_INSTALL_LIBDIR="$BFS_PKG_LIBDIR_NAME"',
    '--libdir="$BFS_PKG_LIBDIR"',
    '"--host=${BFS_MULTILIB_HOST:-i686-pc-linux-gnu}"',
    '_bfs_meson_arch_args=(--cross-file .bfsos-compat32.cross)',
    '_bfs_validate_compat32_payload',
    'compat-32 payload contains files in native library directories',
):
    assert needle in extension, needle

for p in pkgfiles:
    s = p.read_text(errors="replace")
    if not re.search(r"(?m)^pkg_build\s*\(", s):
        assert "_bfs_require_compat32_extension 2" in s, p
        assert not re.search(r"(?m)^\s*(?:\./configure|meson setup|cmake -S)\b", s), p

libxml2 = (COMPAT / "libxml2-32/Pkgfile").read_text()
assert "build_type=configure_build" in libxml2
flac = (COMPAT / "flac-32/Pkgfile").read_text()
assert "build_type=cmake_build" in flac
lcms2 = (COMPAT / "lcms2-32/Pkgfile").read_text()
assert "rm -rf $PKG/usr/{bin,include,share/man}" in lcms2
libffi = (COMPAT / "libffi-32/Pkgfile").read_text()
assert re.search(r"(?m)^release=3$", libffi)

pkgutils = (ROOT / "ports/core/pkgutils/Pkgfile").read_text()
assert re.search(r"(?m)^release=35$", pkgutils)

gstreamer = (COMPAT / "gstreamer-32/Pkgfile").read_text()
assert "CRUX Linux" not in gstreamer
assert "_cross_file" not in gstreamer
gstbase = (COMPAT / "gst-plugins-base-32/Pkgfile").read_text()
assert "gl_platform=$PKGMK_GST_PLATFORM" in gstbase
assert "CRUX Linux" not in gstbase

mpg = (COMPAT / "mpg123-32/Pkgfile").read_text()
assert re.search(r"(?m)^# Depends on:.*\bopenal-32\b", mpg)
openssl = (COMPAT / "openssl11-32/Pkgfile").read_text()
assert "linux-x86" in openssl and "linux-x86_64" not in openssl
pipewire = (COMPAT / "pipewire-32/Pkgfile").read_text()
assert "xorg-libxcb-32" not in pipewire and "libxcb-32" in pipewire

wine = (CONTRIB / "wine-staging/Pkgfile").read_text()
assert '"$SRC/wine-staging-$version/staging/patchinstall.py"' in wine
assert '"$SRC/wine-$version/configure" $build_opt' in wine
steam = (CONTRIB / "steam/Pkgfile").read_text()
for dep in ("alsa-plugins-32", "fontconfig-32", "libX11-32", "libva-32", "vulkan-loader-32"):
    assert re.search(rf"(?m)^# Depends on:.*\b{re.escape(dep)}\b", steam), dep

print("compat-32/contrib build-contract regression: PASS")
