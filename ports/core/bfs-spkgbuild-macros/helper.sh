#!/bin/sh
#
# BFSOS/StormFS shared spkgbuild helpers
#
# Installed as /usr/share/bfsos/spkgbuild.helper by
# ports/core/bfs-spkgbuild-macros and sourced by spkgbuild recipes that need
# the automatic build-type detection that the former CRUX pkgmk extension
# provided.  Everything here is POSIX shell; the recipes are sourced and run
# by scratchpkg's pkgbuild, which uses build() as the single build hook.
#
# Environment provided by pkgbuild:
#   $SRC    unpacked sources for this port (cwd during build())
#   $PKG    staging directory that becomes the package payload
#   $name, $version, $release, $CFLAGS, $JOBS
#
# Recipes that define an explicit build() do not need this file.

bfs_die() {
    printf 'ERROR: %s\n' "$*" >&2
    return 1
}

# Compatibility libraries are built for i686.  scratchpkg has no per-port
# architecture switch, so *-32 recipes call bfs_compat32 first.
bfs_compat32() {
    BFS_COMPAT32=1
    BFS_MULTILIB_HOST="${BFS_MULTILIB_HOST:-i686-pc-linux-gnu}"
    export BFS_COMPAT32 BFS_MULTILIB_HOST
    export CHOST="${CHOST:-$BFS_MULTILIB_HOST}"
    export CC="${CC:-gcc -m32}"
    export CXX="${CXX:-g++ -m32}"
    export PKG_CONFIG_LIBDIR="/usr/lib32/pkgconfig:/usr/share/pkgconfig"
    export PKG_CONFIG_PATH=""
    export BFS_PKG_LIBDIR="/usr/lib32"
    export BFS_PKG_LIBDIR_NAME="lib32"
    return 0
}

# Refuse a 32-bit package that leaked files into the 64-bit library paths.
bfs_compat32_validate() {
    [ -n "${BFS_COMPAT32:-}" ] || return 0

    _bfs_bad=""
    for _bfs_native in "$PKG/usr/lib" "$PKG/lib"; do
        [ -d "$_bfs_native" ] || continue
        _bfs_bad="$_bfs_bad$(find "$_bfs_native" -mindepth 1 ! -type d -print 2>/dev/null)"
    done

    if [ -n "$_bfs_bad" ]; then
        printf 'ERROR: compat-32 payload contains files in native library directories:\n%s\n' \
            "$_bfs_bad" >&2
        printf 'ERROR: expected compat libraries under /usr/lib32\n' >&2
        return 1
    fi
    return 0
}

# build_opt may be a plain string (spkgbuild style) or a bash-style array
# (legacy spkgbuild style).  Normalise both into BFS_BUILD_OPTS.
bfs_collect_build_opt() {
    BFS_BUILD_OPTS=""
    if [ -n "${build_opt:-}" ]; then
        eval 'BFS_BUILD_OPTS="${build_opt[*]}"'
    fi
    return 0
}

