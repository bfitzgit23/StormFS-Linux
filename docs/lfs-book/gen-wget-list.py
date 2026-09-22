#!/usr/bin/env python3
"""Generate the wget-list for the StormFS LFS book.

Collects the upstream source URLs of every package covered by the book
(toolchain packages from chapter 3, base system packages from chapter 4,
and the kernel from chapter 9) by reading the source=(...) arrays of the
corresponding Pkgfiles in the StormFS ports tree.

Usage:
    gen-wget-list.py [--output wget-list] [--ports DIR]

The resulting file contains one URL per line so it can be consumed with:

    wget -i wget-list -P sources
    # or
    aria2c -i wget-list -d sources
"""

import argparse
import re
import sys
from pathlib import Path

# Chapter 3 - temporary toolchain (build order).
TOOLCHAIN_PKGS = [
    "pkgutils",
    "binutils",   # pass 1 / pass 2
    "gmp",
    "mpfr",
    "mpc",
    "gcc",        # pass 1 / pass 2 / pass 3
    "linux-headers",
    "glibc",
    "libxcrypt",
    "m4",
    "ncurses",
    "bash",
    "bison",
    "bzip2",
    "coreutils",
    "diffutils",
    "file",
    "findutils",
    "gawk",
    "gettext",
    "grep",
    "gzip",
    "make",
    "patch",
    "perl",
    "zlib",
    "xz",
    "libtirpc",
    "libnsl",
    "python3",
    "sed",
    "tar",
    "texinfo",
    "openssl",
    "ca-certificates",
    "curl",
    "libarchive",
    "util-linux",
]

# Chapter 4 - base system (131 ports, build order).
BASE_PKGS = [
    "aaa_filesystem",
    "linux-headers",
    "man-pages",
    "glibc",
    "autoconf",
    "zlib",
    "bzip2",
    "xz",
    "file",
    "ncurses",
    "readline",
    "m4",
    "bc",
    "binutils",
    "ninja",
    "pkgconf",
    "libxcrypt",
    "gmp",
    "mpfr",
    "mpc",
    "attr",
    "acl",
    "gcc",
    "libcap",
    "psmisc",
    "sed",
    "tzdata",
    "iana-etc",
    "bison",
    "flex",
    "pcre2",
    "grep",
    "bash",
    "libtool",
    "gdbm",
    "gperf",
    "expat",
    "inetutils",
    "perl",
    "perl-xml-parser",
    "intltool",
    "automake",
    "openssl",
    "ca-certificates",
    "curl",
    "gettext",
    "elfutils",
    "libffi",
    "sqlite",
    "python3",
    "coreutils",
    "check",
    "diffutils",
    "gawk",
    "findutils",
    "groff",
    "less",
    "gzip",
    "zstd",
    "iptables",
    "libtirpc",
    "iproute2",
    "kbd",
    "libpipeline",
    "make",
    "patch",
    "man-db",
    "tar",
    "texinfo",
    "python3-setuptools",
    "python3-pip",
    "python3-flit-core",
    "python3-packaging",
    "python3-installer",
    "python3-build",
    "python3-pyproject-hooks",
    "python3-wheel",
    "libuv",
    "libarchive",
    "cmake",
    "fmt",
    "xxhash",
    "ccache",
    "boost",
    "meson",
    "kmod",
    "linux-pam",
    "shadow",
    "libpng",
    "which",
    "freetype",
    "fuse",
    "grub",
    "popt",
    "mandoc",
    "efivar",
    "efibootmgr",
    "grub-efi",
    "vim",
    "nano",
    "python3-markupsafe",
    "python3-tomli",
    "python3-pytz",
    "python3-babel",
    "python3-jinja2",
    "systemd",
    "util-linux",
    "dbus",
    "procps-ng",
    "e2fsprogs",
    "fakeroot",
    "pkgutils",
    "dialog",
    "prt-get",
    "httpup",
    "ports",
    "prt-utils",
    "lzo",
    "btrfs-progs",
    "dosfstools",
    "exfatprogs",
    "f2fs-tools",
    "mdadm",
    "libaio",
    "lvm2",
    "inih",
    "liburcu",
    "xfsprogs",
    "openssh",
    "genfstab",
    "signify",
]

