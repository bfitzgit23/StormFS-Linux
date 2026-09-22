#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
MOD_PATH = ROOT / "scripts" / "checkupdate.py"
spec = importlib.util.spec_from_file_location("bfs_checkupdate", MOD_PATH)
mod = importlib.util.module_from_spec(spec)
sys.modules["bfs_checkupdate"] = mod
assert spec.loader is not None
spec.loader.exec_module(mod)

# Exact-filename directory matching: pre-release must not outrank stable.
listing = '''
<a href="acl-2.3.2.tar.xz">acl-2.3.2.tar.xz</a>
<a href="acl-2.4.0.tar.xz">acl-2.4.0.tar.xz</a>
<a href="acl-2.4.1.tar.xz">acl-2.4.1.tar.xz</a>
<a href="acl-2.5.0-rc1.tar.xz">acl-2.5.0-rc1.tar.xz</a>
'''
vals = mod.versions_from_filename_listing(listing, "acl-2.4.0.tar.xz", "2.4.0")
latest, reason = mod.choose_verified("2.4.0", vals)
assert not reason and latest == "2.4.1", (latest, reason, vals)

# Git tags are accepted only if one mapping pattern reproduces current exactly.
vals, reason = mod.git_tag_versions(
    ["v2.3.0", "v2.4.0", "v2.4.1", "other-99.0"], "2.4.0"
)
latest, verify_reason = mod.choose_verified("2.4.0", vals)
assert not reason and not verify_reason and latest == "2.4.1"
vals, reason = mod.git_tag_versions(["foo-9.9", "foo-10.0"], "2.4.0")
assert reason and not vals


# v10 must reject known false-positive classes seen in the full maintained-tree audit.
def fake(rel, version):
    return mod.Port(Path('/tmp') / rel, rel, rel.rsplit('/', 1)[-1], version, [])

assert not mod.candidate_allowed('20060301-alt06', '2.17.0', fake('core/bash-completion','2.17.0'), 'git-tags')
assert not mod.candidate_allowed('4.4.3-sunos-x86_64', '4.4.2', fake('core/cmake','4.4.2'), 'directory')
assert not mod.candidate_allowed('6.19.14', '6.18.49', fake('core/linux-lts','6.18.49'), 'directory')
assert not mod.candidate_allowed('5.45.2', '5.44.0', fake('core/perl','5.44.0'), 'directory')
assert not mod.candidate_allowed('3.3.0b1', '3.2.9', fake('core/python3-cython','3.2.9'), 'pypi:cython')
assert not mod.candidate_allowed('1.29.2', '1.28.6', fake('opt/gstreamer','1.28.6'), 'directory')
assert not mod.candidate_allowed('2.53.92', '2.52.6', fake('gnome/webkitgtk','2.52.6'), 'directory')
assert not mod.candidate_allowed('4.23.4', '3.24.52', fake('opt/gtk3','3.24.52'), 'gnome-cache')
assert not mod.candidate_allowed('3.94.0', '2.24.33', fake('opt/gtk','2.24.33'), 'gnome-cache')
assert not mod.candidate_allowed('2.90.7', '2.24.33', fake('opt/gtk','2.24.33'), 'gnome-cache')
assert not mod.candidate_allowed('2.3.2', '2.3.1', fake('opt/taglib','2.3.1'), 'git-tags')
assert not mod.candidate_allowed('3.7.2', '2.74.3', fake('opt/libsoup','2.74.3'), 'gnome-cache')
assert not mod.candidate_allowed('5.5.1', '5.2.4', fake('opt/lua52','5.2.4'), 'directory')
assert not mod.candidate_allowed('5.5.1', '5.4.9', fake('opt/lua','5.4.9'), 'directory')
assert mod.candidate_allowed('5.4.9', '5.4.8', fake('opt/lua','5.4.8'), 'directory')
assert not mod.candidate_allowed('24-init', '22.1.8', fake('opt/llvm','22.1.8'), 'git-tags')
assert not mod.candidate_allowed('4.2.0-cqp-extended', '4.2.0', fake('opt/svt-av1','4.2.0'), 'git-tags')
assert not mod.candidate_allowed('26.0.99.901', '21.1.24', fake('xorg/xorg-server','21.1.24'), 'directory')
assert not mod.candidate_allowed('3.92.0', '3.41.2', fake('gnome/gcr','3.41.2'), 'gnome-cache')
assert not mod.candidate_allowed('3.97.0', '3.60.0', fake('gnome/gnome-terminal','3.60.0'), 'git-tags')
assert not mod.candidate_allowed('2.91.92', '2.31.0', fake('gnome/libwnck2','2.31.0'), 'gnome-cache')
assert not mod.candidate_allowed('1.90.0', '1.58.2', fake('opt/pango','1.58.2'), 'gnome-cache')
assert not mod.candidate_allowed('24.19.0-headers', '24.19.0', fake('opt/nodejs','24.19.0'), 'directory')
assert not mod.candidate_allowed('4.1-video', '2.24.1', fake('xorg/libva','2.24.1'), 'git-tags')
assert mod.only_if_newer('0.9.7', '0.8.2') == '0.9.7'
assert mod.candidate_allowed('8.22.0', '8.21.0', fake('core/curl','8.21.0'), 'directory')
assert mod.candidate_allowed('20260817', '20260805', fake('core/iana-etc','20260805'), 'git-tags')
# Explicit release channels must not be crossed by numeric sorting.
assert not mod.candidate_allowed('155.0', '153.2.0esr', fake('opt/firefox-esr','153.2.0esr'), 'directory')
assert mod.candidate_allowed('153.3.0esr', '153.2.0esr', fake('opt/firefox-esr','153.2.0esr'), 'directory')

