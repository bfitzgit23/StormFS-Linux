livecd /home/gentoo/BFSOS # cat bootstrap.sh
#!/bin/bash -e

# Bootstrap environments do not necessarily have generated UTF-8 locales.
# The POSIX C locale is always available and keeps all bootstrap stages
# deterministic.
unset LC_CTYPE
unset LC_COLLATE
unset LC_MESSAGES
unset LC_MONETARY
unset LC_NUMERIC
unset LC_TIME

export LANG=C
export LC_ALL=C
export LANGUAGE=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# BFS release. The VERSION file is authoritative when present.
if [ -f "$SCRIPT_DIR/VERSION" ]; then
    BFS_VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION")"
else
    BFS_VERSION="0.9.0"
fi

BUILD_DATE="$(date +%Y%m%d)"

ARCHIVE_DIR="$SCRIPT_DIR/archives"
TOOLCHAIN_ARCHIVE_DIR="$ARCHIVE_DIR/toolchain"
BASE_ARCHIVE_DIR="$ARCHIVE_DIR/base"

_ensure_archive_dirs() {
    mkdir -p "$TOOLCHAIN_ARCHIVE_DIR" "$BASE_ARCHIVE_DIR"
}

_clean_start() {
    local answer

    echo
    echo "Start a completely clean BFS build?"
    echo
    echo "This will permanently delete:"
    echo "  $LFS"
    echo "  $TOOLS"
    echo "  $packagedir/*"
    echo "  $TOOLCHAIN_ARCHIVE_DIR/bfs-toolchain-*.tar.xz"
    echo "  $BASE_ARCHIVE_DIR/bfs-rootfs-*.tar.xz"
    echo
    printf "Type YES to continue, or press Enter to keep existing files: "
    read -r answer

    if [ "$answer" != "YES" ]; then
        echo
        echo "Keeping existing build files."
        return 0
    fi

    case "$LFS" in
        /tmp/lfs-rootfs)
            ;;
        *)
            echo "ERROR: Refusing to remove unexpected LFS path: $LFS" >&2
            exit 1
            ;;
    esac

    case "$TOOLS" in
        /tmp/lfs-tools)
            ;;
        *)
            echo "ERROR: Refusing to remove unexpected tools path: $TOOLS" >&2
            exit 1
            ;;
    esac

    echo
    echo "Removing old BFS build files..."

    sudo rm -rf -- "$LFS"
    sudo rm -rf -- "$TOOLS"

    mkdir -p "$packagedir"

    find "$packagedir" \
        -mindepth 1 \
        -maxdepth 1 \
        -exec rm -rf -- {} +

    _ensure_archive_dirs

    find "$TOOLCHAIN_ARCHIVE_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        -type f \
        -name 'bfs-toolchain-*.tar.xz' \
        -delete

    find "$BASE_ARCHIVE_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        -type f \
        -name 'bfs-rootfs-*.tar.xz' \
        -delete

    echo
    echo "Clean start completed."
}

_latest_archive() {
    local directory="$1"
    local pattern="$2"
    local latest

    latest="$(
        find "$directory" -maxdepth 1 -type f -name "$pattern" -printf '%f\n' 2>/dev/null |
            sort -V |
            tail -n 1
    )"

    [ -n "$latest" ] || return 1

    printf '%s/%s\n' "$directory" "$latest"
}

_clear_rootfs() {
    case "$LFS" in
        /tmp/lfs-rootfs)
            ;;
        *)
            echo "ERROR: Refusing to clear unexpected LFS path: $LFS" >&2
            exit 1
            ;;
    esac

    mkdir -p "$LFS"
    find "$LFS" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
}

