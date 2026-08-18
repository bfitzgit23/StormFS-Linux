# Chapter 3: Building the Temporary Toolchain

This chapter describes building the temporary cross-compilation toolchain that will be used to build the base system. The toolchain is built as a regular user (never as root) and produces a complete set of 32-bit and 64-bit cross-compilers, linkers, and essential build utilities.

## 3.1 Overview

The temporary toolchain is built in isolation from the host system's libraries and headers. It consists of:

1. **pkgutils** — CRUX package management tools (bootstrapped from source)
2. **GCC pass 1** — Cross-compiler without libc
3. **Glibc** — C library (both 32-bit and 64-bit)
4. **GCC pass 2** — Cross-compiler with libc, builds 32-bit libstdc++
5. **Binutils pass 2** — Linker rebuilt against the new libc
6. **GCC pass 3** — Final cross-compiler, non-bootstrap
7. **Essential utilities** — Shell, text tools, and build dependencies

Each package is built using the `bootstrap_build()` function from its port Pkgfile. Packages are installed directly into `$TOOLS` (`/tmp/lfs-tools`).

> **Important:** The temporary toolchain must be built as a regular user, never as root.

## 3.2 Bootstrapping pkgutils

pkgutils is the CRUX package management toolkit. It must be bootstrapped from the upstream tarball before any other toolchain package can be built.

### Source

- **URL:** `https://crux.nu/files/pkgutils-5.40.12.tar.xz`
- **Version:** 5.40.12

### Build Steps

```sh
# Download the source
$ mkdir -p sources
$ curl -o sources/pkgutils-5.40.12.tar.xz \
    https://crux.nu/files/pkgutils-5.40.12.tar.xz

# Extract
$ rm -rf /tmp/pkgutils-5.40.12
$ tar -xf sources/pkgutils-5.40.12.tar.xz -C /tmp
```

### Patch: Remove --static Flag

The upstream Makefile links pkgutils statically, which is not needed for the bootstrap:

```sh
$ sed -i \
    -e 's/ --static//' \
    -e 's/ -static//' \
    /tmp/pkgutils-5.40.12/Makefile
```

### Patch: UTF-8 Locale Detection

GCC 16.2 archives contain UTF-8 pathnames. The bootstrap patches pkgmk to prefer a UTF-8 C locale when available:

```sh
$ sed -i '/^export LC_ALL=C\.UTF-8$/c\
_bfs_utf8_locale=""\
for _bfs_locale in C.UTF-8 C.utf8; do\
    if locale -a 2>/dev/null | grep -Fxiq "$_bfs_locale"; then\
        _bfs_utf8_locale="$_bfs_locale"\
        break\
    fi\
done\
if [ -n "$_bfs_utf8_locale" ]; then\
    export LC_ALL="$_bfs_utf8_locale"\
else\
    export LC_ALL=C\
fi\
unset _bfs_utf8_locale _bfs_locale' \
    /tmp/pkgutils-5.40.12/pkgmk.in
```

### Compile and Install

```sh
# Build
$ make -j$(nproc) -C /tmp/pkgutils-5.40.12

# Install to the toolchain
$ make -j$(nproc) \
    -C /tmp/pkgutils-5.40.12 \
    BINDIR="$TOOLS/bin" \
    MANDIR="$TOOLS/man" \
    ETCDIR="$TOOLS/etc" \
    install

# Clean up
$ rm -rf /tmp/pkgutils-5.40.12
```

### Verification

```sh
$ $TOOLS/bin/pkgmk --version
```

## 3.3 Toolchain Package List

The following packages are built in order. Each uses the `bootstrap_build()` function from its port Pkgfile.

### Package Build Order