# ABI-family package names must remain on their legacy compatibility lines.
assert not mod.candidate_allowed('2.2.1', '1.38.1', fake('gnome/libpeas','1.38.1'), 'gnome-cache')
assert not mod.candidate_allowed('2.36.4', '2.28.5', fake('opt/atkmm','2.28.5'), 'gnome-cache')
assert not mod.candidate_allowed('2.56.2', '2.46.5', fake('opt/pangomm','2.46.5'), 'gnome-cache')

# Every maintained Pkgfile must source cleanly and retain a real name/version.
count = 0
for tree in mod.TREES:
    for pkgfile in sorted((ROOT / "ports" / tree).glob("*/Pkgfile")):
        port = mod.eval_pkgfile(pkgfile)
        assert port.name, f"empty name after sourcing {pkgfile}"
        assert port.version, f"empty version after sourcing {pkgfile}"
        assert not any(ch.isspace() for ch in port.name), f"invalid whitespace in name for {pkgfile}: {port.name!r}"
        count += 1

assert count >= 1110, count


# v6 source-repair regressions: these are specific failures found during the
# full maintained-tree audit and must not regress to dead/ambiguous locations.
def port(rel):
    return mod.eval_pkgfile(ROOT / "ports" / rel / "Pkgfile")

p = port("opt/autoconf-archive")
assert any("ftp.gnu.org/gnu/autoconf-archive/" in s for s in p.sources), p.sources

p = port("opt/dbus-python")
assert p.version == "1.4.0" and any(s.endswith("dbus-python-1.4.0.tar.xz") for s in p.sources), p.sources

p = port("opt/texlive")
assert p.version == "20260301", p.version
assert all("/2025/" not in s for s in p.sources), p.sources
assert not any("upstream_fixes" in s for s in p.sources), p.sources

p = port("opt/libclc")
assert p.version == "23.1.1", p.version
assert any("llvm-project-23.1.1.src.tar.xz" in s for s in p.sources), p.sources

for rel in (
    "plasma/kactivities", "plasma/kactivities-stats", "plasma/kemoticons", "plasma/kinit",
):
    p = port(rel)
    assert p.version == "5.115.0" and any("/Attic/frameworks/5.115/" in s for s in p.sources), (rel, p.sources)

for rel in (
    "plasma/kdelibs4support", "plasma/kdesignerplugin", "plasma/kdewebkit",
    "plasma/khtml", "plasma/kjs", "plasma/kjsembed", "plasma/kmediaplayer",
    "plasma/kross", "plasma/kxmlrpcclient",
):
    p = port(rel)
    assert p.version == "5.115.0" and any("/Attic/frameworks/5.115/portingAids/" in s for s in p.sources), (rel, p.sources)


