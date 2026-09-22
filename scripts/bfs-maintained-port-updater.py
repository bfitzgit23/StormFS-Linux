#!/usr/bin/env python3
"""Transactional BFSOS maintained-port updater.

Consumes only verified UPDATE rows from checkupdate.py's TSV output.  The
checker remains read-only; this program owns reviewable source edits.

Safety rules:
- never update a port if its current version no longer matches the audit row;
- reset release=1 only when version changes;
- inventory every source= companion before writing;
- reject missing local companions; version-named patches are applicability-tested rather than rejected by filename alone;
- vendor remote patch/diff URLs (including aliased, redirected, and small suffix-less patch endpoints) before the Pkgfile edit;
- reject HTML/empty/non-patch patch downloads and same-name collisions;
- validate auto-applied patches against the proposed source tree before commit;
- write the Pkgfile last so a failed patch/source transaction cannot leave a
  version bump without its required companion files.

The default is a dry run.  Use --apply only after reviewing the proposed set.
"""
from __future__ import annotations

import argparse
import csv
import dataclasses
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
REMOTE = ("http://", "https://", "ftp://")
PATCH_SUFFIXES = (".patch", ".diff", ".patch.gz", ".diff.gz", ".patch.xz", ".diff.xz", ".patch.bz2", ".diff.bz2")
ARCHIVE_SUFFIXES = (".tar", ".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst", ".tgz", ".tbz2", ".txz", ".zip")


@dataclasses.dataclass
class AuditRow:
    status: str
    port: str
    current: str
    latest: str
    provider: str
    reason: str
    source: str


@dataclasses.dataclass
class Meta:
    name: str
    version: str
    release: str
    patch_opt: str
    skip_patch: bool
    auto_patch: bool
    sources: list[str]


class UpdateError(RuntimeError):
    pass


def run(cmd: list[str], *, cwd: Path | None = None, capture: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        check=False,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        env={**os.environ, "LC_ALL": "C"},
    )


