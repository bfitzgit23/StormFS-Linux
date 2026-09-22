#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
compat = ROOT / "ports" / "compat-32"
pkgfiles = sorted(compat.glob("*/Pkgfile"))
assert len(pkgfiles) == 172, len(pkgfiles)
assert all((p.parent / ".32bit").is_file() for p in pkgfiles)

custom = []
automatic = []
for p in pkgfiles:
    s = p.read_text(errors="replace")
    assert not re.search(r"(?m)^build\s*\(\)\s*\{", s), p
    assert "-m32" not in s, p
    assert "gnux32" not in s, p
    cp = subprocess.run(["bash", "-n", str(p)], capture_output=True, text=True)
    assert cp.returncode == 0, (p, cp.stderr)
    if re.search(r"(?m)^pkg_build\s*\(", s):
        custom.append(p)
        assert "# Custom build required:" in s, p
        assert re.search(r"pkg_build\s*\(\s*\)\s*\{\s*\n\s*\(\s*\n\s*set -e", s), p
    else:
        automatic.append(p)
        assert "_bfs_require_compat32_extension 2" in s, p

assert len(automatic) >= 125, len(automatic)
assert len(custom) <= 45, len(custom)

conf = (ROOT / "ports/core/pkgutils/pkgmk.conf").read_text()
extension = (ROOT / "ports/core/pkgutils/extension").read_text()
assert 'BFS_MULTILIB_HOST="i686-pc-linux-gnu"' in conf
assert 'PKG_CONFIG_LIBDIR="/usr/lib32/pkgconfig:/usr/share/pkgconfig"' in conf
assert 'export CFLAGS="-O2 -march=i686 -pipe -m32"' in conf
assert 'BFS_PKG_LIBDIR=/usr/lib32' in extension
assert 'BFS_PKG_EXTENSION_API=2' in extension
assert '_bfs_validate_compat32_payload' in extension
assert "cpu_family = 'x86'" in extension
assert '_bfs_meson_arch_args=(--cross-file .bfsos-compat32.cross)' in extension

cp = subprocess.run([str(ROOT / "scripts/multilibvercheck.sh")], capture_output=True, text=True)
assert cp.returncode == 0, cp.stdout + cp.stderr
assert "matched=157 special=15 drift=0 unexplained=0" in cp.stdout, cp.stdout
print(f"compat-32 synchronization regression: PASS (172 ports; {len(automatic)} generic; {len(custom)} documented custom)")
