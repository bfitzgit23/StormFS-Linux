# Chapter 20: LXQt Desktop

## Overview

LXQt is the Qt-based successor to LXDE, offering a lightweight and modular desktop environment. This chapter covers installing and configuring LXQt with OpenRC on StormFS Linux.

## Prerequisites

Before installing LXQt, ensure the following are configured:

- X Window System or Wayland ([Chapter 10: Display Managers](chapters/10-display-managers.md))
- Audio configuration ([Chapter 11: Audio Configuration](chapters/11-audio.md))

## Installation

### Core Packages

```bash
prt-get install lxqt-meta
```

### LXQt Components

```bash
prt-get install lxqt-panel lxqt-session lxqt-qtplugin
prt-get install pcmanfm-qt lxterminal qterminal
```

### Recommended Additions

```bash
prt-get install sddm lightdm
prt-get install arc-icons arc-themes
```

## SDDM/LightDM Integration

### SDDM (Recommended)

```bash
# Install SDDM
prt-get install sddm

# Enable SDDM
sudo rc-update add sddm default

# Start SDDM
sudo rc-service sddm start
```

Configure `/etc/sddm.conf`:

```ini
[Autologin]
User=stormfs
Session=lxqt

[General]
DisplayServer=wayland

[Theme]
Current=breeze
```

### LightDM

```bash
# Install LightDM
prt-get install lightdm lightdm-gtk-greeter

# Enable LightDM
sudo rc-update add lightdm default

# Start LightDM
sudo rc-service lightdm start
```

Configure `/etc/lightdm/lightdm.conf`:

```ini
[Seat:*]
autologin-user=stormfs
autologin-user-timeout=0
user-session=lxqt
greeter-session=lightdm-gtk-greeter
```

## OpenRC Services for LXQt

### Essential Services

```bash
# Enable LXQt-related services
sudo rc-update add sddm default
sudo rc-update add dbus default
sudo rc-update add polkitd default
sudo rc-update add upowerd default
```

### LXQt Service Init Script

```bash
cat > /etc/init.d/lxqt-services <<'EOF'
#!/sbin/openrc-run

depend() {
    need dbus
    after elogind
    before sddm
}

start() {
    ebegin "Starting LXQt services"
    # Start LXQt panel
    /usr/bin/lxqt-panel &
    eend $?
}

stop() {
    ebegin "Stopping LXQt services"
    killall lxqt-panel 2>/dev/null
    eend $?
}
EOF

chmod +x /etc/init.d/lxqt-services
```

### Service Management

```bash
# Check display manager status
rc-service sddm status

# Check dependencies
rc-depend -v sddm

# List LXQt-related services
ls /etc/init.d/ | grep -E "(sddm|lxqt|pcman)"
```

## Configuring LXQt

### LXQt Configuration Center

```bash
# Launch LXQt Configuration Center
lxqt-config

# Or specific modules
lxqt-config-appearance
lxqt-config-input
lxqt-config-monitor
```

### Panel Configuration

```bash
# Configure panel
lxqt-panel --configure

# Panel settings are stored in
~/.config/lxqt/panel.conf
```

### Desktop Settings

```bash
# Set wallpaper via PCManFM-Qt
pcmanfm-qt --set-wallpaper=/path/to/wallpaper.jpg

# Or via configuration
lxqt-config-appearance
```

### File Manager

```bash
# Configure PCManFM-Qt
pcmanfm-qt

# Set default file manager
xdg-mime default pcmanfm-qt.desktop inode/directory
```

### Default Applications

```bash
# Set default web browser
xdg-settings set default-web-browser firefox.desktop

# Set default terminal
xdg-settings set default-terminal-emulator lxterminal.desktop

# Set default file manager
xdg-mime default pcmanfm-qt.desktop inode/directory
```

## Window Manager Configuration

### Openbox (Default)

```bash
# Install Openbox
prt-get install openbox

# Configure Openbox
mkdir -p ~/.config/openbox
cp /etc/xdg/openbox/rc.xml ~/.config/openbox/rc.xml
```

### Fluxbox Alternative

```bash
# Install Fluxbox
prt-get install fluxbox

# Configure Fluxbox
mkdir -p ~/.fluxbox
echo "session.screen0.toolbar.visible: true" > ~/.fluxbox/init
```

## Tips

- LXQt is highly modular; components can be swapped easily.
- The default window manager is Openbox, but you can use KWin or Xfwm4.
- Use `lxqt-config` to access all LXQt settings from one place.
- LXQt supports both Qt5 and Qt6 themes.
- PCManFM-Qt provides tabbed browsing and bookmarks.

## Troubleshooting

### LXQt Not Starting

1. Check LXQt session:
   ```bash
   lxqt-session
   ```

2. Check panel:
   ```bash
   lxqt-panel
   ```

3. Reset LXQt configuration:
   ```bash
   rm -rf ~/.config/lxqt
   ```

### Panel Issues

1. Restart the panel:
   ```bash
   killall lxqt-panel
   lxqt-panel &
   ```

2. Reset panel configuration:
   ```bash
   rm ~/.config/lxqt/panel.conf
   ```

## Next Steps

After LXQt configuration, proceed to [Chapter 21: Window Managers](chapters/21-window-managers.md) for window manager setup.
