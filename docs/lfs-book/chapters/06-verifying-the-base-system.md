# Chapter 6: Verifying the Base System

This chapter describes Stage 4: verifying the completed base system. This stage checks that all expected files, tools, and configurations are present and functional before the rootfs archive is created.

> **Important:** Stage 4 requires root privileges. The verification must pass before Stage 5 (archiving) can proceed.

## 6.1 Overview

The verification stage performs three categories of checks:

1. **Filesystem checks** — Verify key files and directories exist
2. **Chroot tests** — Verify tools work correctly inside the chroot
3. **Toolchain leakage** — Verify no references to `/tmp/lfs-tools`

All checks must pass. If any check fails, the verification marker (`.bfs-verified`) is removed and Stage 5 cannot proceed.

### Running Verification

From the interactive menu:

```
Option 4: Verify completed base system (required)
```

Or from the command line:

```sh
$ sudo ./bootstrap.sh 4
```

## 6.2 Filesystem Checks

The first set of checks verifies that critical files exist in the rootfs.

### Critical Binaries

```sh
# Checking existence of key binaries:
for path in \
    /usr/bin/bash \
    /usr/bin/gcc \
    /usr/bin/g++ \
    /usr/bin/ld \
    /usr/bin/make \
    /usr/bin/pkgmk
do
    if [ -e "$path" ] || [ -L "$path" ]; then
        printf '  [PASS] %s\n' "$path"
    else
        printf '  [FAIL] %s is missing\n' "$path" >&2
    fi
done
```

### Package Database

```sh
# Verifying the package database exists:
if [ -f /var/lib/pkg/db ]; then
    printf '  [PASS] /var/lib/pkg/db\n'
else
    printf '  [FAIL] /var/lib/pkg/db is missing\n' >&2
fi
```

### Critical Directories

```sh
for path in /etc /var /usr; do
    if [ -d "$path" ]; then
        printf '  [PASS] %s\n' "$path"
    else
        printf '  [FAIL] %s is missing\n' "$path" >&2
    fi
done
```

## 6.3 Chroot Tests

After filesystem checks pass, virtual filesystems are mounted and a comprehensive chroot test is executed.

### Mounting for Tests

```sh
mountfs
```

### Test Categories

#### 6.3.1 Toolchain Availability

Verify that essential build tools are available:

```sh
for cmd in gcc g++ ld make pkg-config pkgmk pkgadd pkginfo; do
    command -v "$cmd" >/dev/null 2>&1 || fail "$cmd is not available"
    pass "$cmd"
done
```

#### 6.3.2 Shell and Runtime Linker

```sh
# Verify bash is executable
[ -x /bin/bash ] || fail "/bin/bash is not executable"

# Verify /bin/sh exists and is not a broken symlink
[ -e /bin/sh ] || fail "/bin/sh is missing"
readlink -e /bin/sh >/dev/null 2>&1 || fail "/bin/sh is a broken link"

# Verify ldconfig works
command -v ldconfig >/dev/null 2>&1 || fail "ldconfig is not available"
ldconfig -p >/dev/null 2>&1 || fail "ldconfig cache cannot be read"

# Verify bash can resolve its dynamic libraries
ldd /bin/bash >/dev/null 2>&1 || fail "/bin/bash dynamic libraries cannot be resolved"
```

#### 6.3.3 Toolchain Leakage Check

This is the most critical check. It verifies the final compiler has no references to the temporary toolchain:

```sh
# GCC specs must not reference /tmp/lfs-tools
if gcc -dumpspecs | grep -Fq /tmp/lfs-tools; then
    fail "GCC specs still reference /tmp/lfs-tools"
fi
pass "GCC specs contain no /tmp/lfs-tools references"

# GCC search paths must not reference /tmp/lfs-tools
if gcc -print-search-dirs | grep -Fq /tmp/lfs-tools; then
    fail "GCC search paths still reference /tmp/lfs-tools"
fi
pass "GCC search paths contain no /tmp/lfs-tools references"
```

If either check fails, the system has **toolchain leakage** and must be rebuilt (Stage 3) or the glibc post-install adjustment must be corrected.

#### 6.3.4 Package Database Integrity

```sh
pkginfo -i >/dev/null 2>&1 || fail "package database is not readable"
pass "package database"
```

#### 6.3.5 C Compilation Test

