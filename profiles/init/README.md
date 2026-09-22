# BFSOS init profiles

The files in this directory are build manifests for the bootstrap's selectable
init policy. They are intentionally separate from package dependency headers:
`pkgmk`/`prt-get` still use each port's `Pkgfile`, while `bootstrap.sh` uses the
selected profile to choose the init and service packages for the base rootfs.

Use `scripts/select-init-profile.sh [systemd|openrc|sysvinit]` to write the
selection before running a base build.

`systemd-audit.tsv` records every upstream recipe containing systemd coupling.
`profiles/init/overlays/openrc/` and `profiles/init/overlays/sysvinit/` contain
generated Pkgfile variants for those recipes.

Service coverage across the profiles:

- OpenRC: `ports/opt/openrc-init-scripts` ships `/etc/init.d` scripts for the
  installer-enabled services plus opt-in daemons (nftables, rsyncd, Kerberos,
  wpa_supplicant, virtlogd/libvirtd, the display managers) and the XDG
  autostart entries for the PipeWire session stack.
- SysVinit: `ports/opt/sysvinit-init-scripts` ships LSB scripts in
  `/etc/rc.d/init.d`, bakes `rc2-5`/`rc0,1,6` links for the same default set
  the installer enables on OpenRC (BLFS link-numbering convention), and the
  BLFS `xdm` dispatcher driven from the commented `dm:5` line in
  `/etc/inittab`.
- Both init ports (`core/sysvinit`, `opt/openrc`) ship a working
  `/etc/inittab`; PID 1 has no console login without it. The bootstrap copies the selected
overlay over `/usr/ports` after importing the upstream tree. The generator is
repeatable:

```sh
python3 scripts/generate-init-variants.py --clean
```
