# Chapter 11: Audio Configuration

## Overview

This chapter covers audio configuration with OpenRC.

## ALSA

ALSA provides basic audio support.

### Installation

```bash
prt-get install alsa-utils
```

### Configuration

```bash
# Enable ALSA
sudo rc-update add alsa boot

# Start ALSA
sudo rc-service alsa start
```

### Save/Restore State

```bash
# Save current state
sudo alsactl store

# Restore saved state
sudo alsactl restore
```

### Volume Control

```bash
# List sound cards
aplay -l

# List controls
amixer scontrols

# Set volume
amixer set Master 50%

# Unmute
amixer set Master unmute
```

## PulseAudio

PulseAudio provides advanced audio features.

### Installation

```bash
prt-get install pulseaudio
```

### System-Wide Mode

For system-wide PulseAudio:

```bash
# Enable PulseAudio
sudo rc-update add pulseaudio default

# Start PulseAudio
sudo rc-service pulseaudio start
```

### User Mode

For per-user PulseAudio (recommended for desktops):

```bash
# Add to user's .bash_profile
pulseaudio --start
```

### Configuration

Edit `/etc/pulse/daemon.conf`:

```ini
default-sample-format = s16le
default-sample-rate = 44100
default-sample-channels = 2
default-fragments = 2
default-fragment-size-msec = 25
```

## PipeWire

PipeWire is a modern multimedia server.

### Installation

```bash
prt-get install pipewire
prt-get install wireplumber
```

### Configuration

```bash
# Enable PipeWire
sudo rc-update add pipewire default
sudo rc-update add wireplumber default

# Start PipeWire
sudo rc-service pipewire start
sudo rc-service wireplumber start
```

### User Mode

For per-user PipeWire:

```bash
# Add to user's .bash_profile
pipewire &
wireplumber &
```

## Audio Applications

### alsamixer

```bash
# Start alsamixer
alsamixer

# Navigate: arrow keys
# Increase volume: up arrow
# Decrease volume: down arrow
# Mute/unmute: m
```

### pavucontrol

```bash
# Start PulseAudio volume control
pavucontrol
```

### pw-top

```bash
# Monitor PipeWire
pw-top
```

## Troubleshooting

### No Sound

1. Check sound cards:
   ```bash
   aplay -l
   ```

2. Check mixer levels:
   ```bash
   amixer
   ```

3. Check PulseAudio:
   ```bash
   pactl list sinks
   ```

### Audio Cracking

1. Increase buffer size in PulseAudio config
2. Check CPU frequency scaling
3. Try different sample rates

## Next Steps

After audio configuration, proceed to [Chapter 12: Bluetooth](chapters/12-bluetooth.md) to configure Bluetooth.