_restore_toolchain() {
    local archive

    archive="$(_latest_archive "$TOOLCHAIN_ARCHIVE_DIR"         'bfs-toolchain-*.tar.xz')" || {
        echo "ERROR: No toolchain archive found in:" >&2
        echo "  $TOOLCHAIN_ARCHIVE_DIR" >&2
        exit 1
    }

    echo "Restoring newest toolchain archive:"
    echo "  $archive"

    tar -tJf "$archive" >/dev/null

    _clear_rootfs
    tar -xJpf "$archive" -C "$LFS"

    rm -f "$TOOLS"
    ln -s "${LFS}${TOOLS}" "$TOOLS"

    if [ ! -x "$TOOLS/bin/gcc" ] ||
        [ ! -x "$TOOLS/bin/ld" ] ||
        [ ! -x "$TOOLS/bin/pkgmk" ]
    then
        echo "ERROR: Restored toolchain failed verification." >&2
        exit 1
    fi

    echo
    echo "Toolchain restored successfully."
    echo "Continue with:"
    echo "  $0 2"
}

_restore_rootfs() {
    local archive

    archive="$(_latest_archive "$BASE_ARCHIVE_DIR"         'bfs-rootfs-*.tar.xz')" || {
        echo "ERROR: No base rootfs archive found in:" >&2
        echo "  $BASE_ARCHIVE_DIR" >&2
        exit 1
    }

    echo "Restoring newest base rootfs archive:"
    echo "  $archive"

    tar -tJf "$archive" >/dev/null

    _clear_rootfs
    tar -xJpf "$archive" -C "$LFS"

    for link in bin lib sbin; do
        if [ ! -e "$LFS/$link" ]; then
            ln -s "usr/$link" "$LFS/$link"
        fi
    done

    if [ -d "$LFS/usr/lib32" ] && [ ! -e "$LFS/lib32" ]; then
        ln -s usr/lib32 "$LFS/lib32"
    fi

    if [ -d "$LFS/usr/libx32" ] && [ ! -e "$LFS/libx32" ]; then
        ln -s usr/libx32 "$LFS/libx32"
    fi

    mkdir -p         "$LFS/dev/pts"         "$LFS/proc"         "$LFS/run"         "$LFS/sys"         "$LFS/tmp"

    if [ -d "${LFS}${TOOLS}" ]; then
        rm -f "$TOOLS"
        ln -s "${LFS}${TOOLS}" "$TOOLS"
    fi

    if [ ! -x "$LFS/usr/bin/bash" ] ||
        [ ! -x "$LFS/usr/bin/gcc" ] ||
        [ ! -f "$LFS/var/lib/pkg/db" ]
    then
        echo "ERROR: Restored base rootfs failed verification." >&2
        exit 1
    fi

    echo
    echo "Base rootfs restored successfully."
    echo "Continue with:"
    echo "  $0 3"
}

_buildtoolchain() {
    _ensure_archive_dirs

    if [ "$(id -u)" = 0 ]; then
        echo "temporary toolchain need to build as regular user"
        exit 1
    fi

    _clean_start

    export PATCH="$SCRIPT_DIR/sources/"
    export BOOTSTRAP=1
    export LFS_TGT=x86_64-lfs-linux-gnu
    export LFS_TGT32=i686-lfs-linux-gnu
    export LFS_TGTX32=x86_64-lfs-linux-gnux32

    mkdir -p ${LFS}${TOOLS} "$sourcedir"
    rm -f "$TOOLS"
    ln -sf "${LFS}${TOOLS}" "$TOOLS"

    cat > /tmp/bootstrap.conf <<EOF
export LANG=C
export LC_ALL=C
export LANGUAGE=C
export MAKEFLAGS=-j$(nproc)

PKGMK_SOURCE_DIR=$sourcedir
PKGMK_PACKAGE_DIR=/tmp/lfs-pkg

. $PWD/files/pkgmk.bootstrap
EOF

    if [ ! "$(PATH=$TOOLS/bin command -v pkgmk)" ]; then
        if [ ! -f "$sourcedir/pkgutils-5.40.12.tar.xz" ]; then
            curl -o "$sourcedir/pkgutils-5.40.12.tar.xz" \
                https://crux.nu/files/pkgutils-5.40.12.tar.xz
        fi

        rm -rf /tmp/pkgutils-5.40.12
        tar -xf "$sourcedir/pkgutils-5.40.12.tar.xz" -C /tmp

        sed -i \
            -e 's/ --static//' \
            -e 's/ -static//' \
            /tmp/pkgutils-5.40.12/Makefile

        make -j"$(nproc)" -C /tmp/pkgutils-5.40.12

        make -j"$(nproc)" \
            -C /tmp/pkgutils-5.40.12 \
            BINDIR="$TOOLS/bin" \
            MANDIR="$TOOLS/man" \
            ETCDIR="$TOOLS/etc" \
            install

        rm -rf /tmp/pkgutils-5.40.12
    fi

    for i in $toolchainpkg; do
        [ -f "$TOOLS/$i" ] && continue

        export tcpkg="$i"

        cd "ports/core/${i%-pass*}"

        mkdir -p /tmp/lfs-pkg

        pkgmk -d -is -if -cf /tmp/bootstrap.conf

        rm -rf /tmp/lfs-pkg

        cd - >/dev/null 2>&1

        touch "$TOOLS/$i"

        unset tcpkg
    done

    rm -f /tmp/bootstrap.conf

    local toolchain_archive

    _ensure_archive_dirs

    toolchain_archive="$TOOLCHAIN_ARCHIVE_DIR/bfs-toolchain-${BFS_VERSION}-${BUILD_DATE}.tar.xz"

    rm -f "$toolchain_archive"

    (
        cd "$LFS"
        XZ_DEFAULTS='-T0' tar -cvJpf "$toolchain_archive" .
    )

    tar -tJf "$toolchain_archive" >/dev/null

    echo
    echo "Toolchain build completed."
    echo "Archive created:"
    echo "  $toolchain_archive"
}