# Apply patch sources the way pkgmk did, before the build runs.
bfs_apply_patches() {
    [ -z "${BFS_SKIP_PATCHES:-}" ] || return 0
    [ "${SPKG_AUTO_PATCH:-yes}" = no ] && return 0
    _bfs_patch_opt="${patch_opt:--p1}"
    for _bfs_patch in "$SRC"/*.patch "$SRC"/*.diff \
                      "$SRC"/*.patch.gz "$SRC"/*.diff.gz \
                      "$SRC"/*.patch.xz "$SRC"/*.diff.xz \
                      "$SRC"/*.patch.bz2 "$SRC"/*.diff.bz2; do
        [ -f "$_bfs_patch" ] || continue
        case $_bfs_patch in
            *.patch.gz|*.diff.gz)
                gzip -dc "$_bfs_patch" | patch -t "$_bfs_patch_opt" || return 1 ;;
            *.patch.xz|*.diff.xz)
                xz -dc "$_bfs_patch" | patch -t "$_bfs_patch_opt" || return 1 ;;
            *.patch.bz2|*.diff.bz2)
                bzip2 -dc "$_bfs_patch" | patch -t "$_bfs_patch_opt" || return 1 ;;
            *)
                patch -t "$_bfs_patch_opt" -i "$_bfs_patch" || return 1 ;;
        esac
    done
    return 0
}

bfs_detect_buildtype() {
    if [ -f meson.build ]; then
        echo meson
    elif [ -f configure ]; then
        echo configure
    elif [ -f CMakeLists.txt ]; then
        echo cmake
    elif [ -f setup.py ]; then
        echo python3
    elif [ -f Makefile.PL ]; then
        echo perlmodule
    elif [ -f Makefile ] || [ -f makefile ]; then
        echo makefile
    else
        return 1
    fi
}

bfs_cmake_policy_args() {
    BFS_CMAKE_POLICY_ARGS=""
    [ "${SPKG_CMAKE_POLICY_COMPAT:-yes}" = no ] && return 0

    eval 'BFS_BUILD_OPTS="${build_opt[*]}"' 2>/dev/null || true
    case " $BFS_BUILD_OPTS " in
        *-DCMAKE_POLICY_VERSION_MINIMUM*) return 0 ;;
    esac

    _bfs_cmake_major=$(cmake --version 2>/dev/null |
        awk 'NR==1 {split($3,v,"."); print v[1]+0}')
    if [ "${_bfs_cmake_major:-0}" -ge 4 ]; then
        BFS_CMAKE_POLICY_ARGS="-DCMAKE_POLICY_VERSION_MINIMUM=${SPKG_CMAKE_POLICY_VERSION_MINIMUM:-3.5}"
    fi
    return 0
}

bfs_cmake_test_args() {
    BFS_CMAKE_TEST_ARGS=""
    [ "${SPKG_RUN_TESTS:-no}" = yes ] && return 0
    [ "${run_tests:-no}" = yes ] && return 0

    for _bfs_opt in BUILD_TESTING BUILD_TESTS ENABLE_TESTS; do
        case " $BFS_BUILD_OPTS " in
            *-D"$_bfs_opt"*) continue ;;
        esac
        if grep -Eiq "(^|[^A-Za-z0-9_])(option[[:space:]]*\([[:space:]]*$_bfs_opt([[:space:]]|\))|set[[:space:]]*\([[:space:]]*$_bfs_opt[[:space:]].*CACHE[[:space:]]+BOOL)" \
            ../CMakeLists.txt 2>/dev/null; then
            BFS_CMAKE_TEST_ARGS="$BFS_CMAKE_TEST_ARGS -D$_bfs_opt=OFF"
        elif [ "$_bfs_opt" = BUILD_TESTING ] &&
             grep -Eiq 'include[[:space:]]*\([[:space:]]*CTest[[:space:]]*\)' ../CMakeLists.txt 2>/dev/null; then
            BFS_CMAKE_TEST_ARGS="$BFS_CMAKE_TEST_ARGS -DBUILD_TESTING=OFF"
        fi
    done
    return 0
}

bfs_makefile_build() {
    bfs_collect_build_opt
    # shellcheck disable=SC2086
    make $BFS_BUILD_OPTS || return 1
    # shellcheck disable=SC2086
    make PREFIX=/usr prefix=/usr SYSCONFDIR=/etc sysconfdir=/etc \
        MANDIR=/usr/share/man mandir=/usr/share/man \
        LIBDIR="${BFS_PKG_LIBDIR:-/usr/lib}" libdir="${BFS_PKG_LIBDIR:-/usr/lib}" \
        PKGCONFIGDIR="${BFS_PKG_LIBDIR:-/usr/lib}/pkgconfig" \
        $BFS_BUILD_OPTS DESTDIR="$PKG" install || return 1
    return 0
}

bfs_perlmodule_build() {
    perl Makefile.PL || return 1
    make || return 1
    make DESTDIR="$PKG" install || return 1
    return 0
}

bfs_python3_build() {
    python3 setup.py build || return 1
    python3 setup.py install --prefix=/usr --root="$PKG" --optimize=1 --skip-build || return 1
    return 0
}

bfs_configure_build() {
    bfs_collect_build_opt

    BFS_CONFIGURE_TEST_ARGS=""
    if [ "${SPKG_RUN_TESTS:-no}" != yes ] && [ "${run_tests:-no}" != yes ]; then
        _bfs_help=$(./configure --help 2>/dev/null || true)
        for _bfs_opt in --disable-tests --disable-test --disable-checks --disable-check; do
            case $_bfs_help in
                *"$_bfs_opt"*) BFS_CONFIGURE_TEST_ARGS="$_bfs_opt"; break ;;
            esac
        done
    fi

    BFS_CONFIGURE_HOST_ARGS=""
    [ -n "${BFS_MULTILIB_HOST:-}" ] && BFS_CONFIGURE_HOST_ARGS="--host=$BFS_MULTILIB_HOST"

    # shellcheck disable=SC2086
    ./configure \
        --prefix=/usr \
        --sysconfdir=/etc \
        --libexecdir=/usr/lib \
        --localstatedir=/var \
        --mandir=/usr/share/man \
        --libdir="${BFS_PKG_LIBDIR:-/usr/lib}" \
        $BFS_CONFIGURE_HOST_ARGS \
        $BFS_CONFIGURE_TEST_ARGS \
        $BFS_BUILD_OPTS || return 1

    make -j"${JOBS:-1}" || return 1
    make DESTDIR="$PKG" install || return 1
    return 0
}

bfs_cmake_build() {
    bfs_collect_build_opt
    bfs_cmake_policy_args
    bfs_cmake_test_args

    mkdir -p cmakebuild && cd cmakebuild || return 1

    # shellcheck disable=SC2086
    cmake -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_SYSCONFDIR=/etc \
        -DCMAKE_INSTALL_LIBDIR="${BFS_PKG_LIBDIR_NAME:-lib}" \
        -DCMAKE_INSTALL_LIBEXECDIR="${BFS_PKG_LIBDIR_NAME:-lib}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DFETCHCONTENT_FULLY_DISCONNECTED=ON \
        -DCMAKE_C_FLAGS_RELEASE="$CFLAGS" \
        -DCMAKE_CXX_FLAGS_RELEASE="$CXXFLAGS" \
        $BFS_CMAKE_POLICY_ARGS \
        $BFS_CMAKE_TEST_ARGS \
        $BFS_BUILD_OPTS \
        -G Ninja .. || return 1
    cmake --build . --parallel "${JOBS:-1}" || return 1
    DESTDIR="$PKG" cmake --install . || return 1
    return 0
}

bfs_meson_build() {
    bfs_collect_build_opt

    BFS_MESON_ARCH_ARGS=""
    if [ -n "${BFS_COMPAT32:-}" ]; then
        cat > .bfsos-compat32.cross <<-EOF || return 1
	[binaries]
	c = 'gcc'
	cpp = 'g++'
	ar = 'ar'
	strip = 'strip'
	pkg-config = 'pkg-config'

	[properties]
	needs_exe_wrapper = false

	[host_machine]
	system = 'linux'
	cpu_family = 'x86'
	cpu = 'i686'
	endian = 'little'
	EOF
        BFS_MESON_ARCH_ARGS="--cross-file .bfsos-compat32.cross"
    fi

    # shellcheck disable=SC2086
    meson setup _meson_build \
        --prefix=/usr \
        --libdir="${BFS_PKG_LIBDIR:-/usr/lib}" \
        --libexecdir="${BFS_PKG_LIBDIR:-/usr/lib}" \
        --includedir=/usr/include \
        --datadir=/usr/share \
        --mandir=/usr/share/man \
        --infodir=/usr/share/info \
        --localedir=/usr/share/locale \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --sharedstatedir=/var/lib \
        --buildtype=plain \
        --auto-features=auto \
        --wrap-mode=nodownload \
        -Db_lto=true \
        -Db_pie=true \
        -Db_thinlto_cache=true \
        $BFS_MESON_ARCH_ARGS \
        $BFS_BUILD_OPTS || return 1

    if [ "${SPKG_RUN_TESTS:-no}" != yes ] && [ "${run_tests:-no}" != yes ]; then
        _bfs_meson_cfg=$(meson configure _meson_build 2>/dev/null || true)
        for _bfs_opt in tests test build_tests build-tests enable_tests enable-tests; do
            case " $BFS_BUILD_OPTS " in
                *-D"$_bfs_opt"*) continue ;;
            esac
            printf '%s\n' "$_bfs_meson_cfg" |
                grep -Eq "^[[:space:]]*$_bfs_opt[[:space:]]" || continue
            meson configure _meson_build "-D$_bfs_opt=disabled" >/dev/null 2>&1 ||
                meson configure _meson_build "-D$_bfs_opt=false" >/dev/null 2>&1 ||
                printf 'warning: could not disable Meson test option %s\n' "$_bfs_opt" >&2
        done
    fi

    meson compile -C _meson_build -j "${JOBS:-1}" || return 1
    if [ "${SPKG_RUN_TESTS:-no}" = yes ] || [ "${run_tests:-no}" = yes ]; then
        meson test -C _meson_build --print-errorlogs || return 1
    fi
    DESTDIR="$PKG" meson install --no-rebuild -C _meson_build || return 1
    return 0
}

# Remove files that are not package payload.
bfs_cleanup_pkg() {
    [ -d "$PKG/usr/share/info" ] && rm -f "$PKG/usr/share/info/dir"
    find "$PKG" -name fonts.dir -exec rm -f {} + 2>/dev/null
    find "$PKG" -name fonts.scale -exec rm -f {} + 2>/dev/null
    find "$PKG" -name perllocal.pod -exec rm -f {} + 2>/dev/null
    find "$PKG" -name charset.alias -exec rm -f {} + 2>/dev/null
    return 0
}

# Automatic build-type detection, the scratchpkg equivalent of the retired
# pkgmk extension.  Optional first argument forces a build type.
bfs_autobuild() {
    export DESTDIR="$PKG"
    export DEST_DIR="$PKG"      # p7zip
    export INSTALLROOT="$PKG"   # syslinux
    export install_root="$PKG"  # glibc
    export INSTALL_ROOT="$PKG"  # qt5
    export CARGO_HOME=/tmp

    bfs_apply_patches || return 1

    _bfs_bt="${1:-}"
    if [ -z "$_bfs_bt" ]; then
        _bfs_bt=$(bfs_detect_buildtype) || {
            bfs_die "failed to detect a build system for $name-$version"
            return 1
        }
    fi

    case $_bfs_bt in
        meson)      bfs_meson_build ;;
        configure)  bfs_configure_build ;;
        cmake)      bfs_cmake_build ;;
        python3)    bfs_python3_build ;;
        perlmodule) bfs_perlmodule_build ;;
        makefile)   bfs_makefile_build ;;
        *)
            bfs_die "unsupported build type: $_bfs_bt"
            return 1
            ;;
    esac || return 1

    bfs_cleanup_pkg || return 1
    bfs_compat32_validate || return 1
    return 0
}
