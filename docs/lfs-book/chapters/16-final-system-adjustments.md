# Chapter 16: Final System Adjustments

This chapter covers the final steps to complete a StormFS Linux installation: system identity, environment setup, cleanup, and verification.

## 16.1 Creating /etc/os-release

The `/etc/os-release` file provides system identification used by `os-release(5)` aware tools:

```bash
cat > /etc/os-release << 'EOF'
NAME="StormFS Linux"
VERSION="1.0"
ID=stormfs
ID_LIKE=crux
VERSION_ID=1.0
PRETTY_NAME="StormFS Linux 1.0"
HOME_URL="https://stormfs.org"
SUPPORT_URL="https://stormfs.org/support"
BUG_REPORT_URL="https://bugs.stormfs.org"
PRIVACY_POLICY_URL="https://stormfs.org/privacy"
BUILD_ID=$(date +%Y%m%d)
VARIANT="Standard"
VARIANT_ID=standard
ANSI_COLOR="1;34"
LOGO=stormfs-logo
EOF
```

Verify:

```bash
cat /etc/os-release
source /etc/os-release && echo "Running $PRETTY_NAME"
```

## 16.2 Setting PATH Correctly

### Verify Current PATH

```bash
echo $PATH
```

Expected PATH for StormFS:

```
/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

### Fix PATH if Incorrect

```bash
# Set the system PATH
cat > /etc/profile.d/00-paths.sh << 'EOF'
# StormFS System PATH
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
EOF

source /etc/profile.d/00-paths.sh
```

### Verify All Paths

```bash
# Check key binaries exist
ls -la /usr/bin/vim
ls -la /usr/bin/bash
ls -la /usr/bin/gcc
ls -la /usr/local/bin/stormfs-*
ls -la /sbin/systemctl
```

## 16.3 Creating /etc/profile.d/ Scripts

The `/etc/profile.d/` directory contains sourced scripts for all login shells.

### Create the Directory

```bash
mkdir -p /etc/profile.d
chmod 755 /etc/profile.d
```

### Essential Scripts

**00-locale.sh** — Locale settings:

```bash
cat > /etc/profile.d/00-locale.sh << 'EOF'
# Set locale environment variables
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LANG}"
EOF
```

**01-editor.sh** — Default editor:

```bash
cat > /etc/profile.d/01-editor.sh << 'EOF'
# Default editor
export EDITOR="${EDITOR:-vim}"
export VISUAL="${VISUAL:-vim}"
EOF
```

**02-paths.sh** — User-local paths:

```bash
cat > /etc/profile.d/02-paths.sh << 'EOF'
# User-local bin directories
if [ -d "$HOME/.local/bin" ] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    PATH="$HOME/.local/bin:$PATH"
fi