_compressrootfs() {
    local rootfs_archive

    _ensure_archive_dirs

    rootfs_archive="$BASE_ARCHIVE_DIR/bfs-rootfs-${BFS_VERSION}-${BUILD_DATE}.tar.xz"

    rm -f "$rootfs_archive"

    (
        cd "$LFS"

        XZ_DEFAULTS='-T0' tar \
            --exclude='./var/lib/pkg/rejected' \
            --exclude=".$TOOLS" \
            --exclude='./tmp/*' \
            --exclude='./dev/*' \
            --exclude='./sys/*' \
            --exclude='./proc/*' \
            --exclude='./run/*' \
            --exclude='./root/.cache' \
            -cvJpf "$rootfs_archive" .
    )

    tar -tJf "$rootfs_archive" >/dev/null

    echo
    echo "Base rootfs compressed successfully."
    echo "Archive created:"
    echo "  $rootfs_archive"
}

_buildbase() {
    if [ "$(id -u)" != 0 ]; then
        echo "base need to build as root"
        exit 1
    fi

    if [ ! -f "$LFS/var/lib/pkg/db" ]; then
        mkdir -pv "$LFS"/{etc,var} "$LFS"/usr/{bin,lib,sbin} "$LFS/dev"

        for i in bash cat chmod dd echo ln mkdir pwd rm stty; do
            ln -svf "$TOOLS/bin/$i" "$LFS/usr/bin"
        done

        for i in env install perl printf touch; do
            ln -svf "$TOOLS/bin/$i" "$LFS/usr/bin"
        done

        for i in bin lib sbin; do
            ln -sv "usr/$i" "$LFS/$i"
        done

        case $(uname -m) in
            x86_64)
                mkdir -pv "$LFS/lib64"
                ;;
        esac

        mkdir -pv "$LFS/usr/lib32" "$LFS/usr/libx32"

        ln -sv usr/lib32 "$LFS/lib32"
        ln -sv usr/libx32 "$LFS/libx32"

        ln -svf \
            "$TOOLS/lib/libgcc_s.so" \
            "$TOOLS/lib/libgcc_s.so.1" \
            "$LFS/usr/lib"

        ln -svf \
            "$TOOLS/lib/libstdc++.a" \
            "$TOOLS/lib/libstdc++.so" \
            "$TOOLS/lib/libstdc++.so.6" \
            "$LFS/usr/lib"

        ln -svf bash "$LFS/bin/sh"

        ln -svf /proc/self/mounts "$LFS/etc/mtab"

        cat ports/core/aaa_filesystem/passwd > "$LFS/etc/passwd"
        cat ports/core/aaa_filesystem/group > "$LFS/etc/group"

        mkdir -p "$LFS/var/lib/pkg"
        touch "$LFS/var/lib/pkg/db"

        mkdir -p "$LFS/$pkgmkpkg"
        mkdir -p "$LFS/$pkgmksrc"
        mkdir -p "$packagedir"
    fi

    rm -rf "$LFS/usr/ports/"

    cp -r ports/ "$LFS/usr/"

    cp files/pkgin "$TOOLS/bin/pkgin"
    chmod +x "$TOOLS/bin/pkgin"

    mkdir -p "$LFS/var/lib/pkgmk"

    cp ports/core/pkgutils/extension \
        "$LFS/var/lib/pkgmk"

    cat > "$LFS/tmp/pkgmk.conf" <<EOF
