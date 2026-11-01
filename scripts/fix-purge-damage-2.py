#!/usr/bin/env python3
"""Second-stage repair for the four recipes the regex pass could not match.

These edits are line-oriented because each damaged region spans a trailing
backslash continuation that is easier to cut by position than by pattern.
Also drops port-local systemd payloads that nothing references any more.
"""
from __future__ import annotations

from pathlib import Path

MARKER = "# systemd integration removed"
SKIP_DIRS = {".git", "scratchpkg", "node_modules", "__pycache__"}


def load(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="surrogateescape")


def save(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", errors="surrogateescape", newline="\n")


def drop_span(path: Path, start_sub: str, end_pred) -> None:
    lines = load(path).splitlines(keepends=True)
    try:
        start = next(i for i, l in enumerate(lines) if start_sub in l)
    except StopIteration:
        print(f"INCOMPLETE  {path}\n    missed start: {start_sub!r}")
        return
    end = next((i for i in range(start, len(lines)) if end_pred(lines[i])), None)
    if end is None:
        print(f"INCOMPLETE  {path}\n    missed end after: {start_sub!r}")
        return
    del lines[start:end + 1]
    save(path, "".join(lines))
    print(f"ok          {path}  (-{end - start + 1} lines)")


def edit(path: Path, old: str, new: str, label: str) -> None:
    text = load(path)
    if old not in text:
        print(f"INCOMPLETE  {path}\n    missed: {label}")
        return
    save(path, text.replace(old, new, 1))
    print(f"ok          {path}  ({label})")


# gpm: the install -d continuation plus the whole gpm.service heredoc.
drop_span(
    Path("ports/opt/gpm/spkgbuild"),
    "install -d -m 0755 ",
    lambda l: l.strip() == "EOF",
)

# lightdm: "# BFSOS systemd service." through the heredoc terminator.
drop_span(
    Path("ports/opt/lightdm/spkgbuild"),
    "# BFSOS systemd service.",
    lambda l: l.strip() == "UNIT",
)

# samba: the stray empty continuation and the removed --with-systemddir flag.
drop_span(
    Path("ports/opt/samba/spkgbuild"),
    "        \\\n",
    lambda l: MARKER in l,
)

# aaa_filesystem: preset directory arg, preset install block, preset source entry.
drop_span(
    Path("ports/core/aaa_filesystem/spkgbuild"),
    f'{MARKER}: "$PKG/usr/lib/systemd/system-preset"',
    lambda l: MARKER in l,
)
drop_span(
    Path("ports/core/aaa_filesystem/spkgbuild"),
    "# BFSOS service policy: explicit distro/vendor presets win first",
    lambda l: "99-bfsos.preset" in l and MARKER in l,
)
edit(
    Path("ports/core/aaa_filesystem/spkgbuild"),
    " 99-bfsos.preset\"",
    "\"",
    "drop preset from source list",
)

# Port-local systemd payloads that nothing references any more.
STALE = [
    "ports/core/aaa_filesystem/99-bfsos.preset",
    "ports/core/bfs-kernel-maintenance/bfs-kernel-finalize.service",
    "ports/core/nftables/nftables.service",
    "ports/core/openssh/sshd.service",
    "ports/core/rsync/rsyncd.service",
    "ports/opt/cups/cups.path",
    "ports/opt/cups/cups.service",
    "ports/opt/cups/cups.socket",
    "ports/opt/wireplumber/90-bfsos-audio.preset",
]

print("\npayload cleanup:")
corpus: list[tuple[Path, str]] = []
for path in Path(".").rglob("*"):
    if not path.is_file() or any(part in SKIP_DIRS for part in path.parts):
        continue
    if path.suffix in {".png", ".jpg", ".gz", ".xz", ".zst", ".tar", ".pyc"}:
        continue
    try:
        corpus.append((path, path.read_text(encoding="utf-8", errors="ignore")))
    except OSError:
        continue

for rel in STALE:
    path = Path(rel)
    if not path.exists():
        print(f"  absent    {rel}")
        continue
    refs = [
        str(other) for other, body in corpus
        if path.name in body and other != path
    ]
    if refs:
        print(f"  KEPT      {rel}  referenced by {', '.join(refs[:3])}")
        continue
    path.unlink()
    print(f"  deleted   {rel}")

print("\nremaining purge markers:")
left = 0
for path in Path("ports").rglob("spkgbuild"):
    for line in load(path).splitlines():
        if MARKER in line:
            left += 1
            print(f"  {path}: {line.strip()[:90]}")
print(f"  total: {left}")
