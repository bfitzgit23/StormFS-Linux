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
