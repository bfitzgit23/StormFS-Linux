#!/usr/bin/env python3
"""BFSOS upstream version checker v10.

Design goals:
- never claim an update unless the current port version can be mapped back to the
  same upstream provider/index that produced the candidate;
- treat local/meta ports as SKIP rather than network failures;
- use provider-aware checks for Git tags, GNOME, KDE, PyPI and Xfce;
- use an exact current-filename template for generic directory indexes;
- report UNVERIFIABLE instead of guessing when a provider cannot be proven;
- never modify Pkgfiles automatically.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import dataclasses
import html
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import threading
import time
from typing import Iterable
from urllib.parse import unquote, urlsplit, urlunsplit

TREES = ("core", "opt", "xorg", "plasma", "gnome", "lxqt", "xfce", "compiz", "contrib")
SKIP_WORDS = ("alpha", "beta", "rc", "pre", "dev", "snapshot", "nightly", "preview")
BLOCKED_QUALIFIERS = (
    "alt", "cqp", "darwin", "dist", "extended", "init", "kernel", "linux",
    "headers", "macos", "sunos", "win32", "win64", "windows", "with-nspr", "xdoc",
    "x86_64", "aarch64",
)
# Compatibility/API branches that are intentionally maintained separately in BFSOS.
# The integer is the number of leading numeric components that must match current.
SERIES_LOCKS = {
    "core/linux-lts": 2,
    "gnome/gcr": 2,
    "gnome/libwnck2": 2,
    "gnome/libgweather": 1,
    "gnome/libpeas": 1,
    "opt/cairomm-1.0": 2,
    "opt/consolekit": 1,
    "opt/atkmm": 2,
    "opt/fuse2": 1,
    "opt/glibmm-2.4": 2,
    "opt/gtk": 2,
    "opt/gtk3": 2,
    "opt/gtkmm3": 2,
    "opt/libsigc++2": 1,
    "opt/libsoup": 2,
    "opt/lua": 2,
    "opt/lua52": 2,
    "opt/pangomm": 2,
    "opt/spirv-llvm-translator": 1,
    "xorg/libva": 1,
}
GSTREAMER_PORTS = {
    "opt/gstreamer", "opt/gst-libav", "opt/gst-plugins-bad",
    "opt/gst-plugins-base", "opt/gst-plugins-good", "opt/gst-plugins-ugly",
}
WEBKIT_PORTS = {"gnome/webkitgtk", "gnome/webkitgtk-41"}
BLOCKED_PORT_VERSIONS = {
    # Historical/abandoned version lines whose numeric value sorts above the
    # actively maintained stable line.
    "opt/pango": {"1.90.0"},
    "opt/taglib": {"2.3.2"},
}
EVEN_MINOR_STABLE_PORTS = {
    "gnome/gnome-terminal",
    "opt/at-spi2-core", "opt/cairomm", "opt/cairomm-1.0", "opt/glib",
    "opt/glibmm", "opt/glibmm-2.4", "opt/glibmm-2.68",
    "opt/gobject-introspection", "opt/gtk4", "opt/gtkmm", "opt/gtkmm3",
    "opt/gtksourceview", "opt/libsoup3", "opt/pango", "opt/pangomm",
}
REMOTE_PREFIXES = ("http://", "https://")

# Stable upstream repositories used only for version discovery when the
# package tarball is hosted on a mirror/archive that does not expose a
# machine-readable directory index. These do not change package sources.
GIT_REPO_OVERRIDES = {
    "core/e2fsprogs": "https://git.kernel.org/pub/scm/fs/ext2/e2fsprogs.git",
    "core/freetype": "https://gitlab.freedesktop.org/freetype/freetype.git",
    "core/libpng": "https://github.com/pnggroup/libpng.git",
    "core/squashfs-tools": "https://github.com/plougher/squashfs-tools.git",
    "opt/freeglut": "https://github.com/freeglut/freeglut.git",
    "opt/gparted": "https://gitlab.gnome.org/GNOME/gparted.git",
    "opt/ghostscript": "https://github.com/ArtifexSoftware/ghostpdl-downloads.git",
    "opt/libndp": "https://github.com/jpirko/libndp.git",
    "opt/smartmontools": "https://github.com/smartmontools/smartmontools.git",
    "opt/swig": "https://github.com/swig/swig.git",
    "opt/taglib": "https://github.com/taglib/taglib.git",
    "xorg/glew": "https://github.com/nigels-com/glew.git",
    "core/procps-ng": "https://gitlab.com/procps-ng/procps.git",
    "core/psmisc": "https://gitlab.com/psmisc/psmisc.git",
    "lxqt/libfm-extra": "https://github.com/lxde/libfm.git",
    "lxqt/menu-cache": "https://github.com/lxde/menu-cache.git",
    "opt/cdrdao": "https://github.com/cdrdao/cdrdao.git",
    "opt/poppler": "https://gitlab.freedesktop.org/poppler/poppler.git",
    "plasma/polkit-qt5": "https://invent.kde.org/libraries/polkit-qt-1.git",
}

PYPI_PROJECT_OVERRIDES = {
    "core/python3-docutils": "docutils",
    "opt/scons": "SCons",
}


@dataclasses.dataclass
class Port:
    path: Path
    rel: str
    name: str
    version: str
    sources: list[str]


@dataclasses.dataclass
class Result:
    port: Port
    status: str
    latest: str = ""
    provider: str = ""
    reason: str = ""
    source: str = ""


class FetchError(RuntimeError):
    pass


class HttpCache:
    def __init__(self, timeout: int):
        self.timeout = timeout
        self._lock = threading.Lock()
        self._cache: dict[str, tuple[bool, str]] = {}
        self._events: dict[str, threading.Event] = {}

    def get(self, url: str) -> str:
        with self._lock:
            if url in self._cache:
                ok, value = self._cache[url]
                if ok:
                    return value
                raise FetchError(value)
            if url in self._events:
                event = self._events[url]
                owner = False
            else:
                event = threading.Event()
                self._events[url] = event
                owner = True

        if not owner:
            event.wait()
            with self._lock:
                ok, value = self._cache[url]
            if ok:
                return value
            raise FetchError(value)

        try:
            cp = subprocess.run(
                [
                    "curl", "--fail", "--location", "--silent", "--show-error",
                    "--compressed", "--connect-timeout", "4", "--max-time",
                    str(self.timeout), "--user-agent", "BFSOS-checkupdate/10", url,
                ],
                text=True,
                encoding="utf-8", errors="replace",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=self.timeout + 3,
                env={**os.environ, "LC_ALL": "C"},
            )
            if cp.returncode != 0:
                msg = cp.stderr.strip() or f"curl exit {cp.returncode}"
                raise FetchError(msg)
            value = cp.stdout
            with self._lock:
                self._cache[url] = (True, value)
            return value
        except (subprocess.TimeoutExpired, FetchError) as exc:
            msg = "timeout" if isinstance(exc, subprocess.TimeoutExpired) else str(exc)
            with self._lock:
                self._cache[url] = (False, msg)
            raise FetchError(msg)
        finally:
            with self._lock:
                self._events.pop(url, None)
                event.set()

    def exists(self, url: str) -> tuple[bool, str]:
        common = [
            "curl", "--fail", "--location", "--silent", "--show-error",
            "--connect-timeout", "4", "--max-time", str(self.timeout),
            "--user-agent", "BFSOS-checkupdate/10",
        ]
        errors: list[str] = []
        for extra in (["--head"], ["--range", "0-0", "--output", "/dev/null"]):
            try:
                cp = subprocess.run(
                    common + extra + [url],
                    text=True, encoding="utf-8", errors="replace",
                    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                    timeout=self.timeout + 3, env={**os.environ, "LC_ALL": "C"},
                )
                if cp.returncode == 0:
                    return True, ""
                err = cp.stderr.strip() or f"curl exit {cp.returncode}"
                # HTTP 416 from a 0-0 range probe proves the endpoint exists,
                # even though the server rejects the byte-range semantics.
                if "416" in err and "--range" in extra:
                    return True, "range probe returned HTTP 416"
                errors.append(err)
            except subprocess.TimeoutExpired:
                errors.append("timeout")
        return False, errors[-1] if errors else "source check failed"


    def resolve(self, url: str) -> tuple[str, str]:
        """Resolve redirects without keeping the response body."""
        cmd = [
            "curl", "--fail", "--location", "--silent", "--show-error",
            "--connect-timeout", "4", "--max-time", str(self.timeout),
            "--user-agent", "BFSOS-checkupdate/10", "--range", "0-0",
            "--output", "/dev/null", "--write-out", "%{url_effective}", url,
        ]
        try:
            cp = subprocess.run(
                cmd, text=True, encoding="utf-8", errors="replace",
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=self.timeout + 3, env={**os.environ, "LC_ALL": "C"},
            )
        except subprocess.TimeoutExpired as exc:
            raise FetchError("timeout") from exc
        if cp.returncode != 0:
            msg = cp.stderr.strip() or f"curl exit {cp.returncode}"
            head = cmd[:]
            range_i = head.index("--range")
            del head[range_i:range_i + 2]
            head.insert(range_i, "--head")
            cp = subprocess.run(
                head, text=True, encoding="utf-8", errors="replace",
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=self.timeout + 3, env={**os.environ, "LC_ALL": "C"},
            )
            if cp.returncode != 0:
                raise FetchError(cp.stderr.strip() or msg)
        effective = cp.stdout.strip()
        if not effective:
            raise FetchError("redirect resolver returned no effective URL")
        return effective, ""


def gcc_release_directory(port: Port, http: HttpCache) -> tuple[str | None, str, str]:
    """Enumerate sibling gcc-X.Y.Z release directories, not one release dir."""
    index = "https://gcc.gnu.org/pub/gcc/releases/"
    text = http.get(index)
    vals = re.findall(r"(?:href=[\"']|>)(?:gcc-)([0-9][0-9A-Za-z._+~-]*)/?", text, re.I)
    vals = uniq_sorted_versions(vals, port.version, port, "gcc-releases")
    if port.version not in vals:
        return None, "gcc-releases", "current GCC release directory is not present in upstream release index"
    latest, reason = choose_verified(port.version, vals, port, "gcc-releases")
    return latest, "gcc-releases", reason


def nss_release_directory(port: Port, http: HttpCache) -> tuple[str | None, str, str]:
    """Enumerate NSS RTM release directories instead of one version-specific directory."""
    index = "https://archive.mozilla.org/pub/security/nss/releases/"
    text = http.get(index)
    vals = []
    for raw in re.findall(r"NSS_([0-9]+(?:_[0-9]+)+)_RTM/?", text, re.I):
        vals.append(raw.replace("_", "."))
    vals = uniq_sorted_versions(vals, port.version, port, "nss-releases")
    if port.version not in vals:
        return None, "nss-releases", "current NSS RTM directory is not present in upstream release index"
    latest, reason = choose_verified(port.version, vals, port, "nss-releases")
    return latest, "nss-releases", reason


def discord_stable(port: Port, http: HttpCache) -> tuple[str | None, str, str]:
    """Use Discord's stable Linux download redirect as the authoritative channel."""
    endpoint = "https://discord.com/api/download/stable?platform=linux&format=tar.gz"
    effective, _ = http.resolve(endpoint)
    m = re.search(r"/apps/linux/([^/]+)/discord-([^/]+)\.tar\.gz(?:$|[?#])", effective)
    if not m or m.group(1) != m.group(2):
        return None, "discord-stable", f"stable redirect did not resolve to a versioned Linux tarball: {effective}"
    latest = m.group(1)
    if not candidate_allowed(latest, port.version, port, "discord-stable"):
        return None, "discord-stable", f"resolved version rejected by stable-channel policy: {latest}"
    latest = only_if_newer(port.version, latest)
    return latest, "discord-stable", ""


