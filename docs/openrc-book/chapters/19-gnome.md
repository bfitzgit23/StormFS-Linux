# Chapter 19: GNOME Desktop

## Overview

GNOME is a modern desktop environment focused on simplicity and elegance. This chapter covers installing and configuring GNOME with OpenRC on StormFS Linux.

## Prerequisites

Before installing GNOME, ensure the following are configured:

- X Window System or Wayland ([Chapter 10: Display Managers](chapters/10-display-managers.md))
- Audio configuration ([Chapter 11: Audio Configuration](chapters/11-audio.md))

## Installation

### Core Packages

```bash
prt-get install gnome gnome-apps-meta
```

### GNOME Core Components

```bash
prt-get install gnome-shell gnome-terminal nautilus
prt-get install gedit eog evince totem
```

### Recommended Additions

```bash
prt-get install gnome-tweaks gnome-shell-extensions
prt-get install gnome-control-center gdm
```

## GDM Integration

### Installation

```bash
prt-get install gdm
```

### OpenRC Service

```bash
# Enable GDM
sudo rc-update add gdm default

# Start GDM
sudo rc-service gdm start
```

### Configuration

Edit `/etc/gdm/custom.conf`:

```ini
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=stormfs

[security]
AllowRemoteAutoLogin=False

[xdmcp]
Enable=false

[chooser]
```

## OpenRC Services for GNOME

### Essential Services

```bash
# Enable GNOME-related services
sudo rc-update add gdm default
sudo rc-update add dbus default
sudo rc-update add polkitd default
sudo rc-update add upowerd default
sudo rc-update add accounts-daemon default
sudo rc-update add colord default
sudo rc-update add avahi-daemon default
```

### GNOME Service Init Script

```bash
cat > /etc/init.d/gnome-services <<'EOF'
#!/sbin/openrc-run

depend() {
    need dbus
    after elogind
    before gdm
}

start() {
    ebegin "Starting GNOME services"
    # Start GNOME Shell services
    /usr/lib/gnome-shell-calendar-server &
    /usr/lib/tracker-miner-fs-3 &
    eend $?
}

stop() {
    ebegin "Stopping GNOME services"
    killall gnome-shell-calendar-server 2>/dev/null
    killall tracker-miner-fs-3 2>/dev/null
    eend $?
}
EOF

chmod +x /etc/init.d/gnome-services
```

### Service Management

```bash
# Check GDM status
rc-service gdm status

# Check dependencies
rc-depend -v gdm

# List GNOME-related services
ls /etc/init.d/ | grep -E "(gdm|gnome|tracker|colord)"
```

## Configuring GNOME

### GNOME Settings

```bash
# Launch Settings
gnome-control-center

# Or specific panels
gnome-control-center display
gnome-control-center network
gnome-control-center sound
```

### GNOME Tweaks

```bash
# Install and launch GNOME Tweaks
prt-get install gnome-tweaks
gnome-tweaks
```

### dconf/gsettings Configuration

```bash
# Set wallpaper
gsettings set org.gnome.desktop.background picture-uri 'file:///path/to/wallpaper.jpg'

# Set theme
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
gsettings set org.gnome.desktop.interface icon-theme 'Adwaita'

# Set font
gsettings set org.gnome.desktop.interface font-name 'Cantarell 11'
gsettings set org.gnome.desktop.interface document-font-name 'Cantarell 11'

# Set cursor theme
gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'
```

### Extensions

```bash
# Install GNOME Extensions
prt-get install gnome-shell-extensions

# Enable extensions
gnome-extensions enable dash-to-dock@dash-to-shell.gnome.org

# List installed extensions
gnome-extensions list

# Extension settings
gnome-extensions prefs dash-to-dock@dash-to-shell.gnome.org
```

### Default Applications

```bash
# Set default web browser
xdg-settings set default-web-browser firefox.desktop

# Set default file manager
xdg-mime default org.gnome.Nautilus.desktop inode/directory

# Set default terminal
xdg-settings set default-terminal-emulator gnome-terminal.desktop
```

## GNOME Settings

### Display

```bash
# Configure display
gnome-control-center display

# Or via gsettings
gsettings set org.gnome.desktop.interface scaling-factor 2
```

### Sound

```bash
# Configure sound
gnome-control-center sound

# Set input volume
gsettings set org.gnome.desktop.sound allow-volume-above-100-percent true
```

### Privacy

```bash
# Configure privacy settings
gsettings set org.gnome.desktop.privacy show-full-name-in-top-bar false
gsettings set org.gnome.desktop.privacy old-files-age 30
```

### Power

```bash
# Configure power settings
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'suspend'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 3600
```

## Tips

- Use `Super` key to open the Activities overview.
- Use `Super+L` to lock the screen.
- GNOME Extensions can be installed from https://extensions.gnome.org.
- Use `gsettings list-keys` to explore available settings.
- GNOME Software provides a graphical package manager.

## Troubleshooting

### GNOME Not Starting

1. Check GNOME Shell:
   ```bash
   gnome-shell --version
   ```

2. Check GDM logs:
   ```bash
   sudo journalctl -u gdm
   ```

3. Reset GNOME settings:
   ```bash
   dconf reset -f /org/gnome/
   ```

### Extensions Not Working

1. Check extension compatibility:
   ```bash
   gnome-extensions show <extension-id>
   ```

2. Disable all extensions:
   ```bash
   gnome-extensions disable --all
   ```

## Next Steps

After GNOME configuration, proceed to [Chapter 20: LXQt Desktop](chapters/20-lxqt.md) for LXQt setup.
