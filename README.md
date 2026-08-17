# BFSOS

BFSOS is an x86_64 source-built Linux distribution maintained by Brian Madonna. It uses an LFS/MLFS-style bootstrap, CRUX `pkgutils`/ports for package builds, `prt-get` for dependency-aware package management, systemd as the default init system, and a Dialog-driven installer with support for advanced storage layouts.

> **Status:** BFSOS is approaching the 1.0 release-candidate stage. The core bootstrap, installer, storage stack, and boot path are under active regression testing. Treat current builds as development/RC software and keep backups of important data.

## Core design

- Source-built temporary toolchain and base system.
- Optional final-toolchain rebuild to validate that the base can rebuild itself.
- CRUX-style ports and `pkgutils`, extended for BFSOS build conventions.
- `prt-get` dependency management and `ports -u` repository synchronization.
- x86_64 multilib support with 32-bit libraries under `/usr/lib32`.
- systemd by default.
- Dracut initramfs generation and GRUB bootloader support.
- UEFI and legacy BIOS installation paths.
- Installer support for Btrfs subvolumes/snapshots, LUKS, LVM, md RAID (linear/JBOD, RAID0, RAID1, RAID10, RAID4/5/6), and combinations of those layers.
- Kernel selection between the current BFSOS kernel and a broad-support Linux 6.12 LTS flavor carrying the Debian 6.12 patch series.
- Optional installer-managed ZRAM swap with explicit enable/disable and configurable sizing.

## Repository layout

- `bootstrap.sh` — authoritative BFSOS bootstrap menu and build stages.
- `ports/` — package recipes. `ports/core` is the release-critical base collection; other collections are broader and may receive cleanup independently of the 1.0 core release.
- `scripts/install-bfs-menu-*.sh` — installer revisions; use the newest validated revision.
- `scripts/` — maintenance, migration, ports, and repository helpers.
- `archives/` — generated toolchain/base archives (normally excluded from Git).
- `logs/` — bootstrap/installer logs (normally excluded from release source archives).

## Recommended build environment

The Gentoo LiveGUI ISO is the primary development/test environment. A Linux host with working compiler/build tools, sufficient disk space, and network access can also be used.

```sh
git clone https://codeberg.org/bmadonnaster/BFSOS.git
cd BFSOS
./bootstrap.sh
```

The interactive bootstrap menu is preferred because it tracks stage readiness, logging, archives, and installer handoff.

## Bootstrap stages

The normal release path is:

1. **Build temporary toolchain** — run as a regular user.
2. **Build base system with temporary toolchain** — requires root; the menu uses `sudo`.
3. **Rebuild base system with final toolchain** — optional but recommended for release validation.
4. **Verify completed base system** — required before archiving.
5. **Create and verify base rootfs archive** — required for installer deployment.
6. Restore newest base rootfs archive.
7. Restore newest temporary-toolchain archive.
8. Chroot into the built/restored BFSOS rootfs.
9. Launch the newest BFSOS installer.

Generated archives are kept under `archives/toolchain/` and `archives/base/`.

## Installer and storage

The installer can construct layered storage such as:

```text
md RAID -> LUKS -> LVM -> Btrfs subvolumes
```

or independent encrypted/LVM stacks for root, `/usr`, `/opt`, `/home`, and `/var`. It generates `/etc/fstab`, `/etc/crypttab`, `/etc/mdadm.conf`, Dracut configuration, persistent GRUB storage arguments, and the final initramfs/bootloader configuration from the selected topology.

Because storage/boot regressions can make a system unbootable, new RAID/LUKS/LVM combinations should be tested in a VM before deploying them to important bare-metal systems.

## Package management

Update the ports tree and installed packages with:

```sh
ports -u
prt-get sysup
```

Install a package and dependencies with:

```sh
prt-get depinst <package>
```

BFSOS uses `python3` as the Python 3 package name; Python module ports use the `python3-*` naming convention.

## Logs and bug reports

Bootstrap package logs are written below `logs/toolchain/` and `logs/base/`. Installer logs are preserved in the installed system under `/var/log/bfs/installer/` when logging is enabled.

When reporting a bug, include the failing stage/package, relevant log, storage topology when applicable, kernel/initramfs version, and whether the failure occurred in a VM or on bare metal.

Issues and support: https://codeberg.org/bmadonnaster/BFSOS/issues

## Current limitations

- BFSOS remains under active 1.0 RC validation; not every hardware/storage combination has been tested.
- The non-core ports collection may contain stale or broken recipes even when the core system is release-ready.
- Installer configuration-profile support is partial; secrets such as passwords and LUKS passphrases are never stored.
- Alternative bootloaders such as Limine are a future enhancement; GRUB is the currently validated bootloader path.

## License

See `LICENSE` and individual port/source licenses where applicable.