export LANG=C
export LC_ALL=C
export LANGUAGE=C

export CPPFLAGS="-I/usr/include"
export CFLAGS="-O2 -march=x86-64 -pipe"
export CXXFLAGS="\${CFLAGS}"
export LDFLAGS="-L/usr/lib -Wl,-rpath-link,/usr/lib"
export LIBRARY_PATH="/usr/lib"

export PKG_CONFIG_PATH="/usr/lib/pkgconfig:/usr/share/pkgconfig"
export PKG_CONFIG_LIBDIR="/usr/lib/pkgconfig:/usr/share/pkgconfig"

export JOBS=$(nproc)
export MAKEFLAGS="-j \$JOBS"

PKGMK_SOURCE_DIR="/$pkgmksrc"
PKGMK_PACKAGE_DIR="/$pkgmkpkg"
PKGMK_WORK_DIR="/tmp/pkgmk-\$name"

. /var/lib/pkgmk/extension
EOF

    LFSPATH=/bin:/usr/bin:/sbin:/usr/sbin

    if [ "${1:-}" != rebuild ]; then
        LFSPATH=$LFSPATH:$TOOLS/bin
    fi

    mountfs

    for i in $basepkg; do
        if [ "${1:-}" != rebuild ]; then
            pkginfo -i -r "$LFS" |
                awk '{print $1}' |
                grep -qx "$i" &&
                continue

            unset _force

            case $i in
                aaa_filesystem|gcc|bash|dash|perl|coreutils|pkgutils)
                    _force=-f
                    ;;
            esac

            chroot "$LFS" \
                env -i \
                HOME=/root \
                TERM="${TERM:-dumb}" \
                LANG=C \
                LC_ALL=C \
                LANGUAGE=C \
                PATH="$LFSPATH" \
                pkgin -d "$i" -is -if -im -cf /tmp/pkgmk.conf \
                || {
                    umountfs
                    exit 1
                }

            pkgadd -r "$LFS" ${_force:-} -f \
                "$(ls -1 "$packagedir/$i#"* | tail -n1)" \
                || {
                    umountfs
                    exit 1
                }

            case $i in
                glibc)
                    cat << EOF > "$LFS/tmp/glibc-postinstall"
#!/bin/sh
set -e

export LANG=C
export LC_ALL=C
export LANGUAGE=C

TOOLS="$TOOLS"
HOST_TRIPLET="\$(uname -m)-pc-linux-gnu"
REAL_LD=""
SAVED_LD="/tmp/ld-real.\$\$"

cleanup() {
    rm -f "\$SAVED_LD"
}

trap cleanup EXIT HUP INT TERM

echo "Adjusting GCC and binutils after glibc"

for candidate in \
    "\$TOOLS/bin/ld.bfd" \
    "\$TOOLS/\$HOST_TRIPLET/bin/ld.bfd" \
    "\$TOOLS/bin/ld-new" \
    "\$TOOLS/\$HOST_TRIPLET/bin/ld-new" \
    "\$TOOLS/bin/ld" \
    "\$TOOLS/\$HOST_TRIPLET/bin/ld"
do
    if [ -f "\$candidate" ] &&
        file "\$candidate" 2>/dev/null | grep -q 'ELF'
    then
        REAL_LD="\$candidate"
        break
    fi