def natural_key(v: str):
    # Comparable across ordinary upstream versions without depending on packaging.
    parts = re.split(r"([0-9]+)", v.lower().replace("~", "-").replace("_", "."))
    return tuple((0, int(p)) if p.isdigit() else (1, p) for p in parts if p != "")


def numeric_components(v: str) -> tuple[int, ...]:
    nums = re.findall(r"\d+", v)
    return tuple(int(x) for x in nums)


def is_prerelease(v: str, current: str = "") -> bool:
    low = v.lower()
    current_low = current.lower()
    for word in SKIP_WORDS:
        if word in low and word not in current_low:
            return True
    # PEP 440 / common upstream forms such as 3.3.0b1, 3.0.0a7, 2.1b1.
    if re.search(r"(?<=\d)(?:a|b|rc)\d+(?:$|[._+-])", low) and not re.search(
        r"(?<=\d)(?:a|b|rc)\d+(?:$|[._+-])", current_low
    ):
        return True
    if re.search(r"(?:^|[._+-])(?:a|b|rc)\d+(?:$|[._+-])", low) and not re.search(
        r"(?:^|[._+-])(?:a|b|rc)\d+(?:$|[._+-])", current_low
    ):
        return True
    # Common upstream development-version convention.
    if ".99." in low and ".99." not in current_low:
        return True
    return False


