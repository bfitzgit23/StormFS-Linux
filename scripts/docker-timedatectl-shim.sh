#!/bin/sh
# Minimal timedatectl for the BFSOS ISO build container.
#
# scripts/bfs-build-iso.sh sync_host_time() tries chrony first and then asks
# timedatectl whether the clock is NTP-synchronised; a container has no systemd
# bus, so without this shim the ISO build aborts with "Unable to synchronize
# host clock".
#
# This shim does not assume success: containers share the host clock, and the
# answer is derived from the chronyd running inside the image. If chrony has no
# reference and no stratum, it reports "no" and the builder still refuses to
# continue, exactly as on a host with a bad clock.
set -u

chrony_synced() {
    if command -v chronyc >/dev/null 2>&1; then
        chronyc tracking 2>/dev/null ||
            sudo -n chronyc tracking 2>/dev/null || true
    fi | awk '
        /^Reference ID/ { ref = $4 }
        /^Stratum/      { stratum = $3 }
        END { exit !(ref != "" && ref != "00000000" && stratum + 0 > 0) }'
}

case "${1:-}" in
    show)
        case "$*" in
            *NTPSynchronized*)
                if chrony_synced; then printf 'yes\n'; else printf 'no\n'; fi
                exit 0
                ;;
            *CanNTP*)
                printf 'yes\n'
                exit 0
                ;;
        esac
        printf 'Local time: %s\n' "$(date)"
        printf 'Universal time: %s\n' "$(date -u)"
        ;;
    set-ntp|set-time|set-timezone|set-local-rtc)
        # Time stays under chrony's control inside the container.
        exit 0
        ;;
    status)
        printf 'Systemd timedatectl compatibility shim (chrony backend)\n'
        if chrony_synced; then printf 'NTP synchronized: yes\n'; else printf 'NTP synchronized: no\n'; fi
        ;;
esac
exit 0
