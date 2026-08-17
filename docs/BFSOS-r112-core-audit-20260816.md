# BFSOS r111 core/packaging audit — 2026-08-16

## Policy

Latest stable upstream is preferred. Current LFS/BLFS and CRUX are integration references; BFSOS-specific patches and compatibility constraints take precedence when documented. Tracker checkboxes remain open until maintainer build/install/boot testing.

## Completed tree cleanup

- Removed: `gcc13`, `filesystem`, `lfs-bootscripts`, `sysvinit`, `runit`, `runit-rc`, `mkinitcpio`, `mkinitramfs`, `mkinitcpio-busybox`.
- Moved non-base packages from core to opt: `argon2`, `dejagnu`, `isl`, `fuse2`, `freetype2`, `git`, `gpm`, `scons`, `wget`, `wgetpaste`, `net-tools`, `wireless-tools`, `syslinux`, `sysklogd`, `eudev`, `dhcpcd`, `tcl`, `expect`.
- Removed duplicate opt copies of `cracklib` and `fakeroot`; retained canonical core copies.
- Core/opt duplicate directory check: none.

## Build safety and caching

- Added static `pkgmk` system account (UID/GID 82).
- Added `bfs-pkgmk` wrapper for root `prt-get` builds: delegates build phase to `pkgmk` through `fakeroot`; falls back to normal pkgmk when privilege helpers are unavailable during bootstrap/migration.
- `/usr/ports` remains root-managed; package source/package/work and ccache locations are writable by `pkgmk`.
- ccache moved into core and refreshed to 4.13.6; fmt 12.2.0 and xxhash 0.8.3 are core dependencies.
- ccache automatic default: 20G in VMs, physical-RAM-sized disk cache on bare metal; user override supported.

## Kernel / CA fixes

- Normal and LTS post-install scripts remove generic `/boot/vmlinuz-BFS-*` and generic initramfs aliases before GRUB regeneration.
- LTS base release and final `-BFS-LTS` release are handled separately; build/modules use explicit LTS LOCALVERSION.
- ca-certificates post-install repairs `/etc/ssl/certs/ca-certificates.crt -> ../cert.pem`.

## Build settings UI

- Bootstrap Settings now includes compiler/build settings for jobs, portable/native/custom CFLAGS, ccache enablement and cache size. Customized Bootstrap values persist and are applied to applicable base builds/pkgmk configuration.
- Installer Settings now includes installed-system compiler/build overrides. `inherited` preserves Bootstrap/base values.

## Refreshed non-LFS ports in this pass

- `ccache 4.13.6`, `fmt 12.2.0`, `xxhash 0.8.3`, `mdadm 4.4`, `pciutils 3.15.0`, `gptfdisk 1.0.10`, `mtools 4.0.49`, `squashfs-tools 4.7.5`, `nasm 3.02`, `libarchive 3.8.8`, `dash 0.5.13`, `nftables 1.1.6`, `libnftnl 1.3.1`, `rsync 3.4.4`.
- nftables and rsync daemon packaging now uses systemd units instead of the removed SysV service files.
- `prt-get` remains 5.19.9 because that is the current CRUX 3.8 port version verified during this audit.

## Static validation

- All core and opt Pkgfiles pass `bash -n`.
- Bootstrap, consolidated installer, kernel post-install scripts, CA post-install, ccache post-install and pkgmk wrapper pass `bash -n`.
- `ports/core/REPO` and `ports/opt/REPO` regenerated after collection changes.
- No duplicate package directory names remain between core and opt.

## Required maintainer regression tests

1. Clean Bootstrap Stage 1/2/3/4 and archive creation.
2. Verify `pkgmk` account/cache ownership and a normal `prt-get sysup` using unprivileged build delegation.
3. Build the same C/C++ package twice and inspect `ccache -s`.
4. Fresh install and upgrade test for ca-certificates, followed by HTTPS curl/pkgmk download.
5. Normal kernel rebuild + GRUB reboot on RAID/LUKS/LVM.
6. Build/install linux-lts; verify normal kernel remains default and both versioned GRUB/initramfs entries boot.
7. Exercise Bootstrap -> Installer build-setting inheritance and installer override behavior.

