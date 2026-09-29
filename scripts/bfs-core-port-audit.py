#!/usr/bin/env python3
"""Static/source-policy audit for BFSOS ports/core.

This intentionally does not claim upstream-version or build/runtime validation.
It records every core Pkgfile and highlights source-tree issues that can be
established without downloading or building packages.
"""
from __future__ import annotations
from pathlib import Path
import argparse, re, shlex


def scalar(text: str, key: str) -> str:
    m = re.search(rf'^\s*{re.escape(key)}\s*=\s*([^\n#]+)', text, re.M)
    if not m:
        return ''
    v=m.group(1).strip().strip('"\'')
    return v


def header_tokens(text: str, label: str) -> list[str]:
    for line in text.splitlines():
        if line.startswith(label):
            return line.split(':',1)[1].split()
    return []


def source_block(text: str) -> str:
    m=re.search(r'^source\s*=\s*\((.*?)\)', text, re.M|re.S)
    if m: return m.group(1)
    m=re.search(r'^source\s*=\s*([^\n]+)', text, re.M)
    return m.group(1) if m else ''


def main() -> int:
    ap=argparse.ArgumentParser()
    ap.add_argument('--root', default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument('--revision', default='r333')
    ap.add_argument('--date', default='2026-09-24')
    ap.add_argument('--md', default='docs/BFSOS-core-audit-r333-20260924.md')
    ap.add_argument('--tsv', default='docs/BFSOS-core-audit-r333-20260924.tsv')
    ns=ap.parse_args()
    root=Path(ns.root).resolve()
    pkgfiles=sorted((root/'ports/core').glob('*/Pkgfile'))
    all_pkgfiles=sorted((root/'ports').glob('*/*/Pkgfile'))
    all_names=set()
    for p in all_pkgfiles:
        t=p.read_text(errors='replace')
        n=scalar(t,'name') or p.parent.name
        all_names.add(n)
        all_names.add(p.parent.name)

    rows=[]
    source_http=[]; remote_patch=[]; setup_py=[]; custom=[]; undocumented=[]
    dep_overlap=[]; unresolved=[]; metadata=[]; syntax=[]
    for p in pkgfiles:
        t=p.read_text(errors='replace')
        name=scalar(t,'name'); ver=scalar(t,'version'); rel=scalar(t,'release')
        if not (name and ver and rel): metadata.append(str(p.relative_to(root)))
        deps=header_tokens(t,'# Depends on:')
        opt=header_tokens(t,'# Optional:')
        both=sorted(set(deps)&set(opt))
        if both: dep_overlap.append((name,both))
        miss=[d for d in deps if d not in all_names]
        if miss: unresolved.append((name,miss))
        src=source_block(t)
        urls=re.findall(r'https?://[^\s)]+',src)
        http=[u for u in urls if u.startswith('http://')]
        patches=[u for u in urls if re.search(r'\.patch(?:\?.*)?$',u,re.I)]
        if http: source_http.append((name,http))
        if patches: remote_patch.append((name,patches))
        has_custom=bool(re.search(r'^\s*pkg_build\s*\(\)',t,re.M))
        documented='Custom build required:' in t
        if has_custom:
            custom.append(name)
            if not documented: undocumented.append(name)
        if re.search(r'python3?\s+setup\.py\s+install',t): setup_py.append(name)
        hooks=[]
        for h in ('bootstrap_build','pre_build','pkg_build','post_build'):
            if re.search(rf'^\s*{h}\s*\(\)',t,re.M): hooks.append(h)
        mode='custom' if has_custom else 'extension'
        rows.append({
            'port':p.parent.name,'name':name,'version':ver,'release':rel,
            'deps':' '.join(deps),'optional':' '.join(opt),'mode':mode,
            'build_opt':'yes' if re.search(r'^\s*build_opt\s*=',t,re.M) else 'no',
            'hooks':','.join(hooks) or '-',
            'http':'yes' if http else 'no','remote_patch':'yes' if patches else 'no',
            'custom_note':'yes' if documented else ('no' if has_custom else '-'),
        })

    backups=sorted(str(p.relative_to(root)) for p in (root/'ports').glob('*/*/Pkgfile*') if p.name!='Pkgfile')

    tsv=root/ns.tsv
    tsv.parent.mkdir(parents=True,exist_ok=True)
    cols=['port','name','version','release','deps','optional','mode','build_opt','hooks','http','remote_patch','custom_note']
    with tsv.open('w') as f:
        f.write('\t'.join(cols)+'\n')
        for r in rows:
            f.write('\t'.join(r[c].replace('\t',' ') for c in cols)+'\n')

    md=root/ns.md
    with md.open('w') as f:
        f.write(f'# BFSOS `ports/core` audit — {ns.revision} source/static pass\n\n')
        f.write(f'Date: {ns.date}\n\n')
        f.write('## Scope and evidence\n\n')
        f.write(f'- Core directories: **{len(list((root/"ports/core").glob("*/")))}**; canonical Pkgfiles: **{len(pkgfiles)}**.\n')
        f.write(f'- Required metadata omissions: **{len(metadata)}**.\n')
        f.write(f'- Hard/optional dependency overlaps: **{len(dep_overlap)}**.\n')
        f.write(f'- Unresolved hard dependency tokens from core against the full BFSOS tree: **{len(unresolved)}**.\n')
        f.write(f'- Plain-HTTP active source URLs after this pass: **{len(source_http)}**.\n')
        f.write(f'- Remote patch URLs still present in core source arrays: **{len(remote_patch)}**.\n')
        f.write(f'- `pkg_build()` recipes: **{len(custom)}**; with an explicit `Custom build required:` rationale: **{len(custom)-len(undocumented)}**.\n')
        f.write(f'- Direct `setup.py install` recipes: **{len(setup_py)}**.\n')
        f.write(f'- Stale `Pkgfile*` backup/copy files anywhere under maintained `ports/`: **{len(backups)}**.\n\n')
        f.write(f'The complete package-by-package inventory is in `{ns.tsv}`. '\
                'This audit is deliberately source/static evidence: package builds, runtime behavior, and a true upstream-version sweep require a networked BFSOS host. '\
                'The sandbox version checker was attempted and could not resolve upstream hosts, so the report does not mislabel unverified package versions as current.\n\n')
        f.write('## Findings requiring follow-up\n\n')
        if remote_patch:
            f.write('### Remote patch vendoring still required\n\n')
            for n,us in remote_patch:
                for u in us: f.write(f'- `{n}`: `{u}`\n')
            f.write('\nThese patch bytes are not present in the supplied project archive. They must be fetched on a networked host, checksum-verified, committed beside each Pkgfile, and the source entries converted to local filenames.\n\n')
        if undocumented:
            f.write('### BFSOS extension-contract review queue\n\n')
            f.write(f'**{len(undocumented)}** core ports still retain `pkg_build()` without an explicit custom-build rationale. This is an audit queue, not proof that all {len(undocumented)} are wrong. Ordinary Autotools/CMake/Meson recipes should migrate to the extension + `build_opt`; genuinely special orchestration should retain `pkg_build()` and gain a concise rationale.\n\n')
            f.write('Ports: ' + ', '.join(f'`{x}`' for x in undocumented) + '\n\n')
        if setup_py:
            f.write('### Legacy Python install-path review\n\n')
            f.write('Direct `setup.py install` remains in: ' + ', '.join(f'`{x}`' for x in setup_py) + '. Review against current upstream packaging when these ports are next rebuilt; do not mass-convert without build testing.\n\n')
        f.write('## Package-by-package inventory\n\n')
        f.write('| Port | Version | Rel | Build path | build_opt | Flags |\n|---|---:|---:|---|---|---|\n')
        for r in rows:
            flags=[]
            if r['remote_patch']=='yes': flags.append('remote-patch')
            if r['custom_note']=='no': flags.append('custom-review')
            if r['name'] in setup_py: flags.append('setup.py')
            f.write(f"| `{r['port']}` | {r['version']} | {r['release']} | {r['mode']} | {r['build_opt']} | {', '.join(flags) or 'OK/static'} |\n")
    print(f'Wrote {md.relative_to(root)}')
    print(f'Wrote {tsv.relative_to(root)}')
    print(f'core_pkgfiles={len(pkgfiles)} remote_patches={len(remote_patch)} custom_review={len(undocumented)} backups={len(backups)}')
    return 0

if __name__=='__main__':
    raise SystemExit(main())
