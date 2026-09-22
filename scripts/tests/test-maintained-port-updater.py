#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
P = ROOT / "scripts" / "bfs-maintained-port-updater.py"
spec = importlib.util.spec_from_file_location("bfs_updater", P)
mod = importlib.util.module_from_spec(spec)
sys.modules["bfs_updater"] = mod
assert spec.loader is not None
spec.loader.exec_module(mod)

sample = '''name=test\nversion=1.2.3\nrelease=7\nsource=(https://example.invalid/test-$version.tar.xz helper.conf)\n'''
out = mod.rewrite_version_release(sample, "1.2.3", "1.2.4")
assert "version=1.2.4" in out
assert "release=1" in out

remote = '''name=x\nversion=2\nrelease=1\nsource=(https://example.invalid/x-$version.tar.xz\n https://example.invalid/fixes/x-$version-fix.patch)\n'''
assert mod.remote_patch_raw_tokens(remote) == ["https://example.invalid/fixes/x-$version-fix.patch"]
assert mod.remote_patch_raw_tokens("source=(alias.patch::https://example.invalid/commit/123)") == ["alias.patch::https://example.invalid/commit/123"]
assert mod.source_filename("alias.patch::https://example.invalid/commit/123") == "alias.patch"
assert mod.is_patch_name("fix.patch.xz")
assert not mod.is_patch_name("thing.tar.xz")

with tempfile.TemporaryDirectory() as td_s:
    td = Path(td_s)
    (td / "Pkgfile").write_text('name=test\nversion=1.2.4\nrelease=1\nsource=(helper-1.2.3.conf)\n')
    (td / "helper-1.2.3.conf").write_text("x")
    meta = mod.eval_meta(td / "Pkgfile")
    probs = mod.inventory_local_companions(meta, td, "1.2.3")
    assert any("old-version-named" in x for x in probs), probs

# Version-named patches are judged by applicability, not filename alone.
with tempfile.TemporaryDirectory() as td_s:
    td = Path(td_s)
    (td / "Pkgfile").write_text('name=test\nversion=1.2.4\nrelease=1\nsource=(fix-1.2.3.patch)\n')
    (td / "fix-1.2.3.patch").write_text("--- a/file\n+++ b/file\n@@ -1 +1 @@\n-old\n+new\n")
    meta = mod.eval_meta(td / "Pkgfile")
    assert mod.inventory_local_companions(meta, td, "1.2.3") == []
    assert mod.versioned_local_patches(meta, "1.2.3") == ["fix-1.2.3.patch"]

# A suffix-less endpoint whose downloaded content is a patch is vendored.
with tempfile.TemporaryDirectory() as td_s:
    td = Path(td_s)
    text = 'name=x\nversion=2\nrelease=1\nsource=(https://example.invalid/x-2.tar.xz https://example.invalid/commit/123)\n'
    (td / "Pkgfile").write_text(text)
    real_download = mod.curl_download
    def fake_download(url, dest, timeout, **kwargs):
        dest.write_text("--- a/file\n+++ b/file\n@@ -1 +1 @@\n-old\n+new\n")
        return url
    mod.curl_download = fake_download
    try:
        rewritten, provenance = mod.vendor_remote_patches(td, text, text, 1)
    finally:
        mod.curl_download = real_download
    assert "123.patch" in rewritten, rewritten
    assert (td / "123.patch").is_file()
    assert provenance

with tempfile.TemporaryDirectory() as td_s:
    p = Path(td_s) / "fix.patch"
    p.write_text("--- a/file\n+++ b/file\n@@ -1 +1 @@\n-old\n+new\n")
    assert mod.looks_like_patch(p)
    p.write_text("<!doctype html><title>404</title>")
    assert not mod.looks_like_patch(p)

print("maintained-port updater regression: PASS")

ftp_src = 'ftp://ftp.gnu.org/gnu/mtools/mtools-4.0.49.tar.bz2'
assert mod.source_url(ftp_src) == ftp_src
assert mod.source_filename(ftp_src) == 'mtools-4.0.49.tar.bz2'
