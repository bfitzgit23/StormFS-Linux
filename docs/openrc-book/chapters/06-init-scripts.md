# Chapter 6: Init Scripts Reference

## Init Script Structure

OpenRC init scripts are shell scripts that follow a specific structure. They are located in `/etc/init.d/`.

### Basic Structure

```bash
#!/sbin/openrc-run

# Description of the service
description "Network Manager daemon"

# Service dependencies
depend() {
    need localmount
    after bootmisc
    before networkmanager
    keyword -stop
}

# Start function
start() {
    ebegin "Starting NetworkManager"
    start-stop-daemon --start --exec /usr/sbin/NetworkManager
    eend $?
}

# Stop function
stop() {
    ebegin "Stopping NetworkManager"
    start-stop-daemon --stop --exec /usr/sbin/NetworkManager
    eend $?
}
```

## Required Functions

### depend()

The `depend()` function defines service dependencies:

```bash
depend() {
    # Service needs this dependency
    need dbus
    
    # Service should start after this dependency
    after xdm
    
    # Service should start before this dependency
    before networkmanager
    
    # Service can use this dependency if available
    use logger
    
    # Service conflicts with this dependency
    break mdraid
    
    # Service belongs to this runlevel
    runlevel default
    runlevel !single
}
```

### start()

The `start()` function starts the service:

```bash
start() {
    ebegin "Starting myservice"
    start-stop-daemon --start --exec /usr/bin/myservice
    eend $?
}
```

### stop()

The `stop()` function stops the service:

```bash
stop() {
    ebegin "Stopping myservice"
    start-stop-daemon --stop --exec /usr/bin/myservice
    eend $?
}
```

## Optional Functions

### status()

The `status()` function checks if the service is running:

```bash
status() {
    # Return 0 if running, 1 if not
    if [ -f /run/myservice.pid ]; then
        return 0
    fi
    return 1
}
```

### reload()

The `reload()` function reloads configuration:

```bash
reload() {
    ebegin "Reloading myservice"
    start-stop-daemon --stop --signal HUP --exec /usr/bin/myservice
    eend $?
}
```

## Helper Functions

### ebegin/eend

These functions handle service start/stop messages:

```bash
# Start message with success/failure
ebegin "Starting myservice"
# ... service start commands ...
eend $?

# With custom error message
ebegin "Starting myservice"
# ... service start commands ...
eend $? "Failed to start myservice"
```

### start-stop-daemon

This is the main tool for managing daemons:

```bash
# Start a daemon
start-stop-daemon --start --exec /usr/bin/mydaemon

# Start with PID file
start-stop-daemon --start --exec /usr/bin/mydaemon --pidfile /run/mydaemon.pid

# Stop a daemon
start-stop-daemon --stop --exec /usr/bin/mydaemon

# Stop with timeout
start-stop-daemon --stop --exec /usr/bin/mydaemon --retry 30

# Send signal
start-stop-daemon --stop --signal HUP --exec /usr/bin/mydaemon
```

### opts

Define command-line options for the service:

```bash
opts="start stop restart reload status"

start() {
    ebegin "Starting myservice"
    start-stop-daemon --start --exec /usr/bin/myservice ${MY_OPTS}
    eend $?
}
```

## Example Init Scripts

### Simple Daemon

```bash
#!/sbin/openrc-run

description="Simple daemon service"

depend() {
    need net
    after logger
}

start() {
    ebegin "Starting simple-daemon"
    start-stop-daemon --start --exec /usr/bin/simple-daemon \
        --pidfile /run/simple-daemon.pid
    eend $?
}

stop() {
    ebegin "Stopping simple-daemon"
    start-stop-daemon --stop --exec /usr/bin/simple-daemon \
        --pidfile /run/simple-daemon.pid
    eend $?
}
```

### One-shot Service

```bash
#!/sbin/openrc-run

description="One-shot service (runs once at boot)"

depend() {
    need localmount
}

start() {
    ebegin "Running one-shot service"
    /usr/bin/one-shot-script
    eend $?
}
```

### Service with Configuration

```bash
#!/sbin/openrc-run

description="Service with configuration"

opts="start stop restart"

depend() {
    need dbus
    after logger
}

start() {
    ebegin "Starting myservice"
    start-stop-daemon --start --exec /usr/bin/myservice \
        --pidfile /run/myservice.pid \
        -- ${MY_OPTS}
    eend $?
}

stop() {
    ebegin "Stopping myservice"
    start-stop-daemon --stop --exec /usr/bin/myservice \
        --pidfile /run/myservice.pid
    eend $?
}
```

## Debugging Init Scripts

### Enable Verbose Mode

```bash
# Run with verbose output
sudo rc-service -v myservice start

# Run with debug output
sudo RC_DEBUG=1 rc-service myservice start
```

### Check Script Syntax

```bash
# Check syntax
bash -n /etc/init.d/myservice

# Run with shellcheck
shellcheck /etc/init.d/myservice
```

## Next Steps

After understanding init scripts, proceed to [Chapter 7: Writing Custom Init Scripts](chapters/07-custom-scripts.md) to create your own.