def candidate_allowed(v: str, current: str, port: Port | None = None, provider: str = "") -> bool:
    if v == current:
        return True
    # Preserve explicit release channels.  In particular, Mozilla ESR ports
    # must never be "updated" to a numerically newer rapid-release build.
    # The same rule protects explicit LTS-labelled packages/providers.
    current_low = current.lower()
    candidate_low = v.lower()
    for channel in ("esr", "lts"):
        if channel in current_low and channel not in candidate_low:
            return False
    if not re.search(r"\d", v) or is_prerelease(v, current):
        return False

    low = v.lower()
    cur_low = current.lower()
    for word in BLOCKED_QUALIFIERS:
        if word in low and word not in cur_low:
            return False

    cur_nums = numeric_components(current)
    cand_nums = numeric_components(v)
    # Semantic-version ports must not be hijacked by unrelated historical date tags.
    if cur_nums and cand_nums and cur_nums[0] < 100 and cand_nums[0] >= 1000:
        return False

    if port is not None:
        if v in BLOCKED_PORT_VERSIONS.get(port.rel, set()):
            return False
        lock = SERIES_LOCKS.get(port.rel)
        if lock and (len(cur_nums) < lock or len(cand_nums) < lock or cur_nums[:lock] != cand_nums[:lock]):
            return False

        # GNOME libraries traditionally use odd minor numbers for development
        # snapshots; keep those out when the installed line is an even stable line.
        if provider == "gnome-cache" and len(cand_nums) >= 2 and 1 <= cand_nums[0] <= 9:
            if len(cur_nums) >= 2 and cur_nums[1] % 2 == 0 and cand_nums[1] % 2 == 1:
                return False

        # GStreamer explicitly documents odd minor series as development snapshots.
        if port.rel in GSTREAMER_PORTS and len(cand_nums) >= 2 and cand_nums[1] % 2 == 1:
            return False

        # WebKitGTK odd minor series are development releases leading to the next even series.
        if port.rel in WEBKIT_PORTS and len(cand_nums) >= 2 and cand_nums[1] % 2 == 1:
            return False

        # Perl uses odd second components for development releases.
        if port.rel == "core/perl" and len(cand_nums) >= 2 and cand_nums[1] % 2 == 1:
            return False

        # Several GNOME-adjacent libraries use odd minor numbers for their
        # development series even when release tarballs are hosted elsewhere.
        if port.rel in EVEN_MINOR_STABLE_PORTS and len(cand_nums) >= 2:
            if len(cur_nums) >= 2 and cur_nums[1] % 2 == 0 and cand_nums[1] % 2 == 1:
                return False

    return True


