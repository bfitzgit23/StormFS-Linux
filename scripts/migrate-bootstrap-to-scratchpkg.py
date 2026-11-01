#!/usr/bin/env python3
"""Rewrite bootstrap.sh from pkgmk/pkgutils to scratchpkg and OpenRC only.

The bootstrap was driven by CRUX pkgmk: a pkgmk binary was bootstrapped into
/tmp/lfs-tools, sources were prefetched with ``pkgmk -do``, and Stages 2/3 ran
``pkgin`` plus ``pkgadd -r`` from the host.  This script rewrites those pieces
to scratchpkg:

  * ports are located by ``spkgbuild`` instead of ``Pkgfile``;
  * the temporary toolchain gets scratchpkg's pkgbuild/pkgadd instead of a
    freshly bootstrapped pkgutils;
  * Stage 1 builds each toolchain port through its ``bootstrap_build()`` hook
    (sources fetched with ``pkgbuild -o``), keeping the existing per-package
    logging, retry and verification flow;
  * Stages 2/3 build and install inside the chroot with ``spkgin``;
  * the package database moves to /var/lib/scratchpkg/db;
  * /etc/scratchpkg.conf replaces /etc/pkgmk.conf and the pkgmk extension;
  * systemd disappears from the base package list and the special-case
    systemd bootstrap transaction.

Every replacement is asserted: a pattern that no longer matches is reported so
the bootstrap is never left half-migrated by a silent no-op.

    python3 scripts/migrate-bootstrap-to-scratchpkg.py --dry-run
    python3 scripts/migrate-bootstrap-to-scratchpkg.py
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

S = re.DOTALL

REPLACEMENTS: list[tuple[str, str, str]] = [
    # ---------------------------------------------------------------- port lookup
    (
        "port lookup by spkgbuild",
        r"-exec test -f '\{\}/Pkgfile' ';'",
        r"-exec test -f '{}/spkgbuild' ';'",
    ),
    # ------------------------------------------------------ toolchain pkgutils seed
    (
        "temporary toolchain uses scratchpkg",
        r"\n    # Existing /tmp/lfs-tools may contain a pristine CRUX pkgmk.*?\n        rm -rf /tmp/pkgutils-5\.40\.12\n    fi\n",
        """
    # The temporary toolchain carries scratchpkg's pkgbuild so Stage 1 can
    # fetch sources and so the toolchain remains self-hosting.  Recipes supply
    # their own bootstrap_build() hook for the Stage-1 cross build.
    for _spkg_tool in pkgbuild pkgadd pkgdel scratch; do
        if [ ! -x "$TOOLS/bin/$_spkg_tool" ]; then
            if [ ! -f "$SCRIPT_DIR/scratchpkg/$_spkg_tool" ]; then
                echo "ERROR: scratchpkg sources are missing: $SCRIPT_DIR/scratchpkg" >&2
                echo "       run: git submodule update --init scratchpkg" >&2
                return 1
            fi
            install -m 0755 "$SCRIPT_DIR/scratchpkg/$_spkg_tool" "$TOOLS/bin/$_spkg_tool" || return 1
        fi
    done
    if [ ! -x "$TOOLS/bin/spkgin" ]; then
        install -m 0755 "$SCRIPT_DIR/files/spkgin" "$TOOLS/bin/spkgin" || return 1
    fi
    unset _spkg_tool
""",
    ),
    # ------------------------------------------------------------- stage-1 staging
    (
        "stage-1 toolchain build hook",
        r"\n        if pkgmk -d -is -if -cf /tmp/bootstrap\.conf; then\n            status=0\n        else\n            status=\$\?\n        fi\n",
        """
        if _spkg_bootstrap_build "$port_dir"; then
            status=0
        else
            status=$?
        fi
""",
    ),
    # -------------------------------------------------------- bootstrap.conf content
    (
        "scratchpkg stage-1 configuration",
        r"\n    cat > /tmp/bootstrap\.conf <<EOF\n.*?\nEOF\n",
        """
    cat > /tmp/bootstrap.conf <<EOF
# scratchpkg configuration for Stage 1 (temporary toolchain).
#
# Keep the Stage-1 source cache in the same package-namespaced layout the
# installed configuration uses, so archives are reused by Stages 2 and 3.
SOURCE_DIR="$sourcedir"
PACKAGE_DIR=/tmp/lfs-pkg
WORK_DIR=/tmp/lfs-work
CBUILD_DIR=/tmp/lfs-cbuild

export CFLAGS="-O2 -pipe"
export CXXFLAGS="\\$CFLAGS"
export MAKEFLAGS=-j$(nproc)

# Stage 1 is deliberately uncached: never inherit the build host's ccache.
export BFS_CCACHE=no

mkdir -p "\\$SOURCE_DIR" "\\$PACKAGE_DIR" "\\$WORK_DIR" "\\$CBUILD_DIR" || exit 1
EOF
""",
    ),
    # ---------------------------------------------------- prefetch via pkgbuild -o
    (
        "prefetch uses pkgbuild",
        r"\n    local bootstrap_pkgmk=\"\$TOOLS/bin/pkgmk\"\n",
        """
    local pkgbuild_cmd="$TOOLS/bin/pkgbuild"
""",
    ),
    (
        "prefetch pkgmk binary patching removed",
        r"\n    # Source prefetch must use the temporary-toolchain pkgmk.*?\n    fi\n\n",
        """
    if [ ! -x "$pkgbuild_cmd" ]; then
        echo "ERROR: pkgbuild is missing from the temporary toolchain: $pkgbuild_cmd" >&2
        return 1
    fi

