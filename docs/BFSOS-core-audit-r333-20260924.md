# BFSOS `ports/core` audit — r333 source/static pass

Date: 2026-09-24

## Scope and evidence

- Core directories: **211**; canonical Pkgfiles: **210**.
- Required metadata omissions: **0**.
- Hard/optional dependency overlaps: **0**.
- Unresolved hard dependency tokens from core against the full BFSOS tree: **0**.
- Plain-HTTP active source URLs after this pass: **0**.
- Remote patch URLs still present in core source arrays: **4**.
- `pkg_build()` recipes: **141**; with an explicit `Custom build required:` rationale: **1**.
- Direct `setup.py install` recipes: **7**.
- Stale `Pkgfile*` backup/copy files anywhere under maintained `ports/`: **0**.

The complete package-by-package inventory is in `docs/BFSOS-core-audit-r333-20260924.tsv`. This audit is deliberately source/static evidence: package builds, runtime behavior, and a true upstream-version sweep require a networked BFSOS host. The sandbox version checker was attempted and could not resolve upstream hosts, so the report does not mislabel unverified package versions as current.

## Findings requiring follow-up

### Remote patch vendoring still required

- `coreutils`: `https://www.linuxfromscratch.org/patches/downloads/coreutils/coreutils-9.11-i18n-1.patch`
- `gptfdisk`: `https://www.linuxfromscratch.org/patches/blfs/svn/$name-$version-convenience-1.patch`
- `python3`: `https://www.linuxfromscratch.org/patches/downloads/Python/Python-$version-openssl_4-1.patch`
- `zlib`: `https://github.com/madler/zlib/commit/36ff1be48ef696cc67b0855f7c8537ce0276210d.patch`

These patch bytes are not present in the supplied project archive. They must be fetched on a networked host, checksum-verified, committed beside each Pkgfile, and the source entries converted to local filenames.

### BFSOS extension-contract review queue

**140** core ports still retain `pkg_build()` without an explicit custom-build rationale. This is an audit queue, not proof that all 140 are wrong. Ordinary Autotools/CMake/Meson recipes should migrate to the extension + `build_opt`; genuinely special orchestration should retain `pkg_build()` and gain a concise rationale.

Ports: `aaa_filesystem`, `attr`, `bash-completion`, `bc`, `bfs-kernel-maintenance`, `binutils`, `bzip2`, `ca-certificates`, `ccache`, `cmake`, `cracklib`, `dbus`, `dracut`, `e2fsprogs`, `efibootmgr`, `efivar`, `elfutils`, `exfatprogs`, `fakeroot`, `fmt`, `freetype`, `gcc`, `gettext`, `glibc`, `gptfdisk`, `httpup`, `iana-etc`, `kbd`, `libaio`, `libcap`, `libevent`, `libmnl`, `libnftnl`, `libnl`, `libnsl`, `libpng`, `libpwquality`, `liburcu`, `libuv`, `libyaml`, `linux`, `linux-firmware`, `linux-headers`, `linux-lts`, `lvm2`, `lz4`, `make-ca`, `man-pages`, `mandoc`, `mdadm`, `meson`, `mpdecimal`, `mtools`, `nano`, `nasm`, `nftables`, `ninja`, `openssl`, `pciutils`, `pcre2`, `perl`, `pkgconf`, `popt`, `ports`, `procps-ng`, `python3-attrs`, `python3-babel`, `python3-build`, `python3-cairo`, `python3-calver`, `python3-certifi`, `python3-chardet`, `python3-charset-normalizer`, `python3-cython`, `python3-docutils`, `python3-doxypypy`, `python3-doxyqml`, `python3-editables`, `python3-flit-core`, `python3-gi_docgen`, `python3-gobject`, `python3-hatch-fancy-pypi-readme`, `python3-hatch-vcs`, `python3-hatchling`, `python3-html5lib`, `python3-idna`, `python3-installer`, `python3-jinja2`, `python3-lxml`, `python3-mako`, `python3-markdown`, `python3-markupsafe`, `python3-meson_python`, `python3-numpy`, `python3-packaging`, `python3-pathspec`, `python3-pip`, `python3-pluggy`, `python3-poetry-core`, `python3-psutil`, `python3-pycparser`, `python3-pygdbmi`, `python3-pygments`, `python3-pyparsing`, `python3-pyproject-hooks`, `python3-pyproject_metadata`, `python3-python-dbusmock`, `python3-pytz`, `python3-pyyaml`, `python3-requests`, `python3-setuptools-scm`, `python3-six`, `python3-tomli`, `python3-tomlkit`, `python3-trove-classifiers`, `python3-typing_extensions`, `python3-typogrify`, `python3-urllib3`, `python3-vcs-versioning`, `python3-webencodings`, `python3-wheel`, `rdfind`, `readline`, `rsync`, `shadow`, `signify`, `sqlite`, `squashfs-tools`, `stripping`, `sudo`, `systemd`, `traceroute`, `tzdata`, `vim`, `which`, `wireless_tools`, `wpa_supplicant`, `xfsprogs`, `xxhash`, `zlib`

