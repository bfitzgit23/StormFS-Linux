# BFSOS init profiles

StormFS Linux uses **OpenRC** as its init system. systemd has been removed from
this tree: there is no systemd port, no systemd profile, and no recipe may build
systemd integration or ship unit files.

The files in this directory are build manifests for the bootstrap's init
policy. They are separate from package dependency headers: scratchpkg still
reads each port's `spkgbuild` and `depends`, while `bootstrap.sh` uses the
selected profile to choose the init and service packages for the base rootfs.

Use `scripts/select-init-profile.sh [openrc|sysvinit]` to write the selection
before running a base build.

- `openrc.packages` — the default profile: OpenRC, the StormFS OpenRC service
  scripts port, and the base daemons (dbus, NetworkManager, bluez, chrony,
  PipeWire, cups, avahi).
- `sysvinit.packages` — the optional SysVinit profile, kept as an alternative
  to OpenRC. It is not systemd and is unaffected by the removal.

Service coverage:

- OpenRC: `ports/opt/openrc` provides `/sbin/openrc-init` and `/etc/inittab`;
  `ports/opt/openrc-init-scripts` ships `/etc/init.d` scripts for the
  installer-enabled services plus opt-in daemons (nftables, rsyncd, Kerberos,
  wpa_supplicant, virtlogd/libvirtd, the display managers) and the XDG
  autostart entries for the PipeWire session stack.
- SysVinit: `ports/opt/sysvinit-init-scripts` ships LSB scripts in
  `/etc/rc.d/init.d`, bakes `rc2-5`/`rc0,1,6` links for the same default set
  the installer enables on OpenRC (BLFS link-numbering convention), and the
  BLFS `xdm` dispatcher driven from the commented `dm:5` line in
  `/etc/inittab`.

Both init ports (`core/sysvinit`, `opt/openrc`) ship a working `/etc/inittab`;
PID 1 has no console login without it. The bootstrap copies the selected
overlay over `/usr/ports` after importing the tree. The generator is
repeatable:

```sh
python3 scripts/generate-init-variants.py --clean
```
