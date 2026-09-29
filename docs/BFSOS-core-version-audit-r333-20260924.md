# BFSOS core upstream-version audit — r333

Date: 2026-09-24

## Result

- Canonical `ports/core/*/Pkgfile` recipes reviewed: **210**.
- Definite stale versions found and updated in this pass: **23**.
- The sweep used current upstream release pages/directories where practical, PyPI for Python packaging components, kernel.org/IANA/Sourceware/official project release pages for fast-moving system components, and the current LFS/BLFS development baselines as a cross-check for the GNU/base toolchain.
- `NO UPDATE SELECTED` means the audit did not identify a newer stable upstream release for that recipe. It is not a package-build claim; changed versions still need normal BFSOS build/install acceptance.
- No package was downgraded merely because an LFS/BLFS baseline lagged a BFSOS version.

## Important corrections found by the second audit

This second sweep found real drift that the previous static core inventory did not catch, including very recent releases of `coreutils`, `expat`, `meson`, `tzdata`, `xxhash`, `xfsprogs`, `systemd`, `util-linux`, `linux-firmware`, plus `elfutils`, `fakeroot`, `rsync`, `vim`, and multiple Python packaging modules. The presence of these misses is why this report treats the version sweep separately from the static recipe audit.

## Complete 210-port inventory

