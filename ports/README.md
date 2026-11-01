# BFSOS / StormFS ports

This tree uses the **scratchpkg** port format. Each package is a port directory
containing an `spkgbuild` build script and a `depends` file listing its
dependencies, one per line. Ports are built with `pkgbuild` and installed with
`pkgadd`, managed through the `scratch` front-end.

The packaging tree was migrated from the CRUX `pkgmk`/`prt-get` layout; see
`scripts/pkgfile-to-spkgbuild.py` for the exact mapping and
`scripts/bfs-scratchpkg-audit.sh` for the conformance check.

## Format

```sh
# description	: Short description
# homepage	: https://example.com/
# maintainer	: StormFS maintainers

name=example          # must equal the port directory name, lower case
version=1.0           # may not contain '-'
release=1             # integer 1-99
source="https://example.com/example-$version.tar.gz
        example.patch"

build() {
	cd "$name-$version" || return 1
	./configure --prefix=/usr
	make
	make DESTDIR="$PKG" install
}
```

* `build()` is the single build hook. `pkgbuild` runs it with the current
  directory set to the unpacked sources and `$PKG` as the staging root.
* `source` is a space separated list. Downloadable URLs land in the source
  cache; local files in the port directory (patches, inittab, service scripts)
  are copied into the work tree. `newname::url` stores a download under a
  different file name, and `noextract="file"` copies instead of extracting.
* Patch sources are applied automatically by the recipes that carry them, at
  the top of `build()`.
* Checksums live in `.checksums` (blake3). `pkgbuild -g` regenerates them, and
  `-m` skips verification.
* `pre-install`, `post-install`, `pre-remove` and `post-remove` scripts in the
  port directory are run as hooks by `scratch`, before or after the matching
  transaction.

## Init system

**OpenRC is the init system.** systemd has been removed from this tree: there is
no systemd port, no systemd init profile, and no recipe builds systemd
integration or ships unit files. Recipes that used to generate units or enable
services now leave that to the init port (`ports/opt/openrc` and
`ports/opt/openrc-init-scripts`).

A SysVinit profile remains available as an alternative to OpenRC. Select it
before a bootstrap:

```sh
scripts/select-init-profile.sh openrc      # default
scripts/select-init-profile.sh sysvinit
BFS_INIT_SYSTEM=openrc ./bootstrap.sh 2
```

`profiles/init/` holds the per-profile base package manifests.

## Shared build helpers

`ports/core/bfs-spkgbuild-macros` installs `/usr/share/bfsos/spkgbuild.helper`.
Recipes without an explicit build system hook source it and call
`bfs_autobuild`, which reproduces the build-type detection the old pkgmk
extension performed (meson, configure, cmake, setup.py, Makefile.PL, Makefile)
driven by `build_opt`. The helper also provides the compat-32 (i686)
environment (`bfs_compat32`) and payload validation.

## Collections

| Collection | Contents |
| --- | --- |
| `core` | base system and build tools, including `scratchpkg` |
| `opt` | desktop stack, OpenRC service scripts, Flatpak |
| `xorg`, `wayland-ish` desktop collections | X.Org, GNOME, Plasma, Xfce, LXQt |
| `compat-32` | 32-bit libraries for Steam and Wine |
| `iso` | live-media packages |
| `contrib` | community ports |

## Common commands

```sh
scratch sync                 # update port repositories
scratch install -y firefox   # build and install a port with its dependencies
scratch build -w vim         # build only, keep the work directory
scratch sysup -y             # upgrade every installed port
scratch remove -y firefox    # remove a port
scratch info firefox         # show build metadata
scratch depends firefox      # print direct dependencies
scratch files firefox        # list installed files
scratch integrity            # verify installed files against the database
```

## Flatpak / Flathub

The Flatpak stack lives in `ports/opt` with supporting pieces in `ports/core`
and `ports/gnome`:

- `flatpak` — runtime and CLI (built with `-D systemd=disabled`; service
  integration is owned by the init port);
- `ostree` — the backing store;
- `flatpak-xdg-utils` — sandboxed `xdg-open`/portal helpers;
- `flathub` — ships `flathub.flatpakrepo` and registers the system-wide remote
  in `post-install`;
- `python3-pyparsing`, `bubblewrap`, `xdg-dbus-proxy`,
  `xdg-desktop-portal*`, `appstream`, `libxmlb`.

Install the graphical store:

```sh
scratch install -y gnome-software
```

## Conventions

- Port directory names and `name=` are lower case and identical.
- Meson packages use `--prefix=/usr --buildtype=release`.
- Initi-agnostic packages must not install service units; the init port owns
  service integration.
- Python module ports use the `python3-*` naming convention and install with
  pip under `--prefix=/usr`.
- New recipes are LF-only; do not introduce CRLF line endings.