def uniq_sorted_versions(values: Iterable[str], current: str, port: Port | None = None, provider: str = "") -> list[str]:
    clean: set[str] = set()
    for v in values:
        v = html.unescape(v).strip().strip("/\"'")
        v = re.sub(r"\.(?:tar\.(?:gz|bz2|xz|zst)|tgz|tbz2|zip)$", "", v)
        if v and candidate_allowed(v, current, port, provider):
            clean.add(v)
    return sorted(clean, key=natural_key)


def choose_verified(current: str, candidates: Iterable[str], port: Port | None = None, provider: str = "") -> tuple[str | None, str]:
    vals = uniq_sorted_versions(candidates, current, port, provider)
    if current not in vals:
        return None, "provider results do not contain the current version"
    return vals[-1], ""


def only_if_newer(current: str, candidate: str | None) -> str | None:
    """Reject cross-series/provider candidates that do not advance current."""
    if not candidate:
        return None
    if natural_key(candidate) <= natural_key(current):
        return current
    return candidate

def eval_pkgfile(pkgfile: Path) -> Port:
    script = r'''
set +u
source "$1" >/dev/null 2>&1 || exit 31
printf '%s\0%s\0' "${name-}" "${version-}"
if declare -p source >/dev/null 2>&1; then
  if declare -p source 2>/dev/null | grep -q '^declare -a'; then
    printf '%s\0' "${source[@]}"
  else
    printf '%s\0' "${source}"
  fi
fi
'''
    cp = subprocess.run(
        ["bash", "--noprofile", "--norc", "-c", script, "bfs-checkupdate", str(pkgfile)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=8,
    )
    if cp.returncode != 0:
        raise RuntimeError(f"Pkgfile evaluation failed ({cp.returncode})")
    fields = cp.stdout.decode("utf-8", "replace").split("\0")
    if fields and fields[-1] == "":
        fields.pop()
    if len(fields) < 2:
        raise RuntimeError("Pkgfile did not define name/version")
    name, version, *sources = fields
    root = pkgfile.parents[2]
    rel = str(pkgfile.parent.relative_to(root))
    return Port(pkgfile.parent, rel, name, version, sources)


def remote_sources(port: Port) -> list[str]:
    out: list[str] = []
    for src in port.sources:
        src = src.strip()
        if "::" in src:
            left, right = src.split("::", 1)
            if right.startswith(REMOTE_PREFIXES):
                src = right
        if src.startswith(REMOTE_PREFIXES):
            out.append(src)
    return out


def hrefs(text: str) -> list[str]:
    return [html.unescape(x) for x in re.findall(r'''href\s*=\s*["']([^"']+)["']''', text, re.I)]


def versions_from_filename_listing(text: str, basename: str, current: str) -> list[str]:
    if current not in basename:
        return []
    prefix, suffix = basename.split(current, 1)
    rx = re.compile(re.escape(prefix) + r"([0-9][0-9A-Za-z._+~:-]*)" + re.escape(suffix) + r"(?:$|[?#])")
    vals = []
    for h in hrefs(text) + re.findall(r"[^\s<>\"']+", text):
        b = h.rsplit("/", 1)[-1]
        m = rx.search(b)
        if m:
            vals.append(m.group(1))
    return vals


def generic_directory(port: Port, source: str, http: HttpCache) -> tuple[str | None, str, str]:
    u = urlsplit(source)
    path = u.path
    basename = path.rsplit("/", 1)[-1]

    variants: list[tuple[str, callable]] = [(port.version, lambda x: x)]
    if "." in port.version:
        variants.append((port.version.replace(".", "_"), lambda x: x.replace("_", ".")))
    if "_" in port.version:
        variants.append((port.version.replace("_", "-"), lambda x: x.replace("-", "_")))
    if ".pre" in port.version:
        variants.append((port.version.replace(".pre", "~pre"), lambda x: x.replace("~pre", ".pre")))

    token = ""
    transform = lambda x: x
    for candidate, fn in variants:
        if candidate and candidate in basename:
            token, transform = candidate, fn
            break
    if not token:
        return None, "directory", "current version is not present in source filename under a known encoding"

    parent = path.rsplit("/", 1)[0] + "/"
    index = urlunsplit((u.scheme, u.netloc, parent, "", ""))
    text = http.get(index)

    prefix, suffix = basename.split(token, 1)
    rx = re.compile(re.escape(prefix) + r"([0-9][0-9A-Za-z._+~:-]*)" + re.escape(suffix) + r"(?:$|[?#])")
    vals = []
    for h in hrefs(text) + re.findall(r"[^\\s<>\\\"']+", text):
        b = h.rsplit("/", 1)[-1]
        m = rx.search(b)
        if m:
            vals.append(transform(m.group(1)))
    latest, reason = choose_verified(port.version, vals, port, "directory")
    return latest, "directory", reason


def git_repo_from_source(source: str) -> str | None:
    u = urlsplit(source)
    host = u.netloc.lower()
    parts = [p for p in u.path.split("/") if p]
    if host == "github.com" and len(parts) >= 2:
        repo = parts[1]
        if repo.endswith(".git"):
            repo = repo[:-4]
        return f"https://github.com/{parts[0]}/{repo}.git"
    if host.startswith("gitlab.") or host == "gitlab.com" or "-/archive" in u.path:
        if "-" in parts:
            cut = parts.index("-")
            parts = parts[:cut]
        elif "archive" in parts:
            parts = parts[:parts.index("archive")]
        if parts:
            repo = "/".join(parts)
            if not repo.endswith(".git"):
                repo += ".git"
            return f"{u.scheme}://{u.netloc}/{repo}"
    if host == "codeberg.org" and len(parts) >= 2:
        repo = "/".join(parts[:2])
        return f"https://codeberg.org/{repo}.git"
    if host == "git.kernel.org":
        m = re.search(r"(.+?\.git)(?:/|$)", u.path)
        if m:
            return f"{u.scheme}://{u.netloc}{m.group(1)}"
    return None


def git_tag_versions(tags: list[str], current: str) -> tuple[list[str], str]:
    reps = [
        (current, lambda x: x),
        (current.replace(".", "_"), lambda x: x.replace("_", ".")),
        (current.replace(".", "-"), lambda x: x.replace("-", ".")),
    ]
    if current.startswith("v") and len(current) > 1:
        bare = current[1:]
        reps.extend([
            (bare, lambda x: "v" + x),
            (bare.replace(".", "_"), lambda x: "v" + x.replace("_", ".")),
            (bare.replace(".", "-"), lambda x: "v" + x.replace("-", ".")),
        ])
    best: list[str] = []
    for rep, transform in reps:
        if rep not in " ".join(tags):
            continue
        patterns: list[tuple[str, str]] = []
        for tag in tags:
            idx = tag.find(rep)
            if idx >= 0:
                patterns.append((tag[:idx], tag[idx + len(rep):]))
        for prefix, suffix in patterns:
            vals: list[str] = []
            for tag in tags:
                if not tag.startswith(prefix) or (suffix and not tag.endswith(suffix)):
                    continue
                end = len(tag) - len(suffix) if suffix else len(tag)
                middle = tag[len(prefix):end]
                v = transform(middle)
                if re.fullmatch(r"[0-9][0-9A-Za-z._+~-]*", v) or (
                    current.startswith("v") and re.fullmatch(r"v[0-9][0-9A-Za-z._+~-]*", v)
                ):
                    vals.append(v)
            if current in vals and len(vals) > len(best):
                best = vals
    if not best:
        return [], "could not derive a tag pattern that maps back to the current version"
    return best, ""


def git_tags(port: Port, source: str, timeout: int, repo_override: str | None = None) -> tuple[str | None, str, str]:
    repo = repo_override or git_repo_from_source(source)
    if not repo:
        return None, "git-tags", "could not infer repository URL"
    try:
        cp = subprocess.run(
            ["git", "ls-remote", "--tags", "--refs", repo],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout + 4,
            env={**os.environ, "GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"},
        )
    except subprocess.TimeoutExpired:
        raise FetchError(f"git tag query timed out: {repo}")
    if cp.returncode != 0:
        raise FetchError(cp.stderr.strip() or f"git ls-remote exit {cp.returncode}")
    tags = []
    for line in cp.stdout.splitlines():
        if "\trefs/tags/" in line:
            tags.append(line.split("\trefs/tags/", 1)[1])
    vals, reason = git_tag_versions(tags, port.version)
    if reason:
        return None, "git-tags", reason
    latest, reason = choose_verified(port.version, vals, port, "git-tags")
    return latest, "git-tags", reason


def gnome(port: Port, source: str, http: HttpCache) -> tuple[str | None, str, str]:
    m = re.search(r"/(?:pub/(?:GNOME|gnome)/)?sources/([^/]+)/", unquote(urlsplit(source).path), re.I)
    if not m:
        return None, "gnome-cache", "could not infer GNOME module"
    module = m.group(1)
    url = f"https://download.gnome.org/sources/{module}/cache.json"
    text = http.get(url)
    # cache.json contains source paths; matching the module filename is resilient
    # across cache schema revisions.
    rx = re.compile(re.escape(module) + r"-([0-9][0-9A-Za-z._+~-]*)\.tar\.(?:xz|gz|bz2|zst)")
    vals = rx.findall(text)
    latest, reason = choose_verified(port.version, vals, port, "gnome-cache")
    return latest, "gnome-cache", reason


def pypi(port: Port, source: str, http: HttpCache) -> tuple[str | None, str, str]:
    basename = urlsplit(source).path.rsplit("/", 1)[-1]
    candidates: list[str] = []
    if port.version in basename:
        prefix = basename.split(port.version, 1)[0].rstrip("-_.")
        if prefix:
            candidates.append(prefix.replace("_", "-"))
    for x in (port.name, re.sub(r"^(?:python3?|py)-", "", port.name)):
        if x and x not in candidates:
            candidates.append(x)
    last = ""
    for project in candidates[:3]:
        try:
            text = http.get(f"https://pypi.org/pypi/{project}/json")
            data = json.loads(text)
        except (FetchError, json.JSONDecodeError) as exc:
            last = str(exc)
            continue
        releases = data.get("releases", {})
        if port.version not in releases:
            last = f"PyPI project {project!r} does not contain current version"
            continue
        vals = releases.keys()
        latest, reason = choose_verified(port.version, vals, port, f"pypi:{project}")
        return latest, f"pypi:{project}", reason
    if last.startswith("curl") or last == "timeout":
        raise FetchError(last)
    return None, "pypi", last or "could not map package name to PyPI project"


def numeric_dirs(text: str) -> list[str]:
    vals = []
    for h in hrefs(text):
        x = h.strip("/")
        if re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,3}", x):
            vals.append(x)
    return vals


