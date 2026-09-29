#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }
require_grep() { local pat="$1" file="$2" msg="$3"; grep -Eq -- "$pat" "$file" || fail "$msg"; }
reject_grep() { local pat="$1" file="$2" msg="$3"; ! grep -Eq -- "$pat" "$file" || fail "$msg"; }

bash -n bootstrap.sh
bash -n scripts/bfs-build-iso.sh
bash -n scripts/install-bfs-menu-current.sh
bash -n files/bfs-prefetch-curl
bash -n ports/opt/geoclue/post-install
pass 'canonical shell syntax'

require_grep 'BFSOS Bootstrap' bootstrap.sh 'bootstrap branding is not BFSOS'
reject_grep 'BFS Linux Bootstrap' bootstrap.sh 'legacy bootstrap branding remains'
require_grep 'BFSOS Installer' scripts/install-bfs-menu-current.sh 'installer branding is not BFSOS'
reject_grep 'BFS Linux Installer' scripts/install-bfs-menu-current.sh 'legacy installer branding remains'
require_grep 'BFSOS Installation Complete' scripts/install-bfs-menu-current.sh 'completion branding missing'
require_grep 'Enter installed BFSOS system \(chroot\)' scripts/install-bfs-menu-current.sh 'post-install BFSOS chroot label missing'
pass 'BFSOS UI branding'

require_grep 'show_installer_help\(\)' scripts/install-bfs-menu-current.sh 'installer contextual help function missing'
for topic in storage raid luks lvm filesystem zram kernel sudo serial base accounts; do
    require_grep "show_installer_help $topic" scripts/install-bfs-menu-current.sh "installer help topic not wired: $topic"
done
require_grep 'Hostname / timezone / locale' scripts/install-bfs-menu-current.sh 'defaults-first basic-system menu missing'
grep -Fq 'Root password login: $ROOT_PASSWORD_POLICY' scripts/install-bfs-menu-current.sh || fail 'root password policy not consolidated under accounts'
reject_grep '[0-9]+ "Root account \[' scripts/install-bfs-menu-current.sh 'standalone Root account menu still exists'
pass 'installer UX source changes'

require_grep 'BFSOS Live Shell' scripts/bfs-build-iso.sh 'live shell heading missing'
reject_grep '5\) Quit menu' scripts/bfs-build-iso.sh 'redundant live Quit menu entry remains'
pass 'live-menu shell/quit cleanup'

require_grep 'https://github.com/bmadonnaster/BFSOS.git' scripts/bfs-build-iso.sh 'ISO builder is not using GitHub'

# Codeberg is retired as an active BFSOS upstream.  The prt-get post-install
# migration is the one intentional exception: it must recognize the old URL
# so existing BFSOS installations can migrate themselves to GitHub.
if grep -RnsI 'codeberg\.org/bmadonnaster/BFSOS' \
    README.md bootstrap.sh files ports scripts \
    --exclude='install-bfs-menu-v50-r*.sh' \
    --exclude='test-r355-ui-security-migration.sh' \
    --exclude='*.md' --exclude='*.log' --exclude='*.tsv' \
    >/tmp/bfsos-r355-codeberg.$$ 2>/dev/null; then

    grep -v '^ports/core/prt-get/post-install:' \
        /tmp/bfsos-r355-codeberg.$$ \
        >/tmp/bfsos-r355-codeberg-active.$$ || true

    if [[ -s /tmp/bfsos-r355-codeberg-active.$$ ]]; then
        cat /tmp/bfsos-r355-codeberg-active.$$ >&2
        rm -f /tmp/bfsos-r355-codeberg.$$ \
              /tmp/bfsos-r355-codeberg-active.$$
        fail 'active BFSOS-specific Codeberg references remain'
    fi
fi

rm -f /tmp/bfsos-r355-codeberg.$$ \
      /tmp/bfsos-r355-codeberg-active.$$

require_grep 'https://codeberg.org/bmadonnaster/BFSOS.git' \
    ports/core/prt-get/post-install \
    'legacy Codeberg migration detector missing'

require_grep 'https://github.com/bmadonnaster/BFSOS.git' \
    ports/core/prt-get/post-install \
    'GitHub migration destination missing'

pass 'active GitHub migration references'

if grep -RnsI -E 'AIza[0-9A-Za-z_-]{20,}' ports/opt/geoclue README.md docs/INSTALL.md scripts files >/tmp/bfsos-r355-secret.$$ 2>/dev/null; then
    cat /tmp/bfsos-r355-secret.$$ >&2
    rm -f /tmp/bfsos-r355-secret.$$
    fail 'Google API-key-like value remains in maintained Geoclue/current documentation paths'
fi
rm -f /tmp/bfsos-r355-secret.$$
require_grep 'rm -f /etc/geoclue/conf.d/90-lfs-google.conf' ports/opt/geoclue/post-install 'Geoclue legacy credential override cleanup missing'
pass 'Geoclue maintained-tree credential cleanup'

require_grep 'PKGMK_DOWNLOAD_PROG="\$SCRIPT_DIR/files/bfs-prefetch-curl"' bootstrap.sh 'prefetch wrapper is not restored'
require_grep 'refusing to write archive data to an interactive terminal' files/bfs-prefetch-curl 'stdout guard missing from prefetch wrapper'
pass 'prefetch wrapper source guard'

require_grep '1\|toolchain\|build-toolchain\)' bootstrap.sh 'direct stage 1 dispatch missing'
require_grep '2\|base\|build-base\)' bootstrap.sh 'direct stage 2 dispatch missing'
require_grep '3\|rebuild\|rebuild-base\)' bootstrap.sh 'direct stage 3 dispatch missing'
require_grep '4\|verify\|verify-base\)' bootstrap.sh 'direct stage 4 dispatch missing'
require_grep '5\|archive\|archive-base\)' bootstrap.sh 'direct stage 5 dispatch missing'
require_grep 'full\|full-bootstrap\|all\)' bootstrap.sh 'full bootstrap dispatch missing'
pass 'direct bootstrap dispatch source'

require_grep 'NAME="BFSOS"' ports/core/aaa_filesystem/Pkgfile 'installed os-release NAME not BFSOS'
grep -Fq 'PRETTY_NAME="BFSOS $bfs_version"' ports/core/aaa_filesystem/Pkgfile || fail 'installed os-release PRETTY_NAME not BFSOS'
grep -Fq 'BFSOS $bfs_version \\n \\l' ports/core/aaa_filesystem/Pkgfile || fail 'installed /etc/issue branding not BFSOS'
pass 'installed-system BFSOS branding'

[[ -f docs/INSTALL.md ]] || fail 'docs/INSTALL.md missing'
[[ -f docs/COMMAND-LINE.md ]] || fail 'docs/COMMAND-LINE.md missing'
pass 'current documentation files'

printf 'r355 source-policy regression: PASS\n'