| # | Package | Source | Description |
|---|---------|--------|-------------|
| 1 | binutils-pass1 | binutils 2.47 | Cross-linker (pass 1, no libc) |
| 2 | gmp | gmp (current) | GNU Multiple Precision Arithmetic |
| 3 | mpfr | mpfr (current) | Multiple-precision floating-point |
| 4 | mpc | mpc (current) | Multiple-precision complex arithmetic |
| 5 | gcc-pass1 | gcc 16.2.0 | Cross-compiler (pass 1, no libc) |
| 6 | linux-headers | linux-headers 7.1.8 | Kernel API headers |
| 7 | glibc | glibc 2.44 | GNU C Library (32-bit and 64-bit) |
| 8 | gcc-pass2 | gcc 16.2.0 | Cross-compiler (pass 2, with libc) |
| 9 | binutils-pass2 | binutils 2.47 | Cross-linker (pass 2, with libc) |
| 10 | libxcrypt | libxcrypt (current) | Crypt library |
| 11 | gcc-pass3 | gcc 16.2.0 | Final cross-compiler (non-bootstrap) |
| 12 | m4 | m4 (current) | GNU Macro Processor |
| 13 | ncurses | ncurses (current) | Terminal handling library |
| 14 | bash | bash (current) | GNU Bourne-Again Shell |
| 15 | bison | bison (current) | GNU Parser Generator |
| 16 | bzip2 | bzip2 (current) | Compression utility |
| 17 | coreutils | coreutils (current) | Core GNU utilities |
| 18 | diffutils | diffutils (current) | File comparison tools |
| 19 | file | file (current) | File type identification |
| 20 | findutils | findutils (current) | Directory search tools |
| 21 | gawk | gawk (current) | GNU Awk |
| 22 | gettext | gettext (current) | GNU internationalization |
| 23 | grep | grep (current) | Pattern matching |
| 24 | gzip | gzip (current) | Compression |
| 25 | make | make (current) | Build automation |
| 26 | patch | patch (current) | File patching |
| 27 | perl | perl (current) | Perl interpreter |
| 28 | zlib | zlib (current) | Compression library |
| 29 | xz | xz (current) | XZ compression |
| 30 | libtirpc | libtirpc (current) | Transport-independent RPC |
| 31 | libnsl | libnsl (current) | Name services library |
| 32 | python3 | python3 (current) | Python 3 interpreter |
| 33 | sed | sed (current) | Stream editor |
| 34 | tar | tar (current) | Archiving |
| 35 | texinfo | texinfo (current) | Documentation system |
| 36 | openssl | openssl (current) | TLS/SSL library |
| 37 | ca-certificates | ca-certificates (current) | CA certificate bundle |
| 38 | curl | curl (current) | URL transfer tool |
| 39 | libarchive | libarchive (current) | Archive library |
| 40 | util-linux | util-linux (current) | Linux utilities |

## 3.4 Individual Package Build Details

### 3.4.1 binutils-pass1

- **Source:** `binutils 2.47` — `https://sourceware.org/pub/binutils/releases/binutils-2.47.tar.xz`
- **Purpose:** Provides the cross-linker and assembler for building Glibc and GCC pass 1

```sh
$ cd ports/core/binutils
$ export tcpkg=binutils-pass1
$ pkgmk -d -is -if -cf /tmp/bootstrap.conf
```

Build details from `bootstrap_build()`:
- Configures with `--target=$LFS_TGT --prefix=$TOOLS --with-sysroot=$LFS`
- Disables NLS, Werror, gprofng
- Creates `$TOOLS/lib64` symlink to `lib`
- Creates `$TOOLS/lib32` directory
- Installs into `$TOOLS`

### 3.4.2 gmp, mpfr, mpc

These are GCC's mathematical dependencies, built as static libraries into `$TOOLS`:

```sh
$ export tcpkg=gmp && cd ports/core/gmp && pkgmk -d -is -if -cf /tmp/bootstrap.conf
$ export tcpkg=mpfr && cd ports/core/mpfr && pkgmk -d -is -if -cf /tmp/bootstrap.conf
$ export tcpkg=mpc && cd ports/core/mpc && pkgmk -d -is -if -cf /tmp/bootstrap.conf
```

### 3.4.3 gcc-pass1

- **Source:** `gcc 16.2.0` — `https://ftpmirror.gnu.org/gcc/gcc-16.2.0/gcc-16.2.0.tar.xz`
- **Purpose:** Produces the initial cross-compiler that can compile C and C++ without libc

Key build steps from `bootstrap_build()`:

1. Patches `gcc/config/linux.h`, `gcc/config/i386/linux.h`, and `gcc/config/i386/linux64.h` to point at `$TOOLS` instead of the host system
2. Configures multilib support (`--with-multilib-list=m32,m64`) with 32-bit libraries in `../lib32`
3. Configures with `--with-newlib --without-headers` (no libc yet)
4. Enables `c,c++` languages only
5. Disables threads, shared, decimal-float, and several lib-* components

