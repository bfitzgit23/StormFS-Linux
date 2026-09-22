#!/usr/bin/env python3
"""Verify every maintained Pkgfile evaluates and every local source companion exists."""
from pathlib import Path
import importlib.util
import sys

ROOT = Path(__file__).resolve().parents[2]
UPDATER = ROOT / "scripts" / "bfs-maintained-port-updater.py"
spec = importlib.util.spec_from_file_location("bfs_updater_companion_audit", UPDATER)
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
assert spec.loader is not None
spec.loader.exec_module(mod)

missing = []
errors = []
checked = local = remote = 0
for pkgfile in sorted((ROOT / "ports").glob("*/*/Pkgfile")):
    checked += 1
    try:
        meta = mod.eval_meta(pkgfile)
    except Exception as exc:
        errors.append((pkgfile.relative_to(ROOT), str(exc)))
        continue
    for src in meta.sources:
        if mod.source_url(src):
            remote += 1
            continue
        local += 1
        filename = mod.source_filename(src)
        if not (pkgfile.parent / filename).exists():
            missing.append((pkgfile.relative_to(ROOT), src, filename))

if errors or missing:
    for row in errors:
        print("ERROR", *row, sep="\t", file=sys.stderr)
    for row in missing:
        print("MISSING", *row, sep="\t", file=sys.stderr)
    raise SystemExit(1)

print(
    f"source companion regression: PASS ({checked} Pkgfiles; "
    f"{remote} remote sources; {local} local companions; 0 missing)"
)
