# Chapter 9: Networking

## Overview

This chapter covers network configuration with OpenRC.

## NetworkManager

NetworkManager is the recommended network manager for desktop systems.

### Installation

```bash
prt-get install networkmanager
```

### Configuration

```bash
# Enable NetworkManager
sudo rc-update add networkmanager default

# Start NetworkManager
sudo rc-service networkmanager start
```

### Usage

```bash
# List connections
nmcli connection show

# Connect to WiFi
nmcli device wifi connect "SSID" password "PASSWORD"

# Show status
nmcli general status
```

## dhcpcd

dhcpcd is a lightweight DHCP client.

### Installation

```bash
prt-get install dhcpcd
```

### Configuration

```bash
# Enable dhcpcd
sudo rc-update add dhcpcd boot

# Start dhcpcd
sudo rc-service dhcpcd start
```

### Manual Configuration

```bash
# Request IP address
sudo dhcpcd eth0

# Release IP address
sudo dhcpcd -k eth0
```

## wpa_supplicant

wpa_supplicant handles WiFi authentication.

### Installation

```bash
prt-get install wpa_supplicant
```

### Configuration

Create `/etc/wpa_supplicant/wpa_supplicant.conf`:

```bash
ctrl_interface=/var/run/wpa_supplicant
ctrl_interface_group=wheel

network={
    ssid="your-network-name"
    psk="your-password"
}
```

### Enable and Start

```bash
# Enable wpa_supplicant
sudo rc-update add wpa_supplicant boot

# Start wpa_supplicant
sudo rc-service wpa_supplicant start
```

## Static IP Configuration

### Using /etc/conf.d/net

```bash
# /etc/conf.d/net

# Interface configuration
config_eth0="192.168.1.100/24"
routes_eth0="default via 192.168.1.1"
dns_servers_eth0="8.8.8.8 8.8.4.4"
```

### Enable Network Script

```bash
# Create symlink for interface
sudo ln -s /etc/init.d/net.lo /etc/init.d/net.eth0

# Add to runlevel
sudo rc-update add net.eth0 default

# Start interface
sudo rc-service net.eth0 start
```

## Firewall Configuration

### nftables

```bash
# Install nftables
prt-get install nftables

# Enable nftables
sudo rc-update add nftables boot

# Create ruleset
sudo nano /etc/nftables.nft

# Start nftables
sudo rc-service nftables start
```

### Example Ruleset

```bash
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        
        # Allow loopback
        iif "lo" accept
        
        # Allow established connections
        ct state established,related accept
        
        # Allow SSH
        tcp dport 22 accept
        
        # Allow ICMP
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
    }
    
    chain forward {
        type filter hook forward priority 0; policy drop;
    }
    
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
```

## DNS Configuration

### Using resolvconf

```bash
# Install resolvconf
prt-get install resolvconf

# Configure DNS servers
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf
```

### Using /etc/resolv.conf

```bash
# /etc/resolv.conf
nameserver 8.8.8.8
nameserver 8.8.4.4
search example.com
```

## Next Steps

After networking configuration, proceed to [Chapter 10: Display Managers](chapters/10-display-managers.md) to configure display managers.
