#!/usr/bin/env python3
"""Static inventory/audit for canonical BFSOS ports/xorg recipes."""
from pathlib import Path
import argparse, csv, re, subprocess

ROOT = Path(__file__).resolve().parent.parent

def scalar(text, key):
    m = re.search(rf'^{re.escape(key)}=(.+)$', text, re.M)
    return m.group(1).strip() if m else ''

def depends(text):
    for line in text.splitlines():
        if line.startswith('# Depends on:'):
            return line.split(':',1)[1].strip().split()
    return []

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--tsv', default=str(ROOT/'docs/BFSOS-xorg-audit-r340-20260926.tsv'))
    args=ap.parse_args()
    names={}
    for pf in ROOT.glob('ports/*/*/Pkgfile'):
        s=pf.read_text(errors='ignore'); n=scalar(s,'name').strip("'\"")
        if n: names.setdefault(n,[]).append(str(pf.parent.relative_to(ROOT)))
    rows=[]
    for pf in sorted((ROOT/'ports/xorg').glob('*/Pkgfile')):
        s=pf.read_text(errors='ignore'); deps=depends(s)
        src=[]
        m=re.search(r'^source=\((.*?)\)\s*$',s,re.M|re.S)
        if m: src=re.findall(r'https?://[^\s)]+',m.group(1))
        syntax=subprocess.run(['bash','-n',str(pf)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0
        rows.append({
            'port':pf.parent.name,'name':scalar(s,'name'),'version':scalar(s,'version'),'release':scalar(s,'release'),
            'depends':' '.join(deps),'unresolved_deps':' '.join(d for d in deps if d not in names),
            'build_opt':scalar(s,'build_opt'),'sources':' '.join(src),
            'http_source':'yes' if any(u.startswith('http://') for u in src) else 'no',
            'syntax':'ok' if syntax else 'FAIL'
        })
    out=Path(args.tsv); out.parent.mkdir(parents=True,exist_ok=True)
    with out.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=rows[0].keys(),delimiter='\t'); w.writeheader(); w.writerows(rows)
    print(f'X.Org recipes: {len(rows)}')
    print(f'Syntax failures: {sum(r["syntax"]!="ok" for r in rows)}')
    print(f'Unresolved hard dependencies: {sum(bool(r["unresolved_deps"]) for r in rows)}')
    print(f'Plain HTTP source URLs: {sum(r["http_source"]=="yes" for r in rows)}')
    print(out)
    return 1 if any(r['syntax']!='ok' or r['unresolved_deps'] or r['http_source']=='yes' for r in rows) else 0
if __name__ == '__main__': raise SystemExit(main())