```sh
$ export tcpkg=gcc-pass1 && cd ports/core/gcc && pkgmk -d -is -if -cf /tmp/bootstrap.conf
```

### 3.4.4 linux-headers

- **Source:** `linux-headers 7.1.8` — `https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.1.8.tar.xz`
- **Purpose:** Provides kernel API headers needed by Glibc

```sh
$ export tcpkg=linux-headers && cd ports/core/linux-headers && pkgmk -d -is -if -cf /tmp/bootstrap.conf
```

Build: Runs `make mrproper && make headers`, copies header files to `$TOOLS/include`.

### 3.4.5 glibc

- **Source:** `glibc 2.44` — `https://ftpmirror.gnu.org/glibc/glibc-2.44.tar.xz`
- **Purpose:** Provides the C library for the target system (both 32-bit and 64-bit)

This is the most complex toolchain package. From `bootstrap_build()`:

**32-bit Glibc (first):**
```sh
mkdir -v build32 && cd build32
echo "slibdir=$TOOLS/lib32" > configparms
../configure \
    --prefix="$TOOLS" \
    --host="$LFS_TGT32" \
    --build="$(../scripts/config.guess)" \
    --libdir="$TOOLS/lib32" \
    --enable-kernel=5.10 \
    --with-headers="$TOOLS/include" \
    CC="$LFS_TGT-gcc -m32" \
    CXX="$LFS_TGT-g++ -m32"
make && make install
```

After 32-bit install, creates compatibility link:
```sh
mkdir -p "$TOOLS/$LFS_TGT"
ln -sfn ../lib32 "$TOOLS/$LFS_TGT/lib32"
```

**64-bit Glibc (second):**
```sh
mkdir -v build && cd build
../configure \
    --prefix="$TOOLS" \
    --host="$LFS_TGT" \
    --build="$(../scripts/config.guess)" \
    --enable-kernel=5.10 \
    --with-headers="$TOOLS/include"
make && make install
```

### 3.4.6 gcc-pass2

- **Purpose:** Rebuilds libstdc++ against the newly built Glibc

Two separate builds:

**32-bit libstdc++:**
```sh
../libstdc++-v3/configure \
    --build=x86_64-pc-linux-gnu \
    --host="$LFS_TGT" \
    --prefix="$TOOLS" \
    --libdir="$TOOLS/lib32" \
    --disable-multilib \
    --disable-nls \
    --disable-libstdcxx-threads \
    --disable-libstdcxx-pch \
    --with-gxx-include-dir="$TOOLS/$LFS_TGT/include/c++/$version" \
    CC="$LFS_TGT-gcc -m32" \
    CXX="$LFS_TGT-g++ -m32"
```

**64-bit libstdc++:**
```sh
../libstdc++-v3/configure \
    --host="$LFS_TGT" \
    --prefix="$TOOLS" \
    --disable-multilib \
    --disable-nls \
    --disable-libstdcxx-threads \
    --disable-libstdcxx-pch \
    --with-gxx-include-dir="$TOOLS/$LFS_TGT/include/c++/$version"
```

### 3.4.7 binutils-pass2

- **Purpose:** Rebuilds the linker using the cross-compiler and libc

```sh
CC=$LFS_TGT-gcc \
AR=$LFS_TGT-ar \
RANLIB=$LFS_TGT-ranlib \
../configure \
    --prefix=$TOOLS \
    --enable-shared \
    --disable-nls \
    --disable-werror \
    --enable-64-bit-bfd \
    --with-lib-path=$TOOLS/lib \
    --with-sysroot
make CFLAGS="-O2 -DPATH_MAX=4096"
make install
make -C ld clean
make -C ld LIB_PATH=/usr/lib:/lib:/usr/lib32
cp -v ld/ld-new $TOOLS/bin
```

### 3.4.8 libxcrypt

- **Purpose:** Provides the `crypt()` function for password hashing

### 3.4.9 gcc-pass3

- **Purpose:** Final non-bootstrap GCC build in the toolchain

Configures with `--disable-bootstrap` since it can now use the pass-2 compiler to build itself:

