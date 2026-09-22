# BFSOS init profiles

The files in this directory are build manifests for the bootstrap's selectable
init policy. They are intentionally separate from package dependency headers:
`pkgmk`/`prt-get` still use each port's `Pkgfile`, while `bootstrap.sh` uses the
selected profile to choose the init and service packages for the base rootfs.

Use `scripts/select-init-profile.sh [systemd|openrc|sysvinit]` to write the
selection before running a base build.

`systemd-audit.tsv` records every upstream recipe containing systemd coupling.
`profiles/init/overlays/openrc/` and `profiles/init/overlays/sysvinit/` contain
generated Pkgfile variants for those recipes. The bootstrap copies the selected
overlay over `/usr/ports` after importing the upstream tree. The generator is
repeatable:

```sh
python3 scripts/generate-init-variants.py --clean
```
