# Chapter 5: Service Management

## Basic Service Commands

### Starting Services

```bash
# Start a service
sudo rc-service networkmanager start

# Start with verbose output
sudo rc-service networkmanager -v start
```

### Stopping Services

```bash
# Stop a service
sudo rc-service networkmanager stop

# Stop with verbose output
sudo rc-service networkmanager -v stop
```

### Restarting Services

```bash
# Restart a service
sudo rc-service networkmanager restart

# Reload configuration (if supported)
sudo rc-service networkmanager reload
```

### Checking Service Status

```bash
# Check if a service is running
sudo rc-service networkmanager status

# Check with detailed output
sudo rc-service networkmanager -v status
```

## Managing Multiple Services

### Starting Multiple Services

```bash
# Start multiple services
sudo rc-service networkmanager lightdm sshd start
```

### Stopping Multiple Services

```bash
# Stop multiple services
sudo rc-service networkmanager lightdm sshd stop
```

### Using Service Lists

Create a file with services to manage:

```bash
# /etc/init.d/service-list
networkmanager
lightdm
sshd
bluetooth
```

Then manage them all:

```bash
# Start all services in the list
while read svc; do
    sudo rc-service $svc start
done < /etc/init.d/service-list
```

## Service Information

### Listing Available Services

```bash
# List all available services
ls /etc/init.d/

# List services with descriptions
for svc in /etc/init.d/*; do
    echo "$(basename $svc): $(grep -m1 '# Description:' $svc | sed 's/# Description: //')"
done
```

### Checking Service Dependencies

```bash
# Check service dependencies
rc-depend -v networkmanager

# Show dependency tree
rc-depend -a networkmanager
```

## Service Control

### Enabling/Disabling Services

```bash
# Enable a service for automatic start
sudo rc-update add networkmanager default

# Disable a service
sudo rc-update delete networkmanager default
```

### Conditional Service Start

```bash
# Start service only if not running
rc-service -s networkmanager start

# Stop service only if running
rc-service -s networkmanager stop
```

## Service States

Services can be in several states:

- **started**: Service is running
- **stopped**: Service is not running
- **inactive**: Service is not enabled in any runlevel
- **failed**: Service failed to start

Check service state:

```bash
# Check service state
rc-status default

# Check all runlevels
rc-status -a
```

## Next Steps

After learning service management, proceed to [Chapter 6: Init Scripts Reference](chapters/06-init-scripts.md) to understand init script structure.
