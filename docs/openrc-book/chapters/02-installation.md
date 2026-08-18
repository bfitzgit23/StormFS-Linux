# Chapter 2: Installation

## Installing OpenRC

### Using the StormFS Port

OpenRC is available as a port in the StormFS Linux repository:

```bash
# Install OpenRC
prt-get install openrc

# Install init scripts for common services
prt-get install openrc-init-scripts
```

### Building from Source

To build OpenRC from source:

```bash
# Download the latest stable version
wget https://github.com/OpenRC/openrc/archive/refs/tags/0.55.tar.gz
tar xf 0.55.tar.gz
cd openrc-0.55

# Configure and build
./configure \
    --prefix=/usr \
    --sysconfdir=/etc \
    --libdir=/usr/lib \
    --sbindir=/sbin

make
sudo make install
```

### Post-Installation Setup

After installing OpenRC, you need to:

1. Create runlevel directories
2. Configure the default runlevel
3. Install service scripts
4. Set up boot scripts

```bash
# Create runlevel directories
sudo mkdir -p /etc/runlevels/{sysinit,boot,default,nonetwork,single}

# Set default runlevel
sudo sed -i 's/^#DEFAULT_RUNLEVEL=.*/DEFAULT_RUNLEVEL=3/' /etc/conf.d/rc
```

## Directory Structure

After installation, the following directories should exist:

```
/etc/
├── init.d/              # Service scripts
├── conf.d/              # Service configuration
├── runlevels/           # Runlevel directories
├── rc.conf              # Main configuration
└── env.d/               # Environment variables

/lib/
├── rc/                  # OpenRC core files
│   ├── bin/             # OpenRC binaries
│   ├── sh/              # OpenRC shell functions
│   └── scripts/         # OpenRC scripts
└── systemd/             # Compatibility (optional)
```

## Verifying Installation

Check that OpenRC is installed correctly:

```bash
# Check OpenRC version
openrc --version

# Check available services
ls /etc/init.d/

# Check runlevels
ls /etc/runlevels/
```

## Next Steps

After installation, proceed to [Chapter 3: Configuration](chapters/03-configuration.md) to configure OpenRC for your system.