def kde(port: Port, source: str, http: HttpCache) -> tuple[str | None, str, str]:
    u = urlsplit(source)
    path = u.path
    base = f"{u.scheme}://{u.netloc}"
    basename = path.rsplit("/", 1)[-1]

    suite = None
    root = None
    child_suffix = ""
    same_major = False
    for marker, name, suffix, sm in (
        ("/stable/plasma/", "plasma", "", False),
        ("/stable/release-service/", "release-service", "/src", False),
        ("/stable/frameworks/", "frameworks", "", True),
    ):
        if marker in path:
            suite = name
            root = base + marker
            child_suffix = suffix
            same_major = sm
            break
    if not root:
        return generic_directory(port, source, http)

    top = http.get(root)
    dirs = uniq_sorted_versions(numeric_dirs(top), port.version)
    if same_major:
        major = port.version.split(".", 1)[0]
        dirs = [d for d in dirs if d.split(".", 1)[0] == major]
    if not dirs:
        return None, f"kde-{suite}", "no stable release directories found"
    release_dir = dirs[-1]
    child = f"{root}{release_dir}{child_suffix}/"
    listing = http.get(child)

    # Most KDE coordinated suites carry the release version in every tarball.
    # Frameworks uses X.Y directories while tarballs normally use X.Y.Z.
    vals = versions_from_filename_listing(listing, basename, port.version)
    latest, reason = choose_verified(port.version, vals, port, f"kde-{suite}")
    if latest:
        return latest, f"kde-{suite}", ""

    # If the current version lives in an older directory, inspect its listing as
    # well so current-version mapping can be established, then use the candidate
    # release directory only if the same package exists there.
    current_dir = None
    if suite == "frameworks":
        bits = port.version.split(".")
        current_dir = ".".join(bits[:2]) if len(bits) >= 2 else port.version
    else:
        current_dir = port.version
    current_child = f"{root}{current_dir}{child_suffix}/"
    try:
        current_listing = http.get(current_child)
    except FetchError:
        return None, f"kde-{suite}", reason
    current_vals = versions_from_filename_listing(current_listing, basename, port.version)
    if port.version not in current_vals:
        return None, f"kde-{suite}", "current package not present in KDE suite index"

    candidate_names = hrefs(listing)
    # Build a basename template from current and look for any versioned match.
    if port.version in basename:
        prefix, suffix = basename.split(port.version, 1)
        rx = re.compile(r"(?:^|/)" + re.escape(prefix) + r"([0-9][0-9A-Za-z._+~-]*)" + re.escape(suffix) + r"$")
        vals2 = [m.group(1) for h in candidate_names if (m := rx.search(h))]
        vals2 = uniq_sorted_versions(vals2, port.version, port, f"kde-{suite}")
        if vals2:
            return only_if_newer(port.version, vals2[-1]), f"kde-{suite}", ""
    return None, f"kde-{suite}", "package not found in newest compatible KDE release directory"


