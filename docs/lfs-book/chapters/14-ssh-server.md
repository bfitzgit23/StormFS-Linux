# Chapter 14: SSH Server

This chapter covers installing, configuring, and hardening the OpenSSH server for remote access to StormFS Linux.

## 14.1 Installing OpenSSH

OpenSSH provides encrypted remote access, file transfer, and tunneling. Install from the BLFS build:

```bash
cd /sources
tar -xf openssh-9.7p1.tar.xz
cd openssh-9.7p1

./configure --prefix=/usr                    \
            --sysconfdir=/etc/ssh            \
            --with-md5-passwords=yes         \
            --with-selinux=no                \
            --with-pam=yes                   \
            --with-libedit                   \
            --with-privsep-user=sshd         \
            --with-privsep-path=/var/lib/sshd \
            --with-ssl-dir=/usr              \
            --disable-etc-default-login
make
make install
```

### Post-Installation Setup

```bash
# Create required directories
install -d -m755 /var/lib/sshd
install -d -m755 /etc/ssh/sshd_config.d
install -d -m755 /var/empty

# Set permissions
chown root:root /var/lib/sshd
chmod 755 /var/lib/sshd
chown root:root /var/empty
chmod 555 /var/empty

# Create sshd privilege separation directory
install -m755 /dev/null /run/sshd.pid 2>/dev/null || true
```

### Verify Installation

```bash
sshd -V
ssh -V
```

## 14.2 Configuration (/etc/ssh/sshd_config)

The main SSH server configuration file. Create or edit `/etc/ssh/sshd_config`:

```bash
cat > /etc/ssh/sshd_config << 'SSHEOF'
# StormFS OpenSSH Server Configuration
# /etc/ssh/sshd_config

# Network
Port 22
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::

# Protocol and host keys
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Authentication
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no

# Authorized keys
AuthorizedKeysFile .ssh/authorized_keys

# PAM (Pluggable Authentication Modules)
UsePAM yes

# Privilege separation
UsePrivilegeSeparation sandbox

# Security
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
AllowStreamLocalForwarding no
GatewayPorts no
PermitTunnel no
PermitUserEnvironment no
PermitUserRC no
StrictModes yes

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Session
LoginGraceTime 60
MaxAuthTries 3
MaxSessions 5
MaxStartups 10:30:60
ClientAliveInterval 300
ClientAliveCountMax 2
TCPKeepAlive yes

# Environment
PrintMotd yes
PrintLastLog yes

# Misc
Compression no
Banner /etc/ssh/banner
SSHEOF
```

### Create the Login Banner

```bash
cat > /etc/ssh/banner << 'EOF'
******************************************************************************
              STORMFS LINUX — Authorized Access Only
******************************************************************************
  All connections are monitored and recorded. Disconnect IMMEDIATELY if you
  are not an authorized user. Unauthorized access will be prosecuted.
******************************************************************************
EOF
```

### Split Configuration with Include (Optional)

For modular configuration, use an include directory:

```bash
# In /etc/ssh/sshd_config, add:
Include /etc/ssh/sshd_config.d/*.conf

# Then create modular configs:
cat > /etc/ssh/sshd_config.d/00-security.conf << 'EOF'
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
EOF

cat > /etc/ssh/sshd_config.d/01-session.conf << 'EOF'
LoginGraceTime 60
MaxAuthTries 3
MaxSessions 5
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

cat > /etc/ssh/sshd_config.d/02-forwarding.conf << 'EOF'
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
EOF
```

## 14.3 Key Generation

### Server Host Keys

Generate strong host keys if they do not already exist:

```bash
# Generate RSA key (4096-bit)
ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""

# Generate ECDSA key (521-bit)
ssh-keygen -t ecdsa -b 521 -f /etc/ssh/ssh_host_ecdsa_key -N ""

# Generate Ed25519 key (preferred)
ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
```

Set correct permissions:

```bash
chmod 600 /etc/ssh/ssh_host_*_key
chmod 644 /etc/ssh/ssh_host_*_key.pub
```

### Client Key Generation

Generate an Ed25519 key pair on the **client** machine (your workstation):

```bash
ssh-keygen -t ed25519 -C "user@stormfs-box" -f ~/.ssh/id_ed25519
```

### Copying Public Key to Server

```bash
# Method 1: ssh-copy-id (recommended)
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@stormfs-box

# Method 2: Manual
cat ~/.ssh/id_ed25519.pub | ssh user@stormfs-box \
    "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

### Authorized Keys Configuration

Edit `~/.ssh/authorized_keys` on the server for fine-grained control:

```bash
# Basic key
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... user@stormfs-box

# Key with restrictions (command-only, from-specific-IP)
from="192.168.1.50",command="/usr/local/bin/backup.sh",no-port-forwarding,no-X11-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... backup@workstation
```

### Revoke a Key

```bash
# Remove from authorized_keys
sed -i '/ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA.../d' ~/.ssh/authorized_keys

