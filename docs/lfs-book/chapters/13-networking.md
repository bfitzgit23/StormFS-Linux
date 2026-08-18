# Chapter 13: Networking

This chapter covers network configuration in StormFS Linux, including hostname setup, DNS, firewall rules, and network daemon configuration.

## 13.1 Setting the Hostname

### /etc/hostname

The hostname identifies the machine on the network:

```bash
cat > /etc/hostname << 'EOF'
stormfs-box
EOF
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

### Setting Hostname with systemd

```bash
# Set hostname (updates /etc/hostname and applies immediately)
hostnamectl set-hostname stormfs-box

# Verify
hostnamectl status
hostname
```

## 13.2 systemd-networkd Configuration

systemd-networkd is the recommended network daemon for StormFS, providing DHCP and static configuration.

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

## 13.3 NetworkManager Setup

For desktop systems with WiFi, mobile broadband, and VPN requirements, NetworkManager provides a more feature-rich experience.

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
    -Dsession-tracking=systemd \
    -Dlibaudit=no \
    -Dselinux=no \
    -Dppp=false \
    -Dvapi=false \
    -Dgtk_doc=false \
    -Dtests=false

ninja -C build
ninja -C build install
```

### Enabling NetworkManager

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
dns=systemd
wlbackend=iwd

[logging]
level=INFO
domain=CONFIG,PLATFORM
```

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

## 13.4 DNS Configuration

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

Verify DNSSEC is working:

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

## 13.5 Firewall (nftables)

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

### Starting nftables

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

# Reload rules
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

## 13.6 IPv6 Configuration

systemd-networkd supports IPv6 natively. Example static configuration:

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

## 13.7 Network Troubleshooting

### Diagnostic Commands

```bash
# Interface status
ip addr show
ip link show

# Routing table
ip route show

# DNS resolution test
resolvectl query example.com
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
resolvectl statistics
journalctl -u systemd-resolved -f

# Packet capture
tcpdump -i eth0 -n port 22
tcpdump -i eth0 -n 'host 192.168.1.1'
```

### Common Issues

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| No network at boot | Interface not configured | Check `/etc/systemd/network/` files |
| DNS not resolving | systemd-resolved not running | `systemctl status systemd-resolved` |
| Can't reach gateway | Wrong route or ARP issue | `ip route show; arp -a` |
| WiFi not connecting | iwd/NetworkManager not running | `systemctl status iwd NetworkManager` |
| High latency | MTU mismatch or routing loop | `ping -M do -s 1472 <gateway>` |

## 13.8 References

- [systemd.network(5)](https://www.freedesktop.org/software/systemd/man/systemd.network.html)
- [systemd-resolved(8)](https://www.freedesktop.org/software/systemd/man/systemd-resolved.html)
- [nftables Wiki](https://wiki.nftables.org/)
- [Arch Wiki: Networking](https://wiki.archlinux.org/title/Networking)
- [Chapter 12: System Initialization](chapter-12-system-initialization.md) — systemd overview
- [Chapter 14: SSH Server](chapter-14-ssh-server.md) — Remote access