def xfce(port: Port, source: str, http: HttpCache) -> tuple[str | None, str, str]:
    u = urlsplit(source)
    m = re.search(r"(/src/[^/]+/[^/]+/)([0-9]+\.[0-9]+)/", u.path)
    if not m:
        return generic_directory(port, source, http)
    root = f"{u.scheme}://{u.netloc}{m.group(1)}"
    top = http.get(root)
    dirs = uniq_sorted_versions(numeric_dirs(top), port.version)
    # Xfce core 4.x uses odd minor series for development. 0.x plugin
    # series do not follow that convention (for example 0.5.x pulseaudio).
    dirs = [
        d for d in dirs
        if len(numeric_components(d)) < 2
        or numeric_components(d)[0] != 4
        or numeric_components(d)[1] % 2 == 0
    ]
    if not dirs:
        return None, "xfce-index", "no release-series directories found"
    series = dirs[-1]
    listing = http.get(root + series + "/")
    basename = u.path.rsplit("/", 1)[-1]
    vals = versions_from_filename_listing(listing, basename, port.version)
    if port.version in vals:
        latest, reason = choose_verified(port.version, vals, port, "xfce-index")
        return latest, "xfce-index", reason

    # Current may be in an older series. Prove it there, then find the package in
    # the newest series.
    old_series = m.group(2)
    old_listing = http.get(root + old_series + "/")
    old_vals = versions_from_filename_listing(old_listing, basename, port.version)
    if port.version not in old_vals:
        return None, "xfce-index", "current package not present in Xfce index"
    if port.version not in basename:
        return None, "xfce-index", "current version not literal in source filename"
    prefix, suffix = basename.split(port.version, 1)
    rx = re.compile(r"(?:^|/)" + re.escape(prefix) + r"([0-9][0-9A-Za-z._+~-]*)" + re.escape(suffix) + r"$")
    vals2 = [m.group(1) for h in hrefs(listing) if (m := rx.search(h))]
    vals2 = uniq_sorted_versions(vals2, port.version, port, "xfce-index")
    if vals2:
        return only_if_newer(port.version, vals2[-1]), "xfce-index", ""
    return None, "xfce-index", "package not found in newest Xfce release series"