# Or use a revoked keys file
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA..." >> ~/.ssh/revoked_keys
# Add to sshd_config: RevokedKeysFile /etc/ssh/revoked_keys
```

## 14.4 Enabling and Starting sshd

### Create a systemd Service (if not installed automatically)

```bash
cat > /etc/systemd/system/sshd.service << 'EOF'
[Unit]
Description=OpenSSH server daemon
Documentation=man:sshd(8) man:sshd_config(5)
After=network.target auditd.service
ConditionPathExists=!/etc/ssh/sshd_not_to_be_run

[Service]
Type=notify
EnvironmentFile=-/etc/sysconfig/sshd
ExecStart=/usr/sbin/sshd -D $SSHD_OPTS
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=42s
TimeoutStartSec=infinity
TimeoutStopSec=30s

[Install]
WantedBy=multi-user.target
EOF
```

### Enable and Start

```bash
systemctl daemon-reload
systemctl enable sshd.service
systemctl start sshd.service
systemctl status sshd.service
```

### Verify

```bash
# Check that sshd is listening
ss -tlnp | grep :22

# Test connection locally
ssh -o StrictHostKeyChecking=no user@localhost

# Check logs
journalctl -u sshd.service
```

## 14.5 Security Hardening

### SSH Key-Based Authentication Only

```bash
# /etc/ssh/sshd_config
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
```

### Restrict Users and Groups

```bash
# Allow only specific users
AllowUsers admin deployer

# Allow only users in a specific group
AllowGroups ssh-users admin

# Deny specific users
DenyUsers guest testuser
```

### Chroot SFTP Users

```bash
# /etc/ssh/sshd_config
Match Group sftp-only
    ForceCommand internal-sftp
    ChrootDirectory /home/%u
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
```

Create the required directories:

```bash
groupadd sftp-only
useradd -m -g sftp-only -s /usr/sbin/nologin sftpuser

# Chroot requires ownership by root
chown root:root /home/sftpuser
chmod 755 /home/sftpuser

# Create a writable subdirectory
mkdir /home/sftpuser/upload
chown sftpuser:sftp-only /home/sftpuser/upload
chmod 755 /home/sftpuser/upload
```

### Rate Limiting and Fail2ban

```bash
# Install fail2ban (from BLFS)
cd /sources
tar -xf fail2ban-1.0.2.tar.gz
cd fail2ban-1.0.2

python3 setup.py install --prefix=/usr --install-scripts=/usr/bin

# Configure for SSH
cat > /etc/fail2ban/jail.d/sshd.conf << 'EOF'
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
banaction = nftables
EOF

systemctl enable --now fail2ban
```

### Disable Root Login

```bash
# /etc/ssh/sshd_config
PermitRootLogin no
```

For key-only root access (if absolutely needed):

```bash
PermitRootLogin prohibit-password
```

### SSH Configuration for /etc/ssh/ssh_config (Client-Side)

```bash
cat > /etc/ssh/ssh_config << 'EOF'
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    StrictHostKeyChecking ask
    HashKnownHosts yes
    ForwardAgent no
    ForwardX11 no
    AddKeysToAgent yes

Host stormfs-server
    HostName 192.168.1.100
    User admin
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
EOF
```

### SSH Agent Forwarding (Careful)

```bash
# Only forward when needed
ssh -A user@jump-host

# Or configure per-host
# In ~/.ssh/config:
Host jump-host
    ForwardAgent yes
```

### Audit SSH Configuration

```bash
# Check for weak settings
sshd -T | grep -i "passwordauthentication"
sshd -T | grep -i "permitrootlogin"
sshd -T | grep -i "protocol"

# Test configuration
sshd -t

# List all supported algorithms
sshd -T | grep -i kexalgorithms
sshd -T | grep -i ciphers
sshd -T | grep -i macs
```

### Remove Weak Algorithms

```bash
# /etc/ssh/sshd_config — restrict to strong algorithms
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
```

## 14.6 Advanced: SSH Tunneling and Port Forwarding

### Local Port Forwarding

```bash
# Forward local port 8080 to remote server's port 80
ssh -L 8080:localhost:80 user@stormfs-box

# Forward to a remote host via the server
ssh -L 8080:internal-server:80 user@stormfs-box
```

### Remote Port Forwarding

```bash
# Expose local port 3000 on the server's port 3000
ssh -R 3000:localhost:3000 user@stormfs-box
```

### Dynamic SOCKS Proxy

```bash
# Create a SOCKS proxy on localhost:1080
ssh -D 1080 user@stormfs-box
```

### SSH Multiplexing (Persistent Tunnels)

```bash
# Create a persistent connection
ssh -f -N -M -S /tmp/stormfs-socket user@stormfs-box

# Reuse the connection
ssh -S /tmp/stormfs-socket user@stormfs-box

# Close the master connection
ssh -S /tmp/stormfs-socket -O exit user@stormfs-box
```

## 14.7 References

- [OpenSSH Manual](https://www.openssh.com/manual.html)
- [ssh_config(5)](https://www.openssh.com/man5/ssh_config.html)
- [sshd_config(5)](https://www.openssh.com/man5/sshd_config.html)
- [Chapter 13: Networking](chapter-13-networking.md) — Firewall and network
- [Chapter 12: System Initialization](chapter-12-system-initialization.md) — systemd units