# v6 provider/source regressions for the second unverifiable-source batch.
assert mod.GIT_REPO_OVERRIDES["core/e2fsprogs"].endswith("e2fsprogs.git")
assert mod.GIT_REPO_OVERRIDES["core/freetype"].endswith("freetype.git")
assert mod.GIT_REPO_OVERRIDES["core/libpng"].endswith("libpng.git")
assert mod.GIT_REPO_OVERRIDES["core/squashfs-tools"].endswith("squashfs-tools.git")
assert mod.GIT_REPO_OVERRIDES["opt/freeglut"].endswith("freeglut.git")
assert mod.GIT_REPO_OVERRIDES["opt/gparted"].endswith("gparted.git")
assert mod.GIT_REPO_OVERRIDES["opt/smartmontools"].endswith("smartmontools.git")
assert mod.GIT_REPO_OVERRIDES["opt/swig"].endswith("swig.git")
assert mod.GIT_REPO_OVERRIDES["opt/taglib"].endswith("taglib.git")
assert mod.GIT_REPO_OVERRIDES["xorg/glew"].endswith("glew.git")

vals, reason = mod.git_tag_versions(["VER-2-14-2", "VER-2-14-3"], "2.14.3")
assert not reason and "2.14.3" in vals, (vals, reason)
vals, reason = mod.git_tag_versions(["xdg-utils-1.2.0", "xdg-utils-1.2.1"], "v1.2.1")
assert not reason and "v1.2.1" in vals, (vals, reason)

p = port("opt/fltk")
assert p.version == "1.4.5" and any("github.com/fltk/fltk/releases/download/release-1.4.5/" in x for x in p.sources), p.sources

p = port("opt/unicode-character-database")
assert p.version == "17.0.0"
assert any("/Public/17.0.0/ucd/UCD.zip" in x for x in p.sources), p.sources
assert any("/Public/17.0.0/ucd/Unihan.zip" in x for x in p.sources), p.sources

p = port("opt/texlive")
assert p.version == "20260301" and all("texlive.info/historic/" in x for x in p.sources), p.sources

print(f"checkupdate v10 regression: PASS ({count} maintained Pkgfiles evaluated)")

# provider regressions: source-hosting oddities must map through authoritative providers.
assert mod.PYPI_PROJECT_OVERRIDES["core/python3-docutils"] == "docutils"
assert mod.PYPI_PROJECT_OVERRIDES["opt/scons"] == "SCons"
assert mod.GIT_REPO_OVERRIDES["core/procps-ng"].endswith("procps.git")
assert mod.GIT_REPO_OVERRIDES["core/psmisc"].endswith("psmisc.git")
assert mod.GIT_REPO_OVERRIDES["lxqt/libfm-extra"].endswith("libfm.git")
assert mod.GIT_REPO_OVERRIDES["lxqt/menu-cache"].endswith("menu-cache.git")
assert mod.GIT_REPO_OVERRIDES["opt/cdrdao"].endswith("cdrdao.git")
assert mod.GIT_REPO_OVERRIDES["opt/poppler"].endswith("poppler.git")
assert mod.GIT_REPO_OVERRIDES["plasma/polkit-qt5"].endswith("polkit-qt-1.git")

p = port("opt/swig")
assert p.version == "4.5.1", p.version
p = port("opt/taglib")
assert p.version == "2.3.1", p.version

# v10 provider regressions: release-directory and vendor redirect providers.
class FakeHttp:
    def get(self, url):
        if url == "https://gcc.gnu.org/pub/gcc/releases/":
            return '<a href="gcc-16.2.0/">gcc-16.2.0/</a> <a href="gcc-16.3.0/">gcc-16.3.0/</a>'
        if url == "https://archive.mozilla.org/pub/security/nss/releases/":
            return '<a href="NSS_3_127_RTM/">NSS_3_127_RTM/</a> <a href="NSS_3_128_RTM/">NSS_3_128_RTM/</a>'
        raise AssertionError(url)
    def resolve(self, url):
        assert "discord.com/api/download/stable" in url
        return "https://dl.discordapp.net/apps/linux/1.0.157/discord-1.0.157.tar.gz", ""

latest, provider, reason = mod.gcc_release_directory(fake('opt/mingw-w64-gcc','16.2.0'), FakeHttp())
assert provider == 'gcc-releases' and not reason and latest == '16.3.0', (latest, provider, reason)
latest, provider, reason = mod.discord_stable(fake('opt/discord','0.0.97'), FakeHttp())
assert provider == 'discord-stable' and not reason and latest == '1.0.157', (latest, provider, reason)
latest, provider, reason = mod.nss_release_directory(fake('opt/nss','3.127'), FakeHttp())
assert provider == 'nss-releases' and not reason and latest == '3.128', (latest, provider, reason)
print("checkupdate v10 provider regression: PASS")