def eval_meta(pkgfile: Path) -> Meta:
    script = r'''
set +u
source "$1" >/dev/null 2>&1 || exit 31
printf '%s\0%s\0%s\0%s\0%s\0%s\0' \
  "${name-}" "${version-}" "${release-}" "${patch_opt--p1}" \
  "${skip_patch-}" "${PKGMK_AUTO_PATCH-yes}"
if declare -p source >/dev/null 2>&1; then
  if declare -p source 2>/dev/null | grep -q '^declare -a'; then
    printf '%s\0' "${source[@]}"
  else
    printf '%s\0' "${source}"
  fi
fi
'''
    cp = subprocess.run(
        ["bash", "--noprofile", "--norc", "-c", script, "bfs-updater", str(pkgfile)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    if cp.returncode != 0:
        raise UpdateError(f"Pkgfile evaluation failed ({cp.returncode}): {pkgfile}")
    fields = cp.stdout.decode("utf-8", "replace").split("\0")
    if fields and fields[-1] == "":
        fields.pop()
    if len(fields) < 6:
        raise UpdateError(f"Pkgfile did not define required metadata: {pkgfile}")
    name, version, release, patch_opt, skip_patch, auto_patch, *sources = fields
    return Meta(name, version, release, patch_opt or "-p1", bool(skip_patch), auto_patch != "no", sources)


def source_url(src: str) -> str | None:
    src = src.strip()
    if "::" in src:
        _, rhs = src.split("::", 1)
        if rhs.startswith(REMOTE):
            return rhs
    if src.startswith(REMOTE):
        return src
    return None


def source_filename(src: str) -> str:
    src = src.strip()
    if "::" in src:
        lhs, rhs = src.split("::", 1)
        if rhs.startswith(REMOTE):
            return lhs
    url = source_url(src)
    if url:
        return Path(urlsplit(url).path).name
    return Path(src).name


def is_patch_name(name: str) -> bool:
    low = name.lower().split("?", 1)[0]
    return low.endswith(PATCH_SUFFIXES)


def is_archive_name(name: str) -> bool:
    low = name.lower().split("?", 1)[0]
    return low.endswith(ARCHIVE_SUFFIXES)


def looks_like_patch(path: Path) -> bool:
    if path.stat().st_size == 0:
        return False
    raw = path.read_bytes()[:65536]
    low = raw.lstrip().lower()
    if low.startswith((b"<!doctype html", b"<html", b"<?xml")):
        return False
    if path.name.endswith((".gz", ".xz", ".bz2")):
        # Compressed patch validation occurs after decompression.
        return True
    text = raw.decode("utf-8", "replace")
    return bool(re.search(r"(?m)^(diff --git |--- [^\n]+\n\+\+\+ |Index: )", text))


def rewrite_version_release(text: str, old: str, new: str) -> str:
    vm = re.search(r"(?m)^version=(.*)$", text)
    rm = re.search(r"(?m)^release=(.*)$", text)
    if not vm or not rm:
        raise UpdateError("Pkgfile must contain simple top-level version= and release= assignments")
    current_literal = vm.group(1).strip().strip("'\"")
    if current_literal != old:
        raise UpdateError(f"Pkgfile version assignment is {current_literal!r}, expected audit current {old!r}")
    text = text[:vm.start()] + f"version={new}" + text[vm.end():]
    # find release again because offsets changed
    rm = re.search(r"(?m)^release=(.*)$", text)
    assert rm
    text = text[:rm.start()] + "release=1" + text[rm.end():]
    return text


def remote_source_raw_tokens(text: str) -> list[str]:
    """Return literal remote source tokens in source-like shell text."""
    rx = re.compile(r'''(?P<tok>(?:[^\s()"']+::)?https?://[^\s()"']+)''')
    return [m.group("tok") for m in rx.finditer(text)]


def remote_patch_raw_tokens(text: str) -> list[str]:
    """Recognize explicit patch URLs and alias.patch::suffix-less endpoints."""
    tokens: list[str] = []
    for tok in remote_source_raw_tokens(text):
        if "::" in tok:
            alias, rhs = tok.split("::", 1)
            if is_patch_name(alias) or is_patch_name(Path(urlsplit(rhs).path).name):
                tokens.append(tok)
        else:
            if is_patch_name(Path(urlsplit(tok).path).name):
                tokens.append(tok)
    return tokens


def remote_probe_raw_tokens(text: str) -> list[str]:
    """Return unclassified remote companions whose content may reveal a patch."""
    explicit = set(remote_patch_raw_tokens(text))
    result: list[str] = []
    for tok in remote_source_raw_tokens(text):
        if tok in explicit:
            continue
        name = tok.split("::", 1)[0] if "::" in tok else Path(urlsplit(tok).path).name
        if name and is_archive_name(name):
            continue
        result.append(tok)
    return result


def expand_token_with_pkgfile(token: str, staged_pkgfile: Path) -> str:
    # Let bash expand the same $name/$version expressions used by the Pkgfile.
    script = r'''
set +u
source "$1" >/dev/null 2>&1 || exit 31
raw=$2
eval "printf '%s' \"$raw\""
'''
    cp = run(["bash", "--noprofile", "--norc", "-c", script, "bfs-updater", str(staged_pkgfile), token], capture=True)
    if cp.returncode != 0:
        raise UpdateError(f"could not expand source token: {token}")
    return cp.stdout.strip()


def curl_download(url: str, dest: Path, timeout: int, *, max_filesize: int | None = None) -> str:
    tmp = dest.with_name(dest.name + ".part")
    tmp.unlink(missing_ok=True)
    cmd = [
        "curl", "--fail", "--location", "--silent", "--show-error",
        "--connect-timeout", "10", "--max-time", str(timeout),
        "--retry", "2", "--retry-delay", "1",
    ]
    if max_filesize is not None:
        cmd += ["--max-filesize", str(max_filesize)]
    cmd += ["--output", str(tmp), "--write-out", "%{url_effective}", url]
    cp = run(cmd, capture=True)
    if cp.returncode != 0:
        tmp.unlink(missing_ok=True)
        raise UpdateError(f"download failed: {url}: {cp.stderr.strip()}")
    if not tmp.exists() or tmp.stat().st_size == 0:
        tmp.unlink(missing_ok=True)
        raise UpdateError(f"download was empty: {url}")
    os.replace(tmp, dest)
    return cp.stdout.strip() or url


def vendor_remote_patches(staged_dir: Path, old_text: str, new_text: str, timeout: int) -> tuple[str, list[str]]:
    pkgfile = staged_dir / "Pkgfile"
    pkgfile.write_text(new_text)
    provenance: list[str] = []
    explicit = set(remote_patch_raw_tokens(new_text))
    candidates = remote_source_raw_tokens(new_text)

    for raw in candidates:
        is_explicit = raw in explicit
        expanded = expand_token_with_pkgfile(raw, pkgfile)
        if "::" in expanded:
            alias, url = expanded.split("::", 1)
            hinted_name = alias
        else:
            url = expanded
            hinted_name = Path(urlsplit(url).path).name

        if not is_explicit and hinted_name and is_archive_name(hinted_name):
            continue

        with tempfile.TemporaryDirectory(prefix="bfs-patch-fetch-") as td:
            td_path = Path(td)
            probe_name = hinted_name or "remote-source"
            downloaded = td_path / Path(probe_name).name
            try:
                effective = curl_download(
                    url, downloaded, timeout,
                    max_filesize=None if is_explicit else 16 * 1024 * 1024,
                )
            except UpdateError:
                if is_explicit:
                    raise
                continue

            effective_name = Path(urlsplit(effective).path).name
            content_patch = looks_like_patch(downloaded)
            final_patch = is_patch_name(effective_name)
            alias_patch = bool("::" in expanded and is_patch_name(hinted_name))
            if not (content_patch or final_patch or alias_patch):
                if is_explicit:
                    raise UpdateError(f"remote patch does not look like a patch/diff: {url}")
                continue

            local_name = hinted_name if is_patch_name(hinted_name) else effective_name
            if not is_patch_name(local_name):
                base = Path(hinted_name or effective_name or "upstream-fix").name
                local_name = f"{base}.patch"
            if not local_name or "/" in local_name or local_name in (".", ".."):
                raise UpdateError(f"unsafe patch filename from {expanded}")

            dest = staged_dir / local_name
            if dest.exists():
                if hashlib.sha256(dest.read_bytes()).digest() != hashlib.sha256(downloaded.read_bytes()).digest():
                    raise UpdateError(f"patch collision: local {local_name} differs from {url}")
            else:
                shutil.copy2(downloaded, dest)

        new_text = new_text.replace(raw, local_name, 1)
        provenance.append(f"# BFSOS vendored patch provenance: {local_name} <- {url}")
        pkgfile.write_text(new_text)

    if provenance:
        fresh = [line for line in provenance if line not in new_text]
        if fresh:
            marker = "\n".join(fresh) + "\n"
            m = re.search(r"(?m)^source=", new_text)
            if not m:
                raise UpdateError("Pkgfile has no source= assignment for provenance insertion")
            new_text = new_text[:m.start()] + marker + new_text[m.start():]
    pkgfile.write_text(new_text)
    return new_text, provenance


def inventory_local_companions(meta: Meta, port_dir: Path, old: str) -> list[str]:
    problems: list[str] = []
    for src in meta.sources:
        if source_url(src):
            continue
        name = source_filename(src)
        if not name:
            continue
        path = port_dir / name
        if not path.exists():
            problems.append(f"missing local source companion: {name}")
        if old and old in name and not is_patch_name(name):
            problems.append(f"old-version-named local companion requires review: {name}")
    return problems


def versioned_local_patches(meta: Meta, old: str) -> list[str]:
    return [
        source_filename(src) for src in meta.sources
        if not source_url(src) and is_patch_name(source_filename(src)) and old and old in source_filename(src)
    ]


def decompress_patch(path: Path, out: Path) -> Path:
    if path.name.endswith(".gz"):
        tool = ["gzip", "-dc"]
    elif path.name.endswith(".xz"):
        tool = ["xz", "-dc"]
    elif path.name.endswith(".bz2"):
        tool = ["bzip2", "-dc"]
    else:
        return path
    cp = subprocess.run(tool + [str(path)], stdout=out.open("wb"), stderr=subprocess.PIPE)
    if cp.returncode != 0:
        raise UpdateError(f"cannot decompress patch {path.name}")
    return out


def validate_auto_patch_set(staged_dir: Path, meta: Meta, timeout: int) -> None:
    patch_sources = [src for src in meta.sources if is_patch_name(source_filename(src))]
    if not patch_sources:
        return
    if meta.skip_patch or not meta.auto_patch:
        raise UpdateError("patch-bearing port disables pkgmk auto-patching; manual patch flow requires maintainer review")

    archives = [src for src in meta.sources if is_archive_name(source_filename(src))]
    if not archives:
        raise UpdateError("cannot validate patches: no source archive identified")
    archive_src = archives[0]
    archive_name = source_filename(archive_src)

    with tempfile.TemporaryDirectory(prefix="bfs-patch-validate-") as td_s:
        td = Path(td_s)
        archive = td / archive_name
        url = source_url(archive_src)
        if url:
            curl_download(url, archive, timeout)
        else:
            src = staged_dir / archive_name
            if not src.exists():
                raise UpdateError(f"source archive missing: {archive_name}")
            shutil.copy2(src, archive)
        extract = td / "extract"
        extract.mkdir()
        cp = run(["bsdtar", "-xf", str(archive), "-C", str(extract)], capture=True)
        if cp.returncode != 0:
            raise UpdateError(f"cannot extract proposed source archive {archive_name}: {cp.stderr.strip()}")
        preferred = extract / f"{meta.name}-{meta.version}"
        if preferred.is_dir():
            srcdir = preferred
        else:
            dirs = [p for p in extract.iterdir() if p.is_dir()]
            if len(dirs) != 1:
                raise UpdateError("cannot identify one extracted source directory for patch validation")
            srcdir = dirs[0]

        patch_args = meta.patch_opt.split() if meta.patch_opt else ["-p1"]
        for idx, psrc in enumerate(patch_sources):
            p_name = source_filename(psrc)
            p_path = staged_dir / p_name
            p_url = source_url(psrc)
            if p_url:
                # This is only expected for suffix-less remote patch endpoints;
                # ordinary URLs have already been vendored.
                p_path = td / p_name
                curl_download(p_url, p_path, timeout)
            if not p_path.exists():
                raise UpdateError(f"patch missing for validation: {p_name}")
            plain = decompress_patch(p_path, td / f"patch-{idx}.diff")
            cp = run(["patch", "-t", *patch_args, "-i", str(plain)], cwd=srcdir, capture=True)
            if cp.returncode != 0:
                detail = (cp.stderr or cp.stdout).strip().splitlines()
                tail = detail[-1] if detail else "patch command failed"
                raise UpdateError(f"patch does not apply to {meta.name}-{meta.version}: {p_name}: {tail}")


def read_rows(path: Path) -> list[AuditRow]:
    with path.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    required = {"status", "port", "current", "latest", "provider", "reason", "source"}
    if not rows and path.stat().st_size:
        # Header-only is valid.
        return []
    if rows and not required.issubset(rows[0]):
        raise UpdateError("audit TSV does not have the expected checker columns")
    return [AuditRow(**{k: r.get(k, "") for k in required}) for r in rows]


def update_one(row: AuditRow, apply: bool, timeout: int, validate_patches: bool) -> str:
    if row.status != "UPDATE" or not row.latest:
        raise UpdateError("row is not a verified UPDATE")
    port_dir = ROOT / "ports" / row.port
    pkgfile = port_dir / "Pkgfile"
    if not pkgfile.is_file():
        raise UpdateError(f"port not found: {row.port}")
    before = eval_meta(pkgfile)
    if before.version != row.current:
        raise UpdateError(f"stale audit row: tree has {before.version}, audit expected {row.current}")

    with tempfile.TemporaryDirectory(prefix=f"bfs-update-{before.name}-") as td_s:
        staged = Path(td_s) / before.name
        shutil.copytree(port_dir, staged, symlinks=True)
        staged_pkg = staged / "Pkgfile"
        old_text = staged_pkg.read_text()
        new_text = rewrite_version_release(old_text, row.current, row.latest)
        staged_pkg.write_text(new_text)

        proposed = eval_meta(staged_pkg)
        problems = inventory_local_companions(proposed, staged, row.current)
        if problems:
            raise UpdateError("; ".join(problems))

        # Vendor explicit patch URLs, redirected patch endpoints, and small
        # suffix-less remote companions whose downloaded content is a patch.
        explicit_remote_patches = remote_patch_raw_tokens(new_text)
        probe_candidates = remote_probe_raw_tokens(new_text)
        if explicit_remote_patches and not apply:
            return f"WOULD-REVIEW-PATCHES {row.port} {row.current} -> {row.latest} (remote patch vendoring requires --apply/network)"
        if apply and (explicit_remote_patches or probe_candidates):
            new_text, _ = vendor_remote_patches(staged, old_text, new_text, timeout)
            staged_pkg.write_text(new_text)
            proposed = eval_meta(staged_pkg)

        versioned_patches = versioned_local_patches(proposed, row.current)
        if validate_patches and any(is_patch_name(source_filename(s)) for s in proposed.sources):
            if not apply:
                return f"WOULD-VALIDATE-PATCHES {row.port} {row.current} -> {row.latest}"
            validate_auto_patch_set(staged, proposed, timeout)

        if not apply:
            suffix = f"; versioned patches require applicability validation: {','.join(versioned_patches)}" if versioned_patches else ""
            return f"WOULD-UPDATE {row.port} {row.current} -> {row.latest} release=1{suffix}"

        # Commit newly vendored companion files first and Pkgfile last.
        for child in staged.iterdir():
            if child.name == "Pkgfile":
                continue
            original = port_dir / child.name
            if original.exists():
                continue
            if child.is_file():
                shutil.copy2(child, original)
            elif child.is_dir():
                shutil.copytree(child, original)
        tmp_pkg = pkgfile.with_name("Pkgfile.bfs-update-tmp")
        tmp_pkg.write_text(staged_pkg.read_text())
        os.replace(tmp_pkg, pkgfile)
        return f"UPDATED {row.port} {row.current} -> {row.latest} release=1"


def main() -> int:
    ap = argparse.ArgumentParser(description="Apply verified BFSOS maintained-port update rows transactionally")
    ap.add_argument("tsv", type=Path, help="TSV emitted by checkupdate.py / bfs-maintained-port-version-audit.sh")
    ap.add_argument("ports", nargs="*", help="optional rel paths or package basenames to select")
    ap.add_argument("--apply", action="store_true", help="write reviewed updates (default: dry run)")
    ap.add_argument("--timeout", type=int, default=180, help="per-source download timeout for patch validation")
    ap.add_argument("--no-patch-validation", action="store_true", help="do not validate patch-bearing updates (not recommended)")
    ns = ap.parse_args()

    rows = [r for r in read_rows(ns.tsv) if r.status == "UPDATE"]
    if ns.ports:
        wanted = set(ns.ports)
        rows = [r for r in rows if r.port in wanted or r.port.rsplit("/", 1)[-1] in wanted]
    if not rows:
        print("No verified UPDATE rows selected.")
        return 0

    failures = 0
    for row in sorted(rows, key=lambda r: r.port):
        try:
            print(update_one(row, ns.apply, ns.timeout, not ns.no_patch_validation))
        except UpdateError as exc:
            failures += 1
            print(f"NEEDS-REVIEW {row.port} {row.current} -> {row.latest}: {exc}", file=sys.stderr)
    print(f"Summary: selected={len(rows)} failures/review={failures} mode={'apply' if ns.apply else 'dry-run'}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