```sh
cat > /tmp/bfs-verify.c << 'EOF'
#include <stdio.h>
int main(void) {
    puts("BFS C compiler test passed");
    return 0;
}
EOF

gcc /tmp/bfs-verify.c -o /tmp/bfs-verify-c || fail "C compilation failed"
/tmp/bfs-verify-c >/dev/null || fail "compiled C program failed to run"
pass "C compile and run"
```

#### 6.3.6 C++ Compilation Test

```sh
cat > /tmp/bfs-verify.cpp << 'EOF'
#include <iostream>
int main() {
    std::cout << "BFS C++ compiler test passed\n";
    return 0;
}
EOF

g++ /tmp/bfs-verify.cpp -o /tmp/bfs-verify-cpp || fail "C++ compilation failed"
/tmp/bfs-verify-cpp >/dev/null || fail "compiled C++ program failed to run"
pass "C++ compile and run"
```

#### 6.3.7 Cleanup

After all tests pass:

```sh
rm -f /tmp/bfs-verify.c /tmp/bfs-verify.cpp \
      /tmp/bfs-verify-c /tmp/bfs-verify-cpp
```

### Unmounting After Tests

```sh
umountfs
```

## 6.4 Checking for /tmp/lfs-tools References

Beyond the GCC-specific checks, the verification should also scan for any configuration files or scripts that reference the temporary toolchain path.

### What to Check

1. **GCC specs** (`gcc -dumpspecs`)
2. **GCC search paths** (`gcc -print-search-dirs`)
3. **Linker scripts** (in `/usr/lib/ldscripts/`)
4. **pkg-config files** (`*.pc` files in `/usr/lib/pkgconfig/`)
5. **Build scripts** in `/usr/bin/` and `/usr/sbin/`

### Common Causes of Toolchain Leakage

| Cause | Symptom | Fix |
|-------|---------|-----|
| GCC specs not adjusted | `gcc -dumpspecs` contains `/tmp/lfs-tools` | Re-run glibc post-install |
| Stale .la files | `.la` files contain `/tmp/lfs-tools` paths | Remove or fix .la files |
| pkg-config paths | `*.pc` files reference toolchain | Rebuild affected packages |
| Hardcoded rpaths | Binaries contain `/tmp/lfs-tools` in RPATH | Fix LDFLAGS |

## 6.5 Verification Marker

If all checks pass, a verification marker is created:

```sh
cat > "$LFS/.bfs-verified" << EOF
BFS_VERSION=$BFS_VERSION
BUILD_DATE=$BUILD_DATE
VERIFIED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
```

This marker:

1. Records the version, build date, and verification timestamp
2. Is required before Stage 5 (archiving) can proceed
3. Is removed automatically if verification fails

### If Verification Fails

1. Review the error output for the specific failing check
2. Fix the underlying issue (rebuild a package, adjust configs, etc.)
3. If toolchain leakage: re-run Stage 3 and then Stage 4
4. If missing files: identify which package should have provided them and rebuild it
5. Re-run Stage 4 until all checks pass

## 6.6 Verification Summary

A successful verification outputs:

```
========================================
 BFS BASE SYSTEM VERIFICATION
========================================

Checking base filesystem...
  [PASS] /usr/bin/bash
  [PASS] /usr/bin/gcc
  [PASS] /usr/bin/g++
  [PASS] /usr/bin/ld
  [PASS] /usr/bin/make
  [PASS] /usr/bin/pkgmk
  [PASS] /var/lib/pkg/db
  [PASS] /etc
  [PASS] /var
  [PASS] /usr

Checking final toolchain...
  [PASS] gcc
  [PASS] g++
  [PASS] ld
  [PASS] make
  [PASS] pkg-config
  [PASS] pkgmk
  [PASS] pkgadd
  [PASS] pkginfo

Checking shell and runtime linker...
  [PASS] /bin/sh
  [PASS] ldconfig
  [PASS] /bin/bash dynamic libraries

Checking for temporary-toolchain leakage...
  [PASS] GCC specs contain no /tmp/lfs-tools references
  [PASS] GCC search paths contain no /tmp/lfs-tools references

Checking package database...
  [PASS] package database

Compiling and running a C test...
  [PASS] C compile and run

Compiling and running a C++ test...
  [PASS] C++ compile and run

Verification marker created:
  /tmp/lfs-rootfs/.bfs-verified

========================================
 BFS BASE SYSTEM VERIFICATION PASSED
========================================
```
