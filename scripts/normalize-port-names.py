#!/usr/bin/env python3
"""Normalise port identifiers so scratchpkg's pkgbuild accepts every recipe.

pkgbuild's check_buildscript refuses to build a port when

  * the port directory name differs from ``name=``,
  * ``name`` contains capital letters,
  * ``version`` contains ``-``.

The tree inherited X11-style directory names (``libX11-32``) and a few ports
whose ``name=`` did not match their directory.  This step lowercases those
directories, forces ``name=`` to the directory name, and rewrites every
``depends`` entry that referenced a renamed port.

    python3 scripts/normalize-port-names.py --dry-run
    python3 scripts/normalize-port-names.py
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

NAME_RE = re.compile(r"^name=.*$", re.M)
VERSION_RE = re.compile(r"^version=(.+)$", re.M)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ports", nargs="?", default="ports")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    root = Path(args.ports)
    if not root.is_dir():
        print(f"ERROR: ports tree not found: {root}", file=sys.stderr)
        return 1

    renames: dict[str, str] = {}
    moved = 0
    name_fixed = 0
    dashed_versions: list[str] = []

    for spkgbuild in sorted(root.glob("*/*/spkgbuild")):
        port_dir = spkgbuild.parent
        collection = port_dir.parent
        text = spkgbuild.read_text(encoding="utf-8", errors="replace")

        declared = ""
        match = re.search(r"^name=(.+)$", text, re.M)
        if match:
            declared = match.group(1).strip().strip("\"'")

        target = port_dir.name
        if re.search(r"[A-Z]", target):
            target = target.lower()
            destination = collection / target
            if destination.exists():
                print(f"SKIP rename (target exists): {port_dir} -> {destination}")
                target = port_dir.name
            elif not args.dry_run:
                shutil.move(str(port_dir), str(destination))
                moved += 1
                port_dir = destination
                spkgbuild = destination / "spkgbuild"
            else:
                moved += 1
                port_dir = destination
                spkgbuild = destination / "spkgbuild"

        if declared and declared != port_dir.name:
            renames[declared] = port_dir.name
            name_fixed += 1
            if not args.dry_run:
                text = NAME_RE.sub(f"name={port_dir.name}", text, count=1)
                spkgbuild.write_text(text, encoding="utf-8", newline="\n")

        version_match = VERSION_RE.search(text)
        if version_match:
            version = version_match.group(1).strip().strip("\"'")
            if "-" in version:
                dashed_versions.append(f"{port_dir.name}={version}")

    # Repoint dependencies that still use the old identifiers.
    rewritten = 0
    if renames and not args.dry_run:
        for deps in root.glob("*/*/depends"):
            lines = deps.read_text(encoding="utf-8", errors="replace").splitlines()
            updated = [renames.get(line.strip(), line) for line in lines]
            if updated != lines:
                deps.write_text("\n".join(updated) + "\n", encoding="utf-8", newline="\n")
                rewritten += 1

    print(f"directories renamed     : {moved}")
    print(f"name= corrected         : {name_fixed}")
    print(f"depends files rewritten : {rewritten}")
    if renames:
        print("renamed identifiers:")
        for old, new in sorted(renames.items()):
            print(f"  {old} -> {new}")
    if dashed_versions:
        print("versions still containing '-' (pkgbuild rejects these):")
        for item in dashed_versions:
            print(f"  {item}")
    if args.dry_run:
        print("\n(dry run: nothing written)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
