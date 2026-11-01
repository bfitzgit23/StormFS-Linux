#!/usr/bin/env bash
# Entrypoint for the BFSOS ISO build container (see Dockerfile).
#
# Starts chronyd and waits for the clock to report synchronised, then hands off
# to scripts/bfs-build-iso.sh with whatever arguments the container was given.
# The container has no systemd, so the image ships a timedatectl shim that reads
# chrony's real state.
set -Eeuo pipefail

BUILD_PROJECT_DIR="${BUILD_PROJECT_DIR:-/build/StormFS-Linux}"

# Stage 1 keeps its completed packages in this cache.  $HOME/.cache/bfsos is the
# only build directory the documented run command mounts, so a stopped or
# crashed container resumes at the package that failed instead of rebuilding
# the whole temporary toolchain.  The cache is validated against the current
# package versions, so a version bump still forces a clean rebuild.
export BFS_TOOLS_CACHE="${BFS_TOOLS_CACHE:-/home/builder/.cache/bfsos/bootstrap/tools}"

log() { printf '[BFSOS ISO container] %s\n' "$*"; }

if [ "$(id -u)" -eq 0 ]; then
    printf 'Run this container as the unprivileged builder user; the ISO builder refuses root.\n' >&2
    exit 1
fi

clock_synced() {
    [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)" = yes ]
}

log "Starting chronyd for host clock synchronisation"
sudo mkdir -p /run/chrony
if ! pgrep -x chronyd >/dev/null 2>&1; then
    sudo chronyd -f /etc/chrony/chrony.conf
fi

# Debian's chronyd binds no control socket inside a container, so readiness is
# "the clock reports synchronised" - the same question sync_host_time() asks.
for _ in $(seq 1 30); do
    clock_synced && break
    sleep 1
done
clock_synced || log "warning: clock not yet synchronised; the builder retries for 10s and then stops"

log "Running scripts/bfs-build-iso.sh $*"
exec "$BUILD_PROJECT_DIR/scripts/bfs-build-iso.sh" "$@"
