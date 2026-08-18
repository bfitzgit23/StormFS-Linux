# Chapter 15: Troubleshooting

## Overview

This chapter covers common issues and solutions when using OpenRC.

## Boot Issues

### System Won't Boot

1. **Check boot messages**:
   ```bash
   # Boot with verbose output
   rc verbose

   # Check boot log
   cat /var/log/boot.log
   ```

2. **Boot to single-user mode**:
   ```bash
   # Add to kernel command line
   single
   ```

3. **Check init scripts**:
   ```bash
   # List failed services
   rc-status -a

   # Check specific service
   rc-service myservice status
   ```

### Service Won't Start

1. **Check dependencies**:
   ```bash
   rc-depend -v myservice
   ```

2. **Check logs**:
   ```bash
   cat /var/log/messages | grep myservice
   ```

3. **Test manually**:
   ```bash
   /etc/init.d/myservice start
   ```

## Service Issues

### Service Fails to Start

1. **Check permissions**:
   ```bash
   ls -l /etc/init.d/myservice
   ls -l /usr/bin/myservice
   ```

2. **Check configuration**:
   ```bash
   cat /etc/conf.d/myservice
   ```

3. **Check PID file**:
   ```bash
   ls -l /run/myservice.pid
   ```

### Service Stops Unexpectedly

1. **Check logs**:
   ```bash
   tail -f /var/log/messages
   ```

2. **Check resource usage**:
   ```bash
   top
   free -h
   df -h
   ```

3. **Check for crashes**:
   ```bash
   dmesg | tail
   ```

## Network Issues

### No Network Connection

1. **Check network interface**:
   ```bash
   ip link show
   ```

2. **Check NetworkManager**:
   ```bash
   rc-service networkmanager status
   nmcli general status
   ```

3. **Check WiFi**:
   ```bash
   nmcli device wifi list
   ```

### DNS Issues

1. **Check DNS configuration**:
   ```bash
   cat /etc/resolv.conf
   ```

2. **Test DNS resolution**:
   ```bash
   nslookup google.com
   ping google.com
   ```

3. **Check resolvconf**:
   ```bash
   rc-service resolvconf status
   ```

## Display Issues

### X Won't Start

1. **Check X logs**:
   ```bash
   cat /var/log/Xorg.0.log
   ```

2. **Check display manager**:
   ```bash
   rc-service lightdm status
   ```

3. **Test X manually**:
   ```bash
   startx
   ```

### Black Screen After Login

1. **Check session**:
   ```bash
   ls /usr/share/xsessions/
   ```

2. **Check desktop environment**:
   ```bash
   echo $XDG_CURRENT_DESKTOP
   ```

3. **Check graphics drivers**:
   ```bash
   lspci | grep VGA
   ```

## Audio Issues

### No Sound

1. **Check sound cards**:
   ```bash
   aplay -l
   ```

2. **Check mixer**:
   ```bash
   amixer
   ```

3. **Check PulseAudio**:
   ```bash
   pactl list sinks
   ```

### Audio Cracking

1. **Increase buffer**:
   Edit `/etc/pulse/daemon.conf`:
   ```ini
   default-fragments = 4
   default-fragment-size-msec = 25
   ```

2. **Check CPU frequency**:
   ```bash
   cpupower frequency-info
   ```

## Bluetooth Issues

### Device Not Found

1. **Check Bluetooth**:
   ```bash
   bluetoothctl show
   ```

2. **Check adapter**:
   ```bash
   hciconfig
   ```

3. **Reset adapter**:
   ```bash
   sudo hciconfig hci0 reset
   ```

### Connection Issues

1. **Remove and re-pair**
2. **Check battery level**
3. **Check distance/interference**

## Logging

### Where are the logs?

- `/var/log/messages` - System messages
- `/var/log/auth.log` - Authentication logs
- `/var/log/boot.log` - Boot messages
- `/var/log/Xorg.0.log` - X server logs
- `/var/log/lightdm/` - Display manager logs

### Viewing Logs

```bash
# View system log
tail -f /var/log/messages

# View auth log
tail -f /var/log/auth.log

# View boot log
cat /var/log/boot.log
```

## Getting Help

### Online Resources

- [OpenRC Documentation](https://github.com/OpenRC/openrc)
- [Gentoo Forums](https://forums.gentoo.org)
- [StormFS Linux Forums](https://github.com/bfitzgit23/StormFS-Linux/issues)

### Debugging Commands

```bash
# Enable debug mode
export RC_DEBUG=1

# Verbose output
rc-service -v myservice start

# Check dependencies
rc-depend -v myservice

# List all services
rc-status -a
```

## Next Steps

For advanced topics, proceed to [Chapter 16: Advanced Topics](chapters/16-advanced.md).
