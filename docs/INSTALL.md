# BFSOS 0.9.0 Installation Guide

This guide documents the current BFSOS 0.9.0 live-media and installer flow. Final website screenshots should be captured again after the BFSOS branding/navigation polish pass, but the workflow below is the intended installation sequence.

## 1. Boot the live ISO

The live environment logs in automatically as the `bfs` user. Passwordless sudo is available only for the disposable live session. SSH is disabled by default.

Early in live startup BFSOS offers a console-font choice:

- keep the current/default font;
- large/high-visibility font;
- medium font.

The font can also be changed later from the live menu.

## 2. BFSOS Live Menu

The live menu provides:

1. Bootstrap BFSOS
2. Run BFSOS installer
3. Shell
4. Change console font

Choose **Run BFSOS installer** for a normal installation. The shell is intended for diagnostics/maintenance and returns to the live menu when you type `exit`.

## 3. Installer main menu

The installer tracks each section with states such as `PENDING`, `CONFIGURED`, `COMPLETE`, and `AVAILABLE`. The normal configuration order is:

1. Storage assignment
2. Base archive
3. System settings
4. Kernel selection
5. Optional software
6. Sudo configuration
7. Bootloader
8. Review selections
9. Install BFSOS

Use **Review selections** before starting the installation.

## 4. Storage assignment

The storage menu supports the tools needed for the selected layout:

- partition disks with `cfdisk`;
- assemble or create Linux software RAID;
- configure LUKS encryption;
- configure LVM;
- assign filesystems and mount points;
- configure optional ZRAM swap;
- inspect current storage devices.

Existing partitions can be assigned directly. You do not have to use RAID, LUKS, or LVM.

### Filesystem plan

Before continuing, verify the filesystem plan carefully. It distinguishes devices that will be formatted from devices that will be preserved and shows their mount points.

A typical UEFI layout might be:

```text
/          /dev/vda4   btrfs
/boot      /dev/vda2   ext2
/boot/efi  /dev/vda1   vfat
swap       /dev/vda3   swap
```

Do not continue until the device/action/mount-point list matches your intent.

### ZRAM

ZRAM is optional compressed swap in RAM. The installer offers percentage presets and a custom size. A percentage is the configured ZRAM device size relative to physical RAM; it does not mean that amount of physical memory is reserved immediately.

## 5. Base archive

If a local BFSOS base archive is available, the installer can use it. Otherwise it can download the current versioned base from SourceForge.

For BFSOS 0.9.0 the public base identity is:

```text
BFSOS-base-0.9.0-x86_64.tar.zst
```

The installer downloads the matching checksum and verifies the archive before use. The version, filename, and source are shown so the selected payload is unambiguous.

## 6. System settings

System Settings contains installed-system configuration for:

- hostname, timezone, and locale;
- console/font and optional serial troubleshooting console;
- networking;
- users and groups, including root-password-login policy;
- OpenSSH policy.

Hostname/timezone/locale are presented as defaults-first values: leave defaults unchanged or edit only the fields you want to customize.

The primary standard user is the normal login account. Root password login is locked by default unless explicitly enabled. A blank password entry never creates an empty-password login; it leaves that account's password login locked.

## 7. Kernel selection

The maintained choices are:

- `linux-lts` 6.18.54 — BFSOS default LTS kernel;
- `linux` 7.2.8 — optional current kernel;
- no kernel — advanced/custom installations only.

The LTS kernel is the normal release choice.

## 8. Sudo configuration

The installer can:

- omit sudo;
- install sudo and require the user's password;
- install sudo with passwordless access for wheel-group users.

Password-required sudo is the safer general-purpose default. Passwordless sudo is convenient but grants wheel users privilege escalation without another password prompt.

## 9. Bootloader

The installer supports UEFI and legacy BIOS GRUB installation. On UEFI systems, verify the EFI System Partition is assigned to `/boot/efi`. The installer can also configure the EFI fallback loader when selected.

## 10. Review selections

The scrollable review is the final sanity check. It includes:

- filesystem format/preserve actions and mount points;
- hostname/timezone/locale;
- base archive;
- users/groups and login policy;
- networking and SSH;
- bootloader configuration;
- serial-console state;
- kernel/package/sudo selections;
- RAID/LUKS/LVM/ZRAM/Btrfs state;
- installation totals.

Read the review before selecting **Install BFSOS**.

## 11. Installation completion

After installation succeeds, BFSOS displays a summary containing the installed hostname, kernel, boot mode, bootloader, root filesystem, snapshot state, primary user, and installer-log path.

The final menu provides two normal actions:

- **Enter installed BFSOS system (chroot)** — perform additional target-system maintenance before rebooting;
- **Finish and unmount the installed system** — cleanly leave the target and return to the live environment.

After finishing/unmounting, shut down or reboot and remove/eject the installation ISO before booting the installed system.

## Accessibility and recovery notes

- The console font can be enlarged before entering the installer and configured for the installed system.
- The live shell is available for diagnostics.
- Installer storage screens include contextual help for destructive/advanced choices.
- If an earlier installer run is detected, the installer can resume it or clear installer-managed temporary state and start fresh without deliberately formatting unrelated storage.

## Logs

Installer logs are retained under:

```text
/var/log/bfs/installer/
```

Include the relevant log when reporting an installation failure.
