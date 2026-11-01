#!/usr/bin/env python3
"""compat-32 port consistency check for the scratchpkg tree.

Every 32-bit compat port must

  * live in a directory whose name ends in ``-32`` and match its ``name=``,
  * carry the ``.32bit`` marker that the sync tooling keys on,
  * build through the shared ``bfs_compat32`` environment so it targets i686 and
    stages into /usr/lib32,
  * validate its payload (``bfs_compat32_validate``) so 64-bit librarydirs are
    never polluted,
  * parse as shell, and never reintroduce a CRUX ``pkg_build`` hook.
"""

from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
COMPAT = ROOT / "ports" / "compat-32"

recipes = sorted(COMPAT.glob("*/spkgbuild"))
assert recipes, f"no compat-32 recipes found under {COMPAT}"

failures: list[str] = []
for recipe in recipes:
    port = recipe.parent
    name = port.name
    text = recipe.read_text(encoding="utf-8", errors="replace")

    if not name.endswith("-32"):
        failures.append(f"{name}: directory name does not end in -32")
    if not (port / ".32bit").is_file():
        failures.append(f"{name}: missing .32bit marker")
    if not re.search(rf"(?m)^name={re.escape(name)}$", text):
        failures.append(f"{name}: name= does not match the directory")
    if "bfs_compat32" not in text:
        failures.append(f"{name}: build does not use the shared bfs_compat32 environment")
    if "bfs_compat32_validate" not in text:
        failures.append(f"{name}: build does not validate the compat-32 payload")
    if re.search(r"(?m)^pkg_build\s*\(\s*\)", text):
        failures.append(f"{name}: CRUX pkg_build hook must be merged into build()")

    check = subprocess.run(["bash", "-n", str(recipe)], capture_output=True, text=True)
    if check.returncode != 0:
        failures.append(f"{name}: shell syntax error: {check.stderr.strip()}")

if failures:
    print(f"compat-32 consistency: FAIL ({len(failures)} problems)")
    for failure in failures:
        print(f"  {failure}")
    raise SystemExit(1)

print(f"compat-32 consistency: PASS ({len(recipes)} ports)")
