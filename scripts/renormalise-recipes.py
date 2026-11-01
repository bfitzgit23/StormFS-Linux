#!/usr/bin/env python3
"""Re-normalise recipes after the bulk re-conversion of restored Pkgfiles.

Re-converting regenerated recipes straight from the CRUX Pkgfiles undid several
scratchpkg-specific normalisations.  This restores them idempotently:

* ``PKGMK_*`` variables become ``SPKG_*`` (the helper and scratchpkg only know
  the latter).
* ``name=`` matches the lowercase directory name.
* Retired ``_bfs_require_compat32_extension`` calls are dropped.
* ``depends`` entries are lowercased when a port with that name exists, and the
  removed systemd port is replaced by eudev where a recipe still referenced it.
"""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

ENCODING = "utf-8"
ERRORS = "surrogateescape"
PORTS = Path("ports")


def read(p: Path) -> str:
    return p.read_text(encoding=ENCODING, errors=ERRORS)


def write(p: Path, s: str) -> None:
    p.write_text(s, encoding=ENCODING, errors=ERRORS, newline="\n")


dirs = [d for c in sorted(PORTS.iterdir()) if c.is_dir() for d in sorted(c.iterdir()) if d.is_dir()]
canonical = {d.name.lower(): d.name for d in dirs}
names = set(canonical)

pkgmk = hook = renamed = 0
for d in dirs:
    rec = d / "spkgbuild"
    if not rec.is_file():
        continue
    text = read(rec)
    new, n = re.subn(r"\bPKGMK_", "SPKG_", text)
    pkgmk += n
    text = new
    new, n = re.subn(r"(?m)^[ \t]*_bfs_require_compat32_extension[ \t]+\d+[ \t]*\n", "", text)
    hook += n
    text = new
    new = re.sub(r"(?m)^name=.*$", f"name={d.name}", text)
    if new != text:
        renamed += 1
        text = new
    write(rec, text)

print(f"PKGMK_ occurrences rewritten: {pkgmk}")
print(f"retired compat32 hook calls removed: {hook}")
print(f"name= lines corrected: {renamed}")

dep_files = dep_edits = 0
for p in sorted(PORTS.rglob("depends")):
    entries = read(p).split()
    out: list[str] = []
    changed = False
    for dep in entries:
        low = canonical.get(dep.lower(), dep)
        if low == "systemd":
            low = "eudev"
            changed = True
        if low != dep:
            changed = True
        if low not in out:
            out.append(low)
        elif low != dep:
            changed = True
    text = "\n".join(out) + ("\n" if out else "")
    if changed and text != read(p):
        write(p, text)
        dep_edits += 1
    dep_files += 1

print(f"depends files rewritten: {dep_edits} of {dep_files}")

bad = [p for p in sorted(PORTS.rglob("spkgbuild"))
       if subprocess.run(["bash", "-n", str(p)], capture_output=True).returncode != 0]
print(f"syntax failures: {len(bad)}")
for p in bad[:10]:
    print(" ", p)

missing: dict[str, str] = {}
for p in sorted(PORTS.rglob("depends")):
    for dep in read(p).split():
        if dep.lower() not in names:
            missing.setdefault(dep, str(p.parent))
print(f"unresolved dependency names: {len(missing)}")
for dep, where in sorted(missing.items()):
    print(f"  {dep}  <- {where}")