# Chapter 9 - the kernel itself.
KERNEL_PKGS = ["linux"]

# Packages whose source URL cannot be derived statically from their Pkgfile.
# Used verbatim when Pkgfile parsing yields nothing; refresh on version bumps.
FALLBACK_URLS = {}

# Matches:  VAR=$(printf "%i%.2i%.2i%.2i" ${version//./ })
# (the sqlite versioning scheme: dot-separated fields, zero-padded to width 2)
PRINTF_SPLIT_RE = re.compile(
    r"^\s*([A-Za-z_][A-Za-z0-9_]*)=\$\(printf\s+\"%i((?:%.2i)+)\"\s+\$\{(\w+)//([^}/]*)/([^}]*)\}",
    re.MULTILINE,
)

SOURCE_RE = re.compile(r"source\s*=\s*\((.*?)\)", re.DOTALL)

# Top-level (unindented) VAR=value assignments in a Pkgfile.
ASSIGN_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$", re.MULTILINE)
# $VAR or ${EXPR} where EXPR may carry a bash operator:
#   % %% # ##  (prefix/suffix strip),  / //  (substitution),  :off[:len]  (slice)
EXPAND_RE = re.compile(r"\$\{([^}]+)\}|\$([A-Za-z_][A-Za-z0-9_]*)")


def parse_vars(text: str):
    """Parse simple top-level VAR=value assignments from a Pkgfile."""
    variables = {}
    for m in ASSIGN_RE.finditer(text):
        key, val = m.group(1), m.group(2).strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        else:
            val = re.split(r"\s+#", val, maxsplit=1)[0].rstrip()
        if "$(" in val or "`" in val:
            continue  # dynamic value; cannot be resolved statically
        variables[key] = val
    # Recognize the zero-padded printf idiom, e.g. sqlite:
    #   _version=$(printf "%i%.2i%.2i%.2i" ${version//./ })
    m = PRINTF_SPLIT_RE.search(text)
    if m and m.group(3) in variables:
        n_fields = 1 + m.group(2).count("%.2i")
        fields = variables[m.group(3)].replace(m.group(4), m.group(5)).split()
        padded = fields[0] + "".join(
            (fields[i] if i < len(fields) else "").rjust(2, "0") or "00"
            for i in range(1, n_fields)
        )
        variables[m.group(1)] = padded
    return variables


def _glob_to_regex(pat: str) -> str:
    return "".join(".*" if c == "*" else "." if c == "?" else re.escape(c) for c in pat)


def _apply_op(value: str, op: str, pat: str) -> str:
    regex = _glob_to_regex(pat)
    if op == "%":  # strip shortest matching suffix
        m = re.match(r"^(.*?)(" + regex + r")$", value)
        return m.group(1) if m else value
    if op == "%%":  # strip longest matching suffix
        m = re.match(r"^(.*)(" + regex + r")$", value)
        return m.group(1) if m else value
    if op == "#":  # strip shortest matching prefix
        m = re.match(r"^(" + regex + r")(.*)$", value)
        return m.group(2) if m else value
    if op == "##":  # strip longest matching prefix
        m = re.match(r"^(" + regex + r")(.*)$", value)
        return m.group(2) if m else value
    return value


