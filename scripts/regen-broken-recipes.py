#!/usr/bin/env python3
"""Regenerate recipes that fail ``bash -n`` from their tracked Pkgfiles.

The plasma recipes were damaged by a bad repair heuristic, and a handful of
restored recipes were mangled by the converter's handling of a quoted
``build_opt`` that spans lines.  Both are recovered the same deterministic way:

1. copy the git-tracked ``Pkgfile`` for the port into a scratch tree,
2. run the real converter over that scratch tree,
3. take its ``spkgbuild`` - and if the converter's own output is still invalid
   bash, splice the verbatim ``build_opt`` / ``source`` blocks from the Pkgfile
   over the broken ones.
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

ENCODING = "utf-8"
ERRORS = "surrogateescape"
SCRATCH = Path(".regen-scratch")
STOP = re.compile(r"^(?:[A-Za-z_][A-Za-z0-9_]*=|build\s*\(\))")


def read(p: Path) -> str:
    return p.read_text(encoding=ENCODING, errors=ERRORS)


def write(p: Path, s: str) -> None:
    p.write_text(s, encoding=ENCODING, errors=ERRORS, newline="\n")


def parses(p: Path) -> bool:
    return subprocess.run(["bash", "-n", str(p)], capture_output=True).returncode == 0


def block_end(lines: list[str], start: int) -> int:
    """Index of the last line of an assignment starting at ``start``."""
    first = lines[start]
    if re.match(r"^source=\(", first):
        depth = first.count("(") - first.count(")")
        i = start
        while depth > 0 and i + 1 < len(lines):
            i += 1
            depth += lines[i].count("(") - lines[i].count(")")
        return i
    i = start
    quotes = first.count('"')
    while i + 1 < len(lines):
        if quotes % 2 == 0 and not lines[i].rstrip().endswith("\\"):
            break
        if STOP.match(lines[i + 1]):
            break
        i += 1
        quotes += lines[i].count('"')
    return i


def find(lines: list[str], key: str) -> tuple[int, int] | None:
    for i, line in enumerate(lines):
        if re.match(rf"^{key}=", line):
            return i, block_end(lines, i)
    return None


def splice(rec: str, pkg: str) -> str:
    pkg_lines = pkg.split("\n")
    rec_lines = rec.split("\n")
    edits = []
    for key in ("build_opt", "source"):
        src = find(pkg_lines, key)
        dst = find(rec_lines, key)
        if not src or not dst:
            continue
        block = pkg_lines[src[0]:src[1] + 1]
        if key == "source":
            joined = " ".join(l.strip() for l in block)
            joined = joined[len("source=("):] if joined.startswith("source=(") else joined.split("=", 1)[1]
            if joined.endswith(")"):
                joined = joined[:-1]
            block = ['source="' + " ".join(joined.split()) + '"']
        edits.append((dst[0], dst[1], block))
    for start, end, block in sorted(edits, key=lambda e: e[0], reverse=True):
        rec_lines[start:end + 1] = block
    return "\n".join(rec_lines)


def main() -> int:
    failing = [p for p in sorted(Path("ports").rglob("spkgbuild")) if not parses(p)]
    print(f"failing recipes: {len(failing)}")
    if not failing:
        return 0

    if SCRATCH.exists():
        shutil.rmtree(SCRATCH)
    staged = []
    pkg_text: dict[Path, str] = {}
    for rec in failing:
        rel = rec.parent.relative_to("ports")
        cp = subprocess.run(
            ["git", "show", f"HEAD:ports/{rel.as_posix()}/Pkgfile"],
            capture_output=True, text=True, encoding=ENCODING, errors=ERRORS,
        )
        if cp.returncode != 0 or not cp.stdout.strip():
            print(f"  SKIP {rel}: no tracked Pkgfile")
            continue
        target = SCRATCH / rel
        target.mkdir(parents=True, exist_ok=True)
        write(target / "Pkgfile", cp.stdout)
        pkg_text[rel] = cp.stdout
        staged.append(rel)

    if not staged:
        return 0
    cp = subprocess.run([sys.executable, "scripts/pkgfile-to-spkgbuild.py", str(SCRATCH)],
                        capture_output=True, text=True)
    print(cp.stdout.strip().splitlines()[-2:] if cp.stdout else cp.stderr[-400:])

    fixed = spliced = 0
    for rel in staged:
        new = SCRATCH / rel / "spkgbuild"
        if not new.is_file():
            print(f"  FAIL {rel}: converter produced nothing")
            continue
        text = read(new)
        if not parses(new):
            # the converter unlinks the Pkgfile, so splice from the saved copy
            text = splice(text, pkg_text[rel])
            write(new, text)
            spliced += 1
            if not parses(new):
                print(f"  STILL BROKEN {rel}")
                continue
        write(Path("ports") / rel / "spkgbuild", text)
        fixed += 1
    print(f"regenerated {fixed} recipes ({spliced} needed a build_opt/source splice)")

    remaining = [p for p in sorted(Path("ports").rglob("spkgbuild")) if not parses(p)]
    print(f"remaining syntax failures: {len(remaining)}")
    for p in remaining[:10]:
        print(" ", p)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
