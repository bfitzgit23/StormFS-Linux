#!/usr/bin/env python3
"""Migrate the remaining helper scripts from pkgtools/systemd to scratchpkg/OpenRC.

bootstrap.sh is handled by its own migration scripts.  This pass covers the ISO
builder, the installer and GUI front-ends, and the maintenance helpers:

  * prt-get / pkginfo / pkgrm / pkgmk commands become scratch, pkgbuild and
    pkgadd equivalents;
  * pacman invocations become scratch install/remove;
  * systemctl service management becomes rc-update / rc-service;
  * pkgmk/prt-get configuration paths (.conf, cache dirs, /var/lib/pkg) move to
    their scratchpkg locations.

    python3 scripts/migrate-scripts-to-scratchpkg.py --dry-run
    python3 scripts/migrate-scripts-to-scratchpkg.py
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

SKIP = {
    "bootstrap.sh",
    "scripts/migrate-bootstrap-to-scratchpkg.py",
    "scripts/fix-bootstrap-remainder.py",
    "scripts/pkgfile-to-spkgbuild.py",
    "scripts/normalize-port-names.py",
    "scripts/purge-systemd.py",
    "scripts/migrate-scripts-to-scratchpkg.py",
}

TARGETS = (
    "scripts/*.sh",
    "scripts/*.py",
    "iso-builder/*.sh",
    "iso-builder/liverootfs/root/*.sh",
    "iso-builder/liverootfs/usr/bin/stormfs-installer",
    "*.sh",
    "*.py",
)

# Order matters: longer, more specific commands first.
REPLACEMENTS: list[tuple[str, str]] = [
    # prt-get family
    (r"\bprt-get\s+depinst\b", "scratch install -y"),
    (r"\bprt-get\s+sysup\b", "scratch sysup -y"),
    (r"\bprt-get\s+update\b", "scratch sysup -y"),
    (r"\bprt-get\s+install\b", "scratch install -y"),
    (r"\bprt-get\s+remove\b", "scratch remove -y"),
    (r"\bprt-get\s+search\b", "scratch search"),
    (r"\bprt-get\s+isinst\b", "scratch isinstalled"),
    (r"\bprt-get\s+info\b", "scratch info"),
    (r"\bprt-get\s+listinst\b", "scratch installed"),
    (r"\bprt-get\s+cat\b", "scratch cat"),
    (r"\bprt-get\b", "scratch"),
    # pkgutils family
    (r"\bpkginfo\s+-li\b", "scratch files"),
    (r"\bpkginfo\s+-i\b", "scratch installed"),
    (r"\bpkginfo\s+-o\b", "scratch provide"),
    (r"\bpkginfo\b", "scratch info"),
    (r"\bpkgrm\b", "scratch remove -y"),
    (r"\bpkgmk\b", "pkgbuild"),
    (r"\bpkgadd\b", "pkgadd"),
    # pacman family
    (r"\bpacman\s+-Syu\b", "scratch sysup -y"),
    (r"\bpacman\s+-S\b", "scratch install -y"),
    (r"\bpacman\s+-Rns?\b", "scratch remove -y"),
    (r"\bpacman\b", "scratch"),
    (r"\bmakepkg\b", "pkgbuild"),
    (r"\brepo-add\b", "scratch"),
    # systemd service management
    (r"\bsystemctl\s+enable\s+([\w@.-]+)", r"rc-update add \1 default"),
    (r"\bsystemctl\s+disable\s+([\w@.-]+)", r"rc-update del \1 default"),
    (r"\bsystemctl\s+start\s+([\w@.-]+)", r"rc-service \1 start"),
    (r"\bsystemctl\s+stop\s+([\w@.-]+)", r"rc-service \1 stop"),
    (r"\bsystemctl\s+restart\s+([\w@.-]+)", r"rc-service \1 restart"),
    (r"\bsystemctl\s+is-enabled\s+([\w@.-]+)", r"rc-update show | grep \1"),
    (r"\bsystemctl\s+set-default\s+graphical\.target", "rc-update add display-manager default"),
    (r"\bsystemctl\s+daemon-reload\b", "true"),
    # paths and configuration
    (r"/var/lib/pkg/db", "/var/lib/scratchpkg/db"),
    (r"/var/lib/pkg\b", "/var/lib/scratchpkg"),
    (r"/var/lib/pkgmk\b", "/var/lib/scratchpkg"),
    (r"/var/cache/pkg/", "/var/cache/scratchpkg/"),
    (r"/etc/pkgmk\.conf", "/etc/scratchpkg.conf"),
    (r"/etc/prt-get\.conf", "/etc/scratchpkg.repo"),
    (r"/etc/prtdir\.conf", "/etc/scratchpkg.repo"),
    (r"\bpkgmk\.conf\b", "scratchpkg.conf"),
    (r"\bprt-get\.conf\b", "scratchpkg.repo"),
]


def migrate(text: str) -> tuple[str, int]:
    changes = 0
    for pattern, replacement in REPLACEMENTS:
        text, count = re.subn(pattern, replacement, text)
        changes += count
    return text, changes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    seen: set[str] = set()
    files: list[Path] = []
    for pattern in TARGETS:
        for path in Path(".").glob(pattern):
            key = str(path).replace("\\", "/")
            if not path.is_file() or key in SKIP or key in seen:
                continue
            seen.add(key)
            files.append(path)

    changed = 0
    for path in sorted(files):
        text = path.read_text(encoding="utf-8", errors="replace")
        new_text, changes = migrate(text)
        if not changes:
            continue
        changed += 1
        print(f"updated: {path} ({changes} substitutions)")
        if not args.dry_run:
            path.write_text(new_text, encoding="utf-8", newline="\n")

    print(f"\nfiles changed: {changed}")

    leftovers: list[str] = []
    for path in sorted(files):
        text = path.read_text(encoding="utf-8", errors="replace")
        for number, line in enumerate(text.splitlines(), 1):
            if re.search(r"prt-get|pkginfo|pkgmk|pacman|systemctl|makepkg|repo-add", line):
                leftovers.append(f"{path}:{number}: {line.strip()[:100]}")
    if leftovers:
        print(f"leftovers needing review ({len(leftovers)}):")
        for item in leftovers[:40]:
            print(f"  {item}")
    else:
        print("no legacy package-manager or systemd commands remain")
    if args.dry_run:
        print("\n(dry run: nothing written)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
