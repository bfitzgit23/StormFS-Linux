#!/usr/bin/env python3
"""Remove systemd coupling from every port recipe.

The tree no longer ships systemd: init is OpenRC only.  Recipes that used to
build systemd integration, install unit files or enable services must stop
doing so, otherwise the packages would either fail to configure or install
host integration files for a service manager that is not present.

    python3 scripts/purge-systemd.py --dry-run
    python3 scripts/purge-systemd.py

What is rewritten
-----------------
* build options flip to their disabled form (-Dsystemd=enabled ->
  -Dsystemd=disabled, --with-systemd -> --without-systemd, ...);
* lines that install/copy/link unit files, tmpfiles, sysusers or presets into
  /usr/lib/systemd are dropped;
* service-manager commands (systemctl, systemd-tmpfiles, systemd-sysusers) are
  dropped from build scripts;
* ``systemd`` and ``systemd-*`` entries are removed from ``depends`` files.

Removal lines that *delete* systemd artefacts are kept on purpose, and anything
still mentioning systemd afterwards is reported for manual review.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

FLAGS = (
    (re.compile(r"-Dsystemd=enabled"), "-Dsystemd=disabled"),
    (re.compile(r"-Dsystemd=true"), "-Dsystemd=disabled"),
    (re.compile(r"-Dsystemd=yes"), "-Dsystemd=disabled"),
    (re.compile(r"-Dlibsystemd=true"), "-Dlibsystemd=false"),
    (re.compile(r"-Dsystemd-logind=true"), "-Dsystemd-logind=false"),
    (re.compile(r"-Dsystemd_logind=true"), "-Dsystemd_logind=false"),
    (re.compile(r"--with-systemd(?![-\w])"), "--without-systemd"),
    (re.compile(r"--enable-systemd(?![-\w])"), "--disable-systemd"),
    (re.compile(r"-Dsystemd-integration=true"), "-Dsystemd-integration=false"),
)

DROP_LINE = re.compile(
    r"^\s*(?:install|cp|mv|ln|systemctl|systemd-tmpfiles|systemd-sysusers)\b"
)
SYSTEMD_PATH = re.compile(r"/usr/(?:lib|share)/systemd|/etc/systemd|\.service\b|\.socket\b|\.timer\b")
DELETES = re.compile(r"^\s*(?:rm|find|rmdir)\b")


def rewrite_recipe(text: str) -> tuple[str, int]:
    changed = 0
    out: list[str] = []
    for line in text.splitlines():
        original = line
        for pattern, replacement in FLAGS:
            line = pattern.sub(replacement, line)
        if line != original:
            changed += 1

        if SYSTEMD_PATH.search(line):
            if DROP_LINE.match(line):
                changed += 1
                continue
            if re.match(r"^\s*#", line):
                out.append(line)
                continue
            if not DELETES.match(line):
                changed += 1
                out.append(f"\t# systemd integration removed: {line.strip()}")
                continue
        out.append(line)
    return "\n".join(out) + "\n", changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ports", nargs="?", default="ports")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--report-only", action="store_true")
    args = parser.parse_args()

    root = Path(args.ports)
    if not root.is_dir():
        print(f"ERROR: ports tree not found: {root}", file=sys.stderr)
        return 1

    recipes = 0
    deps_changed = 0
    for spkgbuild in sorted(root.glob("*/*/spkgbuild")):
        text = spkgbuild.read_text(encoding="utf-8", errors="replace")
        if "systemd" not in text:
            continue
        new_text, changed = rewrite_recipe(text)
        if not args.dry_run and not args.report_only and changed:
            spkgbuild.write_text(new_text, encoding="utf-8", newline="\n")
        recipes += 1

    for depends in sorted(root.glob("*/*/depends")):
        lines = depends.read_text(encoding="utf-8", errors="replace").splitlines()
        kept = [l for l in lines if l.strip() and not re.match(r"^systemd(-|$)", l.strip())]
        if kept != [l for l in lines if l.strip()]:
            deps_changed += 1
            if not args.dry_run and not args.report_only:
                depends.write_text("\n".join(kept) + "\n", encoding="utf-8", newline="\n")

    print(f"recipes mentioning systemd : {recipes}")
    print(f"depends files de-systemd'd : {deps_changed}")

    remaining: list[str] = []
    for spkgbuild in sorted(root.glob("*/*/spkgbuild")):
        for number, line in enumerate(
            spkgbuild.read_text(encoding="utf-8", errors="replace").splitlines(), 1
        ):
            if "systemd" in line and not line.lstrip().startswith("#"):
                remaining.append(f"{spkgbuild}:{number}: {line.strip()}")
    if remaining:
        print(f"\nmanual review needed ({len(remaining)} lines):")
        for item in remaining[:60]:
            print(f"  {item}")
        if len(remaining) > 60:
            print(f"  ... {len(remaining) - 60} more")
    else:
        print("\nno active systemd references remain in port recipes")
    if args.dry_run:
        print("\n(dry run: nothing written)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
