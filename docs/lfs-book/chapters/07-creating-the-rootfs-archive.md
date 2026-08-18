# Chapter 7: Creating the Rootfs Archive

This chapter describes Stage 5: compressing the verified base system into an XZ archive. This archive is the deployable artifact used by the installer and live ISO builder.

> **Important:** Stage 5 requires root privileges. Stage 4 verification must have passed first.

## 7.1 Overview

The rootfs archive is a compressed tarball of the entire `/tmp/lfs-rootfs` directory, excluding virtual filesystems, build artifacts, and the temporary toolchain. It is the final output of the bootstrap process.

### Archive Naming Convention

```
bfs-rootfs-<version>-<date>.tar.xz
```

Example: `bfs-rootfs-0.9.0-20260817.tar.xz`

### Archive Location

```
archives/base/bfs-rootfs-*.tar.xz
```

### Running Stage 5

From the interactive menu:

```
Option 5: Create/compress base rootfs archive (required)
```

Or from the command line:

```sh
$ sudo ./bootstrap.sh 5
```

## 7.2 Prerequisites

Before archiving, verify:

1. **Verification passed** — `$LFS/.bfs-verified` exists
2. **No active mounts** — Virtual filesystems and bind mounts must be unmounted
3. **Running as root** — Archive creation requires root access

### Pre-Archive Checks

The bootstrap script verifies that no bootstrap mounts are still active:

```sh
for mount_path in \
    "$LFS/dev/pts" \
    "$LFS/dev" \
    "$LFS/run" \
    "$LFS/proc" \
    "$LFS/sys" \
    "$LFS/$pkgmkwork" \
    "$LFS/$pkgmkpkg" \
    "$LFS/$pkgmksrc"
do
    if mountpoint -q "$mount_path"; then
        echo "ERROR: Refusing to archive while bootstrap mount is active: $mount_path" >&2
        return 1
    fi
done
```

### Unmounting Before Archive

The `umountfs` function unmounts all virtual filesystems:

```sh
umountfs
```

## 7.3 Compression with XZ Parallel

The archive is created using XZ compression with parallel encoding across all available CPU cores:

```sh
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
    -cJpf "$rootfs_archive" .
```

### XZ Options

| Option | Meaning |
|--------|---------|
| `-T0` | Use all available CPU cores for compression |
| `-c` | Write to stdout (piped to tar) |
| `-J` | Use XZ compression |
| `-p` | Preserve permissions |
| `-f` | Force overwrite of output file |

### tar Options

| Option | Meaning |
|--------|---------|
| `--exclude` | Pattern of paths to exclude |
| `-c` | Create archive |
| `-J` | XZ compression |
| `-p` | Preserve permissions |
| `-f` | Output filename |

## 7.4 Exclusions

The following paths are excluded from the archive to prevent leaking build artifacts and virtual filesystem contents:

### Exclusion List

| Pattern | Reason |
|---------|--------|
| `./var/lib/pkg/rejected` | Rejected package files (build artifact) |
| `.$TOOLS` (resolves to `./tmp/lfs-tools`) | Temporary toolchain symlink |
| `./tmp/*` | Temporary files, build configs, toolchain directory |
| `./dev/*` | Virtual filesystem (bind-mounted during build) |
| `./sys/*` | Virtual filesystem |
| `./proc/*` | Virtual filesystem |
| `./run/*` | Virtual filesystem (tmpfs) |
| `./root/.cache` | User cache (build artifact) |

### What IS Included

The archive includes everything else:

- `/usr/` — All installed packages, libraries, headers, documentation
- `/etc/` — System configuration files
- `/var/` — Package database, locale data, zoneinfo, logs
- `/bin -> usr/bin`, `/lib -> usr/lib`, `/sbin -> usr/sbin` — Symlinks
- `/lib64`, `/lib32` — Library compatibility symlinks
- `/boot/` — Boot files (if any packages installed them)
- `/home/`, `/root/` — Home directories
- `/opt/`, `/srv/`, `/mnt/`, `/media/` — Empty directories from aaa_filesystem

## 7.5 Archive Verification

After creation, the archive is verified by multiple checks:

### 1. Integrity Check

```sh
tar -tJf "$rootfs_archive" >/dev/null
```

This reads every block of the XZ archive and verifies checksums.

### 2. Required File Checks

```sh
if ! tar -tJf "$rootfs_archive" | grep -q '^\./usr/bin/bash$'; then
    echo "ERROR: Archive missing /usr/bin/bash" >&2
fi

if ! tar -tJf "$rootfs_archive" | grep -q '^\./usr/bin/pkgmk$'; then
    echo "ERROR: Archive missing /usr/bin/pkgmk" >&2
fi

if ! tar -tJf "$rootfs_archive" | grep -q '^\./etc/os-release$'; then
    echo "ERROR: Archive missing /etc/os-release" >&2
fi
```

### 3. Ownership Fix

If created via sudo, ownership is returned to the invoking user:

```sh
if [ -n "${SUDO_UID:-}" ] && [ -n "${SUDO_GID:-}" ]; then
    chown "$SUDO_UID:$SUDO_GID" "$rootfs_archive"
fi
```

## 7.6 Archive Size

Typical archive sizes depend on the number of installed packages and compression settings:

| Configuration | Approximate Size |
|--------------|-----------------|
| Base system only | 800 MB – 1.2 GB |
| With XZ parallel | 600 MB – 900 MB |
| With Zstd | 900 MB – 1.4 GB |

The `-T0` flag uses all CPU cores for parallel compression, significantly reducing archive creation time at the cost of slightly larger archives compared to single-threaded `-e` (extreme) compression.

## 7.7 Restoring from Archive

The archive can be restored using Stage 6 (menu option 6):

```sh
$ sudo ./bootstrap.sh 6
```

This:

1. Clears the existing rootfs
2. Extracts the archive into `$LFS`
3. Recreates the merged-/usr symlinks
4. Recreates virtual filesystem mount points
5. Verifies the restored rootfs

### Manual Restore

```sh
# Clear existing rootfs
$ sudo rm -rf /tmp/lfs-rootfs/*

# Extract archive
$ sudo tar -xJpf archives/base/bfs-rootfs-*.tar.xz -C /tmp/lfs-rootfs

# Recreate symlinks
$ sudo ln -s usr/bin /tmp/lfs-rootfs/bin
$ sudo ln -s usr/lib /tmp/lfs-rootfs/lib
$ sudo ln -s usr/sbin /tmp/lfs-rootfs/sbin

# Recreate mount points
$ sudo mkdir -p /tmp/lfs-rootfs/{dev/pts,proc,sys,run,tmp}

# Verify
$ ls /tmp/lfs-rootfs/usr/bin/bash
$ ls /tmp/lfs-rootfs/usr/bin/gcc
$ ls /tmp/lfs-rootfs/var/lib/pkg/db
```

## 7.8 Complete Stage 5 Output

A successful Stage 5 outputs:

```
Restoring newest base rootfs archive:
  archives/base/bfs-rootfs-0.9.0-20260817.tar.xz

Base rootfs compressed successfully.

Archive created and verified:
  archives/base/bfs-rootfs-0.9.0-20260817.tar.xz
```
