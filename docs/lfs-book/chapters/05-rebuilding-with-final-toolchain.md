# Chapter 5: Rebuilding with the Final Toolchain

This chapter describes Stage 3: rebuilding the entire base system using the toolchain that was just built in Stage 2. This is the self-hosting validation step that proves the base system can reproduce itself.

## 5.1 Overview

Stage 3 is **optional but recommended** for release validation. It rebuilds every base system package using only the final system's compiler, linker, and tools — without the temporary toolchain in `PATH`.

### Why Rebuild?

The purpose of Stage 3 is to verify that the base system is self-hosting:

1. **No toolchain leakage**: The final compiler must not reference `/tmp/lfs-tools`
2. **Reproducibility**: The system should produce identical packages when rebuilt
3. **Release readiness**: A system that can rebuild itself is ready for deployment

### Stage 2 vs Stage 3

| Aspect | Stage 2 | Stage 3 |
|--------|---------|---------|
| Compiler | Temporary toolchain | Final system compiler |
| PATH | Includes `$TOOLS/bin` | System PATH only |
| Marker | `.bfs-stage2-complete` | `.bfs-stage3-complete` |
| Package manager | `pkgin -d` | `prt-get update` |
| Build config | `/tmp/pkgmk.conf` | `/etc/pkgmk.conf` |
| Required | Yes | Optional |

## 5.2 Self-Hosting Validation

### Prerequisites

Before starting Stage 3, verify:

1. Stage 2 completed (`.bfs-stage2-complete` exists)
2. Running as root
3. Virtual filesystems are mounted

### Running Stage 3

From the interactive menu:

```
Option 3: Rebuild base system with final toolchain (optional)
```

Or from the command line:

```sh
$ sudo ./bootstrap.sh 3
```

### Build Process

During Stage 3, the chroot PATH is limited to system paths:

```sh
PATH=/bin:/usr/bin:/sbin:/usr/sbin
```

Note the absence of `$TOOLS/bin`. Every package is built using the system's own `gcc`, `make`, `pkg-config`, and other tools.

Packages are rebuilt using `prt-get` instead of `pkgin`:

```sh
chroot "$LFS" \
    env -i \
    HOME=/root \
    TERM="${TERM:-dumb}" \
    LANG=C \
    LC_ALL=C \
    LANGUAGE=C \
    PATH=/bin:/usr/bin:/sbin:/usr/sbin \
    prt-get update -im -fr -if -fi "$i"
```

### prt-get Flags

| Flag | Meaning |
|------|---------|
| `-i` | Install the built package |
| `-m` | Use makepkg to build |
| `-f` | Force (reinstall even if present) |
| `-r` | Remove build directory after install |
| `-i` | Interactive (ask for confirmation) |

## 5.3 Using prt-get Instead of pkgin

Stage 3 uses `prt-get` instead of `pkgin` because:

1. `prt-get` is installed as a proper package in Stage 2 (via `pkgutils`)
2. It resolves dependencies from the installed package database
3. It uses the system's `/etc/pkgmk.conf` for build configuration
4. It does not depend on the temporary toolchain

### prt-get Configuration

The system's `/etc/pkgmk.conf` is used:

```sh
export LANG=C
export LC_ALL=C
export LANGUAGE=C

export CPPFLAGS="-I/usr/include"
export CFLAGS="-O2 -march=x86-64 -pipe"
export CXXFLAGS="${CFLAGS}"
export LDFLAGS="-L/usr/lib -Wl,-rpath-link,/usr/lib"
export LIBRARY_PATH="/usr/lib"

export PKG_CONFIG_PATH="/usr/lib/pkgconfig:/usr/share/pkgconfig"
export PKG_CONFIG_LIBDIR="/usr/lib/pkgconfig:/usr/share/pkgconfig"

export JOBS=$(nproc)
export MAKEFLAGS="-j $JOBS"

PKGMK_SOURCE_DIR="/var/cache/pkg/sources"
PKGMK_PACKAGE_DIR="/var/cache/pkg/packages"
PKGMK_WORK_DIR="/var/cache/pkg/build-work/pkgmk-$name"
```

### Ports Tree in Chroot

The ports tree is copied into the chroot at `/usr/ports/` during Stage 2. prt-get searches this tree for package recipes.

## 5.4 Verifying No Toolchain Leakage

After Stage 3 completes, the verification step (Chapter 6) checks that the final compiler has no references to `/tmp/lfs-tools`.

### GCC Specs Check

```sh
$ gcc -dumpspecs | grep -Fq /tmp/lfs-tools
# If this prints anything, the build has toolchain leakage
```

### GCC Search Paths Check

```sh
$ gcc -print-search-dirs | grep -Fq /tmp/lfs-tools
# If this prints anything, the build has toolchain leakage
```

### Why Toolchain Leakage Matters

If the final compiler references `/tmp/lfs-tools`, then:

1. The system depends on a path that won't exist after deployment
2. The system is not truly self-hosting
3. The rootfs archive would be non-portable

The glibc post-install adjustment (Chapter 4, Section 4.3) is what prevents this by modifying GCC's specs file to use `/usr/lib` instead of `$TOOLS/lib`.

## 5.5 Stage 3 Completion

After all packages are rebuilt successfully:

```sh
touch "$LFS/.bfs-stage3-complete"
```

This marker:

1. Replaces `.bfs-stage2-complete` (which is removed)
2. Signals that the system has been validated as self-hosting
3. Is required before Stage 4 verification can proceed meaningfully

### What Changes After Stage 3

- All packages are rebuilt with the final compiler
- Package database entries are updated
- Build logs are refreshed
- The rootfs is ready for verification and archiving

### If Stage 3 Fails

If a package fails to rebuild:

1. Check the build log in `logs/base/`
2. Fix the port recipe or dependencies
3. Clean the failed package's build directory
4. Re-run Stage 3

Stage 2 results are still usable if Stage 3 fails — Stage 3 is purely for validation.

## 5.6 Differences from Stage 2

| Aspect | Stage 2 | Stage 3 |
|--------|---------|---------|
| Chroot PATH | `.../bin:$TOOLS/bin` | `/bin:/usr/bin:/sbin:/usr/sbin` |
| Build config | `/tmp/pkgmk.conf` | `/etc/pkgmk.conf` |
| Package manager | `pkgin -d` | `prt-get update` |
| Compiler source | Temporary toolchain | System GCC |
| Headers | `$TOOLS/include` | `/usr/include` |
| Libraries | `$TOOLS/lib` | `/usr/lib` |
| Purpose | Bootstrap the system | Validate self-hosting |

Stage 3 is a clean rebuild. The same port recipes are used, but the build environment is the final system itself.
