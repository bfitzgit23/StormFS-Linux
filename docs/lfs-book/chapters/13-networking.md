# Chapter 13: Networking

This chapter covers OpenRC-first network configuration in StormFS Linux, including hostname setup, DNS, firewall rules, and network daemon configuration. The systemd-networkd material is optional compatibility content.

## 13.1 Setting the Hostname

### /etc/hostname

The hostname identifies the machine on the network:

```bash
cat > /etc/hostname << 'EOF'
stormfs-box
EOF
```

## 13.2 OpenRC Network Services (Default)

OpenRC should start the network services. Use `dhcpcd` for DHCP and `iwd` plus `dhcpcd` for Wi-Fi; do not enable systemd-networkd or systemd-resolved in an OpenRC installation.

### Wired DHCP

```bash
cat > /etc/conf.d/net << 'EOF'
config_eth0="dhcp"
EOF

rc-update add networking boot
rc-update add dhcpcd default 2>/dev/null || true
rc-service networking start
rc-service dhcpcd start 2>/dev/null || true
```

### Wi-Fi with iwd

```bash
prt-get install iwd dhcpcd 2>/dev/null || true
rc-update add iwd default
rc-update add dhcpcd default
rc-service iwd start
rc-service dhcpcd start

iwctl station wlan0 scan
iwctl station wlan0 get-networks
iwctl station wlan0 connect "MyNetwork"
```

### Static IPv4

```bash
cat > /etc/conf.d/net << 'EOF'
config_eth0="192.168.1.100/24"
route_eth0="default via 192.168.1.1"
dns_servers_eth0="1.1.1.1 8.8.8.8"
EOF
rc-service networking restart
```

### OpenRC Hostname

```bash
echo stormfs-box > /etc/hostname
hostname stormfs-box
rc-update show
```

### Verify OpenRC Networking

```bash
rc-status
ip addr show
ip route show
getent hosts example.com
```

### /etc/hosts

The hosts file provides static hostname-to-IP mappings:

```bash
cat > /etc/hosts << 'EOF'
# IPv4
127.0.0.1       localhost
127.0.1.1       stormfs-box

# IPv6
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF
```

Replace `stormfs-box` with your chosen hostname. The second line maps the hostname to `127.0.1.1` (standard Debian/Ubuntu convention) or to your LAN IP.

### Optional systemd Hostname Integration

```bash
# Set hostname (updates /etc/hostname and applies immediately)
hostnamectl set-hostname stormfs-box

# Verify
hostnamectl status
hostname
```

## 13.3 OpenRC Equivalents for systemd-networkd

The systemd-networkd examples in the next section are retained as reference. The equivalent OpenRC configurations use the `networking` service, `/etc/conf.d/net`, `dhcpcd`, `iwd`, and `openresolv`.

### OpenRC DHCP and DNS

```bash
prt-get install dhcpcd openresolv

cat > /etc/conf.d/net << 'EOF'
config_eth0="dhcp"
EOF

# dhcpcd supplies the lease; openresolv updates /etc/resolv.conf
rc-update add networking boot
rc-update add dhcpcd default
rc-service networking start
rc-service dhcpcd start
```

Use a static resolver only when a DHCP or NetworkManager resolver is not managing the file:

```bash
ln -sf /run/resolvconf/resolv.conf /etc/resolv.conf
resolvconf -u
```

### OpenRC Wi-Fi with iwd

```bash
prt-get install iwd dhcpcd openresolv
rc-update add iwd default
rc-update add dhcpcd default
rc-service iwd start
rc-service dhcpcd start

iwctl station wlan0 scan
iwctl station wlan0 connect "MyNetwork"
```

For a persistent iwd network, save its credentials through `iwctl` under `/var/lib/iwd/`; let `dhcpcd` manage the address and DNS lease.

### OpenRC Static Address, Bond, and Bridge

The Linux interfaces created by `ip`, `bridge`, and `ip link` are independent of the init system. Put the commands in `/etc/local.d/network.start`, or use the equivalent `net.*` variables supported by the installed OpenRC networking scripts:

