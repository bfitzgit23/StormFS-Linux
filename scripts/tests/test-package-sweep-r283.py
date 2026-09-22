#!/usr/bin/env python3
from pathlib import Path
import re, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]

def pkg(rel):
    p = ROOT / 'ports' / rel / 'Pkgfile'
    if not p.is_file():
        raise AssertionError(f'missing Pkgfile: {rel}')
    return p.read_text(errors='replace')

def value(rel, key):
    m = re.search(rf'^{re.escape(key)}=(.+)$', pkg(rel), re.M)
    if not m:
        raise AssertionError(f'{rel}: missing {key}=')
    return m.group(1).strip().strip('"\'')

def expect_ver(rel, ver):
    got=value(rel,'version')
    if got != ver:
        raise AssertionError(f'{rel}: version {got}, expected {ver}')

expected = {
    'core/xz':'5.8.4', 'core/fuse':'3.18.3',
    'contrib/librsvg':'2.63.0', 'opt/ghostscript':'10.08.0',
    'opt/llvm':'23.1.1', 'compat-32/llvm-32':'23.1.1',
    'opt/libclc':'23.1.1', 'opt/rust-bindgen':'0.73.2',
    'opt/poppler':'26.09.0', 'opt/libpcap':'1.10.7', 'compat-32/libpcap-32':'1.10.7',
    'opt/imlib2':'1.12.7', 'compat-32/imlib2-32':'1.12.7',
    'opt/libgcrypt':'1.12.3', 'compat-32/libgcrypt-32':'1.12.3',
    'opt/openldap':'2.7.1', 'compat-32/openldap-32':'2.7.1',
    'opt/samba':'4.24.7', 'opt/glib':'2.90.0', 'compat-32/glib-32':'2.90.0',
    'opt/firefox':'155.0.1', 'opt/firefox-bin':'155.0.1', 'opt/discord':'1.0.157',
    'opt/nss':'3.128', 'compat-32/nss-32':'3.128',
    'opt/libedit':'20260512_3.1', 'opt/libksba':'1.8.1',
    'opt/hyphen':'2.8.9', 'opt/gavl':'2.0.1', 'opt/ftjam':'2.5.3rc2',
    'opt/x265':'4.3', 'opt/unrar':'7.2.7', 'opt/nodejs':'24.21.0', 'core/ca-certificates':'20260813',
    'opt/publicsuffix-list':'20260913', 'opt/rapidjson':'20250205.24b5e7a',
    'opt/lua':'5.4.9', 'compat-32/vkd3d-32':'2.1',
    'compat-32/vulkan-tools-32':'1.4.357.0', 'compat-32/libnm-32':'1.58.1',
    'compat-32/nvidia-fb-32':'595.99.02',
}
for rel, ver in expected.items(): expect_ver(rel, ver)

# Cohesive KDE family refresh: old release train versions may not remain in plasma collection.
versions=[]
for p in sorted((ROOT/'ports/plasma').glob('*/Pkgfile')):
    m=re.search(r'^version=(.+)$',p.read_text(errors='replace'),re.M)
    if m: versions.append(m.group(1).strip().strip('"\''))
for old in ('6.29.0','6.7.4','26.08.0'):
    if old in versions: raise AssertionError(f'plasma collection still contains stale {old}')
for cur, minimum in (('6.30.0',74),('6.7.5',58),('26.08.1',17)):
    if versions.count(cur) < minimum:
        raise AssertionError(f'plasma collection has only {versions.count(cur)} entries at {cur}, expected >= {minimum}')

for rel in ('opt/gstreamer','opt/gst-libav','opt/gst-plugins-base','opt/gst-plugins-good','opt/gst-plugins-bad','opt/gst-plugins-ugly'):
    expect_ver(rel,'1.28.7')

# NSS must be one coherent release and include the command-line tool the old recipe omitted.
if 'nss_certdata_version=3.128' not in pkg('core/ca-certificates'):
    raise AssertionError('ca-certificates is not pinned to NSS 3.128 certdata')
nss=pkg('opt/nss')
for token in ('certutil','modutil','pk12util'):
    if token not in nss: raise AssertionError(f'opt/nss missing {token} packaging')
if 'nss-3.54-standalone-2.patch' in nss:
    raise AssertionError('opt/nss still references obsolete standalone patch')
if (ROOT/'ports/opt/nss/nss-3.54-standalone-2.patch').exists():
    raise AssertionError('obsolete NSS 3.54 patch still present')

# Replaced duplicate/stale ports must stay gone.
for rel in ('opt/freetype2','opt/cracklib-words','opt/lld'):
    if (ROOT/'ports'/rel/'Pkgfile').exists():
        raise AssertionError(f'obsolete duplicate port returned: {rel}')

# Current build systems / hooks, not recipes pkgmk silently ignores.
gk=pkg('gnome/gnome-keyring')
if not re.search(r'^pkg_build\(\)',gk,re.M) or 'meson setup' not in gk or './configure' in gk:
    raise AssertionError('gnome-keyring 50 recipe is not using pkg_build()+Meson')
if not re.search(r'^pkg_build\(\)',pkg('core/python3-certifi'),re.M):
    raise AssertionError('python3-certifi pkg_build hook is still misspelled')
wn=pkg('gnome/libwnck2')
if re.search(r'# Depends on:.*\bfreetype2\b',wn):
    raise AssertionError('libwnck2 still depends on removed freetype2 duplicate')

# Lua 5.4.9 must not carry the old 5.4.8 remote patch.
lua=pkg('opt/lua')
if '5.4.8' in lua or re.search(r'https?://\S+\.(?:patch|diff)',lua):
    raise AssertionError('Lua still carries an old/remote patch companion')
if 'liblua.so.5.4.9' not in lua:
    raise AssertionError('Lua shared-library recipe missing 5.4.9 soname payload')

req=pkg('core/python3-requests')
req_patch=(ROOT/'ports/core/python3-requests/requests-use_system_certs-2.patch').read_text(errors='replace')
if 'requests-2.33.0' in req_patch or '2.32.' in req_patch:
    raise AssertionError('Requests system-cert patch still carries stale release paths/context')
for token in ('/etc/pki/tls/certs/ca-bundle.crt', '_PIP_STANDALONE_CERT'):
    if token not in req_patch:
        raise AssertionError(f'Requests system-cert patch missing {token}')

psl=pkg('opt/publicsuffix-list')
if 'source=(public_suffix_list-$version.dat)' not in psl:
    raise AssertionError('publicsuffix-list is not using the versioned vendored data companion')
psl_data = ROOT / 'ports/opt/publicsuffix-list' / f"public_suffix_list-{value('opt/publicsuffix-list','version')}.dat"
if not psl_data.is_file() or psl_data.stat().st_size < 100000:
    raise AssertionError('publicsuffix-list vendored data companion is missing or implausibly small')
if 'https://publicsuffix.org/list/public_suffix_list.dat' not in psl_data.read_text(errors='replace')[:4096]:
    raise AssertionError('publicsuffix-list vendored data lacks canonical upstream provenance')
rapid=pkg('opt/rapidjson')
if '_commit=' not in rapid or re.search(r'/archive/(?:refs/heads/)?master',rapid):
    raise AssertionError('rapidjson is not pinned to an immutable commit')

# Compat synchronization must be exact after the native sweep.
out=subprocess.check_output([str(ROOT/'scripts/multilibvercheck.sh')], cwd=ROOT, text=True)
needle='compat-32 summary: matched=157 special=15 drift=0 unexplained=0'
if needle not in out:
    raise AssertionError(f'compat summary changed:\n{out}')

print('r283 maintained-package sweep regression: PASS')
