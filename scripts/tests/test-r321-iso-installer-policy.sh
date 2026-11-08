#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "r321 ISO/installer policy regression: FAIL: $*" >&2; exit 1; }

iso=scripts/bfs-build-iso.sh
inst=scripts/install-bfs-menu-current.sh

grep -Fq 'BASE_MODE="${BFS_ISO_BASE_MODE:-auto}"' "$iso" || fail "ISO builder is not local-first by default"
grep -Fq -- '--sourceforge-base' "$iso" || fail "explicit SourceForge mode missing"
grep -Fq -- '--local-base PATH' "$iso" || fail "explicit local-base path mode missing"
grep -Fq 'project_base_candidates' "$iso" || fail "local project-base discovery helper missing"
grep -Fq '*.tar.zst|*.tar.zst.tmp' "$iso" || fail "temporary .tar.zst validation support missing"
! grep -Fq 'bfs-live-enable-ssh' "$iso" || fail "obsolete live SSH enable helper is still present"
grep -Fq 'ssh-keygen -A' "$iso" || fail "manual live SSH instructions missing"
! grep -A20 "cat > \"\$root/usr/local/sbin/bfs-live-init\"" "$iso" | grep -Fq 'ssh-keygen -A' || \
    fail "live init still generates SSH host keys automatically"
grep -Fq 'rm -f "$root"/etc/ssh/ssh_host_*' "$iso" || fail "ISO build does not remove baked SSH host keys"

grep -Fq '(fd|sr|loop)[0-9]+$/' "$inst" || fail "installer does not filter floppy/optical/loop pseudo-disks"
grep -Fq '# Back from Ready to install returns to the main installer menu.' "$inst" || fail "review Back-loop fix missing"

# The scratchpkg migration removed the CRUX ports command.  Installation must
# use portsync and pull every Venom Linux collection, including s6-services.
! grep -Eq '^[[:space:]]*ports -u([[:space:]]|$)' "$inst" || fail "installer still invokes the removed ports tool"
! grep -Eq '^[[:space:]]*command -v ports([[:space:]]|$)' "$inst" || fail "installer still requires the removed ports command"
grep -Fq 'portsync -r' "$inst" || fail "installer does not synchronize ports with scratchpkg"
grep -Fq 'configure_venom_ports_repositories' "$inst" || fail "installer Venom repository setup missing"
grep -Fq 'ln -sfn ../venom-core/NEWS /usr/ports/main/NEWS' "$inst" || \
    fail "portnews news-directory compatibility link missing"
# scratch isinstalled is a one-package status check and returns 1 for a
# missing package.  A pipefail pipeline over a whole closure aborts silently
# under set -e, before the package-upgrade error can be reported.
! grep -Fq 'scratch isinstalled $dependency_closure' "$inst" || \
    fail "installed-system dependency preflight still pipes a closure through isinstalled"
grep -Fq 'for dependency in $dependency_closure' "$inst" || \
    fail "installed-system dependency preflight does not check each package"
grep -Fq 'if ! scratch isinstalled "$dependency"' "$inst" || \
    fail "installed-system dependency preflight does not use isinstalled's status"
# Older base archives contain stale BFSOS recipes. Refresh Git and cpio from
# the checked-out tree before entering the chroot so installer-side recipe
# fixes apply without a base-archive rebuild.
grep -Fq 'for transitional_port in git cpio' "$inst" || \
    fail "installer does not refresh the Git/cpio provisioning recipes"
grep -Fq 'PROJECT_DIR/ports/opt/$transitional_port' "$inst" || \
    fail "installer recipe refresh is not sourced from the project tree"
grep -Fq 'local wpa_port=core/wpa_supplicant' "$inst" || \
    fail "installer does not refresh the wpa_supplicant recipe"
! grep -Fq 'autoreconf -fi' ports/opt/cpio/spkgbuild || \
    fail "cpio still regenerates autotools files instead of using its shipped configure"