| Port | Version after r333 | Audit result | Evidence/method |
|---|---:|---|---|
| `aaa_filesystem` | `1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `acl` | `2.4.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `attr` | `2.6.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `autoconf` | `2.73` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `automake` | `1.18.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `bash` | `5.3` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `bash-completion` | `2.18.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `bc` | `7.1.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `bfs-kernel-maintenance` | `1.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `binutils` | `2.47` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `bison` | `3.8.2` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `btrfs-progs` | `7.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `bzip2` | `1.0.8` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `ca-certificates` | `20260813` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `ccache` | `4.14` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `check` | `0.15.2` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `cmake` | `4.4.3` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `coreutils` | `9.12` | UPDATED 9.11 → 9.12 | GNU release 2026-09-14 |
| `cracklib` | `2.10.3` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `curl` | `8.22.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `dash` | `0.5.13.5` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `dbus` | `1.16.2` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `dialog` | `1.3-20260721` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `diffutils` | `3.12` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `dosfstools` | `4.2` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `dracut` | `112` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `e2fsprogs` | `1.47.4` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `efibootmgr` | `18` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `efivar` | `39` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `elfutils` | `0.196` | UPDATED 0.195 → 0.196 | Sourceware release 2026-08-14 |
| `exfatprogs` | `1.4.3` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `expat` | `2.8.5` | UPDATED 2.8.4 → 2.8.5 | upstream release 2026-09-22 |
| `f2fs-tools` | `1.16.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `fakeroot` | `2.1.4` | UPDATED 1.37.1.1 → 2.1.4 | Debian upstream source 2026-07 |
| `file` | `5.48` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `findutils` | `4.11.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `flex` | `2.6.4` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `fmt` | `12.2.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `freetype` | `2.14.3` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `fuse` | `3.18.3` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `gawk` | `5.4.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `gcc` | `16.2.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `gdbm` | `1.26` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `genfstab` | `31` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `gettext` | `1.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `glibc` | `2.44` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `gmp` | `6.3.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `gperf` | `3.3` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `gptfdisk` | `1.0.10` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `grep` | `3.12` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `groff` | `1.24.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `grub` | `2.14` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `grub-efi` | `2.14` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `gzip` | `1.14` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `httpup` | `0.5.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `iana-etc` | `20260817` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `inetutils` | `2.8` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `inih` | `62` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `intltool` | `0.51.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `iproute2` | `7.2.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `iptables` | `1.8.13` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `kbd` | `2.10.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `kmod` | `34.2` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `less` | `704` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `libaio` | `0.3.113` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `libarchive` | `3.8.9` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `libcap` | `2.78` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `libevent` | `2.1.13` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `libffi` | `3.8.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `libmnl` | `1.0.5` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `libnftnl` | `1.3.2` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `libnl` | `3.12.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `libnsl` | `2.0.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `libpipeline` | `1.5.8` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `libpng` | `1.6.58` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `libpwquality` | `1.4.5` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `libtirpc` | `1.3.7` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `libtool` | `2.6.2` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `liburcu` | `0.15.6` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `libuv` | `1.52.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `libxcrypt` | `4.5.2` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `libyaml` | `0.2.5` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `linux` | `7.2.7` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `linux-firmware` | `20260916` | UPDATED 20260810 → 20260916 | kernel.org linux-firmware tag |
| `linux-headers` | `6.18.53` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `linux-lts` | `6.18.53` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `linux-pam` | `1.7.2` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `lvm2` | `2.03.42` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `lz4` | `1.10.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `lzo` | `2.10` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `m4` | `1.4.21` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `make` | `4.4.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `make-ca` | `1.16.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `man-db` | `2.13.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `man-pages` | `6.19` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `mandoc` | `1.14.6` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `mdadm` | `4.6` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `meson` | `1.12.1` | UPDATED 1.12.0 → 1.12.1 | Meson/PyPI release 2026-09-22 |
| `mpc` | `1.4.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `mpdecimal` | `4.0.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `mpfr` | `4.2.2` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `mtools` | `4.0.49` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `nano` | `9.2` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `nasm` | `3.02` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `ncurses` | `6.6` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `nftables` | `1.1.7` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `ninja` | `1.13.2` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `openssh` | `10.5p1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `openssl` | `4.0.2` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `patch` | `2.8` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `pciutils` | `3.15.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `pcre2` | `10.48` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `perl` | `5.44.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `perl-class-inspector` | `1.36` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `perl-file-sharedir` | `1.118` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `perl-file-sharedir-install` | `0.14` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `perl-xml-parser` | `2.59` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `pkgconf` | `3.0.7` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `pkgutils` | `5.40.12` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `popt` | `1.19` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `ports` | `1.6` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `procps-ng` | `4.0.7` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `prt-get` | `5.19.10` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `prt-utils` | `1.3.7` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `psmisc` | `23.7` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3` | `3.14.7` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-attrs` | `26.1.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-babel` | `2.18.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-build` | `1.6.1` | UPDATED 1.6.0 → 1.6.1 | PyPI |
| `python3-cairo` | `1.29.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-calver` | `2025.10.20` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-certifi` | `2026.7.22` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-chardet` | `7.6.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-charset-normalizer` | `3.5.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-cython` | `3.3.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-docutils` | `0.23` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-doxypypy` | `0.8.8.7` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-doxyqml` | `0.5.3` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-editables` | `0.6` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-flit-core` | `4.1.0` | UPDATED 4.0.2 → 4.1.0 | PyPI |
| `python3-gi_docgen` | `2026.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-gobject` | `3.58.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-hatch-fancy-pypi-readme` | `25.1.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-hatch-vcs` | `0.5.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-hatchling` | `1.32.4` | UPDATED 1.32.0 → 1.32.4 | PyPI |
| `python3-html5lib` | `1.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-idna` | `3.20` | UPDATED 3.19 → 3.20 | PyPI |
| `python3-installer` | `1.0.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-jinja2` | `3.1.6` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-lxml` | `6.1.3` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-mako` | `1.4.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-markdown` | `3.10.3` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-markupsafe` | `3.0.3` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-meson_python` | `0.20.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-numpy` | `2.5.3` | UPDATED 2.5.2 → 2.5.3 | PyPI release 2026-09-06 |
| `python3-packaging` | `26.3` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-pathspec` | `1.1.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-pip` | `26.2.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-pluggy` | `1.6.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-ply` | `3.11` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-poetry-core` | `2.5.0` | UPDATED 2.4.1 → 2.5.0 | PyPI |
| `python3-psutil` | `7.2.2` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-pycparser` | `3.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-pygdbmi` | `0.11.0.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-pygments` | `2.21.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-pyparsing` | `3.3.3` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-pyproject-hooks` | `1.3.3` | UPDATED 1.2.0 → 1.3.3 | PyPI |
| `python3-pyproject_metadata` | `0.12.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-python-dbusmock` | `0.38.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-pytz` | `2026.3.post1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-pyxdg` | `0.28` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-pyyaml` | `6.0.3` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-requests` | `2.34.2` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-setuptools` | `84.0.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-setuptools-scm` | `10.3.4` | UPDATED 10.2.3 → 10.3.4 | PyPI |
| `python3-six` | `1.17.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-tomli` | `2.4.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-tomlkit` | `0.15.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-trove-classifiers` | `2026.9.21.13` | UPDATED 2026.6.1.19 → 2026.9.21.13 | PyPI |
| `python3-typing_extensions` | `4.16.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-typogrify` | `2.1.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-urllib3` | `2.7.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-vcs-versioning` | `2.4.1` | UPDATED 2.3.4 → 2.4.1 | PyPI |
| `python3-webencodings` | `0.6.1` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `python3-wheel` | `0.48.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `rdfind` | `1.8.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `readline` | `8.3` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `rsync` | `3.5.1` | UPDATED 3.5.0 → 3.5.1 | upstream/BLFS current |
| `sed` | `4.10` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `shadow` | `4.20.2` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `signify` | `0.14` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `sqlite` | `3.53.4` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `squashfs-tools` | `4.7.5` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `stripping` | `1.0` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `sudo` | `1.9.17p2` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `systemd` | `261.3` | UPDATED 261.2 → 261.3 | systemd stable release |
| `tar` | `1.35` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `texinfo` | `7.3` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `traceroute` | `2.1.6` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `tzdata` | `2026d` | UPDATED 2026c → 2026d | IANA release 2026-09-11 |
| `util-linux` | `2.42.4` | UPDATED 2.42.3 → 2.42.4 | kernel.org current |
| `vim` | `9.2.1119` | UPDATED 9.2.1036 → 9.2.1119 | upstream patchlevel sweep |
| `which` | `2.25` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `wireless_tools` | `30.pre9` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `wpa_supplicant` | `2.12` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `xfsprogs` | `7.2.0` | UPDATED 7.1.1 → 7.2.0 | kernel.org release 2026-09-17 |
| `xxhash` | `0.8.4` | UPDATED 0.8.3 → 0.8.4 | upstream release 2026-09-19 |
| `xz` | `5.8.4` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `zlib` | `1.3.2` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |
| `zstd` | `1.5.7` | NO UPDATE SELECTED | fresh r333 upstream/baseline review; no newer stable version identified |

## Build/runtime note

Version freshness and source-tree consistency are separate from build acceptance. All canonical core Pkgfiles pass `bash -n` in this source tree, but the 23 version bumps above should be rebuilt through normal BFSOS `pkgmk`/`prt-get` paths before they are marked runtime verified.
