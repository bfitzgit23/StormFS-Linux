# BFSOS maintained command-line entry points

The interactive menus remain the default user interface, but Bootstrap and the ISO builder also provide direct command-line entry points for repeatable maintainer workflows.

## Bootstrap

```text
./bootstrap.sh                     interactive menu
./bootstrap.sh 1                   build temporary toolchain
./bootstrap.sh 2                   build base with temporary toolchain
./bootstrap.sh 3                   rebuild base with final toolchain
./bootstrap.sh 4                   verify base
./bootstrap.sh 5                   create/compress base archive
./bootstrap.sh 6                   restore newest base archive
./bootstrap.sh 7                   restore newest toolchain archive
./bootstrap.sh 8                   chroot into BFSOS root
./bootstrap.sh 9                   launch installer
./bootstrap.sh full                run complete automated build through Stage 5
./bootstrap.sh resume-full         resume at first incomplete stage
./bootstrap.sh iso [ISO options]   launch ISO builder
./bootstrap.sh --help              full maintained usage
```

Invalid arguments fail instead of silently opening the menu.

## Noninteractive host bootstrap

Run this from the repository root on the host. It requires a regular user and
sudo; Stage 1 must not be run as root. The `sudo -v` at the start is the only
intended interactive step, and the state directory persists across interrupted
builds.

<!-- noninteractive-host-bootstrap:start -->
```sh
sudo -v || exit 1
BFS_STATE_DIR="${BFS_STATE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/bfsos/bootstrap}" \
BFS_FULL_BOOTSTRAP_ASSUME_YES=yes \
BFS_FULL_BOOTSTRAP_NO_INSTALL_PROMPT=yes \
./bootstrap.sh full
```
<!-- noninteractive-host-bootstrap:end -->

`BFS_FULL_BOOTSTRAP_ASSUME_YES=yes` skips the full-build confirmation.
`BFS_FULL_BOOTSTRAP_NO_INSTALL_PROMPT=yes` skips the final installer handoff.
Keep `BFS_STATE_DIR` on persistent storage and use the same path if you later
resume with `./bootstrap.sh resume-full`. A long unattended build also needs a
sudo policy whose timestamp does not expire before the root stages run.

## ISO builder

```text
scripts/bfs-build-iso.sh
scripts/bfs-build-iso.sh --local-base /path/to/BFSOS-base-0.9.0-x86_64.tar.zst
scripts/bfs-build-iso.sh --sourceforge-base
scripts/bfs-build-iso.sh --refresh-base
scripts/bfs-build-iso.sh --git-ref main
```

By default the builder prefers a verified current-release base from the maintained local archive area. Explicit SourceForge mode is useful for release-mirror validation. `--refresh-base` forces a new remote download.

## Stage3 archive builder for LFS systems (scratchpkg / pacman)

`scripts/lfs-mkstage3.sh` builds or packs an LFS root filesystem as a stage3
archive with either package manager. It is the adaptation of the Vylen
`make_tarball.sh` (emerald/`.epkg`) flow for LFS + scratchpkg and LFS + pacman,
and keeps that script's config file, package list and `--clean`/`--compress`/
`--force` interface.

```text
scripts/lfs-mkstage3.sh --pkgmgr scratchpkg --rootfs /mnt/lfs \
    --pkg-dir /var/cache/scratchpkg/packages --packages lfs-packages.txt --compress
scripts/lfs-mkstage3.sh --pkgmgr pacman --rootfs /mnt/lfs --compress --compressor zstd
scripts/lfs-mkstage3.sh --rootfs /mnt/lfs --compress --dry-run   # autodetect, print only
```

The package manager is autodetected from the root (scratchpkg
`var/lib/scratchpkg/db`, pacman `var/lib/pacman`) unless `--pkgmgr` is given.
`--compress` on an already populated root packs it and nothing else.
`scripts/lfs-mkstage3.conf.example` documents the defaults, and
`bash scripts/tests/test-lfs-mkstage3.sh` runs the regression test.

## Installer

```text
scripts/install-bfs-menu-current.sh
scripts/install-bfs-menu-current.sh --console-font 20
scripts/install-bfs-menu-current.sh --no-log
scripts/install-bfs-menu-current.sh --log-file /path/to/log
```

The installer currently remains menu-driven for destructive/storage decisions. Reusable non-secret configuration profiles can be saved/loaded from Installer Settings. A future fully non-interactive installation mode must require explicit storage/account policy rather than guessing destructive defaults.