```bash
install -d -m 0755 /etc/local.d
cat > /etc/local.d/network.start << 'EOF'
#!/bin/sh
ip link add bond0 type bond mode 802.3ad 2>/dev/null || true
ip link set eth0 down 2>/dev/null || true
ip link set eth0 master bond0 2>/dev/null || true
ip link set bond0 up
ip addr add 192.168.1.100/24 dev bond0 2>/dev/null || true
ip route replace default via 192.168.1.1
EOF
chmod 755 /etc/local.d/network.start
rc-update add local default
```

For an OpenRC bridge, replace the bond commands with `ip link add br0 type bridge`, enslave the physical interface with `ip link set eth0 master br0`, and assign the address to `br0`, never to the enslaved port.

### OpenRC NetworkManager Alternative

NetworkManager already has an OpenRC service in `openrc-init-scripts`. Build it with `-D session_tracking=none` for the OpenRC profile; ConsoleKit2 supplies the desktop session/seat API separately when needed. Do not use the systemd session-tracking backend on an OpenRC-only system.

```bash
prt-get install networkmanager openrc-init-scripts
rc-update del networking boot 2>/dev/null || true
rc-update del dhcpcd default 2>/dev/null || true
rc-update add dbus boot
rc-update add networkmanager default
rc-service networkmanager start
```

### OpenRC Network Troubleshooting

```bash
rc-status --all
rc-service networking status
rc-service dhcpcd status
rc-service iwd status
ip addr show
ip route show
cat /etc/resolv.conf
getent hosts example.com
```

## 13.4 Optional systemd-networkd Configuration

systemd-networkd is an optional compatibility daemon for systemd installations. OpenRC installations should use the networking service described in Sections 13.2 and 13.3.

### Enabling systemd-networkd

```bash
# Disable NetworkManager if switching from it
systemctl disable --now NetworkManager 2>/dev/null

# Enable systemd-networkd
systemctl enable systemd-networkd systemd-resolved

# Start
systemctl start systemd-networkd systemd-resolved
```

### Static IP Configuration

Create `/etc/systemd/network/10-eth0-static.network`:

```ini
[Match]
Name=eth0

[Network]
Address=192.168.1.100/24
Gateway=192.168.1.1
DNS=1.1.1.1
DNS=8.8.8.8
Domains=stormfs.local

[Route]
Gateway=192.168.1.1
Destination=0.0.0.0/0
Metric=100

[Route]
Destination=192.168.1.0/24
Metric=100
```

### DHCP Configuration

Create `/etc/systemd/network/20-eth0-dhcp.network`:

```ini
[Match]
Name=eth0

[Network]
DHCP=yes

[DHCPv4]
UseDNS=yes
UseNTP=yes
UseHostname=yes
RouteMetric=100

[DHCPv6]
UseDNS=yes
UseNTP=yes
```

### WiFi Configuration (iwd)

For WiFi, use **iwd** (iNet Wireless Daemon) with systemd-networkd:

```bash
# Install iwd (if not already installed)
# Start iwd
systemctl enable --now iwd

# Configure WiFi
iwctl station wlan0 scan
iwctl station wlan0 get-networks
iwctl station wlan0 connect "MyNetwork"
```

Create `/etc/systemd/network/25-wifi.network`:

```ini
[Match]
Name=wlan0

[Network]
DHCP=yes

[DHCPv4]
UseDNS=yes
UseNTP=yes
```

### Bonding / Bridging

**Bond (LACP):**

```bash
cat > /etc/systemd/network/30-bond0.netdev << 'EOF'
[NetDev]
Name=bond0
Kind=bond

[Bond]
Mode=802.3ad
TransmitHashPolicy=layer3+4
EOF

cat > /etc/systemd/network/30-bond0.network << 'EOF'
[Match]
Name=bond0

[Network]
Bond=bond0
DHCP=yes
EOF
```

**Bridge:**

