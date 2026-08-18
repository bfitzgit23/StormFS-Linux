# Chapter 11: Package Management (CRUX/pkgutils)

StormFS Linux adopts **CRUX's pkgutils** package management system for its simplicity, source-based approach, and minimal overhead. This chapter covers the tools, port system, and repository management.

## 11.1 pkgutils Overview

pkgutils is a lightweight, source-based package management toolkit. Packages are built from **ports** (build recipes) using `pkgmk`, installed with `pkgadd`, and queried with `pkginfo`.

### Core Commands

| Command | Purpose |
|---------|---------|
| `pkgmk` | Build a package from a port (Pkgfile) |
| `pkgadd` | Install a built package (.pkg.tar.zst) |
| `pkginfo` | Query installed or built packages |
| `pkgutil` | Upgrade, remove, and manage packages |
| `prt-get` | Dependency-aware front-end to pkgutils |

### Installing pkgutils from Source

```bash
cd /sources
tar -xf pkgutils-21.07.20230724.tar.xz
cd pkgutils-21.07.20230724

# Patch for musl/libc compatibility if needed
# patch -Np1 -i ../pkgutils-musl.patch

./configure --prefix=/usr \
            --bindir=/usr/bin \
            --libdir=/usr/lib/pkgutils
make
make install
```

## 11.2 Building Packages with pkgmk

### Basic Usage

```bash
cd /path/to/port/
pkgmk -d
```

The `-d` flag builds the package in the current directory. `pkgmk` reads the `Pkgfile` in the port directory and:

1. Downloads source tarballs (as specified in the `source` array)
2. Executes the `build()` function to compile
3. Packages the result into `/var/spool/pkg/` as a `.pkg.tar.zst` file

### Common pkgmk Flags

| Flag | Purpose |
|------|---------|
| `-d` | Build in current directory |
| `-c` | Clean before building (remove previous build artifacts) |
| `-rf` | Force rebuild even if package exists |
| `-ui` | Update and install (requires `prt-get`) |
| `-P /path` | Specify alternate prefix directory |

### Build Output

Packages are placed in `/var/spool/pkg/` by default:

```bash
ls /var/spool/pkg/
# example: nano-8.1-1.pkg.tar.zst
```

### Incremental Builds

pkgmk caches the extracted sources in `/var/spool/pkg/sources/`. To force a fresh source download:

```bash
pkgmk -c -d
```

## 11.3 Installing Packages with pkgadd

```bash
# Install a package from the spool
pkgadd /var/spool/pkg/nano-8.1-1.pkg.tar.zst

# Install from a URL
pkgadd https://pkg StormFS.org/repo/pkgs/nano-8.1-1.pkg.tar.zst
```

### What pkgadd Does

1. Extracts the package to `/`
2. Runs `post_install()` if defined in the port's Pkgfile
3. Registers the package in `/var/lib/pkg/`

### Package Database

Installed packages are tracked in:

```
/var/lib/pkg/
├── nano/
│   ├──.desc
│   ├── footprint
│   └── pkgfile
```

## 11.4 Querying Packages with pkginfo

```bash
# List all installed packages
pkginfo -i

# Show files in an installed package
pkginfo -l nano

# Show package description
pkginfo -d nano

# Show a specific installed package's Pkgfile
pkginfo -R nano

# List files provided by a package
pkginfo -a nano
```

### Querying Built Packages

```bash
# List packages in the spool
pkginfo -t

# Show info about a built (not installed) package
pkginfo -i /var/spool/pkg/nano-8.1-1.pkg.tar.zst
```

## 11.5 Removing Packages with pkgutil

```bash
# Remove a package
pkgutil -r nano

# Remove a package and its unused dependencies
pkgutil -ry nano

# Upgrade a single package (reinstall over existing)
pkgutil -i /var/spool/pkg/nano-8.1-1.pkg.tar.zst

# Upgrade all installed packages from spool
pkgutil -u
```

### pkgutil Flags

| Flag | Purpose |
|------|---------|
| `-i <pkg>` | Install a package |
| `-r <pkg>` | Remove a package |
| `-ry <pkg>` | Remove package and orphaned dependencies |
| `-u` | Upgrade all installed packages from spool |
| `-ui` | Upgrade and install (interactive, integrates with prt-get) |
| `-l` | List installed packages |

## 11.6 prt-get — Dependency Resolution

`prt-get` is a higher-level front-end that adds dependency resolution, repository management, and easier upgrades.