def netfilter_release_page(port: Port, http: HttpCache) -> tuple[str | None, str, str]:
    module = port.name
    url = f"https://www.netfilter.org/projects/{module}/downloads.html"
    text = http.get(url)
    rx = re.compile(re.escape(module) + r"-([0-9][0-9A-Za-z._+~-]*)\.tar\.(?:xz|bz2|gz)")
    vals = rx.findall(text)
    latest, reason = choose_verified(port.version, vals, port, "netfilter")
    return latest, "netfilter", reason


def provider_check(port: Port, source: str, http: HttpCache, timeout: int) -> tuple[str | None, str, str]:
    host = urlsplit(source).netloc.lower()
    path = urlsplit(source).path

    if port.rel in PYPI_PROJECT_OVERRIDES:
        project = PYPI_PROJECT_OVERRIDES[port.rel]
        text = http.get(f"https://pypi.org/pypi/{project}/json")
        data = json.loads(text)
        vals = data.get("releases", {}).keys()
        latest, reason = choose_verified(port.version, vals, port, f"pypi:{project}")
        return latest, f"pypi:{project}", reason
    if port.rel in GIT_REPO_OVERRIDES:
        return git_tags(port, source, timeout, GIT_REPO_OVERRIDES[port.rel])
    if port.rel in {"core/iptables", "core/libmnl"}:
        return netfilter_release_page(port, http)
    if port.rel == "opt/mingw-w64-gcc":
        return gcc_release_directory(port, http)
    if port.rel == "opt/discord":
        return discord_stable(port, http)
    if port.rel == "opt/nss":
        return nss_release_directory(port, http)

    if host in {"download.gnome.org", "ftp.gnome.org"}:
        return gnome(port, source, http)
    if host in {"pypi.org", "pypi.python.org", "files.pythonhosted.org", "pythonhosted.org", "pypi.io"}:
        return pypi(port, source, http)
    if host == "download.kde.org":
        return kde(port, source, http)
    if host == "archive.xfce.org":
        return xfce(port, source, http)
    if (
        host == "github.com" or host == "gitlab.com" or host.startswith("gitlab.")
        or host == "git.kernel.org" or host == "codeberg.org" or "/-/archive/" in path
    ):
        return git_tags(port, source, timeout)
    return generic_directory(port, source, http)


def check_port(port: Port, http: HttpCache, timeout: int) -> Result:
    sources = remote_sources(port)
    if not port.name or not port.version:
        return Result(port, "ERROR", reason="missing name/version")
    if not sources:
        return Result(port, "SKIP", reason="local/meta port: no remote source")
    source = sources[0]
    try:
        latest, provider, reason = provider_check(port, source, http, timeout)
    except FetchError as exc:
        # A provider/index failure is not evidence the package source is broken.
        ok, source_reason = http.exists(source)
        if ok:
            return Result(port, "UNVERIFIABLE", provider="source-ok", reason=f"provider fetch failed: {exc}", source=source)
        return Result(port, "FETCH-ERROR", provider="source", reason=source_reason or str(exc), source=source)
    except Exception as exc:
        return Result(port, "ERROR", reason=f"{type(exc).__name__}: {exc}", source=source)

    if latest is None:
        ok, source_reason = http.exists(source)
        extra = "current source reachable" if ok else f"current source check failed: {source_reason}"
        return Result(port, "UNVERIFIABLE", provider=provider, reason=f"{reason}; {extra}", source=source)
    status = "CURRENT" if latest == port.version else "UPDATE"
    return Result(port, status, latest=latest, provider=provider, source=source)