## Retained core inventory

- `aaa_filesystem` — `1`
- `acl` — `2.4.0`
- `attr` — `2.6.0`
- `autoconf` — `2.73`
- `automake` — `1.18.1`
- `bash` — `5.3`
- `bc` — `7.0.3`
- `binutils` — `2.47`
- `bison` — `3.8.2`
- `btrfs-progs` — `7.1`
- `bzip2` — `1.0.8`
- `ca-certificates` — `20260716`
- `ccache` — `4.13.6`
- `check` — `0.15.2`
- `cmake` — `4.4.2`
- `coreutils` — `9.11`
- `cracklib` — `2.9.11`
- `curl` — `8.21.0`
- `dash` — `0.5.13`
- `dbus` — `1.16.2`
- `dialog` — `1.3-20260107`
- `diffutils` — `3.12`
- `dosfstools` — `4.2`
- `dracut` — `111`
- `e2fsprogs` — `1.47.4`
- `efibootmgr` — `18`
- `efivar` — `39`
- `elfutils` — `0.195`
- `exfatprogs` — `1.4.2`
- `expat` — `2.8.3`
- `f2fs-tools` — `1.16.0`
- `fakeroot` — `1.37.1.1`
- `file` — `5.48`
- `findutils` — `4.11.0`
- `flex` — `2.6.4`
- `fmt` — `12.2.0`
- `freetype` — `2.14.3`
- `fuse` — `3.18.2`
- `gawk` — `5.4.1`
- `gcc` — `16.2.0`
- `gdbm` — `1.26`
- `genfstab` — `1.0`
- `gettext` — `1.0`
- `glibc` — `2.44`
- `gmp` — `6.3.0`
- `gperf` — `3.3`
- `gptfdisk` — `1.0.10`
- `grep` — `3.12`
- `groff` — `1.24.1`
- `grub` — `2.14`
- `grub-efi` — `2.14`
- `gzip` — `1.14`
- `httpup` — `0.5.1`
- `iana-etc` — `20260805`
- `inetutils` — `2.8`
- `inih` — `62`
- `intltool` — `0.51.0`
- `iproute2` — `7.1.0`
- `iptables` — `1.8.13`
- `kbd` — `2.10.0`
- `kmod` — `34.2`
- `less` — `704`
- `libaio` — `0.3.113`
- `libarchive` — `3.8.8`
- `libcap` — `2.78`
- `libevent` — `2.1.12`
- `libffi` — `3.8.0`
- `libmnl` — `1.0.5`
- `libnftnl` — `1.3.1`
- `libnl` — `3.11.0`
- `libnsl` — `2.0.1`
- `libpipeline` — `1.5.8`
- `libpng` — `1.6.58`
- `libtirpc` — `1.3.7`
- `libtool` — `2.6.2`
- `liburcu` — `0.15.6`
- `libuv` — `1.51.0`
- `libxcrypt` — `4.5.2`
- `linux` — `7.1.8`
- `linux-api-headers` — `7.1.8`
- `linux-firmware` — `20260622`
- `linux-headers` — `7.1.8`
- `linux-lts` — `6.12.101`
- `linux-pam` — `1.7.2`
- `lvm2` — `2.03.41`
- `lz4` — `1.10.0`
- `lzo` — `2.10`
- `m4` — `1.4.21`
- `make` — `4.4.1`
- `make-ca` — `1.16.1`
- `man-db` — `2.13.1`
- `man-pages` — `6.18`
- `mandoc` — `1.14.6`
- `mdadm` — `4.4`
- `meson` — `1.12.0`
- `mpc` — `1.4.1`
- `mpdecimal` — `4.0.1`
- `mpfr` — `4.2.2`
- `mtools` — `4.0.49`
- `nano` — `9.1`
- `nasm` — `3.02`
- `ncurses` — `6.6`
- `nftables` — `1.1.6`
- `ninja` — `1.13.2`
- `openssh` — `10.4p1`
- `openssl` — `4.0.1`
- `patch` — `2.8`
- `pciutils` — `3.15.0`
- `pcre2` — `10.47`
- `perl` — `5.44.0`
- `perl-xml-parser` — `2.47`
- `pkgconf` — `3.0.5`
- `pkgutils` — `5.40.12`
- `popt` — `1.19`
- `ports` — `1.6`
- `procps-ng` — `4.0.7`
- `prt-get` — `5.19.9`
- `prt-utils` — `1.3.7`
- `psmisc` — `23.7`
- `python3` — `3.14.7`
- `python3-attrs` — `24.3.0`
- `python3-babel` — `2.18.0`
- `python3-build` — `1.5.0`
- `python3-cairo` — `1.27.0`
- `python3-calver` — `2022.6.26`
- `python3-certifi` — `2024.12.14`
- `python3-chardet` — `5.1.0`
- `python3-charset-normalizer` — `3.0.1`
- `python3-docutils` — `0.21.2`
- `python3-doxypypy` — `0.8.8.7`
- `python3-doxyqml` — `0.5.3`
- `python3-editables` — `0.5`
- `python3-flit-core` — `4.0.2`
- `python3-gi_docgen` — `2024.1`
- `python3-gobject` — `3.50.0`
- `python3-hatch-fancy-pypi-readme` — `24.1.0`
- `python3-hatch-vcs` — `0.4.0`
- `python3-hatchling` — `1.27.0`
- `python3-html5lib` — `1.1`
- `python3-idna` — `3.10`
- `python3-installer` — `1.0.1`
- `python3-jinja2` — `3.1.6`
- `python3-lxml` — `5.3.0`
- `python3-mako` — `1.3.6`
- `python3-markdown` — `3.4.1`
- `python3-markupsafe` — `3.0.3`
- `python3-meson_python` — `0.17.0`
- `python3-numpy` — `2.2.2`
- `python3-packaging` — `26.3`
- `python3-pathspec` — `0.12.1`
- `python3-pip` — `26.1.2`
- `python3-pluggy` — `1.5.0`
- `python3-ply` — `3.11`
- `python3-psutil` — `5.9.8`
- `python3-pycparser` — `2.22`
- `python3-pygdbmi` — `0.11.0.0`
- `python3-pygments` — `2.18.0`
- `python3-pyproject-hooks` — `1.2.0`
- `python3-pyproject_metadata` — `0.8.0`
- `python3-python-dbusmock` — `0.31.1`
- `python3-pytz` — `2026.2`
- `python3-pyxdg` — `0.28`
- `python3-pyyaml` — `6.0.2`
- `python3-requests` — `2.32.2`
- `python3-setuptools` — `84.0.0`
- `python3-setuptools-scm` — `8.2.1`
- `python3-six` — `1.16.0`
- `python3-tomli` — `2.4.1`
- `python3-trove-classifiers` — `2024.4.10`
- `python3-typing_extensions` — `4.12.2`
- `python3-typogrify` — `2.0.7`
- `python3-urllib3` — `2.2.3`
- `python3-webencodings` — `0.5.1`
- `python3-wheel` — `0.48.0`
- `rdfind` — `1.8.0`
- `readline` — `8.3`
- `rsync` — `3.4.4`
- `sed` — `4.10`
- `shadow` — `4.20.2`
- `signify` — `0.14`
- `sqlite` — `3.53.4`
- `squashfs-tools` — `4.7.5`
- `stripping` — `1.0`
- `sudo` — `1.9.17p2`
- `systemd` — `261.2`
- `tar` — `1.35`
- `texinfo` — `7.3`
- `tzdata` — `2026c`
- `util-linux` — `2.42.2`
- `vim` — `9.2.0954`
- `which` — `2.25`
- `wireless_tools` — `30.pre9`
- `wpa_supplicant` — `2.11`
- `xfsprogs` — `7.1.1`
- `xxhash` — `0.8.3`
- `xz` — `5.8.3`
- `zlib` — `1.3.2`
- `zstd` — `1.5.7`
