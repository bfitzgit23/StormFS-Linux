#!/usr/bin/env python3
"""Add the `description` variable scratchpkg requires to every spkgbuild.

`pkgbuild` aborts with "'description' is empty!" when the variable is unset,
but the pkgmk -> spkgbuild migration only carried the CRUX-style
`# description : ...` header comment across.  This derives the variable from
that comment (falling back to the port name) and inserts it immediately before
the `name=` line, which is where the other required fields live.

Idempotent: recipes that already define `description=` are left untouched.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

COMMENT_RE = re.compile(r"^[ \t]*#[ \t]*description[ \t]*:[ \t]*(?P<text>.*\S)[ \t]*$", re.M)
NAME_RE = re.compile(r"^[ \t]*name=(?P<name>[^\s#]+)", re.M)
HAS_DESCRIPTION_RE = re.compile(r"^[ \t]*description=", re.M)


def quote(value: str) -> str:
    """Escape a description for a double-quoted shell assignment."""
    value = value.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$")
    value = value.replace("`", "\\`")
    return f'description="{value}"'


def rewrite(path: Path) -> str:
    """Return "fixed", "ok" or "skip" for one recipe."""
    text = path.read_text(encoding="utf-8")
    if HAS_DESCRIPTION_RE.search(text):
        return "ok"

    comment = COMMENT_RE.search(text)
    if comment:
        description = comment.group("text").strip()
    else:
        name = NAME_RE.search(text)
        if not name:
            return "skip"
        description = f"{name.group('name')} package"

    line = quote(description)
    name_line = NAME_RE.search(text)
    if name_line:
        start = name_line.start()
        text = f"{text[:start]}{line}\n{text[start:]}"
    else:
        text = f"{line}\n{text}"

    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    return "fixed"


def main() -> int:
    recipes = sorted(ROOT.glob("ports/*/*/spkgbuild"))
    if not recipes:
        print("ERROR: no spkgbuild files found", file=sys.stderr)
        return 1

    counts = {"fixed": 0, "ok": 0, "skip": 0}
    skipped = []
    for path in recipes:
        result = rewrite(path)
        counts[result] += 1
        if result == "skip":
            skipped.append(path)

    print(f"recipes: {len(recipes)}")
    print(f"  description added: {counts['fixed']}")
    print(f"  already present:   {counts['ok']}")
    print(f"  no name/comment:   {counts['skip']}")
    for path in skipped[:10]:
        print(f"    {path.relative_to(ROOT)}")

    return 0 if counts["skip"] == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