### Installing prt-get

```bash
cd /sources
tar -xf prt-get-5.37.1.tar.xz
cd prt-get-5.37.1

./configure --prefix=/usr \
            --sysconfdir=/etc
make
make install
```

### Repository Configuration

Edit `/etc/prt-get.conf`:

```bash
# /etc/prt-get.conf

# Repositories in order of priority (first match wins)
PRTPATH=/usr/ports:/usr/local/ports

# Verbosity: 0=quiet, 1=normal, 2=verbose
VERBOSE=1

# Build directory
PKGDIR=/var/spool/pkg

# Dependency handling
# Options: warn, yes, no
DEPENDENCY_CHECK=yes

# When a package has multiple providers, use the first one
AVOID = "package-a package-b"
```

### Using prt-get

```bash
# Install a package with dependencies
prt-get install nano

# Install a package and rebuild it if already installed
prt-get install --force nano

# Remove a package and unused dependencies
prt-get remove nano

# Remove orphaned dependencies
prt-getorphans

# Upgrade all installed packages
prt-get sysup

# Upgrade a specific package
prt-get diff nano

# Search for a package in repositories
prt-get search nano

# Show package info
prt-get info nano

# Show dependency tree
prt-get depstree nano

# List outdated packages
prt-get list-orphans
prt-get list-non-python2-orphans

# Rebuild a package
prt-get rebuild nano
```

### Handling Dependency Conflicts

If two packages provide the same virtual dependency, prt-get will ask or follow the `AVOID` list:

```bash
# /etc/prt-get.conf
AVOID = "openssl-compat"
```

## 11.7 Port Structure — Pkgfile Format

A **port** is a directory containing at minimum a `Pkgfile` and a `signature` file (for integrity).

### Example Pkgfile

```bash
# stormfs ports — nano
# Maintainer: StormFS Development Team <dev@stormfs.org>

# Dependency note: nano requires ncurses for terminal support

nano() {
    # Package metadata
    name=nano
    version=8.1
    release=1
    source=($name.org/Files/nano-$version.tar.xz)

    # Build options
    CFLAGS="$CFLAGS -O2"
    CXXFLAGS="$CXXFLAGS -O2"

    build() {
        cd $name-$version

        ./configure \
            --prefix=/usr \
            --sysconfdir=/etc \
            --enable-color \
            --enable-nls \
            --enable-utf8 \
            --docdir=/usr/share/doc/$name-$version

        make
        make install DESTDIR=$PKG

        # Install documentation
        mkdir -p $PKG/usr/share/doc/$name-$version
        install -m644 doc/nano.html $PKG/usr/share/doc/$name-$version/

        # Install locale files
        make install DESTDIR=$PKG
    }

    post_install() {
        echo "nano installed. Set as default editor with:"
        echo "  update-alternatives --set editor /usr/bin/nano"
    }
}
```

### Pkgfile Variables

| Variable | Description |
|----------|-------------|
| `name` | Package name |
| `version` | Package version |
| `release` | Package release number (bump on rebuild) |
| `source` | Array of source URLs |
| `CFLAGS` | Compiler flags (inherited or custom) |
| `CXXFLAGS` | C++ compiler flags |
| `build()` | Function that compiles and installs into `$PKG` |
| `pre_install()` | Runs before installation |
| `post_install()` | Runs after installation |
| `pre_remove()` | Runs before removal |
| `post_remove()` | Runs after removal |

### Special Variables

| Variable | Value |
|----------|-------|
| `$PKG` | Temporary install root (e.g., `/var/spool/pkg/name-version/`) |
| `$name` | Package name |
| `$version` | Package version |
| `$source` | Array of downloaded sources |

### Signature File

Each port should have a `signature` file with checksums:

```bash
# stormfs ports — nano
# Generated: 2026-08-17

md5sums=(skip)
sha256sums=("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
```

To generate checksums:

```bash
updpkgsums
```

## 11.8 Creating Custom Ports

### Step-by-Step Example: Creating a Port for `jq`

**1. Create the port directory:**

```bash
mkdir -p /usr/ports/contrib/jq
cd /usr/ports/contrib/jq
```

**2. Download and identify the source:**

```bash
# Find the download URL
# https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-1.7.1.tar.gz
```

**3. Create the Pkgfile:**

