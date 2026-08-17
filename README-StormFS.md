# StormFS

StormFS is an x86_64 source-built Linux distribution maintained by the StormFS community. It uses an LFS/MLFS-style bootstrap, CRUX `pkgutils`/ports for package builds, `prt-get` for dependency-aware package management, systemd as the default init system, a PyQt5 graphical installer, and a live ISO for easy deployment.

> **Status:** StormFS is approaching the 1.0 release-candidate stage. The core bootstrap, graphical installer, storage stack, and boot path are under active regression testing. Treat current builds as development/RC software and keep backups of important data.

## Core design

- Source-built temporary toolchain and base system.
- Optional final-toolchain rebuild to validate that the base can rebuild itself.
- CRUX-style ports and `pkgutils`, extended for StormFS build conventions.
- `prt-get` dependency management and `ports -u` repository synchronization.
- x86_64 multilib support with 32-bit libraries under `/usr/lib32`.
- systemd by default.
- Dracut initramfs generation and GRUB bootloader support.
- UEFI and legacy BIOS installation paths.
- PyQt5 graphical installer with disk partitioning, system configuration, and desktop environment selection.
- Live ISO with LightDM, XFCE default desktop, and auto-login.
- Installer support for Btrfs subvolumes/snapshots, LUKS, LVM, md RAID (linear/JBOD, RAID0, RAID1, RAID10, RAID4/5/6), and combinations of those layers.
- Kernel selection between the current StormFS kernel and a broad-support Linux 6.12 LTS flavor carrying the Debian 6.12 patch series.
- Optional installer-managed ZRAM swap with explicit enable/disable and configurable sizing.

## Repository layout

- `bootstrap.sh` — authoritative StormFS bootstrap menu and build stages.
- `stormfs-gui.py` — PyQt5 graphical installer application.
- `iso-builder/` — live ISO build scripts and overlay files.
- `ports/` — package recipes. `ports/core` is the release-critical base collection; other collections are broader and may receive cleanup independently of the 1.0 core release.
- `scripts/` — maintenance, migration, ports, and repository helpers.
- `archives/` — generated toolchain/base archives (normally excluded from Git).
- `logs/` — bootstrap/installer logs (normally excluded from release source archives).
- `.oh-my-bash/` — oh-my-bash shell framework (submodule).
- `StormFS-grub-theme/` — custom GRUB bootloader theme (submodule).
- `adw-gtk3/` — adw-gtk3 GTK theme (submodule).
- `tela-icon-theme/` — Tela icon theme (submodule).
- `tela-circle-icon-theme/` — Tela Circle icon theme (submodule).

## Quick start

### Building from source

The recommended build environment is the Gentoo LiveGUI ISO or any Linux host with working compiler/build tools, sufficient disk space, and network access.

```sh
git clone --recurse-submodules https://github.com/bfitzgit23/StormFS-Linux.git
cd StormFS-Linux
sudo python3 stormfs-gui.py
```

Or use the interactive bootstrap menu:

```sh
./bootstrap.sh
```

### Building the live ISO

```sh
sudo ./iso-builder/mkiso.sh rootfs-stormfs
```

The ISO will be output to `iso/stormfs-YYYYMMDD.iso`. Test it with:

```sh
./iso-builder/run_qemu iso/stormfs-YYYYMMDD.iso
```

## Bootstrap stages

The normal release path is:

1. **Build temporary toolchain** — run as a regular user.
2. **Build base system with temporary toolchain** — requires root; the menu uses `sudo`.
3. **Rebuild base system with final toolchain** — optional but recommended for release validation.
4. **Verify completed base system** — required before archiving.
5. **Create and verify base rootfs archive** — required for installer deployment.
6. Restore newest base rootfs archive.
7. Restore newest temporary-toolchain archive.
8. Chroot into the built/restored StormFS rootfs.
9. Launch the StormFS installer (graphical or text-based).

Generated archives are kept under `archives/toolchain/` and `archives/base/`.

## Graphical installer

The PyQt5-based installer (`stormfs-gui.py`) provides a wizard-style interface for:

1. **Build configuration** — compiler jobs, optimization level, ccache.
2. **Automated build** — runs stages 1-4 with live log output.
3. **Disk selection** — choose target disk from detected block devices.
4. **Partition layout** — configure root, EFI/BIOS boot, swap, and /home partitions.
5. **System configuration** — hostname, timezone, locale, keymap.
6. **User setup** — username, password, root password.
7. **Desktop selection** — display server, DE/WM, audio, GPU drivers, themes.
8. **Installation** — automated partitioning, rootfs extraction, bootloader setup.

### Desktop environment choices

- **Display servers:** Xorg, Wayland, or both
- **Desktop environments:** GNOME, KDE Plasma, XFCE, LXQt, Cinnamon, MATE
- **Window managers:** Sway, i3, Hyprland, Openbox, Awesome, Bspwm
- **Audio:** PipeWire (default) or PulseAudio
- **GPU drivers:** Mesa (AMD/Intel), NVIDIA proprietary, Nouveau, VirtualBox, VMware
- **Themes:** adw-gtk3, Tela icons, Tela Circle icons, oh-my-bash, StormFS GRUB theme

## Live ISO features

- Boot modes: UEFI and legacy BIOS
- LightDM display manager with GTK greeter
- Auto-login as live user `stormfs`
- Default XFCE desktop environment
- Desktop installer shortcut
- RAM boot option (copies rootfs to memory)
- SquashFS with overlayfs for live session
- Automatic cleanup of installer after installation

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

StormFS uses `python3` as the Python 3 package name; Python module ports use the `python3-*` naming convention.

## Included themes and tools

The following are included as git submodules:

| Submodule | Description |
|-----------|-------------|
| `.oh-my-bash` | Bash framework with themes and plugins |
| `StormFS-grub-theme` | Custom GRUB bootloader theme for StormFS |
| `adw-gtk3` | GTK3 theme inspired by GNOME Adwaita |
| `tela-icon-theme` | Material Design-style flat icon theme |
| `tela-circle-icon-theme` | Material Design-style circle icon theme |

Clone with submodules:
```sh
git clone --recurse-submodules https://github.com/bfitzgit23/StormFS-Linux.git
```

Or initialize after cloning:
```sh
git submodule update --init --recursive
```

## Logs and bug reports

Bootstrap package logs are written below `logs/toolchain/` and `logs/base/`. Installer logs are preserved in the installed system under `/var/log/stormfs/installer/` when logging is enabled.

When reporting a bug, include the failing stage/package, relevant log, storage topology when applicable, kernel/initramfs version, and whether the failure occurred in a VM or on bare metal.

Issues and support: https://github.com/bfitzgit23/StormFS-Linux/issues

## Current limitations

- StormFS remains under active 1.0 RC validation; not every hardware/storage combination has been tested.
- The non-core ports collection may contain stale or broken recipes even when the core system is release-ready.
- Installer configuration-profile support is partial; secrets such as passwords and LUKS passphrases are never stored.
- Alternative bootloaders such as Limine are a future enhancement; GRUB is the currently validated bootloader path.

## License

See `LICENSE` and individual port/source licenses where applicable.