grep -Fq 'bfs_autobuild' ports/opt/cpio/spkgbuild || \
    fail "cpio recipe lost its build hook"
# Stage 2 builds autoconf before m4, so the installed autom4te records the
# temporary toolchain's m4. Repair that path for existing base archives and
# prevent it from being baked into new ones.
grep -Fq 's|/tmp/lfs-tools/bin/m4|/usr/bin/m4|g' "$inst" || \
    fail "installer does not repair autom4te's temporary-toolchain m4 path"
grep -Fq 's|/tmp/lfs-tools/bin/m4|/usr/bin/m4|g' ports/core/autoconf/spkgbuild || \
    fail "autoconf recipe bakes in the temporary-toolchain m4 path"
grep -Fq 'M4=/usr/bin/m4 ./bootstrap.sh' ports/core/rdfind/spkgbuild || \
    fail "rdfind bootstrap does not use the target m4"
# CONFIG_THUNDERBOLT was replaced by CONFIG_USB4. Older base archives carry
# the obsolete guard, so refresh the BFSOS kernel ports before building them.
grep -Fq 'for kernel_port in linux linux-lts; do' "$inst" || \
    fail "installer does not refresh both BFSOS kernel ports"
grep -Fq 'PROJECT_DIR/ports/core/$kernel_port' "$inst" || \
    fail "installer does not copy the refreshed BFSOS kernel port"
for kernel_port in linux linux-lts; do
    grep -Fq 'scripts/config --module USB4' "ports/core/$kernel_port/spkgbuild" || \
        fail "$kernel_port recipe does not enable USB4"
    if grep -Fq -- '--module THUNDERBOLT' "ports/core/$kernel_port/spkgbuild" || \
       grep -Fq 'CONFIG_THUNDERBOLT=' "ports/core/$kernel_port/config"; then
        fail "$kernel_port still references the retired THUNDERBOLT symbol"
    fi
done
# Pagure's newt release endpoint returns 404. Use the byte-identical BLFS
# mirror for both recipes, and discard stale cached archives in existing
# targets because pkg_fetch reuses any file with the expected name.
for newt_port in opt/newt compat-32/libnewt-32; do
    grep -Fq 'https://anduin.linuxfromscratch.org/BLFS/newt/newt-$version.tar.gz' \
        "ports/$newt_port/spkgbuild" || fail "$newt_port does not use the newt mirror"
done
grep -Fq 'for newt_port in opt/newt compat-32/libnewt-32; do' "$inst" || \
    fail "installer does not refresh both newt recipes"
grep -Fq 'sources/newt-0.52.25.tar.gz*' "$inst" || \
    fail "installer does not discard the stale newt source archive"
grep -Fq 'packages/newt#*.pkg.tar.*' "$inst" || \
    fail "installer does not discard the stale newt package"
grep -Fq 'packages/libnewt-32#*.pkg.tar.*' "$inst" || \
    fail "installer does not discard the stale libnewt-32 package"
# Existing targets may also have an older NSS recipe or a truncated 3.129
# source download. Refresh both recipes and discard cached NSS artifacts.
grep -Fq 'for nss_port in opt/nss compat-32/nss-32; do' "$inst" || \
    fail "installer does not refresh both NSS recipes"
grep -Fq 'sources/nss-3.129.tar.gz*' "$inst" || \
    fail "installer does not discard the stale NSS source archive"
grep -Fq 'packages/nss#*.pkg.tar.*' "$inst" || \
    fail "installer does not discard the stale NSS package"
grep -Fq 'packages/nss-32#*.pkg.tar.*' "$inst" || \
    fail "installer does not discard the stale NSS-32 package"