```bash
cat > Pkgfile << 'PKGFILE'
# stormfs ports — jq
# Maintainer: Your Name <you@stormfs.org>

jq() {
    name=jq
    version=1.7.1
    release=1
    source=($name-$version.tar.gz)

    build() {
        cd $name-$version

        ./configure \
            --prefix=/usr \
            --sysconfdir=/etc \
            --with-oniguruma=builtin \
            --disable-docs

        make -j$(nproc)
        make install DESTDIR=$PKG
    }

    post_install() {
        echo "jq $version installed successfully."
    }
}
PKGFILE
```

**4. Generate the signature file:**

```bash
updpkgsums
```

**5. Build and test:**

```bash
pkgmk -d
pkgadd /var/spool/pkg/jq-1.7.1-1.pkg.tar.zst
```

**6. Verify installation:**

```bash
which jq
jq --version
pkginfo -l jq
```

### Testing Your Port

Always test in a clean environment or container before contributing:

```bash
# Build with debug output
pkgmk -d -v

# Install to a test prefix
make install DESTDIR=/tmp/test-install
```

## 11.9 Repository Management (REPO Files)

### Repository Configuration

Repositories are defined by their directory on the filesystem. Each repository is a directory tree of ports:

```
/usr/ports/
├── core/
│   ├── bash/
│   │   └── Pkgfile
│   ├── coreutils/
│   │   └── Pkgfile
│   ├── gcc/
│   │   └── Pkgfile
│   └── ...
├── contrib/
│   ├── nano/
│   │   └── Pkgfile
│   ├── vim/
│   │   └── Pkgfile
│   └── ...
└── opt/
    ├── firefox/
    │   └── Pkgfile
    └── ...
```

### Repository Sources in prt-get

```bash
# /etc/prt-get.conf
PRTPATH=/usr/ports:/usr/local/ports
```

### Creating a Custom Repository

```bash
# Create repository directory
mkdir -p /usr/local/ports/custom/{myapp1,myapp2}

# Add to prt-get.conf
PRTPATH=/usr/ports:/usr/local/ports

# Build and install
cd /usr/local/ports/custom/myapp1
pkgmk -d
pkgadd /var/spool/pkg/myapp1-1.0-1.pkg.tar.zst
```

### Repository Mirrors

To mirror the StormFS repository:

```bash
# Using rsync
rsync -av --delete \
    rsync://mirror.stormfs.org/stormfs-ports/ \
    /usr/ports/

# Using wget (full mirror)
wget -r -np -nH --cut-dirs=1 \
    http://mirror.stormfs.org/stormfs-ports/ \
    -P /usr/ports/
```

## 11.10 Using the Port Manager GUI

StormFS includes a graphical port management interface for desktop users.

### Launching the Port Manager

```bash
stormfs-portmanager &
```

Or from the application menu: **System → Port Manager**

### Features

- **Search ports** across all configured repositories
- **View port details** including dependencies, description, and changelog
- **Build and install** packages with one click
- **Upgrade outdated** packages
- **View build logs** for troubleshooting
- **Manage repositories** (add/remove/reorder)

### Configuration

The GUI reads its configuration from `/etc/prt-get.conf` and stores user preferences in `~/.config/stormfs/portmanager.conf`.

### Terminal Integration

All operations in the GUI run the same CLI commands under the hood. You can always inspect what the GUI did:

```bash
# Check recent package operations
grep -r "pkgadd\|pkgutil" /var/log/stormfs-portmanager.log
```

## 11.11 Advanced Topics

### Cross-Compilation

To build packages for a different architecture:

```bash
ARCH=aarch64 pkgmk -d
```

### Using Alternate Prefixes

```bash
# Build for a custom prefix
PKGDIR=/tmp/staging pkgmk -d
```

### Package Signing

Sign your packages for integrity verification:

```bash
# Generate a signing key
gpg --gen-key

# Sign a package
gpg --armor --detach-sign /var/spool/pkg/nano-8.1-1.pkg.tar.zst

# Verify a package
gpg --verify /var/spool/pkg/nano-8.1-1.pkg.tar.zst.sig
```

## 11.12 References

- [CRUX Package Management](https://crux.nu/Handbook#packagemanagement)
- [pkgutils Man Page](https://crux.nu/man/pkgmk)
- [prt-get Man Page](https://crux.nu/man/prt-get)
- [Chapter 12: System Initialization](chapter-12-system-initialization.md)
- [Chapter 09: Linux Kernel](chapter-09-linux-kernel.md)