```bash
cat > /etc/systemd/network/40-br0.netdev << 'EOF'
[NetDev]
Name=br0
Kind=bridge
EOF

cat > /etc/systemd/network/40-br0.network << 'EOF'
[Match]
Name=br0

[Network]
Address=192.168.1.10/24
Gateway=192.168.1.1
DNS=1.1.1.1
EOF

cat > /etc/systemd/network/41-eth0-bridge.network << 'EOF'
[Match]
Name=eth0

[Network]
Bridge=br0
EOF
```

## 13.5 NetworkManager Setup with OpenRC

For desktop systems with WiFi, mobile broadband, and VPN requirements, NetworkManager provides a more feature-rich experience.

For the OpenRC profile, build NetworkManager without the systemd session-tracking backend. The systemd variant is retained below for installations that intentionally select systemd.

### Installing NetworkManager

```bash
cd /sources
tar -xf NetworkManager-1.48.4.tar.xz
cd NetworkManager-1.48.4

meson setup build \
    --prefix=/usr \
    --sysconfdir=/etc \
    --localstatedir=/var \
    -Dmodify_system=true \
    -Dsession-tracking=none \
    -Dlibaudit=no \
    -Dselinux=no \
    -Dppp=false \
    -Dvapi=false \
    -Dgtk_doc=false \
    -Dtests=false

ninja -C build
ninja -C build install
```

For a systemd installation, use the systemd session-tracking backend instead:

```bash
meson setup build-systemd \
    --prefix=/usr \
    --sysconfdir=/etc \
    --localstatedir=/var \
    -Dmodify_system=true \
    -Dsession-tracking=systemd \
    -Dlibaudit=no \
    -Dselinux=no \
    -Dppp=false \
    -Dvapi=false \
    -Dgtk_doc=false \
    -Dtests=false
ninja -C build-systemd
ninja -C build-systemd install
```

### Enabling NetworkManager with OpenRC (default)

```bash
# Remove conflicting OpenRC services when using NetworkManager
rc-update del networking boot 2>/dev/null || true
rc-update del dhcpcd default 2>/dev/null || true

# Enable NetworkManager through OpenRC
rc-update add networkmanager default
rc-service networkmanager start
```

### Enabling NetworkManager with systemd (reference)

On a systemd installation, keep the systemd service path instead:

```bash
# Disable systemd-networkd if switching
systemctl disable --now systemd-networkd

# Enable NetworkManager
systemctl enable NetworkManager
systemctl start NetworkManager
```

### Basic Configuration

Edit `/etc/NetworkManager/NetworkManager.conf`:

```ini
[main]
plugins=keyfile
dns=default
wlbackend=iwd

[logging]
level=INFO
domain=CONFIG,PLATFORM
```

For a systemd installation using `systemd-resolved`, retain this systemd-specific DNS setting:

```ini
[main]
plugins=keyfile
dns=systemd
wlbackend=iwd
```

The OpenRC default uses `dns=default` and `openresolv`; do not run both resolver managers against `/etc/resolv.conf`.

### Managing Connections

```bash
# List connections
nmcli connection show

# Add a wired connection
nmcli connection add type ethernet con-name "Home" ifname eth0 \
    ipv4.addresses 192.168.1.100/24 \
    ipv4.gateway 192.168.1.1 \
    ipv4.dns "1.1.1.1,8.8.8.8" \
    ipv4.method manual

# Add a DHCP connection
nmcli connection add type ethernet con-name "DHCP" ifname eth0 \
    ipv4.method auto

# Activate a connection
nmcli connection up "Home"

# Add WiFi
nmcli device wifi connect "MyNetwork" password "MyPassword" ifname wlan0

# Show device status
nmcli device status

# Show connection details
nmcli connection show "Home"

# Modify a connection
nmcli connection modify "Home" ipv4.dns "9.9.9.9"
```

## 13.6 DNS Configuration

### /etc/resolv.conf

If using systemd-resolved, this file is managed automatically. If using static DNS:

