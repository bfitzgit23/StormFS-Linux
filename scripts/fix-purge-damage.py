#!/usr/bin/env python3
"""Repair spkgbuild recipes left malformed by the systemd purge pass.

The purge commented out individual lines, which broke multi-line shell
commands (dangling continuations), left raw unit-file heredoc bodies behind,
and in several ports commented out `source=`/`build_opt=` assignments
outright. This script restores the intended non-systemd recipe shape.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

MARKER = "# systemd integration removed"


def load(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="surrogateescape")


def save(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", errors="surrogateescape", newline="\n")


def apply(path: Path, edits: list[tuple[str, str, bool]]) -> bool:
    text = original = load(path)
    missed: list[str] = []
    for old, new, is_regex in edits:
        if is_regex:
            updated = re.sub(old, new, text, count=1, flags=re.S)
        else:
            updated = text.replace(old, new, 1)
        if updated == text:
            missed.append(old)
        text = updated
    if text != original:
        save(path, text)
    status = "ok" if not missed else "INCOMPLETE"
    print(f"{status:11} {path}")
    for pattern in missed:
        print(f"    missed: {pattern.splitlines()[0][:78]!r}")
    for line in text.splitlines():
        if MARKER in line:
            print(f"    remains: {line.strip()[:88]}")
    return not missed


BS = "\\"
EDITS: dict[str, list[tuple[str, str, bool]]] = {
    "ports/core/bfs-kernel-maintenance/spkgbuild": [
        (
            f'\t{MARKER}: source="bfs-kernel-maintenance bfs-kernel-finalize.service README"',
            'source="bfs-kernel-maintenance README"',
            False,
        ),
        (
            f'\n\t{MARKER}: "$PKG/usr/lib/systemd/system/bfs-kernel-finalize.service" || return 1',
            "",
            False,
        ),
    ],
    "ports/core/nftables/spkgbuild": [
        (
            f'\t{MARKER}: source="https://www.netfilter.org/pub/nftables/nftables-$version.tar.xz nftables.nft nftables.service"',
            'source="https://www.netfilter.org/pub/nftables/nftables-$version.tar.xz nftables.nft"',
            False,
        ),
    ],
    "ports/core/rsync/spkgbuild": [
        (
            f'\t{MARKER}: source="https://www.samba.org/ftp/$name/src/$name-$version.tar.gz {BS} rsyncd.conf rsyncd.service rsync.driver"',
            'source="https://www.samba.org/ftp/$name/src/$name-$version.tar.gz rsyncd.conf rsync.driver"',
            False,
        ),
    ],
    "ports/opt/rpcbind/spkgbuild": [
        (
            f'\t{MARKER}: build_opt="--with-systemdsystemunitdir=/usr/lib/systemd/system --enable-warmstarts"',
            'build_opt="--enable-warmstarts"',
            False,
        ),
    ],
    "ports/opt/wireplumber/spkgbuild": [
        (
            'source="https://gitlab.freedesktop.org/pipewire/$name/-/archive/$version/$name-$version.tar.gz 90-bfsos-audio.preset"',
            'source="https://gitlab.freedesktop.org/pipewire/$name/-/archive/$version/$name-$version.tar.gz"',
            False,
        ),
        (
            f'\n    install -Dm644 "$SRC/90-bfsos-audio.preset" {BS}\n'
            f'\t{MARKER}: "$PKG/usr/lib/systemd/user-preset/90-bfsos-audio.preset" || return 1',
            "",
            False,
        ),
    ],
    "ports/opt/chrony/spkgbuild": [
        (
            "# NOTE: OpenRC profile integration (chronyd service script) ships in the\n"
            "# openrc-init-scripts port; systemd units below are inert on non-systemd builds.",
            "# NOTE: OpenRC profile integration (chronyd service script) ships in the\n"
            "# openrc-init-scripts port.",
            False,
        ),
        (
            '        "$PKG/usr/lib/sysusers.d" "$PKG/usr/lib/tmpfiles.d" || return 1',
            '    install -d "$PKG/usr/lib/sysusers.d" "$PKG/usr/lib/tmpfiles.d" || return 1',
            False,
        ),
        (
            rf'\n\t{MARKER}: cat > "[^"]*chronyd\.service" <<\'EOC\'.*?\nEOC\n\}}',
            "\n}",
            True,
        ),
    ],
    "ports/opt/cups/spkgbuild": [
        (
            f'\t{MARKER}: source="https://github.com/OpenPrinting/cups/releases/download/v$version/$name-$version-source.tar.gz cups.service cups.socket cups.path"',
            'source="https://github.com/OpenPrinting/cups/releases/download/v$version/$name-$version-source.tar.gz"',
            False,
        ),
        (
            f'\n\t{MARKER}: "$PKG/usr/lib/systemd/system/"\n',
            "",
            False,
        ),
    ],
    "ports/core/openssh/spkgbuild": [
        (
            f'\t{MARKER}: source="https://ftp.openbsd.org/pub/OpenBSD/OpenSSH/portable/$name-$version.tar.gz sshd.service"',
            'source="https://ftp.openbsd.org/pub/OpenBSD/OpenSSH/portable/$name-$version.tar.gz"',
            False,
        ),
        (
            f'\n\t{MARKER}: "$PKG/usr/lib/systemd/system/sshd.service"',
            "",
            False,
        ),
    ],
    "ports/opt/kerberos/spkgbuild": [
        (
            r"\n    # MIT Kerberos itself does not install systemd units\..*?\nUNIT\n\}",
            "\n}",
            True,
        ),
    ],
    "ports/opt/gpm/spkgbuild": [
        (
            rf"\n    install -d -m 0755 {BS}\n\t{MARKER}: [^\n]*\n\n"
            rf"\t{MARKER}: cat > [^\n]*<<'EOF'.*?\nEOF\n\}}",
            "\n}",
            True,
        ),
    ],
    "ports/opt/lightdm/spkgbuild": [
        (
            rf"\n    # BFSOS systemd service\.\n    install -Dm644 /dev/stdin {BS}\n.*?\nUNIT\n",
            "\n",
            True,
        ),
    ],
    "ports/core/aaa_filesystem/spkgbuild": [
        (
            rf'^[ \t]*{MARKER}: "\$PKG/usr/lib/systemd/system-preset" {BS}\n',
            "",
            True,
        ),
        (
            rf"\n    # BFSOS service policy: explicit distro/vendor presets win first; any\n"
            rf"    # unit not explicitly covered remains disabled until deliberately enabled\.\n"
            rf"    install -m 0644 99-bfsos\.preset {BS}\n\t{MARKER}: [^\n]*\n",
            "\n",
            True,
        ),
        (
            r'(^source="[^"]*?) 99-bfsos\.preset"',
            r'\1"',
            True,
        ),
    ],
    "ports/opt/samba/spkgbuild": [
        (
            rf"\n        --without-systemd {BS}\n        {BS}\n\t{MARKER}: --with-systemddir=[^\n]* {BS}\n",
            "\n        --without-systemd \\\n",
            True,
        ),
    ],
    "ports/compat-32/avahi-32/spkgbuild": [
        (
            f'"$PKG/usr/share" {BS}\n\t{MARKER}: "$PKG/usr/lib/systemd" "$PKG/etc" "$PKG/var"',
            '"$PKG/usr/share" "$PKG/etc" "$PKG/var"',
            False,
        ),
    ],
    "ports/plasma/plasma-login-manager/spkgbuild": [
        (
            f'        "$PKG/usr/lib/sysusers.d" "$PKG/usr/lib/tmpfiles.d" {BS}',
            f'    install -d {BS}\n        "$PKG/usr/lib/sysusers.d" "$PKG/usr/lib/tmpfiles.d" {BS}',
            False,
        ),
        (
            '\n    for unit in "$PKG"/opt/kf6/lib/systemd/system/*; do'
            '\n        [ -e "$unit" ] || continue\n    done'
            '\n    for unit in "$PKG"/opt/kf6/lib/systemd/user/*; do'
            '\n        [ -e "$unit" ] || continue\n    done',
            "",
            False,
        ),
        (
            r"\n    sed -i '/\^ExecStart=.*?\n    \}\n",
            "\n",
            True,
        ),
        (
            r"\n    # Fail the package build if upstream changes the service name/layout\..*?return 1\n    \}\n\}",
            "\n}",
            True,
        ),
    ],
}

STALE_PAYLOADS = [
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


def main() -> int:
    failures = 0
    for rel, edits in EDITS.items():
        path = Path(rel)
        if not path.exists():
            print(f"MISSING     {rel}")
            failures += 1
            continue
        if not apply(path, edits):
            failures += 1

    print("\nstale payloads still referenced elsewhere:")
    for rel in STALE_PAYLOADS:
        path = Path(rel)
        if not path.exists():
            print(f"  absent   {rel}")
            continue
        stem = path.name
        refs = []
        for candidate in Path("ports").rglob("spkgbuild"):
            if candidate == path.parent / "spkgbuild":
                continue
            if stem in load(candidate):
                refs.append(str(candidate))
        print(f"  {'REFERENCED' if refs else 'unused  '} {rel}"
              + (f" -> {', '.join(refs[:3])}" if refs else ""))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