done

if [ -z "\$REAL_LD" ]; then
    echo "ERROR: No real ELF ld executable found."

    echo
    echo "Available linker candidates:"

    for candidate in \
        "\$TOOLS/bin/ld.bfd" \
        "\$TOOLS/\$HOST_TRIPLET/bin/ld.bfd" \
        "\$TOOLS/bin/ld-new" \
        "\$TOOLS/\$HOST_TRIPLET/bin/ld-new" \
        "\$TOOLS/bin/ld" \
        "\$TOOLS/\$HOST_TRIPLET/bin/ld"
    do
        if [ -e "\$candidate" ]; then
            file "\$candidate"
        fi
    done

    exit 1
fi

echo "Using linker: \$REAL_LD"

# Save the real linker before renaming any path that may refer to it.
cp -av "\$REAL_LD" "\$SAVED_LD"

if [ -e "\$TOOLS/bin/ld" ] &&
    [ ! -e "\$TOOLS/bin/ld-old" ]
then
    mv -v "\$TOOLS/bin/ld" "\$TOOLS/bin/ld-old"
fi

if [ -e "\$TOOLS/\$HOST_TRIPLET/bin/ld" ] &&
    [ ! -e "\$TOOLS/\$HOST_TRIPLET/bin/ld-old" ]
then
    mv -v \
        "\$TOOLS/\$HOST_TRIPLET/bin/ld" \
        "\$TOOLS/\$HOST_TRIPLET/bin/ld-old"
fi

install -m 0755 "\$SAVED_LD" "\$TOOLS/bin/ld"
install -m 0755 \
    "\$SAVED_LD" \
    "\$TOOLS/\$HOST_TRIPLET/bin/ld"

gcc -dumpspecs | sed \
    -e "s@\$TOOLS@@g" \
    -e "/\*startfile_prefix_spec:/{n;s@.*@/usr/lib/ @}" \
    -e '/\*cpp:/{n;s@\$@ -isystem /usr/include@}' \
    > "\$(dirname "\$(gcc --print-libgcc-file-name)")/specs"

echo 'int main(void) { return 0; }' > dummy.c

cc -c dummy.c -o dummy.o

rm -f dummy.c dummy.o

echo 'int main(void) { return 0; }' > dummy.c

cc dummy.c -v -Wl,--verbose > dummy.log 2>&1

readelf -l a.out | grep ': /lib' \
    > /tmp/adjusttoolchainresult || true

grep -o '/usr/lib.*/crt[1in].*succeeded' dummy.log \
    >> /tmp/adjusttoolchainresult || true

grep -B1 '^ /usr/include' dummy.log \
    >> /tmp/adjusttoolchainresult || true

grep 'SEARCH.*/usr/lib' dummy.log |
    sed 's|; |\n|g' \
    >> /tmp/adjusttoolchainresult || true

grep "/lib.*/libc.so.6 " dummy.log \
    >> /tmp/adjusttoolchainresult || true

grep found dummy.log \
    >> /tmp/adjusttoolchainresult || true

rm -fv dummy.c dummy.o a.out dummy.log
EOF

                    chroot "$LFS" \
                        env -i \
                        HOME=/root \
                        TERM="${TERM:-dumb}" \
                        LANG=C \
                        LC_ALL=C \
                        LANGUAGE=C \
                        PATH="$LFSPATH" \
                        sh /tmp/glibc-postinstall

                    rm -f "$LFS/tmp/glibc-postinstall"
                    ;;
            esac
        else
            chroot "$LFS" \
                env -i \
                HOME=/root \
                TERM="${TERM:-dumb}" \
                LANG=C \
                LC_ALL=C \
                LANGUAGE=C \
                PATH="$LFSPATH" \
                prt-get update -im -fr -if -fi "$i" \
                || {
                    umountfs
                    exit 1
                }
        fi
    done

    umountfs

    echo
    echo "base system build completed"
}