```bash
cat > /etc/resolv.conf << 'EOF'
# StormFS DNS Configuration
# Generated: 2026-08-17

# Primary DNS (Cloudflare)
nameserver 1.1.1.1

# Secondary DNS (Google)
nameserver 8.8.8.8

# Tertiary DNS (Quad9)
nameserver 9.9.9.9

# Search domains
search stormfs.local

# Options
options timeout:2 attempts:3
EOF
```

### /etc/nsswitch.conf

The Name Service Switch configuration determines the order of name resolution:

```bash
cat > /etc/nsswitch.conf << 'EOF'
passwd:         files systemd
group:          files systemd
shadow:         files
gshadow:        files

hosts:          files resolve [!UNAVAIL=return] dns myhostname
networks:       files resolve

protocols:      db files
services:       db files
ethers:         db files
rpc:            db files

netgroup:       files
sudoers:        files
EOF
```

### DNSSEC Validation

For the OpenRC resolver path, inspect the resolver file and query directly:

```bash
cat /etc/resolv.conf
getent hosts example.com
# Test DNSSEC
dig +dnssec example.com
```

On a systemd-resolved installation, use its status and cache commands:

```bash
# Check DNSSEC status
resolvectl status | grep -i dnssec

# Test DNSSEC
dig +dnssec example.com
```

### Private DNS / Split DNS

For VPN or split DNS configurations:

```bash
# /etc/systemd/network/10-vpn.network
[Match]
Name=tun0

[Network]
DNS=10.0.0.1
Domains=~corp.example.com

[Route]
Destination=10.0.0.0/8
Gateway=10.0.0.1
```

## 13.7 Firewall (nftables)

StormFS uses **nftables** as the packet filtering framework, replacing iptables.

### Installing nftables

```bash
cd /sources
tar -xf nftables-1.1.1.tar.xz
cd nftables-1.1.1

./configure --prefix=/usr \
            --sysconfdir=/etc \
            --enable-json \
            --disable-man-doc
make
make install
```

### Basic Firewall Rules

Create `/etc/nftables.conf`:

```bash
#!/usr/sbin/nft -f

# Flush all existing rules
flush ruleset

# Define variables
define WAN = eth0
define LAN = 192.168.1.0/24
define ALLOWED_TCP_PORTS = { 22, 80, 443 }
define ALLOWED_UDP_PORTS = { 53, 123 }

# inet table (handles both IPv4 and IPv6)
table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;

        # Allow established and related connections
        ct state established,related accept

        # Allow loopback
        iif "lo" accept

        # Allow ICMP (ping)
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        # Allow SSH from LAN
        ip saddr $LAN tcp dport 22 accept

        # Allow HTTP/HTTPS from anywhere
        tcp dport { 80, 443 } accept

        # Allow DNS
        tcp dport 53 accept
        udp dport 53 accept

        # Allow NTP
        udp dport 123 accept

        # Log and drop everything else
        log prefix "[NFT-DROP] " counter drop
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
        # No forwarding by default for a workstation
    }

    chain output {
        type filter hook output priority filter; policy accept;
        # Allow all outbound traffic
    }
}

# NAT table (for masquerading, if needed)
table ip nat {
    chain prerouting {
        type nat hook prerouting priority dstnat;
    }

    chain postrouting {
        type nat hook postrouting priority srcnat;
        # Masquerade outbound traffic on WAN
        oifname "eth0" masquerade
    }
}
```

### Starting nftables with OpenRC (default)

```bash
# Enable at boot through OpenRC
rc-update add nftables default

# Load rules
rc-service nftables start

# Verify rules
nft list ruleset
```

### Starting nftables with systemd (reference)

```bash
# Enable at boot
systemctl enable nftables

# Load rules
systemctl start nftables

# Verify rules
nft list ruleset
```

### Managing Rules

```bash
# List all rules
nft list ruleset

# Add a rule interactively
nft add rule inet filter input tcp dport 8080 accept

# Delete a rule
nft -a list chain inet filter input  # shows rule handles
nft delete rule inet filter input handle 3

# Flush all rules
nft flush ruleset

# Save rules
nft list ruleset > /etc/nftables.conf

# Reload rules through OpenRC
rc-service nftables reload
```

