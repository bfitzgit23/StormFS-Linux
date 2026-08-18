# Chapter 7: Writing Custom Init Scripts

## Overview

This chapter explains how to write custom OpenRC init scripts for services that don't come with pre-made scripts.

## Template

Use this template as a starting point:

```bash
#!/sbin/openrc-run

# Service description
description "Description of the service"

# Service options
extra_commands="status reload"
extra_started_commands="pause cont hup"

# Dependency function
depend() {
    need net
    after logger
    before nginx
    keyword -stop
}

# Start function
start() {
    ebegin "Starting myservice"
    start-stop-daemon --start --background \
        --make-pidfile --pidfile /run/myservice.pid \
        --exec /usr/bin/myservice -- ${MY_OPTS}
    eend $?
}

# Stop function
stop() {
    ebegin "Stopping myservice"
    start-stop-daemon --stop --retry=TERM/30/KILL/5 \
        --pidfile /run/myservice.pid
    eend $?
}

# Status function
status() {
    [ -f /run/myservice.pid ] && \
        kill -0 $(cat /run/myservice.pid) 2>/dev/null
}

# Reload function
reload() {
    ebegin "Reloading myservice"
    start-stop-daemon --stop --signal HUP \
        --pidfile /run/myservice.pid
    eend $?
}
```

## Step-by-Step Guide

### Step 1: Create the Script

```bash
sudo nano /etc/init.d/myservice
```

### Step 2: Make Executable

```bash
sudo chmod 755 /etc/init.d/myservice
```

### Step 3: Add to Runlevel

```bash
sudo rc-update add myservice default
```

### Step 4: Test

```bash
# Test start
sudo rc-service myservice start

# Test stop
sudo rc-service myservice stop

# Check status
sudo rc-service myservice status
```

## Common Patterns

### Background Daemon

```bash
start() {
    ebegin "Starting mydaemon"
    start-stop-daemon --start --background \
        --make-pidfile --pidfile /run/mydaemon.pid \
        --exec /usr/bin/mydaemon
    eend $?
}
```

### Foreground Daemon

```bash
start() {
    ebegin "Starting mydaemon"
    start-stop-daemon --start \
        --exec /usr/bin/mydaemon -- ${OPTS}
    eend $?
}
```

### One-shot Script

```bash
start() {
    ebegin "Running one-shot"
    /usr/local/bin/one-shot-script
    eend $?
}
```

### Service with Environment File

```bash
depend() {
    need localmount
}

start() {
    ebegin "Starting myservice"
    source /etc/conf.d/myservice
    start-stop-daemon --start --exec /usr/bin/myservice
    eend $?
}
```

## Best Practices

1. Always use `ebegin`/`eend` for user feedback
2. Use `start-stop-daemon` for daemon management
3. Create PID files for long-running daemons
4. Handle signals properly (SIGHUP for reload)
5. Test your scripts thoroughly
6. Add appropriate dependencies
7. Use meaningful descriptions
8. Document your script

## Debugging

### Enable Debug Mode

```bash
export RC_DEBUG=1
sudo rc-service myservice start
```

### Verbose Output

```bash
sudo rc-service -v myservice start
```

### Check Dependencies

```bash
sudo rc-depend -v myservice
```

## Next Steps

After writing custom scripts, proceed to [Chapter 8: Migration from Systemd](chapters/08-migration.md) if migrating from systemd.