mountfs() {
    umountfs

    mkdir -p "$LFS/dev" "$LFS/run" "$LFS/proc" "$LFS/sys"

    mount --bind /dev "$LFS/dev"

    mount -t devpts devpts \
        "$LFS/dev/pts" \
        -o gid=5,mode=620

    mount -t proc proc "$LFS/proc"
    mount -t sysfs sysfs "$LFS/sys"
    mount -t tmpfs tmpfs "$LFS/run"

    if [ -h "$LFS/dev/shm" ]; then
        mkdir -p "$LFS/$(readlink "$LFS/dev/shm")"
    fi

    mkdir -p "$LFS/$pkgmksrc"
    mkdir -p "$LFS/$pkgmkpkg"

    mount --bind "$sourcedir" "$LFS/$pkgmksrc"
    mount --bind "$packagedir" "$LFS/$pkgmkpkg"
}

umountfs() {
    unmount "$LFS/dev/pts"
    unmount "$LFS/dev"
    unmount "$LFS/run"
    unmount "$LFS/proc"
    unmount "$LFS/sys"
    unmount "$LFS/$pkgmkpkg"
    unmount "$LFS/$pkgmksrc"
}

unmount() {
    while true; do
        mountpoint -q "$1" || break
        umount "$1" 2>/dev/null
    done
}

export LFS=/tmp/lfs-rootfs
export TOOLS=/tmp/lfs-tools

export PATH=$TOOLS/bin:$PATH

toolchainpkg="
binutils-pass1
gmp
mpfr
mpc
gcc-pass1
linux-headers
glibc
gcc-pass2
binutils-pass2
libxcrypt
gcc-pass3
m4
ncurses
bash
bison
bzip2
coreutils
diffutils
file
findutils
gawk
gettext
grep
gzip
make
patch
perl
zlib
xz
libtirpc
libnsl
python
sed
tar
texinfo
openssl
ca-certificates
curl
libarchive
"

basepkg="
aaa_filesystem
linux-headers
man-pages
glibc
autoconf
zlib
bzip2
xz
file
ncurses
readline
m4
bc
binutils
pkgconf
libxcrypt
gmp
mpfr
mpc
attr
acl
gcc
libcap
psmisc
sed
tzdata
iana-etc
bison
flex
pcre2
grep
bash
libtool
gdbm
gperf
expat
inetutils
perl
perl-xml-parser
intltool
autoconf
automake
openssl
ca-certificates
curl
gettext
elfutils
libffi
sqlite
python
coreutils
check
diffutils
gawk
findutils
groff
less
gzip
zstd
iptables
libtirpc
iproute2
kbd
libpipeline
make
patch
man-db
tar
texinfo
python3-setuptools
python3-pip
python3-flit-core
python3-packaging
python3-installer
python3-build
python3-pyproject-hooks
python3-wheel
util-linux
meson
ninja
kmod
linux-pam
shadow
libpng
which
freetype
fuse
grub
popt
mandoc
efivar
efibootmgr
grub-efi
vim
nano
python3-markupsafe
python3-packaging
python3-tomli
python3-pyproject-hooks
python3-build
python3-installer
python3-pytz
python3-babel
python3-jinja2
systemd
dbus
procps-ng
util-linux
e2fsprogs
libarchive
pkgutils
dialog
prt-get
httpup
ports
prt-utils
signify
"

sourcedir="$PWD/sources"
packagedir="$PWD/packages"

pkgmkpkg="var/cache/pkg/packages"
pkgmksrc="var/cache/pkg/sources"

if [ -z "${1:-}" ]; then
    cat << EOF
Usage:
  $0 <options>

Options:
  1  build temporary toolchain
  2  build base system (using temporary toolchain)
  3  rebuild base system (using final system toolchain itself)
  4  compress base rootfs
  5  resume from newest toolchain archive
  6  resume from newest base rootfs archive
EOF

    exit 0
fi

case $1 in
    1)
        _buildtoolchain
        ;;
    2)
        _buildbase
        ;;
    3)
        _buildbase rebuild
        ;;
    4)
        _compressrootfs
        ;;
    5)
        _restore_toolchain
        ;;
    6)
        _restore_rootfs
        ;;
    *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
esac

exit 0
