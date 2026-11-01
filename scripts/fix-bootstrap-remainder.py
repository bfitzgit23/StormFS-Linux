#!/usr/bin/env python3
"""Second-pass cleanup of bootstrap.sh after migrate-bootstrap-to-scratchpkg.py.

Handles the pieces that need multi-line surgery or that a regex could not
safely anchor:

  * Stage 2/3 build+install transaction (integrity options and the host-side
    pkgadd call) becomes a single ``spkgin`` invocation inside the chroot;
  * the target ``$LFS/tmp/pkgmk.conf`` heredoc becomes a scratchpkg config;
  * the pkgmk downloader-patching block is dropped (scratchpkg needs no such
    patch) and replaced by a pkgbuild availability check;
  * remaining pkgmk paths, cache variables and comments are renamed;
  * the base package list drops the retired manager and systemd, and gains
    scratchpkg plus the shared spkgbuild macros.

    python3 scripts/fix-bootstrap-remainder.py --dry-run
    python3 scripts/fix-bootstrap-remainder.py
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

BS = "\\"


def cont(line: str) -> str:
    return f"{line} {BS}"


NEW_TRANSACTION = [
    "            # scratchpkg builds and installs in one transaction inside the",
    "            # chroot, so no host-side pkgadd step is required.",
    cont('            chroot "$LFS"'),
    cont("                env -i"),
    cont("                HOME=/root"),
    cont('                TERM="${TERM:-dumb}"'),
    cont('                PATH="$LFSPATH"'),
    cont('                spkgin ${_force:-} --config="$spkg_conf" "$i"'),
    "                || {",
    "                    status=$?",
    '                    _close_active_package_log "$status"',
    "                    umountfs",
    '                    return "$status"',
    "                }",
    "",
]

NEW_CONFIG_HEREDOC = [
    '    cat > "$LFS/tmp/scratchpkg.conf" <<EOF',
    "# scratchpkg configuration used while building Stages 2 and 3.",
    "#",
    "# Init is OpenRC for the whole tree: service integration belongs to the",
    "# init port, never to individual packages, and no systemd units are built.",
    'export CFLAGS="$CFLAGS"',
    'export CXXFLAGS="$' + '{CFLAGS}"',
    'export CPPFLAGS="-I/usr/include"',
    'export LDFLAGS="-L/usr/lib -Wl,-rpath-link,/usr/lib"',
    'export LIBRARY_PATH="/usr/lib"',
    'export PKG_CONFIG_PATH="/usr/lib/pkgconfig:/usr/share/pkgconfig"',
    'export PKG_CONFIG_LIBDIR="/usr/lib/pkgconfig:/usr/share/pkgconfig"',
    "",
    'export XORG_PREFIX="/usr"',
    'export XORG_CONFIG="--prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-static"',
    "",
    'JOBS=${BFS_BUILD_JOBS/auto/$(nproc)}',
    "export JOBS",
    'export MAKEFLAGS="-j $JOBS"',
    "",
    "# Bootstrap-safe ccache policy: active only once the target ccache package",
    "# has installed ccache and its compiler wrappers inside the rootfs.",
    'export BFS_CCACHE="$BFS_CCACHE"',
    'export BFS_CCACHE_SIZE="$resolved_ccache_size"',
    'export CCACHE_DIR="/var/cache/ccache"',
    'if [ "$BFS_CCACHE" = yes ] && [ -x /usr/bin/ccache ] && [ -x /usr/lib/ccache/gcc ]; then',
    '    export PATH="/usr/lib/ccache:$PATH"',
    "fi",
    "",
    'SOURCE_DIR="/$spkgsrc"',
    'PACKAGE_DIR="/$spkgpkg"',
    'WORK_DIR="/$spkgwork"',
    'CBUILD_DIR="/var/lib/scratchpkg/cbuild"',
    'mkdir -p "$SOURCE_DIR" "$PACKAGE_DIR" "$WORK_DIR" "$CBUILD_DIR" || exit 1',
    "EOF",
]

RENAMES = [
    ('pkgmkpkg="var/cache/pkg/packages"', 'spkgpkg="var/cache/scratchpkg/packages"'),
    ('pkgmksrc="var/cache/pkg/sources"', 'spkgsrc="var/cache/scratchpkg/sources"'),
    ('pkgmkwork="var/cache/pkg/build-work"', 'spkgwork="var/cache/scratchpkg/work"'),
    ("$pkgmkpkg", "$spkgpkg"),
    ("$pkgmksrc", "$spkgsrc"),
    ("$pkgmkwork", "$spkgwork"),
    ("var/lib/pkgmk", "var/lib/scratchpkg"),
    ("var/lib/pkg/", "var/lib/scratchpkg/"),
    ("/etc/pkgmk.conf", "/etc/scratchpkg.conf"),
    ("$LFS/tmp/pkgmk.conf", "$LFS/tmp/scratchpkg.conf"),
    ("/tmp/pkgmk.systemd-bootstrap.conf", "/tmp/scratchpkg.conf"),
    ('local pkgmk_conf="$1"', 'local spkg_conf="$1"'),
    ("pkgmk_conf", "spkg_conf"),
    ("$TOOLS/bin/pkgmk", "$TOOLS/bin/pkgbuild"),
    ("$LFS/usr/bin/pkgmk", "$LFS/usr/bin/pkgbuild"),
    ("'/usr/bin/pkgmk'", "'/usr/bin/pkgbuild'"),
    ("'pkgmk'", "'pkgbuild'"),
    ("files/pkgin", "files/spkgin"),
    ("pkgin -d", "spkgin"),
    ("dedicated pkgmk account", "package-build account"),
    ("passwd pkgmk", "passwd pkgbuild"),
    ("terminate pkgmk", "terminate pkgbuild"),
    ("the actual pkgmk/download error", "the actual pkgbuild/download error"),
    ("pkgmk requires every configured", "pkgbuild requires every configured"),
    ("temporary pkgmk package directory", "temporary pkgbuild package directory"),
    ("CRUX pkgmk", "CRUX pkgbuild"),
]

DROP_PACKAGES = ("pkgutils", "prt-get", "prt-utils", "httpup", "ports", "pacman", "signify", "systemd")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("script", nargs="?", default="bootstrap.sh")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    path = Path(args.script)
    if not path.is_file():
        print(f"ERROR: not found: {path}", file=sys.stderr)
        return 1

    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()

    # 1) Stage 2/3 transaction.
    start = next((i for i, l in enumerate(lines) if 'integrity_opts=""' in l), None)
    pkgadd = next((i for i, l in enumerate(lines) if 'pkgadd -r "$LFS"' in l), None)
    if start is not None and pkgadd is not None and pkgadd > start:
        end = pkgadd
        while end < len(lines) and lines[end].strip() != "}":
            end += 1
        lines[start : end + 1] = NEW_TRANSACTION
        print("stage 2/3 transaction rewritten")
    else:
        print("WARN: stage 2/3 transaction anchors not found")

    # 2) Target build configuration heredoc.
    h_start = next(
        (i for i, l in enumerate(lines) if 'cat > "$LFS/tmp/pkgmk.conf" <<EOF' in l), None
    )
    if h_start is not None:
        h_end = next(
            (i for i in range(h_start, len(lines)) if "pkgmk/extension" in lines[i]), None
        )
        if h_end is not None:
            closing = next((i for i in range(h_end, len(lines)) if lines[i].strip() == "EOF"), h_end)
            lines[h_start : closing + 1] = NEW_CONFIG_HEREDOC
            print("target build configuration heredoc rewritten")
        else:
            print("WARN: heredoc terminator not found")
    else:
        print("WARN: target heredoc anchor not found")

    # 3) Drop the pkgmk downloader-patching block.
    p_start = next(
        (i for i, l in enumerate(lines) if "sed -i" in l and "PKGMK_DOWNLOAD_PROG" in l), None
    )
    if p_start is not None:
        p_end = next(
            (i for i in range(p_start, len(lines)) if "does not support bfs-prefetch-curl" in lines[i]),
            None,
        )
        if p_end is not None:
            while p_end < len(lines) and lines[p_end].strip() != "fi":
                p_end += 1
            lines[p_start : p_end + 1] = [
                '    if [ ! -x "$pkgbuild_cmd" ]; then',
                '        echo "ERROR: pkgbuild is missing from the temporary toolchain: $pkgbuild_cmd" >&2',
                "        return 1",
                "    fi",
            ]
            print("pkgmk downloader patch block replaced with a pkgbuild check")
    else:
        print("WARN: downloader patch block anchor not found")

    text = "\n".join(lines) + "\n"

    # 4) Remaining renames.
    for old, new in RENAMES:
        text = text.replace(old, new)

    # 5) Base package list.
    for name in DROP_PACKAGES:
        text = re.sub(rf"(?m)^{re.escape(name)}$\n", "", text)
    if "\nscratchpkg\n" not in text:
        text = text.replace("fakeroot\n", "fakeroot\nscratchpkg\nbfs-spkgbuild-macros\n", 1)

    # 6) Copy the shared helper instead of the pkgmk extension.
    text = text.replace(
        'cp ports/core/pkgutils/extension \\\n        "$LFS/var/lib/scratchpkg"',
        'install -D -m 0755 ports/core/bfs-spkgbuild-macros/helper.sh \\\n        "$LFS/usr/share/bfsos/spkgbuild.helper"',
    )

    # 7) Comment-only wording sweep.
    out = []
    for line in text.splitlines():
        if line.lstrip().startswith("#") and "pkgmk" in line:
            line = line.replace("pkgmk.conf", "scratchpkg.conf").replace("pkgmk", "pkgbuild")
        out.append(line)
    text = "\n".join(out) + "\n"

    remaining = [
        f"{n}: {l.strip()}"
        for n, l in enumerate(text.splitlines(), 1)
        if re.search(r"pkgmk|prt-get|pkginfo|var/lib/pkg/", l)
    ]
    print(f"\nremaining legacy references: {len(remaining)}")
    for item in remaining[:20]:
        print(f"  {item}")

    if args.dry_run:
        print("\n(dry run: nothing written)")
        return 0

    path.write_text(text, encoding="utf-8", newline="\n")
    print(f"\nwrote {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
