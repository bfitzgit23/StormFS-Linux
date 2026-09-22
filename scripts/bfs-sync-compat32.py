#!/usr/bin/env python3
"""Audit/synchronize BFSOS compat-32 versions against maintained native ports.

Default mode is read-only.  --write updates only the version= assignment and
ensures the .32bit marker exists; it never rewrites sources/build logic.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PORTS = ROOT / "ports"
ALIASES = {
    "xorg-libxmu": "libXmu",
    "xorg-libxkbfile": "libxkbfile",
    "libgmp": "gmp",
    "libnewt": "newt",
    "libpcre2": "pcre2",
    "libsdl2": "sdl2",
    "sqlite3": "sqlite",
    "libnm": "networkmanager",
    "vulkan-tools": "vulkan-headers",
    "nvidia-fb": "nvidia",
}
# Compatibility-only ABI/history packages with no maintained native counterpart.
SPECIAL = {
    "db", "libappindicator-sharp", "libcaca", "libidn133",
    "libindicator-gtk2", "libjpeg6-turbo", "libpcre",
    "libpng12", "libsdl", "libtiff4", "libudev0-shim",
    "openssl11", "python", "rtmpdump", "speexdsp",
}

ASSIGN_RE = re.compile(r"^(name|version)=(.+)$", re.M)

def metadata(pkgfile: Path) -> tuple[str, str, str]:
    text = pkgfile.read_text(errors="replace")
    vals = {m.group(1): m.group(2).strip().strip("\"'") for m in ASSIGN_RE.finditer(text)}
    if not vals.get("name") or not vals.get("version"):
        raise ValueError(f"missing name/version: {pkgfile}")
    return vals["name"], vals["version"], text

def native_index():
    out: dict[str, tuple[str, Path]] = {}
    for tree in PORTS.iterdir():
        if not tree.is_dir() or tree.name == "compat-32":
            continue
        for pkgfile in tree.glob("*/Pkgfile"):
            try:
                name, version, _ = metadata(pkgfile)
            except ValueError:
                continue
            out.setdefault(name, (version, pkgfile))
    return out

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help="synchronize version= values and .32bit markers")
    ns = ap.parse_args()
    native = native_index()
    matched = special = drift = errors = 0
    for pkgfile in sorted((PORTS / "compat-32").glob("*/Pkgfile")):
        name, version, text = metadata(pkgfile)
        base = name[:-3] if name.endswith("-32") else pkgfile.parent.name.removesuffix("-32")
        target = ALIASES.get(base, base)
        if target not in native:
            # case-only X.Org naming differences
            hits = [k for k in native if k.casefold() == target.casefold()]
            if len(hits) == 1:
                target = hits[0]
        if target in native:
            matched += 1
            want, source = native[target]
            if version != want:
                drift += 1
                print(f"DRIFT {name}: {version} -> {want} ({source.relative_to(ROOT)})")
                if ns.write:
                    new = re.sub(r"(?m)^version=.*$", f"version={want}", text, count=1)
                    pkgfile.write_text(new)
            if ns.write:
                (pkgfile.parent / ".32bit").touch()
        else:
            special += 1
            if base not in SPECIAL:
                errors += 1
                print(f"UNEXPLAINED {name}: no native counterpart", file=sys.stderr)
            else:
                print(f"SPECIAL {name}: compatibility-only {version}")
                if ns.write:
                    (pkgfile.parent / ".32bit").touch()
    print(f"compat-32 summary: matched={matched} special={special} drift={drift} unexplained={errors}")
    return 1 if errors or (drift and not ns.write) else 0

if __name__ == "__main__":
    raise SystemExit(main())