# Keep the release tag fully pinned: a variable followed by _RTM is parsed
# as one variable by POSIX shells, producing NSS_/ and a 404.
for nss_port in opt/nss compat-32/nss-32; do
    nss_url="$(NSS_PORT="$nss_port" sh -c '. "./ports/$NSS_PORT/spkgbuild"; printf "%s\n" "$source"' | awk '{print $1}')"
    [ "$nss_url" = 'https://archive.mozilla.org/pub/security/nss/releases/NSS_3_129_RTM/src/nss-3.129.tar.gz' ] || \
        fail "$nss_port generates the wrong NSS source URL: $nss_url"
done
# GLib installs gschema.dtd, which is not a schema source. The packaged
# scratchpkg port and the installer compatibility repair must ignore it so
# minimal installs do not run glib-compile-schemas with no schema files.
scratchpkg_port=ports/core/scratchpkg
grep -Fq 'release=3' "$scratchpkg_port/spkgbuild" || \
    fail "scratchpkg trigger repair release is missing"
grep -Fq 'grep -Eq "^usr/share/glib-2.0/schemas/.*[.]gschema[.](xml|override)$"' \
    "$scratchpkg_port/spkgbuild" || \
    fail "scratchpkg trigger still matches gschema.dtd"
grep -Fq 'repair_scratchpkg_glib_schema_trigger' "$inst" || \
    fail "installer does not repair existing scratchpkg installations"
for hook in ports/opt/glib/post-install ports/opt/gtk4/post-install; do
    grep -Fq "*.gschema.xml" "$hook" || \
        fail "$hook compiles an empty GLib schema directory"
done
grep -Fq 'for glib_hook_port in opt/glib opt/gtk4; do' "$inst" || \
    fail "installer does not refresh the guarded GLib/GTK4 hooks"
# scratchpkg auto-extracts every .zip into $SRC, so the four DocBook releases
# must stay packed until each is unpacked into its own version directory. The
# old recipe looked for nonexistent .zyp files and then failed at its 4.1.2
# catalog workaround.
docbook_port=ports/opt/docbook-xml
! grep -Fq 'bsdtar xf "$SRC/$name-4.$vminor.zyp"' "$docbook_port/spkgbuild" || \
    fail "docbook-xml still reads nonexistent .zyp archives"
grep -Fq 'release=10' "$docbook_port/spkgbuild" || \
    fail "docbook-xml ZIP extraction fix release is missing"
grep -Fq 'noextract="$name-4.5.zip $name-4.4.zip $name-4.3.zip $name-4.2.zip"' \
    "$docbook_port/spkgbuild" || \
    fail "docbook-xml does not keep overlapping ZIP sources packed"
grep -Fq 'unzip -q "$SRC/$name-4.$vminor.zip" -d "$PKG$dest" || return 1' \
    "$docbook_port/spkgbuild" || \
    fail "docbook-xml does not unpack each ZIP into its version directory"
grep -Fq 'docbook_xml_port=opt/docbook-xml' "$inst" || \
    fail "installer does not refresh the docbook-xml recipe"

for repo in core extra nonfree multilib s6 kde-lxqt mate xfce s6-services; do
    grep -Fq "https://codeberg.org/venomlinux/$repo.git" "$inst" || fail "installer Venom repository missing: $repo"
    grep -Fq "https://codeberg.org/venomlinux/$repo.git" ports/core/scratchpkg/scratchpkg.repo || fail "default scratchpkg repository missing: $repo"
done

# The target is OpenRC-only.  Do not make a completed install depend on the
# systemd package just to create the machine ID required by D-Bus.
! grep -Eq '^[[:space:]]*systemd-machine-id-setup([[:space:]]|$)' "$inst" || fail "installer still invokes systemd-machine-id-setup"
grep -Fq 'ensure_machine_id() {' "$inst" || fail "portable machine-id generator missing"
grep -Fq 'dbus-uuidgen' "$inst" || fail "machine-id generator has no D-Bus fallback"
grep -Fq '/proc/sys/kernel/random/uuid' "$inst" || fail "machine-id generator has no kernel fallback"

echo "r321 ISO/installer policy regression: PASS"