# Development paths
if [ -d "$HOME/bin" ] && [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    PATH="$HOME/bin:$PATH"
fi
EOF
```

**03-colors.sh** — Terminal colors:

```bash
cat > /etc/profile.d/03-colors.sh << 'EOF'
# Terminal color support
if [ -x /usr/bin/dircolors ]; then
    if [ -r ~/.dircolors ]; then
        eval "$(dircolors -b ~/.dircolors)"
    else
        eval "$(dircolors -b)"
    fi

    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias diff='diff --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# Check if terminal supports colors
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
    export RED GREEN YELLOW BLUE NC
fi
EOF
```

**04-manpath.sh** — Manual page path:

```bash
cat > /etc/profile.d/04-manpath.sh << 'EOF'
# Manual page path
if [ -d /usr/local/man ]; then
    MANPATH="/usr/local/man:${MANPATH:-}"
fi
export MANPATH
EOF
```

**05-less.sh** — Less pager configuration:

```bash
cat > /etc/profile.d/05-less.sh << 'EOF'
# Less configuration
export LESS="-R -M -i -J -w -X -F"
export LESSHISTFILE="-"
export LESSHISTSIZE=1000
export LESSCHARSET="utf-8"
EOF
```

**06-stormfs.sh** — StormFS-specific settings:

```bash
cat > /etc/profile.d/06-stormfs.sh << 'EOF'
# StormFS specific settings
export STORMFS_VERSION="1.0"
export STORMFS_DIR="/usr/share/stormfs"

# Source StormFS aliases
if [ -f /usr/share/stormfs/aliases.sh ]; then
    . /usr/share/stormfs/aliases.sh
fi
EOF
```

### Make Scripts Executable

```bash
chmod 644 /etc/profile.d/*.sh
```

## 16.4 Stripping Binaries

Stripping debug symbols reduces binary size significantly (often 30–60% savings).

### What Stripping Removes

- Debug symbols (`.debug_*` sections)
- Symbol tables (`.symtab`)
- Some documentation strings

**Note:** Stripping makes debugging with gdb more difficult. Keep unstripped copies if you plan to debug system software.

### Stripping All Binaries

```bash
# Strip all binaries in /usr
find /usr/lib -type f -name \*.a \
    -exec strip --strip-debug {} ';' 2>/dev/null

find /usr/lib -type f \( -name \*.so* -a ! -name \*.so \) \
    -exec strip --strip-unneeded {} ';' 2>/dev/null

find /usr/lib -type f -name \*.so \
    -exec strip --strip-unneeded {} ';' 2>/dev/null

find /usr/{bin,sbin,libexec} -type f \
    -exec strip --strip-all {} ';' 2>/dev/null
```

### Stripping with a Script

Create a more thorough stripping script:

```bash
cat > /usr/local/bin/stormfs-strip << 'STRIP'
#!/bin/bash
# StormFS Binary Strip Script
# Removes debug symbols from system binaries

set -e

echo "Stripping binaries in /usr..."

# Shared libraries
find /usr/lib -type f \( -name '*.so*' -o -name '*.a' \) -exec strip --strip-unneeded {} + 2>/dev/null || true

# Executables
find /usr/bin /usr/sbin /usr/libexec -type f -exec strip --strip-all {} + 2>/dev/null || true

# Libraries with debug info (remove .debug sections)
find /usr/lib -type f -name '*.debug' -delete 2>/dev/null || true

echo "Strip complete."

# Show savings
du -sh /usr/lib/ /usr/bin/ /usr/sbin/
STRIP

chmod 755 /usr/local/bin/stormfs-strip
```

### Verifying Stripped Binaries

```bash
# Check if a binary is stripped
file /usr/bin/bash

# Should show: ELF 64-bit LSB ... stripped
# Unstripped: ... not stripped, with debug_info

# Count stripped vs unstripped
find /usr/bin -type f -exec file {} \; | grep -c "not stripped"
find /usr/bin -type f -exec file {} \; | grep -c "stripped"
```

## 16.5 Cleaning Up Build Artifacts

### Remove Build Source Trees

```bash
# Remove extracted source directories
rm -rf /sources/linux-6.10.6
rm -rf /sources/gcc-14.2.0
rm -rf /sources/glibc-2.40
# ... and all other build directories

# Keep tarballs for reference (optional)
ls /sources/
```

### Clean Package Build Cache

```bash
# Clean pkgmk build cache
rm -rf /var/spool/pkg/sources/*

# Clean temporary build directories
rm -rf /tmp/build-*
rm -rf /tmp/staging
```

### Remove Unnecessary Files

```bash
# Remove documentation (if not needed)
rm -rf /usr/share/doc/{gtk-doc,sgml-doc,info}
rm -rf /usr/share/gtk-doc/html/*
rm -rf /usr/share/doc/*/examples

# Remove locale data you don't need (optional, saves ~100MB)
localedef --list-archive | grep -v -E '(en_US|en_GB|C|POSIX|\.UTF-8)' | \
    xargs localedef --delete-from-archive 2>/dev/null || true

# Remove unwanted man pages (optional)
rm -rf /usr/share/man/{it,ja,ko,zh_CN,zh_TW,fr,de}

# Remove Info pages (if not needed)
rm -rf /usr/share/info/*
```

### Clean systemd Journal

```bash
# Limit journal size
journalctl --vacuum-size=100M

# Or remove old journal data
rm -rf /var/log/journal/*
mkdir -p /var/log/journal
```

## 16.6 Final ldconfig

ldconfig updates the shared library cache so the dynamic linker can find libraries efficiently.

### Running ldconfig

```bash
ldconfig
```

### Verifying the Library Cache

```bash
# Check the cache file
ls -la /etc/ld.so.cache

# View libraries in cache
ldconfig -p | head -20
ldconfig -p | wc -l

# View libraries for a specific package
ldconfig -p | grep openssl
ldconfig -p | grep curl
```

### Configuring Library Paths

Create `/etc/ld.so.conf.d/stormfs.conf`:

```bash
cat > /etc/ld.so.conf.d/stormfs.conf << 'EOF'
# StormFS library paths
/usr/local/lib
/usr/lib
/lib
EOF
```

### Verifying Library Resolution

```bash
# Test that all required libraries can be found
ldd /usr/bin/bash
ldd /usr/bin/vim
ldd /usr/sbin/sshd

# Look for "not found" entries
ldd /usr/bin/* 2>/dev/null | grep "not found" | sort -u
```

### Fixing Missing Libraries

If `ldd` shows "not found":

```bash
# Find which package provides the library
find / -name "libfoo.so*" 2>/dev/null

# Add the path to ldconfig
echo "/usr/local/lib" > /etc/ld.so.conf.d/foo.conf
ldconfig

# Verify
ldd /path/to/binary | grep libfoo
```

## 16.7 Creating /var/log/bfs/ Directory Structure

StormFS uses `/var/log/bfs/` for build system logs and build tracking.

### Create Directory Structure

```bash
mkdir -p /var/log/bfs/{builds,errors,reports,packages}
chmod 755 /var/log/bfs
```

### Directory Layout

```
/var/log/bfs/
├── builds/          # Build logs for each package
│   ├── gcc-14.2.0.log
│   ├── vim-9.1.log
│   └── ...
├── errors/          # Error logs from failed builds
│   ├── 2026-08-17_gcc-fail.log
│   └── ...
├── reports/         # Build reports and summaries
│   ├── initial-build-2026-08-17.txt
│   ├── rebuild-report.txt
│   └── ...
└── packages/        # Package installation records
    ├── installed.list
    ├── removed.list
    └── timestamps
```

### Initializing the Log Structure

```bash
# Record initial installed packages
pkginfo -i > /var/log/bfs/packages/installed.list 2>/dev/null || \
    dpkg -l > /var/log/bfs/packages/installed.list 2>/dev/null || \
    echo "No package manager found" > /var/log/bfs/packages/installed.list

# Create timestamp file
cat > /var/log/bfs/packages/timestamps << EOF
# StormFS Package Timestamps
# Format: package_name install_date
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
EOF

# Record initial build report
cat > /var/log/bfs/reports/initial-build-$(date +%Y-%m-%d).txt << EOF
StormFS Linux Initial Build Report
===================================
Date: $(date)
Hostname: $(hostname)
Kernel: $(uname -r)
Architecture: $(uname -m)

System packages: $(cat /var/log/bfs/packages/installed.list | wc -l)
Disk usage:
$(df -h / /usr /var 2>/dev/null)

End of report.
EOF
```

### Create a Build Logger Script

```bash
cat > /usr/local/bin/bfs-log << 'LOGGER'
#!/bin/bash
# StormFS Build Logger
# Usage: bfs-log <package-name> <command...>
# Example: bfs-log gcc make && make install

set -e

LOGDIR="/var/log/bfs"
PKGNAME="$1"
shift

if [ -z "$PKGNAME" ]; then
    echo "Usage: bfs-log <package-name> <command...>"
    exit 1
fi

LOGFILE="$LOGDIR/builds/${PKGNAME}-$(date +%Y%m%d-%H%M%S).log"
ERRORFILE="$LOGDIR/errors/${PKGNAME}-$(date +%Y%m%d-%H%M%S).log"

echo "Logging build of $PKGNAME to $LOGFILE"
echo "Build started: $(date)" | tee -a "$LOGFILE"

if "$@" >> "$LOGFILE" 2>> "$ERRORFILE"; then
    echo "Build succeeded: $(date)" | tee -a "$LOGFILE"
    echo "$PKGNAME $(date +%Y-%m-%d)" >> "$LOGDIR/packages/timestamps"
    rm -f "$ERRORFILE"  # Remove empty error log
else
    EXITCODE=$?
    echo "Build FAILED (exit $EXITCODE): $(date)" | tee -a "$LOGFILE"
    echo "Error log: $ERRORFILE"
    exit $EXITCODE
fi
LOGGER

chmod 755 /usr/local/bin/bfs-log
```

### Create a Report Generator

```bash
cat > /usr/local/bin/bfs-report << 'REPORT'
#!/bin/bash
# StormFS System Report Generator

REPORTDIR="/var/log/bfs/reports"
REPORT="$REPORTDIR/system-report-$(date +%Y%m%d-%H%M%S).txt"

mkdir -p "$REPORTDIR"

cat > "$REPORT" << EOF
========================================
StormFS Linux System Report
========================================
Generated: $(date)
Hostname: $(hostname)
Kernel: $(uname -r)
Architecture: $(uname -m)

--- Disk Usage ---
$(df -h / 2>/dev/null)

--- Memory ---
$(free -h 2>/dev/null)

--- Uptime ---
$(uptime -p 2>/dev/null)

--- Installed Packages ---
$(pkginfo -i 2>/dev/null | wc -l || echo "N/A")

--- Recent Builds ---
$(ls -lt /var/log/bfs/builds/ 2>/dev/null | head -10)

--- Failed Builds ---
$(ls /var/log/bfs/errors/ 2>/dev/null | wc -l) failures

--- Services ---
$(systemctl list-units --type=service --state=running --no-pager 2>/dev/null | head -20)

========================================
EOF

echo "Report saved to: $REPORT"
REPORT
```

## 16.8 Final Verification

### System Check Script

```bash
cat > /usr/local/bin/stormfs-check << 'CHECK'
#!/bin/bash
# StormFS System Verification

echo "=== StormFS System Check ==="
echo ""

echo "1. Essential files..."
for f in /etc/hostname /etc/hosts /etc/fstab /etc/os-release /etc/shells; do
    [ -f "$f" ] && echo "  [OK] $f" || echo "  [FAIL] $f missing"
done

echo ""
echo "2. Essential directories..."
for d in /proc /sys /dev /run /tmp /var/log /var/cache; do
    [ -d "$d" ] && echo "  [OK] $d" || echo "  [FAIL] $d missing"
done

echo ""
echo "3. Essential binaries..."
for b in bash sh vim cat ls grep find mount umount login su passwd; do
    command -v "$b" &>/dev/null && echo "  [OK] $b" || echo "  [FAIL] $b missing"
done

echo ""
echo "4. Kernel..."
ls /boot/vmlinuz-* 2>/dev/null && echo "  [OK] Kernel image" || echo "  [FAIL] Kernel image missing"
ls /boot/initramfs-* 2>/dev/null && echo "  [OK] initramfs" || echo "  [FAIL] initramfs missing"

echo ""
echo "5. GRUB..."
[ -f /boot/grub/grub.cfg ] && echo "  [OK] grub.cfg" || echo "  [FAIL] grub.cfg missing"

echo ""
echo "6. Library cache..."
[ -f /etc/ld.so.cache ] && echo "  [OK] ld.so.cache" || echo "  [FAIL] ld.so.cache missing"
ISSUES=$(ldd /usr/bin/bash 2>/dev/null | grep -c "not found")
[ "$ISSUES" -eq 0 ] && echo "  [OK] All libraries resolved" || echo "  [FAIL] $ISSUES missing libraries"

echo ""
echo "7. Locale..."
[ -f /etc/locale.conf ] && echo "  [OK] locale.conf" || echo "  [WARN] locale.conf missing"

echo ""
echo "8. Networking..."
[ -f /etc/hostname ] && echo "  [OK] hostname: $(cat /etc/hostname)" || echo "  [FAIL] hostname not set"

echo ""
echo "=== Check Complete ==="
CHECK

chmod 755 /usr/local/bin/stormfs-check
```

### Run the Check

```bash
stormfs-check
```

## 16.9 System Reboot

After all adjustments are complete:

```bash
# Sync filesystems
sync

# Unmount any chroot mounts
umount /dev/pts 2>/dev/null
umount /dev/shm 2>/dev/null
umount /dev 2>/dev/null
umount /proc 2>/dev/null
umount /sys 2>/dev/null

# Reboot
reboot
```

### Post-Reboot Verification

```bash
# Check system identity
cat /etc/os-release
hostname

# Check services
systemctl list-units --type=service --state=running

# Check networking
ip addr show
resolvectl status

# Check disk
df -h

# Check logged in
whoami
id
```

## 16.10 References

- [os-release(5)](https://www.freedesktop.org/software/systemd/man/os-release.html)
- [ld.so(8)](https://www.kernel.org/doc/man-pages/man8/ld.so.8.html)
- [ldconfig(8)](https://www.kernel.org/doc/man-pages/man8/ldconfig.8.html)
- [GNU binutils: strip](https://sourceware.org/binutils/docs/binutils/strip.html)
- [Chapter 11: Package Management](chapter-11-package-management.md)
- [Chapter 15: Base Utilities](chapter-15-base-utilities.md) — Shell configuration