def expand_string(s: str, variables):
    """Expand $VAR / ${VAR} / ${VAR%pat} / ${VAR/pat/rep} / ${VAR:off[:len]}."""

    def repl(m):
        expr = m.group(1) if m.group(1) is not None else m.group(2)
        if m.group(1) is None:
            return variables.get(expr, m.group(0))
        # ${VAR:offset[:length]} - substring expansion
        mslice = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(-?\d+)\s*(?::\s*(-?\d+)\s*)?$", expr)
        if mslice:
            var, off, length = mslice.groups()
            if var not in variables:
                return m.group(0)
            val = variables[var]
            start = int(off)
            if start < 0:
                start = max(len(val) + start, 0)
            if length is None:
                return val[start:]
            n = int(length)
            end = len(val) if n < 0 else start + n
            return val[start:end]
        # ${VAR//pat/rep} or ${VAR/pat/rep} - substitution
        msub = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*(//?)\s*(.*?)\s*/\s*(.*)$", expr)
        if msub:
            var, op, pat, rep = msub.groups()
            if var not in variables:
                return m.group(0)
            regex = _glob_to_regex(pat)
            count = 0 if op == "//" else 1
            return re.sub(regex, rep.replace("\\", "\\\\"), variables[var], count=count)
        # ${VAR%pat}, ${VAR%%pat}, ${VAR#pat}, ${VAR##pat}
        mop = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*(%%|##|%|#)\s*(.*)$", expr)
        if mop:
            var, op, pat = mop.groups()
            if var in variables:
                return _apply_op(variables[var], op, pat)
            return m.group(0)
        return variables.get(expr, m.group(0))

    prev = None
    while prev != s:
        prev = s
        s = EXPAND_RE.sub(repl, s)
    return s


def find_port(ports_dir: Path, name: str):
    """Locate <ports_dir>/<collection>/<name>/Pkgfile across all collections."""
    if not ports_dir.is_dir():
        return None
    for collection in sorted(p for p in ports_dir.iterdir() if p.is_dir()):
        pkgfile = collection / name / "Pkgfile"
        if pkgfile.is_file():
            return pkgfile
    return None


def extract_urls(pkgfile: Path):
    """Return concrete remote source URLs from a Pkgfile's source=(...) array."""
    text = pkgfile.read_text(encoding="utf-8", errors="replace")
    variables = parse_vars(text)
    m = SOURCE_RE.search(text)
    if not m:
        return []
    urls = []
    for token in m.group(1).split():
        # support "alias::real-url" rename syntax
        url = expand_string(token.split("::", 1)[-1], variables)
        if "://" in url and "$" not in url:
            urls.append(url)
        elif "://" in url:
            print(
                f"warning: {pkgfile.parent.name}: cannot resolve variables in {url}",
                file=sys.stderr,
            )
    return urls


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--output", default="wget-list", help="output file (default: wget-list)")
    ap.add_argument("--ports", default="", help="path to the ports tree (default: <repo>/ports)")
    args = ap.parse_args()

    book_dir = Path(__file__).resolve().parent
    repo_root = book_dir.parents[1]
    ports_dir = Path(args.ports) if args.ports else repo_root / "ports"

    seen_pkgs = set()
    ordered_pkgs = []
    for pkg in TOOLCHAIN_PKGS + BASE_PKGS + KERNEL_PKGS:
        if pkg not in seen_pkgs:
            seen_pkgs.add(pkg)
            ordered_pkgs.append(pkg)

    seen_urls = set()
    lines = []
    missing = []

    for pkg in ordered_pkgs:
        pkgfile = find_port(ports_dir, pkg)
        urls = extract_urls(pkgfile) if pkgfile else []
        if not urls and pkg in FALLBACK_URLS:
            urls = FALLBACK_URLS[pkg]
            print(f"note: {pkg}: using fallback URL(s) from gen-wget-list.py", file=sys.stderr)
        if pkgfile is None:
            missing.append(pkg)
            continue
        if not urls:
            print(f"warning: {pkg}: no remote sources found in {pkgfile}", file=sys.stderr)
            continue
        for url in urls:
            if url not in seen_urls:
                seen_urls.add(url)
                lines.append(url)

    out = Path(args.output)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")

    print(f"wrote {len(lines)} URLs ({len(ordered_pkgs) - len(missing)} packages) to {out}")
    if missing:
        print(f"warning: {len(missing)} packages have no Pkgfile in {ports_dir}:", file=sys.stderr)
        for pkg in missing:
            print(f"  - {pkg}", file=sys.stderr)


if __name__ == "__main__":
    main()
