#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

python3 - "$ROOT" <<'PY'
from pathlib import Path
from collections import defaultdict, Counter
import re, sys
root=Path(sys.argv[1])
ports=list(sorted(root.glob('ports/*/*/Pkgfile')))
ident=defaultdict(list); deps={}; versions={}; placeholder=[]; oldmaint=[]; setup=[]; legacy=[]; badhooks=[]
for p in ports:
    txt=p.read_text(errors='replace'); rel=p.relative_to(root)
    name=next((x.split('=',1)[1].strip() for x in txt.splitlines() if x.startswith('name=')),None)
    ver=next((x.split('=',1)[1].strip() for x in txt.splitlines() if x.startswith('version=')),None)
    if name: ident[name].append(rel); versions[name]=(ver,rel)
    d=[]
    for line in txt.splitlines():
        if line.startswith('# Depends on:'): d=line.split(':',1)[1].split(); break
    deps[name]=d
    if 'Add your top line text here' in txt or 'Your line to add at the top here' in txt: placeholder.append(rel)
    if 'Maintainer: Brian Madonna email ' in txt: oldmaint.append(rel)
    if re.search(r'python3?\s+setup\.py\s+install',txt): setup.append(rel)
    if re.search(r'^\s*build\s*\(\s*\)\s*\{',txt,re.M): legacy.append(rel)
    if re.search(r'^\s*(?:build_pkg|pkg_buile|pkg_buid|pkgbuild)\s*\(\s*\)\s*\{',txt,re.M): badhooks.append(rel)

print(f'BFSOS ports-tree audit: {len(ports)} Pkgfiles')
for collection in sorted((root/'ports').iterdir()):
    if collection.is_dir(): print(f'  {collection.name:12s} {len(list(collection.glob("*/Pkgfile"))):4d}')

dups={k:v for k,v in ident.items() if len(v)>1}
print(f'\nDuplicate package identities: {len(dups)}')
for k,v in sorted(dups.items()): print(' ',k,':',', '.join(map(str,v)))

names=set(ident)
port_names={p.parent.name for p in ports}
resolvable=names | port_names
# Keep this diagnostic conservative: report unresolved tokens but do not fail; virtual/toolchain names can be intentional.
common={'bash','sh','gcc','glibc','cmake','make','ninja','perl','pkg-config','python','python2','python3','rust','cargo','systemd','linux-pam','udev','openssl','dbus','mesa','xorg-libs'}
missing=defaultdict(list)
for name,ds in deps.items():
    for d in ds:
        if d not in resolvable and d not in common: missing[d].append(versions.get(name,(None,'?'))[1])
print(f'\nUnresolved hard-dependency tokens (review; may include virtuals): {len(missing)}')
for k,v in sorted(missing.items()): print(' ',k,':',', '.join(map(str,v[:8])))

print(f'\nPlaceholder metadata headers: {len(placeholder)}')
for p in placeholder[:80]: print(' ',p)
if len(placeholder)>80: print(f'  ... {len(placeholder)-80} more')
print(f'Legacy Brian maintainer syntax: {len(oldmaint)}')
print(f'Legacy build() functions: {len(legacy)}')
for p in legacy[:80]: print(' ',p)
print(f'Misspelled pkg_build() hooks: {len(badhooks)}')
for p in badhooks[:80]: print(' ',p)
print(f'Explicit setup.py install recipes: {len(setup)}')
for p in setup: print(' ',p)

# Current BLFS GNOME chapter coverage. Some GNOME-support packages intentionally
# live outside ports/gnome, so test package identities, not collection paths.
blfs_gnome_apps = {
    'baobab','brasero','evince','evolution','file-roller','gnome-calculator',
    'gnome-color-manager','gnome-connections','gnome-disk-utility','gnome-logs',
    'gnome-maps','gnome-nettool','gnome-power-manager','gnome-system-monitor',
    'gnome-terminal','gnome-weather','gucharmap','loupe','seahorse','showtime','snapshot'
}
missing_gnome_apps=sorted(blfs_gnome_apps - names)
print(f'\nCurrent BLFS GNOME application identities missing: {len(missing_gnome_apps)}')
for n in missing_gnome_apps: print(' ',n)
for n in ('gweather-locations','glycin','blueprint-compiler'):
    if n not in names: print(' GNOME support package missing:', n)

print('\nFocused suite versions:')
for col in ('compiz','xfce','lxqt','gnome','plasma'):
    print(f'[{col}]')
    for p in sorted((root/'ports'/col).glob('*/Pkgfile')):
        txt=p.read_text(errors='replace')
        n=next((x.split('=',1)[1].strip() for x in txt.splitlines() if x.startswith('name=')),'?')
        v=next((x.split('=',1)[1].strip() for x in txt.splitlines() if x.startswith('version=')),'?')
        print(f'  {n:36s} {v}')

if dups or badhooks:
    raise SystemExit(2)
PY