For a systemd installation, reload the same service with:

```bash
systemctl reload nftables
```

### Common Firewall Patterns

**Rate limiting SSH:**

```nft
# In the input chain:
tcp dport 22 meter ssh-rate { ip saddr limit rate 3/minute burst 5 packets } accept
tcp dport 22 drop
```

**Blocking a specific IP:**

```nft
ip saddr 10.20.30.40 drop
```

**Allowing ICMP with rate limit:**

```nft
ip protocol icmp icmp type echo-request limit rate 5/second accept
```

### Firewall Alternatives

For a more user-friendly interface, consider:

- **ufw** (Uncomplicated Firewall) — wrapper around nftables/iptables
- **firewalld** — D-Bus based firewall management with zones

## 13.8 IPv6 Configuration

For OpenRC, configure IPv6 in `/etc/conf.d/net` and let the `networking` service apply it. The following systemd-networkd example is optional compatibility material:

```ini
# /etc/systemd/network/10-eth0-ipv6.network
[Match]
Name=eth0

[Network]
Address=2001:db8::100/64
Gateway=2001:db8::1
DNS=2001:4860:4860::8888

[DHCPv6]
Use=yes
```

Enable IPv6:

```bash
# Check if IPv6 is enabled
cat /proc/sys/net/ipv6/conf/eth0/disable_ipv6

# Enable IPv6
echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6
```

## 13.9 Network Troubleshooting

### Diagnostic Commands

The OpenRC commands are the default diagnostic path:

```bash
# Interface status
ip addr show
ip link show

# Routing table
ip route show

# DNS resolution test
getent hosts example.com
dig example.com

# Connectivity test
ping -c 3 8.8.8.8
ping -c 3 example.com

# Traceroute
traceroute example.com

# Port testing
ss -tlnp                           # Listening TCP ports
ss -ulnp                           # Listening UDP ports
ss -tnp | grep :22                 # Check SSH connections

# Network statistics
netstat -s
ss -s

# DNS debug
rc-status
logread 2>/dev/null || tail -f /var/log/messages

# Packet capture
tcpdump -i eth0 -n port 22
tcpdump -i eth0 -n 'host 192.168.1.1'
```

### systemd Diagnostic Commands (reference)

On a systemd installation, the corresponding network and resolver checks remain:

```bash
resolvectl status
resolvectl statistics
resolvectl query example.com
journalctl -u systemd-resolved -f
systemctl status systemd-networkd systemd-resolved
```

### Common Issues

The OpenRC diagnosis table is the default:

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| No network at boot | Interface not configured | Check `/etc/conf.d/net` and `rc-service networking status` |
| DNS not resolving | Resolver or dhcpcd not running | `rc-service dhcpcd status` and `/etc/resolv.conf` |
| Can't reach gateway | Wrong route or ARP issue | `ip route show; arp -a` |
| WiFi not connecting | iwd/dhcpcd not running | `rc-service iwd status` and `rc-service dhcpcd status` |
| High latency | MTU mismatch or routing loop | `ping -M do -s 1472 <gateway>` |

For a systemd installation, the corresponding diagnosis table is:

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| No network at boot | Interface not configured | Check `/etc/systemd/network/` files |
| DNS not resolving | systemd-resolved not running | `systemctl status systemd-resolved` |
| WiFi not connecting | iwd/NetworkManager not running | `systemctl status iwd NetworkManager` |

## 13.10 References

- [systemd.network(5)](https://www.freedesktop.org/software/systemd/man/systemd.network.html)
- [systemd-resolved(8)](https://www.freedesktop.org/software/systemd/man/systemd-resolved.html)
- [nftables Wiki](https://wiki.nftables.org/)
- [Arch Wiki: Networking](https://wiki.archlinux.org/title/Networking)
- [Chapter 12: System Initialization](chapter-12-system-initialization.md) — OpenRC default and optional systemd compatibility
- [Chapter 14: SSH Server](chapter-14-ssh-server.md) — Remote access
