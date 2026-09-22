# BFSOS ports

This tree follows the upstream BFSOS/CRUX packaging format. Each package is a
port directory containing a `Pkgfile`; optional local sources, patches,
`post-install`, `.md5sum`, `.footprint`, and signature files remain beside it.
Builds are performed with `pkgmk` and dependencies are declared in the
`# Depends:` header for `prt-get`.

The current baseline is imported from:

<https://codeberg.org/bmadonnaster/BFSOS>

## Init profiles

The bootstrap supports one selected init system per build:

- `systemd` — the upstream default;
- `openrc` — OpenRC plus SysVinit compatibility and BFSOS OpenRC service scripts;
- `sysvinit` — SysVinit plus the LFS boot scripts.

Select interactively or non-interactively before building:

```sh
scripts/select-init-profile.sh
scripts/select-init-profile.sh openrc
BFS_INIT_SYSTEM=openrc ./bootstrap.sh 2
```

The selection is stored in `.bfs-init-profile` and is consumed by the
bootstrap's base package transaction. Profile package manifests live under
`profiles/init/`.

All three init packages are kept as separate ports. Service implementations
are not removed from packages merely because another profile is selected;
profile-specific service packages install only the selected init integration.

## Flatpak / Flathub

The Flatpak application stack lives in `ports/opt` with supporting pieces in
`ports/core` and `ports/gnome`:

- `flatpak` — the Flatpak runtime and CLI (init-neutral: built with
  `-Dsystemd=disabled`, service integration owned by the init profiles);
- `ostree` — libostree, Flatpak's backing store;
- `flatpak-xdg-utils` — sandboxed `xdg-open`/portal helpers;
- `flathub` — ships the official `flathub.flatpakrepo` (including its GPG
  key) and registers the system-wide Flathub remote in `post_install`;
- `python3-pyparsing` — Flatpak build dependency;
- `bubblewrap`, `xdg-dbus-proxy`, `xdg-desktop-portal*`, `appstream`,
  `libxmlb` — existing sandbox/portal/AppStream stack.

Install the graphical store with native-package and Flathub integration:

```sh
prt-get depinst gnome-software
```

`ports/gnome/gnome-software` builds with the Flatpak plugin enabled and
installs `bfsos-appstream`, which regenerates the native AppStream catalog
(`/usr/share/app-info/xmls/bfsos.xml.gz`) from the prt-get/pkgutils package
database so BFSOS applications appear in the store alongside Flathub apps.

## Conventions

- `pkg_build()` is the canonical BFSOS build hook executed by `pkgmk`
  extensions; plain `build()` is legacy CRUX style and should not be used in
  new recipes.
- Meson packages use `--prefix=/usr --buildtype=release`.
- Init-related service artifacts (systemd units, tmpfiles) are removed from
  packages in `pkg_build()`; init profiles own service integration.
- Python module ports use the `python3-*` naming convention and install with
  pip under `--prefix=/usr`.
- New recipes are LF-only; do not reintroduce CRLF line endings.
