#!/usr/bin/env python3
"""Convert CRUX-style ``Pkgfile`` recipes into scratchpkg ``spkgbuild`` recipes.

This is the tool used to migrate the port tree (kept for reproducibility):

    python3 scripts/pkgfile-to-spkgbuild.py --dry-run
    python3 scripts/pkgfile-to-spkgbuild.py

Mapping
-------
* ``# Description:`` / ``# URL:`` / ``# Maintainer:`` become the spkgbuild
  header comments ``# description :`` / ``# homepage :`` / ``# maintainer :``.
* ``# Depends on:`` / ``# Depends:`` become a ``depends`` file, one entry per
  line.  ``# Optional:`` is documentation only and stays a comment.
* ``source=( ... )`` becomes the space separated ``source="..."`` form.
* Hooks merge the way the retired pkgmk extension ran them:

      patch sources -> pre_build -> (pkg_build | detected build) -> post_build

  An explicit ``pkg_build()`` replaces the automatic build; recipes with
  neither ``build()`` nor ``pkg_build()`` call the shared ``bfs_autobuild``
  helper, which reproduces the old build_opt driven detection.
* ``*-32`` recipes get the ``bfs_compat32`` environment.
* ``.footprint``, ``.md5sum``, ``.signature`` and ``Pkgfile.before-*`` backups
  are deleted; scratchpkg records blake3 sums in ``.checksums``.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

ARCHIVE_RE = re.compile(r"\.(tar|tgz|tbz2|txz|zst|tzst|lz4|zip|rpm|7z)(\.|$)", re.I)
PATCH_RE = re.compile(r"\.(patch|diff)(\.(gz|xz|bz2))?$", re.I)
META = (
    ("description", re.compile(r"^#\s*description\s*:\s?(.*)$", re.I)),
    ("homepage", re.compile(r"^#\s*url\s*:\s?(.*)$", re.I)),
    ("maintainer", re.compile(r"^#\s*maintainer\s*:\s?(.*)$", re.I)),
    ("depends", re.compile(r"^#\s*depends(?:\s+on)?\s*:\s?(.*)$", re.I)),
    ("optional", re.compile(r"^#\s*optional(?:\s+depends)?\s*:\s?(.*)$", re.I)),
)
FUNC_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{")
ASSIGN_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$")
OBSOLETE = (".footprint", ".md5sum", ".md5sums", ".signature", ".signatures",
            ".httpup-urlinfo", ".pkgfiles", "REPO")
HELPER = "/usr/share/bfsos/spkgbuild.helper"
PATCH_LOOP = (
    "\t# Apply patch sources; pkgbuild does this automatically.",
    '\tfor _p in "$SRC"/*.patch "$SRC"/*.diff; do',
    '\t\t[ -f "$_p" ] || continue',
    '\t\tpatch -t "${patch_opt:--p1}" -i "$_p" || return 1',
    "\tdone",
)


def tokens(block: str) -> list[str]:
    out = []
    for raw in block.splitlines():
        line = raw.split(" #", 1)[0].strip()
        if not line or line.startswith("#"):
            continue
        out.extend(m.group(1) or m.group(2) or m.group(3)
                   for m in re.finditer(r'"([^"]*)"|\'([^\']*)\'|(\S+)', line))
    return out


def parse(path: Path) -> dict:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    meta, vars_, funcs, order, source, i = {}, {}, {}, [], [], 0
    i = 0
    while i < len(lines) and not (FUNC_RE.match(lines[i]) or ASSIGN_RE.match(lines[i])):
        for key, pattern in META:
            m = pattern.match(lines[i])
            if m and m.group(1).strip():
                meta[key] = (meta.get(key, "") + " " + m.group(1).strip()).strip()
                break
        i += 1
    while i < len(lines) and not FUNC_RE.match(lines[i]):
        m = ASSIGN_RE.match(lines[i])
        if not m:
            i += 1
            continue
        key, rest = m.group(1), m.group(2)
        block, depth = [lines[i]], rest.count("(") - rest.count(")")
        if key == "source" and rest.lstrip().startswith("("):
            while depth > 0 and i + 1 < len(lines):
                i += 1
                block.append(lines[i])
                depth += lines[i].count("(") - lines[i].count(")")
            source.extend(tokens("\n".join(block)[
                "\n".join(block).find("(") + 1: "\n".join(block).rfind(")")]))
            i += 1
            continue
        while depth > 0 and i + 1 < len(lines):
            i += 1
            block.append(lines[i])
            depth += lines[i].count("(") - lines[i].count(")")
        vars_[key] = "\n".join(block)
        i += 1
    while i < len(lines):
        m = FUNC_RE.match(lines[i])
        if not m:
            i += 1
            continue
        name, block, depth = m.group(1), [lines[i]], lines[i].count("{") - lines[i].count("}")
        i += 1
        while i < len(lines) and depth > 0:
            block.append(lines[i])
            depth += lines[i].count("{") - lines[i].count("}")
            i += 1
        funcs[name] = "\n".join(block)
        order.append(name)
    return {"meta": meta, "vars": vars_, "funcs": funcs, "order": order, "source": source,
            "dir": path.parent}


def body(recipe: dict, hook: str) -> str:
    text = recipe["funcs"][hook]
    inner = text.split("\n", 1)[1] if "\n" in text else ""
    inner = inner.rstrip()
    if inner.endswith("}"):
        inner = inner[:-1]
    return inner.rstrip("\n")


def render(recipe: dict) -> tuple[str, list[str]]:
    meta, funcs, source, name = recipe["meta"], recipe["funcs"], recipe["source"], recipe["dir"].name
    compat = name.endswith("-32")
    out = [f"# description\t: {meta.get('description') or name + ' package'}"]
    if meta.get("homepage"):
        out.append(f"# homepage\t: {meta['homepage']}")
    out.append(f"# maintainer\t: {meta.get('maintainer') or 'StormFS maintainers'}")
    if meta.get("optional"):
        out.append(f"# optional\t: {meta['optional']}")
    out.append("")
    for key, block in recipe["vars"].items():
        if key != "source":
            out.append(block)
    joined = " ".join(source)
    out.append(f'source="{joined}"' if joined else 'source=""')
    out.append("")

    autobuild = "pkg_build" not in funcs and "build" not in funcs
    pre = body(recipe, "pre_build") if "pre_build" in funcs else ""
    post = body(recipe, "post_build") if autobuild and "post_build" in funcs else ""
    if autobuild:
        main = ""
    elif "pkg_build" in funcs:
        main = "\n".join(body(recipe, h) for h in ("pkg_build", "post_build") if h in funcs)
    else:
        main = body(recipe, "build")

    build = ["build() {"]
    if autobuild or compat:
        build.append(f"\t. {HELPER} || return 1")
    if compat:
        build.append("\tbfs_compat32")
    if any(ARCHIVE_RE.search(t) for t in source) and not re.search(r"^\s*cd\b[^\n]*\$name", main, re.M):
        build.append('\tcd "$name-$version" || return 1')
    if any(PATCH_RE.search(t.split("::")[-1]) for t in source) and "patch" not in main:
        build.extend(PATCH_LOOP)
    if pre:
        build.append(pre)
    if autobuild:
        build.append("\tbfs_autobuild")
        if post:
            build.append(post)
    else:
        build.append(main)
    if compat:
        build.append("\tbfs_compat32_validate || return 1")
    build.append("}")
    out.extend(build)
    for hook in recipe["order"]:
        if hook in ("build", "pkg_build", "pre_build", "post_build"):
            continue
        out.append("")
        out.append(funcs[hook])
    deps = [d for d in re.split(r"[\s,]+", meta.get("depends", "")) if d]
    return "\n".join(out).rstrip("\n") + "\n", deps


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ports", nargs="?", default="ports")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    root = Path(args.ports)
    files = sorted(root.glob("*/*/Pkgfile"))
    done = 0
    for path in files:
        text, deps = render(parse(path))
        if not args.dry_run:
            (path.parent / "spkgbuild").write_text(text, encoding="utf-8", newline="\n")
            if deps:
                (path.parent / "depends").write_text("\n".join(deps) + "\n",
                                                      encoding="utf-8", newline="\n")
            path.unlink()
            for stale in OBSOLETE:
                target = path.parent / stale
                if target.exists():
                    target.unlink()
            for backup in path.parent.glob("Pkgfile.before-*"):
                backup.unlink()
        done += 1
    print(f"Pkgfiles found : {len(files)}")
    print(f"converted      : {done}")
    if args.dry_run:
        print("(dry run: nothing written)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