def discover(root: Path, args: list[str]) -> list[Path]:
    if args:
        out: list[Path] = []
        for item in args:
            p = Path(item).expanduser()
            if p.is_dir() and (p / "Pkgfile").is_file():
                out.append(p / "Pkgfile")
                continue
            if p.is_file() and p.name == "Pkgfile":
                out.append(p)
                continue
            matches = list((root / "ports").glob(f"*/{item}/Pkgfile"))
            if len(matches) == 1:
                out.append(matches[0])
            elif not matches:
                print(f"Port not found: {item}", file=sys.stderr)
            else:
                print(f"Ambiguous port name {item}: " + ", ".join(str(x.parent) for x in matches), file=sys.stderr)
        return sorted(set(out))

    repo = os.environ.get("REPO", "").strip()
    roots = [Path(x) for x in repo.split()] if repo else [root / "ports" / t for t in TREES]
    out = []
    for r in roots:
        out.extend(sorted(r.glob("*/Pkgfile")))
    return out


def tsv_escape(s: str) -> str:
    return s.replace("\t", " ").replace("\n", " ").replace("\r", " ")


def print_result(r: Result, verbose: bool = False):
    base = f"{r.status:<12} {r.port.rel:<42} {r.port.version}"
    if r.latest:
        base += f" -> {r.latest}"
    if r.provider:
        base += f"  [{r.provider}]"
    if r.reason and (r.status not in {"CURRENT"} or verbose):
        base += f"  {r.reason}"
    print(base)


def main() -> int:
    ap = argparse.ArgumentParser(description="BFSOS verified upstream version checker v10")
    ap.add_argument("ports", nargs="*", help="port path or unique package name")
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("-n", action="store_true", help="accepted for compatibility; update overrides are not used by v2")
    ap.add_argument("-u", "--update", action="store_true", help="disabled: v10 keeps auditing separate from updater writes")
    ap.add_argument("--jobs", type=int, default=10)
    ap.add_argument("--timeout", type=int, default=10)
    ap.add_argument("--tsv", help="write complete machine-readable results to this path")
    ns = ap.parse_args()
    if ns.update:
        print("ERROR: -u is intentionally disabled in checker v10. Use bfs-maintained-port-updater.py on reviewed UPDATE rows.", file=sys.stderr)
        return 2

    root = Path(__file__).resolve().parents[1]
    pkgfiles = discover(root, ns.ports)
    if not pkgfiles:
        print("No ports selected.", file=sys.stderr)
        return 2

    ports: list[Port] = []
    early: list[Result] = []
    for p in pkgfiles:
        try:
            ports.append(eval_pkgfile(p))
        except Exception as exc:
            fake = Port(p.parent, str(p.parent), p.parent.name, "?", [])
            early.append(Result(fake, "ERROR", reason=str(exc)))

    print(f"BFSOS verified upstream version checker v10")
    print(f"Ports: {len(pkgfiles)}   Jobs: {max(1, ns.jobs)}   Timeout: {ns.timeout}s")
    print("Policy: UPDATE is emitted only when the provider can map the current version back to the same release set.")
    print()

    http = HttpCache(max(3, ns.timeout))
    results: list[Result] = list(early)
    done = 0
    lock = threading.Lock()
    started = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, ns.jobs)) as ex:
        futures = {ex.submit(check_port, p, http, ns.timeout): p for p in ports}
        for fut in concurrent.futures.as_completed(futures):
            results.append(fut.result())
            with lock:
                done += 1
                if done % 25 == 0 or done == len(ports):
                    print(f"... checked {done}/{len(ports)}", file=sys.stderr, flush=True)

    results.sort(key=lambda r: r.port.rel)
    for r in results:
        print_result(r, ns.verbose)

    counts: dict[str, int] = {}
    for r in results:
        counts[r.status] = counts.get(r.status, 0) + 1
    elapsed = time.monotonic() - started
    print("\nSummary:")
    for key in ("CURRENT", "UPDATE", "UNVERIFIABLE", "FETCH-ERROR", "SKIP", "ERROR"):
        print(f"  {key:<12} {counts.get(key, 0)}")
    print(f"  TOTAL        {len(results)}")
    print(f"  ELAPSED      {elapsed:.1f}s")

    if ns.tsv:
        out = Path(ns.tsv)
        with out.open("w", encoding="utf-8") as f:
            f.write("status\tport\tcurrent\tlatest\tprovider\treason\tsource\n")
            for r in results:
                f.write("\t".join(tsv_escape(x) for x in (
                    r.status, r.port.rel, r.port.version, r.latest, r.provider, r.reason, r.source
                )) + "\n")
        print(f"TSV: {out}")

    return 1 if counts.get("ERROR", 0) else 0


if __name__ == "__main__":
    raise SystemExit(main())