""",
    ),
    (
        "prefetch download call",
        r'"\$bootstrap_pkgmk" -do -cf "\$pkgmk_conf"',
        '"$pkgbuild_cmd" -o --config="$pkgmk_conf"',
    ),
    # -------------------------------------------------------------- package database
    (
        "package database path",
        r"\$LFS/var/lib/pkg/db",
        "$LFS/var/lib/scratchpkg/db",
    ),
    (
        "package database creation",
        r'mkdir -p "\$LFS/var/lib/pkg"\n        touch "\$LFS/var/lib/pkg/db"',
        'mkdir -p "$LFS/var/lib/scratchpkg/db"',
    ),
    # ------------------------------------------------ stage 2/3 build and install
    (
        "stage 2/3 systemd special case removed",
        r"\n            if \[ \"\$\{1:-\}\" != rebuild \] && \[ \"\$i\" = systemd \]; then\n.*?\n            fi\n",
        "\n",
    ),
    (
        "stage 2/3 integrity options removed",
        r'\n            integrity_opts=""\n.*?development integrity bypass active:\$integrity_opts" >&2\n            fi\n',
        "\n",
    ),
    (
        "stage 2/3 install through spkgin",
        r'            chroot "\$LFS" \\\n                env -i \\\n                HOME=/root \\\n                TERM="\$\{TERM:-dumb\}" \\\n                PATH="\$LFSPATH" \\\n                pkgin -d "\$i" \$integrity_opts -cf "\$pkgmk_conf" \\\n                \|\| \{\n                    status=\$\?\n                    _close_active_package_log "\$status"\n                    umountfs\n                    return "\$status"\n                \}\n\n            pkgadd -r "\$LFS" \$\{_force:-\} -f \\\n                "\$\(ls -1 "\$packagedir/\$i#"\) " \|\| \{\n                    status=\$\?\n                    _close_active_package_log "\$status"\n                    umountfs\n                    return "\$status"\n                \}\n',
        """
            # scratchpkg builds and installs in one transaction inside the
            # chroot, so no host-side pkgadd step is needed.
            chroot "$LFS" \\
                env -i \\
                HOME=/root \\
                TERM="${TERM:-dumb}" \\
                PATH="$LFSPATH" \\
                spkgin ${_force:-} --config="$pkgmk_conf" "$i" \\
                || {
                    status=$?
                    _close_active_package_log "$status"
                    umountfs
                    return "$status"
                }
""",
    ),
    # ------------------------------------------------------------- verification
    (
        "verify pkgbuild presence",
        r'_verify_path "\$LFS/usr/bin/pkgmk"',
        '_verify_path "$LFS/usr/bin/pkgbuild"\n    _verify_path "$LFS/usr/share/bfsos/spkgbuild.helper"',
    ),
    (
        "verify toolchain commands",
        r"for cmd in gcc g\+\+ ld make pkg-config pkgmk pkgadd pkginfo; do",
        "for cmd in gcc g++ ld make pkg-config pkgbuild pkgadd scratch; do",
    ),
    (
        "verify package database readable",
        r'pkginfo -i >/dev/null 2>&1 \|\| fail "package database is not readable"',
        'scratch installed >/dev/null 2>&1 || fail "package database is not readable"',
    ),
]

NEW_FUNCTION = '''
# Build one Stage-1 toolchain port through its bootstrap_build() hook.
#
# scratchpkg's pkgbuild installs into /, which is wrong for the temporary
# toolchain, so sources are fetched and unpacked with pkgbuild (-o, -x) and the
# recipe's bootstrap_build() is then run with $TOOLS as the install prefix.
_spkg_bootstrap_build() {
    local port_dir="$1"
    local conf=/tmp/bootstrap.conf
    local workdir=/tmp/lfs-work
    local srcdir="$workdir/\${port_dir##*/}/src"

    (
        cd "$port_dir" || return 1

        pkgbuild -o --config="$conf" || return 1
        pkgbuild -x --config="$conf" || return 1

        # shellcheck disable=SC1091
        . ./spkgbuild || return 1

        SRC="$srcdir"
        PKG="$TOOLS"
        export SRC PKG TOOLS

        cd "$srcdir" || return 1
        if [ -d "$srcdir/$name-$version" ]; then
            cd "$srcdir/$name-$version" || return 1
        fi

        if command -v bootstrap_build >/dev/null 2>&1; then
            bootstrap_build
        else
            # shellcheck disable=SC1091
            . "$SCRIPT_DIR/ports/core/bfs-spkgbuild-macros/helper.sh"
            bfs_autobuild
        fi
    )
}
'''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("script", nargs="?", default="bootstrap.sh")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    path = Path(args.script)
    if not path.is_file():
        print(f"ERROR: not found: {path}", file=sys.stderr)
        return 1

    text = path.read_text(encoding="utf-8", errors="replace")
    failures: list[str] = []

    for label, pattern, replacement in REPLACEMENTS:
        new_text, count = re.subn(pattern, replacement, text, count=1, flags=S)
        if count == 0:
            failures.append(label)
            continue
        text = new_text
        print(f"applied: {label}")

    # Insert the Stage-1 helper just before _buildtoolchain.
    if "_spkg_bootstrap_build()" not in text:
        anchor = "_buildtoolchain() {"
        if anchor in text:
            text = text.replace(anchor, NEW_FUNCTION.strip() + "\n\n" + anchor, 1)
            print("applied: stage-1 helper inserted")
        else:
            failures.append("stage-1 helper insertion")

    if failures:
        print("\nNOT APPLIED (pattern did not match):")
        for item in failures:
            print(f"  - {item}")

    if args.dry_run:
        print("\n(dry run: nothing written)")
        return 0

    path.write_text(text, encoding="utf-8", newline="\n")
    print(f"\nwrote {path}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
