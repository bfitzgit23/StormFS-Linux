#!/usr/bin/env python3
"""Lowercase port directory names and repoint every reference to them.

scratchpkg requires ``name=`` to equal the lowercase directory name, so CRUX's
mixed-case port names (libX11, libSM, ...) have to be normalised.  This walks
every collection, renames mixed-case directories to their lowercase form,
rewrites ``name=`` and updates references in depends files and recipes.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path("ports")
ENCODING = "utf-8"
ERRORS = "surrogateescape"


def read(p: Path) -> str:
    return p.read_text(encoding=ENCODING, errors=ERRORS)


def write(p: Path, s: str) -> None:
    p.write_text(s, encoding=ENCODING, errors=ERRORS)


def collections() -> list[Path]:
    return sorted(p for p in ROOT.iterdir() if p.is_dir())


def port_dirs() -> list[Path]:
    return sorted(d for c in collections() for d in c.iterdir() if d.is_dir())


renames: dict[str, str] = {}
for d in port_dirs():
    low = d.name.lower()
    if d.name == low:
        continue
    target = d.parent / low
    if target.exists() and target.resolve() != d.resolve():
        print(f"SKIP  {d} (existing {low})")
        continue
    tmp = d.parent / f".case-rename-{low}"
    d.rename(tmp)
    tmp.rename(target)
    renames[d.name] = low
    print(f"rename {d} -> {low}")

print(f"\nrenamed {len(renames)} directories")

# name= must match the directory name.
bad_name = 0
for d in port_dirs():
    rec = d / "spkgbuild"
    if not rec.is_file():
        continue
    text = read(rec)
    new, n = re.subn(r"(?m)^name=.*$", f"name={d.name}", text)
    if n != 1:
        bad_name += 1
        print(f"WARN  {rec}: {n} name= lines")
        continue
    if new != text:
        write(rec, new)

print(f"name= normalised (record files rewritten in place)")

# Repoint references: depends files, recipes, and helper scripts.
pattern = re.compile(
    r"\b(" + "|".join(re.escape(k) for k in sorted(renames, key=len, reverse=True)) + r")\b"
) if renames else None

touched = 0
changed_files = 0
if pattern:
    targets = list(ROOT.rglob("depends")) + list(ROOT.rglob("spkgbuild"))
    for p in targets:
        if not p.is_file():
            continue
        text = read(p)
        new = pattern.sub(lambda m: renames[m.group(1)], text)
        if new != text:
            write(p, new)
            changed_files += 1
            touched += len(pattern.findall(text))
    print(f"repointed {touched} references in {changed_files} files")

# Report dependencies that do not resolve to any port (case-insensitive).
names = {d.name.lower() for c in collections() for d in c.iterdir() if d.is_dir()}
dangling: dict[str, list[str]] = {}
for p in ROOT.rglob("depends"):
    for dep in read(p).split():
        if dep.lower() not in names:
            dangling.setdefault(dep, []).append(str(p.parent))
print(f"\nunresolved dependency names: {len(dangling)}")
for dep in sorted(dangling)[:40]:
    print(f"  {dep}  <- {dangling[dep][0]}" + (f" (+{len(dangling[dep]) - 1})" if len(dangling[dep]) > 1 else ""))

sys.exit(0)