### Legacy Python install-path review

Direct `setup.py install` remains in: `python3-babel`, `python3-html5lib`, `python3-lxml`, `python3-markupsafe`, `python3-pycparser`, `python3-pytz`, `python3-six`. Review against current upstream packaging when these ports are next rebuilt; do not mass-convert without build testing.

## Package-by-package inventory

| Port | Version | Rel | Build path | build_opt | Flags |
|---|---:|---:|---|---|---|
| `aaa_filesystem` | 1 | 16 | custom | no | custom-review |
| `acl` | 2.4.0 | 2 | extension | no | OK/static |
| `attr` | 2.6.0 | 2 | custom | no | custom-review |
| `autoconf` | 2.73 | 1 | extension | no | OK/static |
| `automake` | 1.18.1 | 1 | extension | no | OK/static |
| `bash` | 5.3 | 1 | extension | yes | OK/static |
| `bash-completion` | 2.18.0 | 1 | custom | no | custom-review |
| `bc` | 7.1.0 | 1 | custom | no | custom-review |
| `bfs-kernel-maintenance` | 1.0 | 3 | custom | no | custom-review |
| `binutils` | 2.47 | 1 | custom | no | custom-review |
| `bison` | 3.8.2 | 1 | extension | no | OK/static |
| `btrfs-progs` | 7.1 | 1 | extension | yes | OK/static |
| `bzip2` | 1.0.8 | 1 | custom | no | custom-review |
| `ca-certificates` | 20260813 | 1 | custom | no | custom-review |
| `ccache` | 4.14 | 1 | custom | no | custom-review |
| `check` | 0.15.2 | 1 | extension | no | OK/static |
| `cmake` | 4.4.3 | 1 | custom | yes | custom-review |
| `coreutils` | 9.12 | 1 | extension | yes | remote-patch |
| `cracklib` | 2.10.3 | 3 | custom | no | custom-review |
| `curl` | 8.22.0 | 1 | extension | yes | OK/static |
| `dash` | 0.5.13.5 | 1 | extension | yes | OK/static |
| `dbus` | 1.16.2 | 2 | custom | no | custom-review |
| `dialog` | 1.3-20260721 | 1 | extension | yes | OK/static |
| `diffutils` | 3.12 | 1 | extension | no | OK/static |
| `dosfstools` | 4.2 | 1 | extension | yes | OK/static |
| `dracut` | 112 | 1 | custom | yes | custom-review |
| `e2fsprogs` | 1.47.4 | 2 | custom | no | custom-review |
| `efibootmgr` | 18 | 2 | custom | no | custom-review |
| `efivar` | 39 | 2 | custom | no | custom-review |
| `elfutils` | 0.196 | 1 | custom | no | custom-review |
| `exfatprogs` | 1.4.3 | 1 | custom | no | custom-review |
| `expat` | 2.8.5 | 1 | extension | no | OK/static |
| `f2fs-tools` | 1.16.0 | 1 | extension | yes | OK/static |
| `fakeroot` | 2.1.4 | 1 | custom | no | custom-review |
| `file` | 5.48 | 1 | extension | no | OK/static |
| `findutils` | 4.11.0 | 1 | extension | yes | OK/static |
| `flex` | 2.6.4 | 1 | extension | no | OK/static |
| `fmt` | 12.2.0 | 3 | custom | no | custom-review |
| `freetype` | 2.14.3 | 1 | custom | no | custom-review |
| `fuse` | 3.18.3 | 1 | extension | no | OK/static |
| `gawk` | 5.4.1 | 1 | extension | no | OK/static |
| `gcc` | 16.2.0 | 2 | custom | no | custom-review |
| `gdbm` | 1.26 | 1 | extension | yes | OK/static |
| `genfstab` | 31 | 2 | custom | no | OK/static |
| `gettext` | 1.0 | 1 | custom | no | custom-review |
| `glibc` | 2.44 | 4 | custom | no | custom-review |
| `gmp` | 6.3.0 | 1 | extension | yes | OK/static |
| `gperf` | 3.3 | 1 | extension | no | OK/static |
| `gptfdisk` | 1.0.10 | 1 | custom | no | remote-patch, custom-review |
| `grep` | 3.12 | 1 | extension | no | OK/static |
| `groff` | 1.24.1 | 1 | extension | yes | OK/static |
| `grub` | 2.14 | 3 | extension | yes | OK/static |
| `grub-efi` | 2.14 | 1 | extension | yes | OK/static |
| `gzip` | 1.14 | 1 | extension | no | OK/static |
| `httpup` | 0.5.1 | 1 | custom | no | custom-review |
| `iana-etc` | 20260817 | 1 | custom | no | custom-review |
| `inetutils` | 2.8 | 1 | extension | yes | OK/static |
| `inih` | 62 | 1 | extension | no | OK/static |
| `intltool` | 0.51.0 | 1 | extension | no | OK/static |
| `iproute2` | 7.2.0 | 1 | extension | no | OK/static |
| `iptables` | 1.8.13 | 1 | extension | yes | OK/static |
| `kbd` | 2.10.0 | 1 | custom | no | custom-review |
| `kmod` | 34.2 | 1 | extension | yes | OK/static |
| `less` | 704 | 1 | extension | no | OK/static |
| `libaio` | 0.3.113 | 2 | custom | no | custom-review |
| `libarchive` | 3.8.9 | 2 | extension | yes | OK/static |
| `libcap` | 2.78 | 1 | custom | no | custom-review |
| `libevent` | 2.1.13 | 2 | custom | no | custom-review |
| `libffi` | 3.8.0 | 1 | extension | yes | OK/static |
| `libmnl` | 1.0.5 | 1 | custom | no | custom-review |
| `libnftnl` | 1.3.2 | 1 | custom | no | custom-review |
| `libnl` | 3.12.0 | 2 | custom | no | custom-review |
| `libnsl` | 2.0.1 | 1 | custom | no | custom-review |
| `libpipeline` | 1.5.8 | 1 | extension | no | OK/static |
| `libpng` | 1.6.58 | 3 | custom | no | custom-review |
| `libpwquality` | 1.4.5 | 2 | custom | no | custom-review |
| `libtirpc` | 1.3.7 | 1 | extension | yes | OK/static |
| `libtool` | 2.6.2 | 1 | extension | no | OK/static |
| `liburcu` | 0.15.6 | 1 | custom | no | custom-review |
| `libuv` | 1.52.1 | 2 | custom | no | custom-review |
| `libxcrypt` | 4.5.2 | 1 | extension | yes | OK/static |
| `libyaml` | 0.2.5 | 1 | custom | no | custom-review |
| `linux` | 7.2.7 | 1 | custom | no | custom-review |
| `linux-firmware` | 20260916 | 1 | custom | no | custom-review |
| `linux-headers` | 6.18.53 | 1 | custom | no | custom-review |
| `linux-lts` | 6.18.53 | 1 | custom | no | custom-review |
| `linux-pam` | 1.7.2 | 4 | extension | yes | OK/static |
| `lvm2` | 2.03.42 | 2 | custom | yes | custom-review |
| `lz4` | 1.10.0 | 1 | custom | no | custom-review |
| `lzo` | 2.10 | 1 | extension | yes | OK/static |
| `m4` | 1.4.21 | 1 | extension | no | OK/static |
| `make` | 4.4.1 | 1 | extension | no | OK/static |
| `make-ca` | 1.16.1 | 6 | custom | no | custom-review |
| `man-db` | 2.13.1 | 1 | extension | yes | OK/static |
| `man-pages` | 6.19 | 1 | custom | no | custom-review |
| `mandoc` | 1.14.6 | 1 | custom | no | custom-review |
| `mdadm` | 4.6 | 2 | custom | no | custom-review |
| `meson` | 1.12.1 | 1 | custom | no | custom-review |
| `mpc` | 1.4.1 | 1 | extension | no | OK/static |
| `mpdecimal` | 4.0.1 | 1 | custom | no | custom-review |
| `mpfr` | 4.2.2 | 1 | extension | yes | OK/static |
| `mtools` | 4.0.49 | 2 | custom | no | custom-review |
| `nano` | 9.2 | 1 | custom | no | custom-review |
| `nasm` | 3.02 | 4 | custom | no | custom-review |
| `ncurses` | 6.6 | 1 | extension | yes | OK/static |
| `nftables` | 1.1.7 | 1 | custom | no | custom-review |
| `ninja` | 1.13.2 | 1 | custom | no | custom-review |
| `openssh` | 10.5p1 | 2 | extension | yes | OK/static |
| `openssl` | 4.0.2 | 1 | custom | no | custom-review |
| `patch` | 2.8 | 1 | extension | no | OK/static |
| `pciutils` | 3.15.0 | 1 | custom | no | custom-review |
| `pcre2` | 10.48 | 1 | custom | no | custom-review |
| `perl` | 5.44.0 | 1 | custom | no | custom-review |
| `perl-class-inspector` | 1.36 | 1 | extension | no | OK/static |
| `perl-file-sharedir` | 1.118 | 1 | extension | no | OK/static |
| `perl-file-sharedir-install` | 0.14 | 1 | extension | no | OK/static |
| `perl-xml-parser` | 2.59 | 1 | extension | no | OK/static |
| `pkgconf` | 3.0.7 | 1 | custom | no | custom-review |
| `pkgutils` | 5.40.12 | 38 | extension | no | OK/static |
| `popt` | 1.19 | 1 | custom | no | custom-review |
| `ports` | 1.6 | 3 | custom | no | custom-review |
| `procps-ng` | 4.0.7 | 1 | custom | no | custom-review |
| `prt-get` | 5.19.10 | 2 | extension | no | OK/static |
| `prt-utils` | 1.3.7 | 4 | extension | no | OK/static |
| `psmisc` | 23.7 | 1 | extension | no | OK/static |
| `python3` | 3.14.7 | 1 | extension | yes | remote-patch |
| `python3-attrs` | 26.1.0 | 1 | custom | no | custom-review |
| `python3-babel` | 2.18.0 | 1 | custom | no | custom-review, setup.py |
| `python3-build` | 1.6.1 | 1 | custom | no | custom-review |
| `python3-cairo` | 1.29.1 | 2 | custom | no | custom-review |
| `python3-calver` | 2025.10.20 | 1 | custom | no | custom-review |
| `python3-certifi` | 2026.7.22 | 2 | custom | no | custom-review |
| `python3-chardet` | 7.6.0 | 3 | custom | no | custom-review |
| `python3-charset-normalizer` | 3.5.1 | 1 | custom | no | custom-review |
| `python3-cython` | 3.3.0 | 1 | custom | no | custom-review |
| `python3-docutils` | 0.23 | 1 | custom | no | custom-review |
| `python3-doxypypy` | 0.8.8.7 | 1 | custom | no | custom-review |
| `python3-doxyqml` | 0.5.3 | 1 | custom | no | custom-review |
| `python3-editables` | 0.6 | 1 | custom | no | custom-review |
| `python3-flit-core` | 4.1.0 | 1 | custom | no | custom-review |
| `python3-gi_docgen` | 2026.1 | 1 | custom | no | custom-review |
| `python3-gobject` | 3.58.0 | 1 | custom | no | custom-review |
| `python3-hatch-fancy-pypi-readme` | 25.1.0 | 2 | custom | no | custom-review |
| `python3-hatch-vcs` | 0.5.0 | 1 | custom | no | custom-review |
| `python3-hatchling` | 1.32.4 | 1 | custom | no | custom-review |
| `python3-html5lib` | 1.1 | 5 | custom | no | custom-review, setup.py |
| `python3-idna` | 3.20 | 1 | custom | no | custom-review |
| `python3-installer` | 1.0.1 | 1 | custom | no | custom-review |
| `python3-jinja2` | 3.1.6 | 1 | custom | no | custom-review |
| `python3-lxml` | 6.1.3 | 1 | custom | no | custom-review, setup.py |
| `python3-mako` | 1.4.1 | 1 | custom | no | custom-review |
| `python3-markdown` | 3.10.3 | 1 | custom | no | custom-review |
| `python3-markupsafe` | 3.0.3 | 1 | custom | no | custom-review, setup.py |
| `python3-meson_python` | 0.20.0 | 1 | custom | no | custom-review |
| `python3-numpy` | 2.5.3 | 1 | custom | no | custom-review |
| `python3-packaging` | 26.3 | 1 | custom | no | custom-review |
| `python3-pathspec` | 1.1.1 | 1 | custom | no | custom-review |
| `python3-pip` | 26.2.1 | 1 | custom | no | custom-review |
| `python3-pluggy` | 1.6.0 | 1 | custom | no | custom-review |
| `python3-ply` | 3.11 | 1 | extension | no | OK/static |
| `python3-poetry-core` | 2.5.0 | 1 | custom | no | custom-review |
| `python3-psutil` | 7.2.2 | 1 | custom | no | custom-review |
| `python3-pycparser` | 3.0 | 1 | custom | no | custom-review, setup.py |
| `python3-pygdbmi` | 0.11.0.0 | 1 | custom | no | custom-review |
| `python3-pygments` | 2.21.0 | 1 | custom | no | custom-review |
| `python3-pyparsing` | 3.3.3 | 1 | custom | no | custom-review |
| `python3-pyproject-hooks` | 1.3.3 | 1 | custom | no | custom-review |
| `python3-pyproject_metadata` | 0.12.1 | 1 | custom | no | custom-review |
| `python3-python-dbusmock` | 0.38.1 | 2 | custom | no | custom-review |
| `python3-pytz` | 2026.3.post1 | 1 | custom | no | custom-review, setup.py |
| `python3-pyxdg` | 0.28 | 1 | extension | no | OK/static |
| `python3-pyyaml` | 6.0.3 | 3 | custom | no | custom-review |
| `python3-requests` | 2.34.2 | 2 | custom | no | custom-review |
| `python3-setuptools` | 84.0.0 | 1 | extension | no | OK/static |
| `python3-setuptools-scm` | 10.3.4 | 1 | custom | no | custom-review |
| `python3-six` | 1.17.0 | 2 | custom | no | custom-review, setup.py |
| `python3-tomli` | 2.4.1 | 1 | custom | no | custom-review |
| `python3-tomlkit` | 0.15.1 | 1 | custom | no | custom-review |
| `python3-trove-classifiers` | 2026.9.21.13 | 1 | custom | no | custom-review |
| `python3-typing_extensions` | 4.16.0 | 1 | custom | no | custom-review |
| `python3-typogrify` | 2.1.0 | 1 | custom | no | custom-review |
| `python3-urllib3` | 2.7.0 | 1 | custom | no | custom-review |
| `python3-vcs-versioning` | 2.4.1 | 1 | custom | no | custom-review |
| `python3-webencodings` | 0.6.1 | 2 | custom | no | custom-review |
| `python3-wheel` | 0.48.0 | 1 | custom | no | custom-review |
| `rdfind` | 1.8.0 | 1 | custom | no | custom-review |
| `readline` | 8.3 | 1 | custom | no | custom-review |
| `rsync` | 3.5.1 | 1 | custom | no | custom-review |
| `sed` | 4.10 | 1 | extension | no | OK/static |
| `shadow` | 4.20.2 | 2 | custom | no | custom-review |
| `signify` | 0.14 | 1 | custom | no | custom-review |
| `sqlite` | 3.53.4 | 1 | custom | no | custom-review |
| `squashfs-tools` | 4.7.5 | 2 | custom | no | custom-review |
| `stripping` | 1.0 | 1 | custom | no | custom-review |
| `sudo` | 1.9.17p2 | 1 | custom | yes | custom-review |
| `systemd` | 261.3 | 1 | custom | no | custom-review |
| `tar` | 1.35 | 1 | extension | no | OK/static |
| `texinfo` | 7.3 | 1 | extension | no | OK/static |
| `traceroute` | 2.1.6 | 1 | custom | no | custom-review |
| `tzdata` | 2026d | 1 | custom | no | custom-review |
| `util-linux` | 2.42.4 | 1 | extension | yes | OK/static |
| `vim` | 9.2.1119 | 1 | custom | no | custom-review |
| `which` | 2.25 | 1 | custom | no | custom-review |
| `wireless_tools` | 30.pre9 | 4 | custom | no | custom-review |
| `wpa_supplicant` | 2.12 | 6 | custom | no | custom-review |
| `xfsprogs` | 7.2.0 | 1 | custom | no | custom-review |
| `xxhash` | 0.8.4 | 1 | custom | no | custom-review |
| `xz` | 5.8.4 | 1 | extension | no | OK/static |
| `zlib` | 1.3.2 | 1 | custom | no | remote-patch, custom-review |
| `zstd` | 1.5.7 | 1 | extension | no | OK/static |