```sh
CC="$LFS_TGT-gcc" \
CXX="$LFS_TGT-g++" \
AR="$LFS_TGT-ar" \
RANLIB="$LFS_TGT-ranlib" \
../configure \
    --with-gmp="$TOOLS" \
    --with-mpc="$TOOLS" \
    --with-mpfr="$TOOLS" \
    --prefix="$TOOLS" \
    --with-local-prefix="$TOOLS" \
    --with-native-system-header-dir="$TOOLS/include" \
    --enable-languages=c,c++ \
    --disable-libstdcxx-pch \
    --disable-bootstrap \
    --disable-libgomp \
    --with-multilib-list=m32,m64
```

After install, creates the `cc` symlink:
```sh
ln -sf gcc "$TOOLS/bin/cc"
```

### 3.4.10 m4 through util-linux

The remaining toolchain packages (m4, ncurses, bash, bison, bzip2, coreutils, diffutils, file, findutils, gawk, gettext, grep, gzip, make, patch, perl, zlib, xz, libtirpc, libnsl, python3, sed, tar, texinfo, openssl, ca-certificates, curl, libarchive, util-linux) are built as standard CRUX port builds using `pkgmk -d -is -if -cf /tmp/bootstrap.conf`.

Each package is installed directly into `$TOOLS` and creates a marker file (`touch "$TOOLS/$i"`) so it can be skipped on rebuild.

## 3.5 Multilib Verification

After all toolchain packages are built, the bootstrap runs a comprehensive multilib verification. This compiles and runs test programs in both 64-bit and 32-bit modes using both C and C++.

### Test Programs

**C test (`bfs-toolchain-test.c`):**
```c
#include <stdio.h>
int main(void) {
    puts("BFS C toolchain test OK");
    return 0;
}
```

**C++ test (`bfs-toolchain-test.cpp`):**
```cpp
#include <iostream>
int main() {
    std::cout << "BFS C++ toolchain test OK\n";
    return 0;
}
```

### Verification Checks

1. **64-bit C compile/link/run** — Compiles with `$TOOLS/bin/$LFS_TGT-gcc`, verifies ELF 64-bit, executes
2. **32-bit C compile/link/run** — Compiles with `-m32` flag, verifies ELF 32-bit, executes
3. **64-bit C++ compile/link/run** — Compiles with `$TOOLS/bin/$LFS_TGT-g++`, verifies ELF 64-bit, executes
4. **32-bit C++ compile/link/run** — Compiles with `-m32`, verifies ELF 32-bit, executes
5. **64-bit startup files** — Verifies `crt1.o` resolves to a real path
6. **32-bit startup files** — Verifies 32-bit `crt1.o` resolves
7. **lib32 compatibility link** — Verifies `$TOOLS/$LFS_TGT/lib32` points to `$TOOLS/lib32`

All checks must pass before the toolchain is archived.

## 3.6 Creating the Toolchain Archive

After successful verification, the toolchain is compressed into an XZ archive:

```sh
$ cd /tmp/lfs-rootfs
$ XZ_DEFAULTS='-T0' tar -cJpf \
    /path/to/BFSOS/archives/toolchain/bfs-toolchain-0.9.0-YYYYMMDD.tar.xz \
    .
```

### Archive Verification

The archive is verified by:

1. **Integrity check:** `tar -tJf` reads the entire archive
2. **Compiler presence:** Verifies `./tmp/lfs-tools/bin/gcc` or `./tmp/lfs-tools/bin/x86_64-lfs-linux-gnu-gcc` exists
3. **Linker presence:** Verifies `./tmp/lfs-tools/bin/ld` or `./tmp/lfs-tools/bin/ld.bfd` exists
4. **pkgmk presence:** Verifies `./tmp/lfs-tools/bin/pkgmk` exists

```sh
$ tar -tJf archives/toolchain/bfs-toolchain-*.tar.xz | \
    grep -Eq '^\./tmp/lfs-tools/bin/(gcc|x86_64-lfs-linux-gnu-gcc)$'

$ tar -tJf archives/toolchain/bfs-toolchain-*.tar.xz | \
    grep -Eq '^\./tmp/lfs-tools/bin/(ld|ld\.bfd)$'

$ tar -tJf archives/toolchain/bfs-toolchain-*.tar.xz | \
    grep -q '^\./tmp/lfs-tools/bin/pkgmk$'
```

### Toolchain Size

A typical toolchain archive is 1.5–2.5 GB, depending on the number of packages and compression settings. XZ with `-T0` (parallel compression across all cores) is used for speed.
