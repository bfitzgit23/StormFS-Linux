# BFSOS init profiles

StormFS Linux uses **rc** (the BSD-style, CRUX-inspired init from
scratchpkg/Venom) as its default init system. systemd has been removed from
this tree: there is no systemd port, no systemd profile, and no recipe may
build systemd integration or ship unit files.

The files in this directory are build manifests for the bootstrap's init
policy. They are separate from package dependency headers: scratchpkg still
reads each port's `spkgbuild` and `depends`, while `bootstrap.sh` uses the
selected profile to choose the init and service packages for the base rootfs.

Use `scripts/select-init-profile.sh [rc|sysvinit]` to write the selection
before running a base build.

- `rc.packages` - the default profile: `ports/core/rc` plus the StormFS LSB
  service scripts, and the base daemons (D-Bus, ConsoleKit, NetworkManager,
  bluez, chrony, PipeWire, cups, avahi).
- `sysvinit.packages` - the optional SysVinit profile, kept as an alternative
  to rc. It is not systemd and is unaffected by the removal.

Service coverage:

- rc: `ports/core/rc` provides `/etc/rc`, `/etc/rc.multi`,
  `/etc/rc.shutdown`, `/etc/rc.single`, `/etc/rc.subr`, `/etc/inittab`,
  `/etc/rc.local`, `modules-load`, and `/etc/rc.conf`. It depends on
  `ports/core/sysvinit` for PID 1 and shutdown/halt/reboot.
- The service scripts are the existing LSB/BLFS scripts in
  `ports/opt/sysvinit-init-scripts`. They install under
  `/etc/rc.d/init.d` and also receive top-level `/etc/rc.d/<name>` symlinks,
  so `DAEMONS="dbus networkmanager ..."` in `/etc/rc.conf` starts them in
  order. The package includes D-Bus, ConsoleKit, NetworkManager, ACPI,
  bluez, gpm, chrony, cups, avahi, OpenSSH, samba, rsync, Kerberos,
  nftables, wpa_supplicant, libvirt, the display managers, and the optional
  kernel-finalize script.
- SysVinit: `ports/opt/sysvinit-init-scripts` also bakes the `rc2-5` /
  `rc0,1,6` links used by the optional LFS-style profile.

Both init ports (`core/sysvinit`, `core/rc`) ship a working `/etc/inittab`;
PID 1 has no console login without it. `rc` is installed after `sysvinit`, so
its inittab is the one used by the rc profile.

The ISO builder and installers generate `/etc/rc.conf` with the selected
timezone, keymap, console font, and service list. Re-running
`scripts/select-init-profile.sh` only changes the build profile; it does not
rewrite an installed system's `/etc/rc.conf`.

The bootstrap copies the selected overlay over `/usr/ports` after importing
the tree. The generator is repeatable:

```sh
python3 scripts/generate-init-variants.py --clean
```
