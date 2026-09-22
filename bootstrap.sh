#!/bin/bash -e

# BFSOS bootstrap r74 - Shadow finalization, ISO handoff, verified-base reuse, and live-ISO policy handoff

# Bootstrap environments do not necessarily have generated UTF-8 locales.
# The POSIX C locale is always available and keeps all bootstrap stages
# deterministic.
unset LC_CTYPE
unset LC_COLLATE
unset LC_MESSAGES
unset LC_MONETARY
unset LC_NUMERIC
unset LC_TIME

export LANG=C
export LC_ALL=C
export LANGUAGE=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PID_FILE="$SCRIPT_DIR/.bootstrap.pid"

# Synchronize the host/live-environment clock before any bootstrap archive or
# package timestamps are created. Prefer chrony (Gentoo LiveGUI), then systemd
# time synchronization, followed by ntpd/ntpdate. A failed sync is a warning,
# not a fatal error, so offline bootstrap work remains possible.
sync_system_clock() {
    local synced=no
    local i=0
    local -a root_cmd=()

    [ "${BFS_TIME_SYNC:-yes}" = yes ] || {
        printf 'Automatic time synchronization disabled (BFS_TIME_SYNC=%s).\n' \
            "${BFS_TIME_SYNC:-no}"
        return 0
    }

    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            root_cmd=(sudo --)
        else
            echo "WARNING: Cannot synchronize the clock: root privileges/sudo are unavailable." >&2
            echo "WARNING: Verify the clock before building packages: $(date)" >&2
            return 0
        fi
    fi

    printf '\nSynchronizing system clock...\n'

    if command -v chronyd >/dev/null 2>&1; then
        if "${root_cmd[@]}" chronyd -q; then
            synced=yes
            printf 'System clock synchronized with chronyd.\n'
        fi
    fi

    if [ "$synced" != yes ] &&
       command -v timedatectl >/dev/null 2>&1 &&
       [ -d /run/systemd/system ]; then
        if "${root_cmd[@]}" timedatectl set-ntp true >/dev/null 2>&1; then
            i=0
            while [ "$i" -lt 15 ]; do
                if [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)" = yes ]; then
                    synced=yes
                    printf 'System clock synchronized with systemd time synchronization.\n'
                    break
                fi
                sleep 1
                i=$((i + 1))
            done
        fi
    fi

    if [ "$synced" != yes ] && command -v ntpd >/dev/null 2>&1; then
        if "${root_cmd[@]}" ntpd -q -g; then
            synced=yes
            printf 'System clock synchronized with ntpd.\n'
        fi
    fi

    if [ "$synced" != yes ] && command -v ntpdate >/dev/null 2>&1; then
        if "${root_cmd[@]}" ntpdate -u pool.ntp.org; then
            synced=yes
            printf 'System clock synchronized with ntpdate.\n'
        fi
    fi

    if [ "$synced" != yes ]; then
        echo "WARNING: Automatic time synchronization was unavailable or failed." >&2
        echo "WARNING: Verify the clock before building packages: $(date)" >&2
    fi

    return 0
}

BOOTSTRAP_SETTINGS_FILE="$SCRIPT_DIR/.bfs-bootstrap-settings"
DIALOGRC_FILE=""
ORIGINAL_DIALOGRC="${DIALOGRC-}"
BFS_THEME="${BFS_BOOTSTRAP_THEME:-slackware}"
# Select the service manager at build time: systemd, openrc, or sysvinit.
BFS_INIT_SYSTEM="${BFS_INIT_SYSTEM-}"
BFS_INIT_SYSTEM_ENV="$BFS_INIT_SYSTEM"

BFS_BUILD_JOBS="auto"
BFS_BUILD_OPT="portable"
BFS_CCACHE="yes"
BFS_CCACHE_SIZE="auto"
BFS_KEEP_SOURCE_ARCHIVES="no"
# Integrity verification is secure-by-default.  Development builds may
# explicitly disable individual checks from Bootstrap Settings.
BFS_VERIFY_MD5="yes"
BFS_VERIFY_SIGNATURE="yes"
BFS_VERIFY_FOOTPRINT="yes"
BFS_BUILD_SETTINGS_CHANGED="no"

_resolve_ccache_size() {
    local requested="${BFS_CCACHE_SIZE:-auto}"
    local mem_kib=0 mem_gib=1

    if [ "$requested" != auto ]; then
        printf '%s\n' "$requested"
        return 0
    fi

    # BFSOS default policy:
    #   VM -> 20G
    #   bare metal -> physical RAM rounded down to GiB
    if command -v systemd-detect-virt >/dev/null 2>&1 &&
       systemd-detect-virt --quiet 2>/dev/null; then
        printf '%s\n' "20G"
        return 0
    fi

    if [ -r /proc/meminfo ]; then
        mem_kib="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || printf '0')"
    fi
    case "$mem_kib" in
        ''|*[!0-9]*) mem_kib=0 ;;
    esac
    if [ "$mem_kib" -gt 0 ]; then
        mem_gib=$((mem_kib / 1024 / 1024))
        [ "$mem_gib" -lt 1 ] && mem_gib=1
    fi
    printf '%sG\n' "$mem_gib"
}

_prepare_target_ccache() {
    local resolved_size=""

    [ "${BFS_CCACHE:-yes}" = yes ] || return 0

    resolved_size="$(_resolve_ccache_size)"
    mkdir -p "$LFS/var/cache/ccache"

    cat > "$LFS/var/cache/ccache/ccache.conf" <<EOF_CCACHE
# Managed by BFSOS bootstrap.
# ccache is intentionally disabled for Stage 1 and becomes active only after
# the BFSOS ccache package and /usr/lib/ccache compiler wrappers exist.
max_size = $resolved_size
EOF_CCACHE

    # Once the dedicated pkgmk account exists, keep the cache owned by it.
    if chroot "$LFS" /usr/bin/getent passwd pkgmk >/dev/null 2>&1; then
        chown -R 82:82 "$LFS/var/cache/ccache" 2>/dev/null || true
        chmod 0775 "$LFS/var/cache/ccache" 2>/dev/null || true
    fi

    printf 'BFSOS ccache policy: enabled after BFSOS ccache is installed; max size %s\n' \
        "$resolved_size"
}

_apply_build_settings() {
    local jobs="$BFS_BUILD_JOBS"
    [ "$jobs" = auto ] && jobs="$(nproc 2>/dev/null || echo 1)"
    export MAKEFLAGS="-j$jobs"
    case "$BFS_BUILD_OPT" in
        native) export CFLAGS="-O2 -march=native -mtune=native -pipe" ;;
        custom:*) export CFLAGS="${BFS_BUILD_OPT#custom:}" ;;
        *) export CFLAGS="-O2 -march=x86-64 -pipe" ;;
    esac
    export CXXFLAGS="$CFLAGS"

    # Do NOT prepend /usr/lib/ccache here.  bootstrap.sh initially runs in a
    # foreign live environment, and Stage 1 must never pick up host ccache
    # wrappers.  Stage 2/3 enable BFSOS ccache from pkgmk.conf only after the
    # target's own /usr/bin/ccache and /usr/lib/ccache wrappers exist.
}

load_bootstrap_settings() {
    BFS_THEME="${BFS_BOOTSTRAP_THEME:-slackware}"
    BFS_INIT_SYSTEM="${BFS_INIT_SYSTEM-}"
    if [ -r "$BOOTSTRAP_SETTINGS_FILE" ]; then
        # shellcheck disable=SC1090
        . "$BOOTSTRAP_SETTINGS_FILE"
    fi
    if [ -r "$SCRIPT_DIR/.bfs-init-profile" ]; then
        # shellcheck disable=SC1090
        . "$SCRIPT_DIR/.bfs-init-profile"
    fi
    [ -n "$BFS_INIT_SYSTEM_ENV" ] && BFS_INIT_SYSTEM="$BFS_INIT_SYSTEM_ENV"
    [ -n "$BFS_INIT_SYSTEM" ] || BFS_INIT_SYSTEM=systemd
    _apply_build_settings
}

save_bootstrap_settings() {
    cat > "$BOOTSTRAP_SETTINGS_FILE" <<EOF_SETTINGS
BFS_BUILD_JOBS='$BFS_BUILD_JOBS'
BFS_BUILD_OPT='$BFS_BUILD_OPT'
BFS_CCACHE='$BFS_CCACHE'
BFS_CCACHE_SIZE='$BFS_CCACHE_SIZE'
BFS_KEEP_SOURCE_ARCHIVES='$BFS_KEEP_SOURCE_ARCHIVES'
BFS_VERIFY_MD5='$BFS_VERIFY_MD5'
BFS_VERIFY_SIGNATURE='$BFS_VERIFY_SIGNATURE'
BFS_VERIFY_FOOTPRINT='$BFS_VERIFY_FOOTPRINT'
BFS_BUILD_SETTINGS_CHANGED='$BFS_BUILD_SETTINGS_CHANGED'
BFS_INIT_SYSTEM='$BFS_INIT_SYSTEM'
EOF_SETTINGS
    _apply_build_settings
}

compiler_build_settings_menu() {
    local choice="" status=0 value="" current_flags=""

    while true; do
        if command -v dialog >/dev/null 2>&1 &&
           [ -r /dev/tty ] &&
           [ -w /dev/tty ]; then
            set +e
            choice="$(
                dialog --stdout --clear \
                    --backtitle "BFS Linux Bootstrap" \
                    --title "Compiler / Build Settings" \
                    --ok-label "Select" \
                    --cancel-label "Back" \
                    --menu \
                    "Current settings:\n\nJobs: $BFS_BUILD_JOBS\nOptimization: $BFS_BUILD_OPT\nccache: $BFS_CCACHE\nccache size: $BFS_CCACHE_SIZE\nKeep source archives: $BFS_KEEP_SOURCE_ARCHIVES\nMD5 verification: $BFS_VERIFY_MD5\nSignature verification: $BFS_VERIFY_SIGNATURE\nFootprint verification: $BFS_VERIFY_FOOTPRINT" \
                    27 86 12 \
                    jobs "Parallel build jobs" \
                    optimization "Compiler optimization policy" \
                    ccache "Enable or disable ccache" \
                    ccache-size "Configure ccache maximum size" \
                    source-cache "Keep downloaded source archives in base archive" \
                    verify-md5 "Verify source MD5/checksums" \
                    verify-signature "Verify source signatures" \
                    verify-footprint "Verify package footprints" \
                    defaults "Restore BFSOS build defaults" \
                    </dev/tty 2>/dev/tty
            )"
            status=$?
            set -e
            [ "$status" -eq 0 ] || return 0

            case "$choice" in
                jobs)
                    set +e
                    value="$(
                        dialog --stdout --clear \
                            --backtitle "BFS Linux Bootstrap" \
                            --title "Parallel Build Jobs" \
                            --ok-label "Apply" \
                            --cancel-label "Back" \
                            --inputbox \
                            "Enter auto or a positive job count.\n\nCurrent: $BFS_BUILD_JOBS" \
                            12 66 "$BFS_BUILD_JOBS" \
                            </dev/tty 2>/dev/tty
                    )"
                    status=$?
                    set -e
                    [ "$status" -eq 0 ] || continue
                    case "$value" in
                        auto) BFS_BUILD_JOBS=auto ;;
                        ''|*[!0-9]*)
                            dialog --clear --backtitle "BFS Linux Bootstrap" \
                                --title "Invalid job count" \
                                --msgbox "Use auto or a positive integer." 8 50 \
                                </dev/tty >/dev/tty 2>&1 || true
                            continue
                            ;;
                        0)
                            dialog --clear --backtitle "BFS Linux Bootstrap" \
                                --title "Invalid job count" \
                                --msgbox "Job count must be greater than zero." 8 50 \
                                </dev/tty >/dev/tty 2>&1 || true
                            continue
                            ;;
                        *) BFS_BUILD_JOBS="$value" ;;
                    esac
                    ;;
                optimization)
                    set +e
                    value="$(
                        dialog --stdout --clear \
                            --backtitle "BFS Linux Bootstrap" \
                            --title "Compiler Optimization" \
                            --ok-label "Apply" \
                            --cancel-label "Back" \
                            --radiolist \
                            "Choose the compiler optimization policy." \
                            18 82 5 \
                            portable "Portable BFSOS x86_64 defaults" \
                                "$([ "$BFS_BUILD_OPT" = portable ] && echo on || echo off)" \
                            native "Optimize for this CPU (-march=native)" \
                                "$([ "$BFS_BUILD_OPT" = native ] && echo on || echo off)" \
                            custom "Enter custom CFLAGS/CXXFLAGS" \
                                "$([[ "$BFS_BUILD_OPT" = custom:* ]] && echo on || echo off)" \
                            </dev/tty 2>/dev/tty
                    )"
                    status=$?
                    set -e
                    [ "$status" -eq 0 ] || continue
                    case "$value" in
                        portable|native)
                            BFS_BUILD_OPT="$value"
                            ;;
                        custom)
                            current_flags=""
                            [[ "$BFS_BUILD_OPT" = custom:* ]] && current_flags="${BFS_BUILD_OPT#custom:}"
                            set +e
                            value="$(
                                dialog --stdout --clear \
                                    --backtitle "BFS Linux Bootstrap" \
                                    --title "Custom Compiler Flags" \
                                    --ok-label "Apply" \
                                    --cancel-label "Back" \
                                    --inputbox \
                                    "Enter the complete CFLAGS/CXXFLAGS value." \
                                    11 82 "$current_flags" \
                                    </dev/tty 2>/dev/tty
                            )"
                            status=$?
                            set -e
                            [ "$status" -eq 0 ] || continue
                            [ -n "$value" ] || continue
                            BFS_BUILD_OPT="custom:$value"
                            ;;
                    esac
                    ;;
                ccache)
                    set +e
                    if dialog --clear \
                        --backtitle "BFS Linux Bootstrap" \
                        --title "ccache" \
                        --yes-label "Enable" \
                        --no-label "Disable" \
                        --yesno \
                        "Enable ccache for applicable BFSOS package builds?\n\nCurrent: $BFS_CCACHE" \
                        11 66 </dev/tty >/dev/tty 2>&1; then
                        BFS_CCACHE=yes
                        status=0
                    else
                        status=$?
                        [ "$status" -eq 1 ] && BFS_CCACHE=no
                    fi
                    set -e
                    [ "$status" -le 1 ] || continue
                    ;;
                ccache-size)
                    set +e
                    value="$(
                        dialog --stdout --clear \
                            --backtitle "BFS Linux Bootstrap" \
                            --title "ccache Size" \
                            --ok-label "Apply" \
                            --cancel-label "Back" \
                            --inputbox \
                            "Enter auto or a ccache size such as 20G, 64G, or 500M.\n\nCurrent: $BFS_CCACHE_SIZE" \
                            12 72 "$BFS_CCACHE_SIZE" \
                            </dev/tty 2>/dev/tty
                    )"
                    status=$?
                    set -e
                    [ "$status" -eq 0 ] || continue
                    [ -n "$value" ] || continue
                    BFS_CCACHE_SIZE="$value"
                    ;;
                source-cache)
                    set +e
                    if dialog --clear \
                        --backtitle "BFS Linux Bootstrap" \
                        --title "Base Source Cache" \
                        --yes-label "Keep" \
                        --no-label "Exclude" \
                        --yesno \
                        "Keep downloaded source archives under /var/cache/pkg/sources in the generated base archive?\n\nCurrent: $BFS_KEEP_SOURCE_ARCHIVES" \
                        12 76 </dev/tty >/dev/tty 2>&1; then
                        BFS_KEEP_SOURCE_ARCHIVES=yes
                        status=0
                    else
                        status=$?
                        [ "$status" -eq 1 ] && BFS_KEEP_SOURCE_ARCHIVES=no
                    fi
                    set -e
                    [ "$status" -le 1 ] || continue
                    ;;
                verify-md5)
                    if [ "$BFS_VERIFY_MD5" = yes ]; then BFS_VERIFY_MD5=no; else BFS_VERIFY_MD5=yes; fi
                    ;;
                verify-signature)
                    if [ "$BFS_VERIFY_SIGNATURE" = yes ]; then BFS_VERIFY_SIGNATURE=no; else BFS_VERIFY_SIGNATURE=yes; fi
                    ;;
                verify-footprint)
                    if [ "$BFS_VERIFY_FOOTPRINT" = yes ]; then BFS_VERIFY_FOOTPRINT=no; else BFS_VERIFY_FOOTPRINT=yes; fi
                    ;;
                defaults)
                    set +e
                    if dialog --clear \
                        --backtitle "BFS Linux Bootstrap" \
                        --title "Restore Build Defaults" \
                        --yes-label "Restore" \
                        --no-label "Cancel" \
                        --yesno \
                        "Restore BFSOS build defaults?\n\nJobs: auto\nOptimization: portable\nccache: yes\nccache size: auto" \
                        13 66 </dev/tty >/dev/tty 2>&1; then
                        BFS_BUILD_JOBS=auto
                        BFS_BUILD_OPT=portable
                        BFS_CCACHE=yes
                        BFS_CCACHE_SIZE=auto
                        BFS_KEEP_SOURCE_ARCHIVES=no
                        BFS_VERIFY_MD5=yes
                        BFS_VERIFY_SIGNATURE=yes
                        BFS_VERIFY_FOOTPRINT=yes
                    fi
                    set -e
                    ;;
            esac

            BFS_BUILD_SETTINGS_CHANGED=yes
            save_bootstrap_settings
        else
            printf '\nCompiler / Build Settings\n=========================\n'
            printf '1) Build jobs           : %s\n' "$BFS_BUILD_JOBS"
            printf '2) Optimization         : %s\n' "$BFS_BUILD_OPT"
            printf '3) ccache               : %s\n' "$BFS_CCACHE"
            printf '4) ccache size          : %s\n' "$BFS_CCACHE_SIZE"
            printf '5) Keep source archives : %s\n' "$BFS_KEEP_SOURCE_ARCHIVES"
            printf '6) Verify MD5/checksums   : %s\n' "$BFS_VERIFY_MD5"
            printf '7) Verify signatures     : %s\n' "$BFS_VERIFY_SIGNATURE"
            printf '8) Verify footprints     : %s\n' "$BFS_VERIFY_FOOTPRINT"
            printf '9) Restore defaults\n'
            printf '10) Back\n'
            printf 'Choose [1-10]: '
            read -r choice </dev/tty 2>/dev/null || read -r choice
            case "$choice" in
                1)
                    printf 'Jobs [auto or number]: '
                    read -r value
                    [ -z "$value" ] || BFS_BUILD_JOBS="$value"
                    ;;
                2)
                    printf 'Optimization [portable/native/custom]: '
                    read -r value
                    case "$value" in
                        portable|native) BFS_BUILD_OPT="$value" ;;
                        custom)
                            printf 'CFLAGS: '
                            read -r value
                            [ -z "$value" ] || BFS_BUILD_OPT="custom:$value"
                            ;;
                    esac
                    ;;
                3)
                    printf 'ccache [yes/no]: '
                    read -r value
                    case "$value" in yes|no) BFS_CCACHE="$value" ;; esac
                    ;;
                4)
                    printf 'ccache size [auto/20G/etc.]: '
                    read -r value
                    [ -z "$value" ] || BFS_CCACHE_SIZE="$value"
                    ;;
                5)
                    printf 'keep source archives in base [yes/no]: '
                    read -r value
                    case "$value" in yes|no) BFS_KEEP_SOURCE_ARCHIVES="$value" ;; esac
                    ;;
                6) case "$BFS_VERIFY_MD5" in yes) BFS_VERIFY_MD5=no ;; *) BFS_VERIFY_MD5=yes ;; esac ;;
                7) case "$BFS_VERIFY_SIGNATURE" in yes) BFS_VERIFY_SIGNATURE=no ;; *) BFS_VERIFY_SIGNATURE=yes ;; esac ;;
                8) case "$BFS_VERIFY_FOOTPRINT" in yes) BFS_VERIFY_FOOTPRINT=no ;; *) BFS_VERIFY_FOOTPRINT=yes ;; esac ;;
                9)
                    BFS_BUILD_JOBS=auto
                    BFS_BUILD_OPT=portable
                    BFS_CCACHE=yes
                    BFS_CCACHE_SIZE=auto
                    BFS_KEEP_SOURCE_ARCHIVES=no
                    BFS_VERIFY_MD5=yes
                    BFS_VERIFY_SIGNATURE=yes
                    BFS_VERIFY_FOOTPRINT=yes
                    ;;
                10|"") return 0 ;;
                *) continue ;;
            esac
            BFS_BUILD_SETTINGS_CHANGED=yes
            save_bootstrap_settings
        fi
    done
}

integrity_verification_settings_menu() {
    local choice=""

    while true; do
        if command -v dialog >/dev/null 2>&1 &&
           [ -r /dev/tty ] && [ -w /dev/tty ]; then
            if ! choice="$(
                dialog --stdout --clear \
                    --backtitle "BFS Linux Bootstrap" \
                    --title "Integrity Verification" \
                    --ok-label "Select" \
                    --cancel-label "Back" \
                    --menu \
                    "Verification is secure-by-default. Disable individual checks only for deliberate development/testing.\n\nMD5/checksums: $BFS_VERIFY_MD5\nSignatures: $BFS_VERIFY_SIGNATURE\nFootprints: $BFS_VERIFY_FOOTPRINT" \
                    19 88 7 \
                    md5 "Verify source MD5/checksums" \
                    signature "Verify source signatures" \
                    footprint "Verify package footprints" \
                    defaults "Restore secure defaults (all enabled)" \
                    </dev/tty 2>/dev/tty
            )"; then
                return 0
            fi

            case "$choice" in
                md5) case "$BFS_VERIFY_MD5" in yes) BFS_VERIFY_MD5=no ;; *) BFS_VERIFY_MD5=yes ;; esac ;;
                signature) case "$BFS_VERIFY_SIGNATURE" in yes) BFS_VERIFY_SIGNATURE=no ;; *) BFS_VERIFY_SIGNATURE=yes ;; esac ;;
                footprint) case "$BFS_VERIFY_FOOTPRINT" in yes) BFS_VERIFY_FOOTPRINT=no ;; *) BFS_VERIFY_FOOTPRINT=yes ;; esac ;;
                defaults)
                    BFS_VERIFY_MD5=yes
                    BFS_VERIFY_SIGNATURE=yes
                    BFS_VERIFY_FOOTPRINT=yes
                    ;;
                *) continue ;;
            esac
        else
            printf '\nIntegrity Verification\n======================\n'
            printf '1) Verify MD5/checksums : %s\n' "$BFS_VERIFY_MD5"
            printf '2) Verify signatures   : %s\n' "$BFS_VERIFY_SIGNATURE"
            printf '3) Verify footprints   : %s\n' "$BFS_VERIFY_FOOTPRINT"
            printf '4) Restore secure defaults\n'
            printf '5) Back\n'
            printf 'Choose [1-5]: '
            read -r choice </dev/tty 2>/dev/null || read -r choice
            case "$choice" in
                1) case "$BFS_VERIFY_MD5" in yes) BFS_VERIFY_MD5=no ;; *) BFS_VERIFY_MD5=yes ;; esac ;;
                2) case "$BFS_VERIFY_SIGNATURE" in yes) BFS_VERIFY_SIGNATURE=no ;; *) BFS_VERIFY_SIGNATURE=yes ;; esac ;;
                3) case "$BFS_VERIFY_FOOTPRINT" in yes) BFS_VERIFY_FOOTPRINT=no ;; *) BFS_VERIFY_FOOTPRINT=yes ;; esac ;;
                4)
                    BFS_VERIFY_MD5=yes
                    BFS_VERIFY_SIGNATURE=yes
                    BFS_VERIFY_FOOTPRINT=yes
                    ;;
                5|"") return 0 ;;
                *) continue ;;
            esac
        fi

        BFS_BUILD_SETTINGS_CHANGED=yes
        save_bootstrap_settings
    done
}

write_dialog_theme_classic() {
    cat > "$DIALOGRC_FILE" <<'EOF_DIALOGRC'
use_colors = ON
use_shadow = ON

# Classic Debian installer-inspired palette, translated from cdebconf/newt:
# newt default root is white-on-blue; windows are black-on-lightgray;
# titles are red-on-lightgray; selected list entries use yellow-on-blue.
screen_color = (WHITE,BLUE,OFF)
shadow_color = (WHITE,BLACK,OFF)
dialog_color = (BLACK,WHITE,OFF)
title_color = (RED,WHITE,ON)
border_color = (BLACK,WHITE,OFF)

button_active_color = (RED,WHITE,ON)
button_inactive_color = (BLACK,WHITE,OFF)
button_key_active_color = (RED,WHITE,ON)
button_key_inactive_color = (BLACK,WHITE,ON)
button_label_active_color = (RED,WHITE,ON)
button_label_inactive_color = (BLACK,WHITE,OFF)

inputbox_color = (YELLOW,BLUE,OFF)
inputbox_border_color = (BLACK,WHITE,OFF)
searchbox_color = (BLACK,WHITE,OFF)
searchbox_title_color = (RED,WHITE,ON)
searchbox_border_color = (BLACK,WHITE,OFF)

position_indicator_color = (YELLOW,BLUE,ON)
menubox_color = (BLACK,WHITE,OFF)
menubox_border_color = (BLACK,WHITE,OFF)
item_color = (BLACK,WHITE,OFF)
item_selected_color = (YELLOW,BLUE,ON)
tag_color = (RED,WHITE,ON)
tag_selected_color = (YELLOW,BLUE,ON)
tag_key_color = (RED,WHITE,ON)
tag_key_selected_color = (YELLOW,BLUE,ON)

check_color = (YELLOW,BLUE,OFF)
check_selected_color = (BLACK,WHITE,ON)
uarrow_color = (RED,WHITE,ON)
darrow_color = (RED,WHITE,ON)
gauge_color = (YELLOW,BLUE,ON)
EOF_DIALOGRC
}

write_dialog_theme_midnight() {
    cat > "$DIALOGRC_FILE" <<'EOF_DIALOGRC'
use_colors = ON
use_shadow = OFF
screen_color = (WHITE,BLACK,ON)
dialog_color = (BLACK,CYAN,ON)
title_color = (YELLOW,CYAN,ON)
border_color = (WHITE,CYAN,ON)
button_active_color = (WHITE,BLUE,ON)
button_inactive_color = (BLACK,CYAN,ON)
menubox_color = (BLACK,CYAN,ON)
menubox_border_color = (WHITE,CYAN,ON)
item_color = (BLACK,CYAN,ON)
item_selected_color = (WHITE,BLUE,ON)
tag_color = (YELLOW,CYAN,ON)
tag_selected_color = (YELLOW,BLUE,ON)
EOF_DIALOGRC
}

write_dialog_theme_light() {
    cat > "$DIALOGRC_FILE" <<'EOF_DIALOGRC'
use_colors = ON
use_shadow = OFF
screen_color = (BLACK,WHITE,ON)
dialog_color = (BLACK,WHITE,ON)
title_color = (BLUE,WHITE,ON)
border_color = (BLUE,WHITE,ON)
button_active_color = (WHITE,BLUE,ON)
button_inactive_color = (BLACK,WHITE,ON)
menubox_color = (BLACK,WHITE,ON)
menubox_border_color = (BLUE,WHITE,ON)
item_color = (BLACK,WHITE,ON)
item_selected_color = (WHITE,BLUE,ON)
tag_color = (BLUE,WHITE,ON)
tag_selected_color = (YELLOW,BLUE,ON)
EOF_DIALOGRC
}

write_dialog_theme_slackware() {
    cat > "$DIALOGRC_FILE" <<'EOF_DIALOGRC'
aspect = 0
separate_widget = ""
tab_len = 0
visit_items = OFF
use_scrollbar = OFF
use_shadow = ON
use_colors = ON

# Slackware's actual dialogrc palette.
screen_color = (WHITE,BLUE,OFF)
shadow_color = (WHITE,BLACK,OFF)
dialog_color = (BLACK,CYAN,OFF)
title_color = (YELLOW,CYAN,ON)
border_color = (CYAN,CYAN,ON)

button_active_color = (WHITE,BLUE,ON)
button_inactive_color = dialog_color
button_key_active_color = button_active_color
button_key_inactive_color = (RED,CYAN,OFF)
button_label_active_color = button_active_color
button_label_inactive_color = (BLACK,CYAN,ON)

inputbox_color = (BLUE,WHITE,OFF)
inputbox_border_color = border_color
searchbox_color = (YELLOW,WHITE,ON)
searchbox_title_color = (WHITE,WHITE,ON)
searchbox_border_color = (RED,WHITE,OFF)

position_indicator_color = button_key_inactive_color
menubox_color = dialog_color
menubox_border_color = border_color
item_color = dialog_color
item_selected_color = screen_color
tag_color = title_color
tag_selected_color = screen_color
tag_key_color = button_key_inactive_color
tag_key_selected_color = (RED,BLUE,ON)

check_color = dialog_color
check_selected_color = (WHITE,CYAN,ON)
uarrow_color = (GREEN,CYAN,ON)
darrow_color = uarrow_color
itemhelp_color = shadow_color
form_active_text_color = inputbox_color
form_text_color = (CYAN,BLUE,ON)
form_item_readonly_color = (CYAN,WHITE,ON)
gauge_color = (BLUE,WHITE,ON)

border2_color = dialog_color
inputbox_border2_color = dialog_color
searchbox_border2_color = dialog_color
menubox_border2_color = dialog_color
EOF_DIALOGRC
}

write_dialog_theme_monochrome() {
    cat > "$DIALOGRC_FILE" <<'EOF_DIALOGRC'
use_colors = OFF
use_shadow = OFF
EOF_DIALOGRC
}

theme_display_name() {
    case "$BFS_THEME" in
        classic) printf '%s' "Classic Debian" ;;
        midnight) printf '%s' "Midnight" ;;
        slackware) printf '%s' "Classic Slackware" ;;
        light) printf '%s' "Light" ;;
        monochrome) printf '%s' "Monochrome" ;;
        *) printf '%s' "$BFS_THEME" ;;
    esac
}

setup_bootstrap_theme() {
    [ -z "$DIALOGRC_FILE" ] || rm -f "$DIALOGRC_FILE"
    DIALOGRC_FILE="$(mktemp /tmp/bfs-bootstrap-dialogrc.XXXXXX)"

    case "$BFS_THEME" in
        classic) write_dialog_theme_classic ;;
        midnight) write_dialog_theme_midnight ;;
        slackware) write_dialog_theme_slackware ;;
        light) write_dialog_theme_light ;;
        monochrome) write_dialog_theme_monochrome ;;
        *) BFS_THEME=slackware; write_dialog_theme_slackware ;;
    esac

    export DIALOGRC="$DIALOGRC_FILE"
}

select_bootstrap_theme() {
    local choice="" status=0

    if command -v dialog >/dev/null 2>&1 &&
       [ -r /dev/tty ] &&
       [ -w /dev/tty ]
    then
        set +e
        choice="$(
            dialog --stdout --clear \
                --backtitle "BFS Linux Bootstrap" \
                --title "Interface Theme" \
                --cancel-label "Back" \
                --radiolist \
                "Choose the bootstrap theme." \
                20 78 7 \
                Slackware "Classic Slackware setup-style cyan theme (default)" \
                    "$([ "$BFS_THEME" = slackware ] && echo on || echo off)" \
                Debian "Classic Debian installer/newt-style theme" \
                    "$([ "$BFS_THEME" = classic ] && echo on || echo off)" \
                monochrome "Best compatibility for SSH and unusual palettes" \
                    "$([ "$BFS_THEME" = monochrome ] && echo on || echo off)" \
                Midnight "Midnight Commander-style theme" \
                    "$([ "$BFS_THEME" = midnight ] && echo on || echo off)" \
                Light "Black text on a light background" \
                    "$([ "$BFS_THEME" = light ] && echo on || echo off)" \
                </dev/tty 2>/dev/tty
        )"
        status=$?
        set -e

        # Cancel/Back means return directly to Bootstrap Settings.
        [ "$status" -eq 0 ] || return 0
        [ -n "$choice" ] || return 0
    else
        echo "  1) Classic Slackware (default)"
        echo "  2) Classic Debian"
        echo "  3) Monochrome"
        echo "  4) Midnight"
        echo "  5) Light"
        echo "  6) Back"
        read -r -p "Choose [1-6, current: $(theme_display_name)]: " choice
        case "$choice" in
            1) choice=slackware ;;
            2) choice=classic ;;
            3) choice=monochrome ;;
            4) choice=midnight ;;
            5) choice=light ;;
            6|"") return 0 ;;
            *) echo "Invalid theme selection."; return 0 ;;
        esac
    fi

    case "$choice" in
        Slackware) choice=slackware ;;
        Debian) choice=classic ;;
        Monochrome) choice=monochrome ;;
        Midnight) choice=midnight ;;
        Light) choice=light ;;
    esac

    BFS_THEME="$choice"
    setup_bootstrap_theme
    save_bootstrap_settings
    return 0
}

bootstrap_theme_settings_menu() {
    local choice="" status=0

    while true; do
        if command -v dialog >/dev/null 2>&1 &&
           [ -r /dev/tty ] &&
           [ -w /dev/tty ]
        then
            set +e
            choice="$(
                dialog --stdout --clear \
                    --backtitle "BFS Linux Bootstrap" \
                    --title "Bootstrap Settings - Interface Theme" \
                    --ok-label "Apply" \
                    --cancel-label "Back" \
                    --radiolist \
                    "Choose the bootstrap interface theme." \
                    20 82 7 \
                    Slackware "Classic Slackware setup-style cyan theme (default)" \
                        "$([ "$BFS_THEME" = slackware ] && echo on || echo off)" \
                    Debian "Classic Debian installer/newt-style theme" \
                        "$([ "$BFS_THEME" = classic ] && echo on || echo off)" \
                    Monochrome "Monochrome - best compatibility for unusual terminals" \
                        "$([ "$BFS_THEME" = monochrome ] && echo on || echo off)" \
                    Midnight "Midnight Commander-style theme" \
                        "$([ "$BFS_THEME" = midnight ] && echo on || echo off)" \
                    Light "Black text on a light background" \
                        "$([ "$BFS_THEME" = light ] && echo on || echo off)" \
                    </dev/tty 2>/dev/tty
            )"
            status=$?
            set -e

            # Back/Esc returns immediately to the main bootstrap menu.
            [ "$status" -eq 0 ] || return 0
            [ -n "$choice" ] || return 0
        else
            clear 2>/dev/null || true
            echo "Bootstrap Settings - Interface Theme"
            echo "===================================="
            echo
            echo "  1) Classic Slackware (default)"
            echo "  2) Classic Debian"
            echo "  3) Monochrome"
            echo "  4) Midnight"
            echo "  5) Light"
            echo "  6) Back to main menu"
            echo
            read -r -p "Choose [1-6, current: $(theme_display_name)]: " choice
            case "$choice" in
                1) choice=slackware ;;
                2) choice=classic ;;
                3) choice=monochrome ;;
                4) choice=midnight ;;
                5) choice=light ;;
                6|"") return 0 ;;
                *) continue ;;
            esac
        fi

        case "$choice" in
            Slackware) choice=slackware ;;
            Debian) choice=classic ;;
            Monochrome) choice=monochrome ;;
            Midnight) choice=midnight ;;
            Light) choice=light ;;
        esac

        BFS_THEME="$choice"
        setup_bootstrap_theme

        # Keep the user in Settings so another theme can be previewed.
        # Back returns to the main menu with no success/pause screen.
    done
}


bootstrap_settings_menu() {
    local choice="" status=0

    while true; do
        if command -v dialog >/dev/null 2>&1 &&
           [ -r /dev/tty ] &&
           [ -w /dev/tty ]; then
            set +e
            choice="$(
                dialog --stdout --clear \
                    --backtitle "BFS Linux Bootstrap" \
                    --title "Bootstrap Settings" \
                    --ok-label "Select" \
                    --cancel-label "Back" \
                    --menu \
                    "Choose a settings category." \
                    17 76 7 \
                    1 "Interface theme" \
                    2 "Compiler / build settings" \
                    3 "Integrity verification" \
                    </dev/tty 2>/dev/tty
            )"
            status=$?
            set -e
            [ "$status" -eq 0 ] || return 0
        else
            clear 2>/dev/null || true
            echo "Bootstrap Settings"
            echo "  1) Interface theme"
            echo "  2) Compiler / build settings"
            echo "  3) Integrity verification"
            echo "  4) Back"
            printf "Choose [1-4]: "
            read -r choice </dev/tty 2>/dev/null || read -r choice
        fi

        case "$choice" in
            1) bootstrap_theme_settings_menu ;;
            2) compiler_build_settings_menu ;;
            3) integrity_verification_settings_menu ;;
            4|"") return 0 ;;
            *) continue ;;
        esac
    done
}

case "${1:-menu}" in
    0|stop|kill|-h|--help|help) ;;
    *)
        # Synchronize once for a top-level bootstrap invocation.  Root stages
        # launched from the interactive menu inherit BFS_SKIP_TIME_SYNC=yes so
        # sudo/subprocess re-entry does not synchronize the clock again.
        if [ "${BFS_SKIP_TIME_SYNC:-no}" != yes ]; then
            sync_system_clock
        fi
        ;;
esac

load_bootstrap_settings
setup_bootstrap_theme

LOG_DIR="$SCRIPT_DIR/logs"
TOOLCHAIN_LOG_DIR="$LOG_DIR/toolchain"
BASE_LOG_DIR="$LOG_DIR/base"

ACTIVE_LOG_FILE=""
ACTIVE_LOG_FIFO=""
ACTIVE_LOG_TEE_PID=""
ACTIVE_LOG_STDOUT_FD=7
ACTIVE_LOG_STDERR_FD=8
CURRENT_BASE_LOGS=()
STAGE_OPERATION_STARTED_EPOCH=0
LAST_FAILED_LOG_FILE=""
STAGE_PREFLIGHT_LOG=""

mkdir -p "$TOOLCHAIN_LOG_DIR" "$BASE_LOG_DIR"

if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ]; then
    COLOR_RED=$'\033[1;31m'
    COLOR_GREEN=$'\033[1;32m'
    COLOR_YELLOW=$'\033[1;33m'
    COLOR_CYAN=$'\033[1;36m'
    COLOR_BOLD_WHITE=$'\033[1;37m'
    COLOR_RESET=$'\033[0m'
else
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_CYAN=""
    COLOR_BOLD_WHITE=""
    COLOR_RESET=""
fi

_sanitize_log_name() {
    local name="$1"

    name="${name//[^a-zA-Z0-9_.+-]/-}"
    printf '%s\n' "$name"
}

_start_stage_preflight_log() {
    local stage="$1" directory="" timestamp=""

    case "$stage" in
        1) directory="$TOOLCHAIN_LOG_DIR" ;;
        2|3|4|5) directory="$BASE_LOG_DIR" ;;
        *) directory="$LOG_DIR" ;;
    esac

    mkdir -p "$directory" || return 1
    timestamp="$(date +%Y%m%d-%H%M%S)"
    STAGE_PREFLIGHT_LOG="$directory/stage${stage}-preflight-${timestamp}.log"
    : > "$STAGE_PREFLIGHT_LOG" || return 1

    # Until a package-specific log replaces this pointer, a pre-package failure
    # must show this transcript rather than the useless 'no package log' text.
    LAST_FAILED_LOG_FILE="$STAGE_PREFLIGHT_LOG"

    {
        printf '============================================================\n'
        printf 'BFS bootstrap Stage %s preflight\n' "$stage"
        printf 'Started: %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
        printf 'User: %s (uid=%s gid=%s)\n' "$(id -un)" "$(id -u)" "$(id -g)"
        printf 'LFS: %s\n' "${LFS:-<unset>}"
        printf 'TOOLS: %s\n' "${TOOLS:-<unset>}"
        printf 'Project: %s\n' "$SCRIPT_DIR"
        printf '============================================================\n\n'
    } >> "$STAGE_PREFLIGHT_LOG"
}

_stage_preflight_note() {
    local message="$*"
    [ -z "${STAGE_PREFLIGHT_LOG:-}" ] || printf '%s\n' "$message" >> "$STAGE_PREFLIGHT_LOG"
    printf '%s\n' "$message" >&2
}

_close_active_package_log() {
    local status="${1:-0}"

    [ -n "$ACTIVE_LOG_FILE" ] || return 0

    printf '\nBuild finished: %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
    printf 'Exit status: %s\n' "$status"
    if [ "$status" -ne 0 ]; then
        LAST_FAILED_LOG_FILE="$ACTIVE_LOG_FILE"
    fi

    exec 1>&"$ACTIVE_LOG_STDOUT_FD" 2>&"$ACTIVE_LOG_STDERR_FD"
    exec 7>&- 8>&-

    if [ -n "$ACTIVE_LOG_TEE_PID" ]; then
        wait "$ACTIVE_LOG_TEE_PID" 2>/dev/null || true
    fi

    [ -z "$ACTIVE_LOG_FIFO" ] || rm -f "$ACTIVE_LOG_FIFO"

    ACTIVE_LOG_FILE=""
    ACTIVE_LOG_FIFO=""
    ACTIVE_LOG_TEE_PID=""
}

_start_package_log() {
    local phase="$1"
    local package="$2"
    local directory=""
    local safe_package=""
    local timestamp=""

    _close_active_package_log 0

    case "$phase" in
        toolchain) directory="$TOOLCHAIN_LOG_DIR" ;;
        base) directory="$BASE_LOG_DIR" ;;
        *)
            echo "ERROR: Unknown build-log phase: $phase" >&2
            return 1
            ;;
    esac

    mkdir -p "$directory"

    safe_package="$(_sanitize_log_name "$package")"
    timestamp="$(date +%Y%m%d-%H%M%S)"
    ACTIVE_LOG_FILE="$directory/${safe_package}-${timestamp}.log"
    ACTIVE_LOG_FIFO="$(mktemp -u /tmp/bfs-build-log.XXXXXX)"
    mkfifo "$ACTIVE_LOG_FIFO"

    exec 7>&1 8>&2
    tee -a "$ACTIVE_LOG_FILE" < "$ACTIVE_LOG_FIFO" >&7 &
    ACTIVE_LOG_TEE_PID=$!
    exec > "$ACTIVE_LOG_FIFO" 2>&1

    if [ "$phase" = base ]; then
        CURRENT_BASE_LOGS+=("$ACTIVE_LOG_FILE")
    fi

    printf '============================================================\n'
    printf 'BFS build phase: %s\n' "$phase"
    printf 'Package:         %s\n' "$package"
    printf 'Started:         %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
    printf 'Port:            %s\n' "$PWD"
    printf 'Log:             %s\n' "$ACTIVE_LOG_FILE"
    printf '============================================================\n\n'
}

_copy_base_logs_into_rootfs() {
    local destination="$LFS/var/log/bfs/bfs-build"
    local log_file=""

    mkdir -p "$destination"

    for log_file in "${CURRENT_BASE_LOGS[@]}"; do
        [ -f "$log_file" ] || continue
        install -m 0644 "$log_file" "$destination/"
    done

    echo
    echo "Base package logs copied to:"
    echo "  $destination"
}


_latest_rootfs_archive() {
    local file="" base="" key="" best="" best_key="" mtime=""
    [ -d "$BASE_ARCHIVE_DIR" ] || return 1
    while IFS= read -r -d '' file; do
        [ -r "$file" ] || continue
        case "$file" in *.tar.xz|*.tar.zst|*.tar.gz) ;; *) continue ;; esac
        base="$(basename "$file")"
        if [[ "$base" =~ ([0-9]{8})[-_]?([0-9]{6}) ]]; then
            key="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
        else
            mtime="$(stat -c '%Y' "$file" 2>/dev/null || printf '0')"
            printf -v key 'mtime-%020d' "$mtime"
        fi
        if [ -z "$best" ] || [[ "$key" > "$best_key" ]] ||
           { [ "$key" = "$best_key" ] && [[ "$file" > "$best" ]]; }; then
            best="$file"; best_key="$key"
        fi
    done < <(
        find "$BASE_ARCHIVE_DIR" -maxdepth 1 -type f \
            \( -name 'bfs-rootfs-*.tar.xz' -o -name 'bfs-rootfs-*.tar.zst' -o -name 'bfs-rootfs-*.tar.gz' \) \
            -print0 2>/dev/null
    )
    [ -n "$best" ] || return 1
    printf '%s\n' "$best"
}

_find_latest_installer() {
    local installer="$SCRIPT_DIR/scripts/install-bfs-menu-current.sh"

    # RC1 policy: there is one authoritative runtime installer entry point.
    # Historical revisions belong in Git and must never be selected at runtime
    # by filename sorting or mtime.
    [ -f "$installer" ] && [ -r "$installer" ] && [ -x "$installer" ] || {
        printf 'ERROR: Authoritative BFSOS installer is missing or not executable: %s\n' "$installer" >&2
        return 1
    }
    if ! bash -n "$installer" >/dev/null 2>&1; then
        printf 'ERROR: Authoritative BFSOS installer has shell syntax errors: %s\n' "$installer" >&2
        return 1
    fi
    printf '%s\n' "$installer"
}

_installer_available() {
    _latest_rootfs_archive >/dev/null 2>&1 && _find_latest_installer >/dev/null 2>&1
}

_launch_bfs_installer() {
    local archive="" installer="" status=0
    archive="$(_latest_rootfs_archive)" || {
        echo "ERROR: No valid BFSOS base rootfs archive is available in:" >&2
        echo "  $BASE_ARCHIVE_DIR" >&2
        return 1
    }
    installer="$(_find_latest_installer)" || {
        echo "ERROR: No executable BFSOS installer was found under:" >&2
        echo "  $SCRIPT_DIR/scripts" >&2
        return 1
    }
    local installer_mtime=""
    installer_mtime="$(stat -c '%y' "$installer" 2>/dev/null || printf 'unknown')"
    echo
    echo "Launching BFSOS installer:"
    echo "  Installer: $installer"
    echo "  Modified : $installer_mtime"
    echo "  Base file: $archive"
    echo
    set +e
    # bootstrap already synchronized the clock.  Preserve standalone installer
    # time synchronization while avoiding a redundant sync on this handoff.
    BFS_TIME_SYNC=no BFS_ARCHIVE="$archive" "$installer"
    status=$?
    set -e
    _reset_terminal_ui
    return "$status"
}

_launch_iso_builder() {
    local builder="$SCRIPT_DIR/scripts/bfs-build-iso.sh"
    local target_user="" target_home=""

    if [ ! -f "$builder" ] || [ ! -r "$builder" ]; then
        echo "ERROR: BFSOS ISO builder is missing or unreadable:" >&2
        echo "  $builder" >&2
        return 1
    fi

    # The ISO builder deliberately runs as a regular user and elevates only the
    # rootfs operations that need sudo.  If bootstrap itself was started with
    # sudo, hand the builder back to the original invoking user instead of
    # launching it as root (which the builder correctly refuses to do).
    if [ "$(id -u)" -eq 0 ]; then
        target_user="${SUDO_USER:-}"
        if [ -z "$target_user" ] || [ "$target_user" = root ]; then
            echo "ERROR: The ISO builder must run as a regular user." >&2
            echo "Run bootstrap as your normal user, or invoke it through sudo from that user." >&2
            return 1
        fi

        target_home="$(getent passwd "$target_user" 2>/dev/null | awk -F: 'NR == 1 { print $6 }')"
        if [ -z "$target_home" ] || [ ! -d "$target_home" ]; then
            echo "ERROR: Could not determine a valid home directory for ISO builder user: $target_user" >&2
            return 1
        fi

        sudo -u "$target_user" -- \
            env \
                HOME="$target_home" \
                USER="$target_user" \
                LOGNAME="$target_user" \
                BFS_ISO_ASSUME_YES="${BFS_ISO_ASSUME_YES:-}" \
                BFS_ISO_SKIP_BOOTSTRAP="${BFS_ISO_SKIP_BOOTSTRAP:-}" \
                BFS_ISO_WORK_DIR="${BFS_ISO_WORK_DIR:-}" \
                BFS_ISO_OUTPUT_DIR="${BFS_ISO_OUTPUT_DIR:-}" \
                BFS_ISO_KERNEL="${BFS_ISO_KERNEL:-}" \
                BFS_ISO_LIVE_MEDIA_WAIT="${BFS_ISO_LIVE_MEDIA_WAIT:-}" \
                BFS_KEEP_SOURCE_ARCHIVES="${BFS_KEEP_SOURCE_ARCHIVES:-}" \
                bash "$builder" "$@"
        return $?
    fi

    # Invoke through bash so the bootstrap handoff does not depend on the
    # executable bit surviving an archive extraction or source-tree copy.
    bash "$builder" "$@"
}

_confirm_full_bootstrap() {
    local status=0 answer=""
    local message="Full Bootstrap will run every build stage in order:\n\n  1. Temporary toolchain\n  2. Base system\n  3. Final-toolchain rebuild\n  4. Base verification\n  5. Base archive compression\n\nFull Bootstrap starts Stage 1 from a CLEAN build state. It removes old /tmp/lfs build trees, package/build-work contents, and previous BFS bootstrap archives. Downloaded source archives are retained.\n\nStage 3 is intentionally included even though it remains optional when stages are run manually.\n\nThe workflow stops immediately if any stage fails.\n\nStart Full Bootstrap now?"

    if [ "${BFS_FULL_BOOTSTRAP_ASSUME_YES:-no}" = yes ]; then
        return 0
    fi

    if command -v dialog >/dev/null 2>&1 &&
       [ -r /dev/tty ] && [ -w /dev/tty ]; then
        if dialog --clear \
            --backtitle "BFS Linux Bootstrap" \
            --title "Run Full Bootstrap" \
            --yes-label "Start" \
            --no-label "Cancel" \
            --defaultno \
            --yesno "$message" 23 88 </dev/tty >/dev/tty 2>&1; then
            return 0
        fi
        return 1
    fi

    printf '\n%s\n' "Full Bootstrap will run Stages 1 -> 2 -> 3 -> 4 -> 5 and stop on the first failure."
    printf 'Start Full Bootstrap? [y/N]: '
    read -r answer </dev/tty 2>/dev/null || read -r answer || true
    case "$answer" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

_finish_full_bootstrap() {
    local archive="" status=0 answer=""
    archive="$(_latest_rootfs_archive 2>/dev/null || true)"

    if [ "${BFS_FULL_BOOTSTRAP_NO_INSTALL_PROMPT:-no}" = yes ]; then
        printf '\nFull Bootstrap completed successfully.\n'
        printf 'Base archive: %s\n' "${archive:-<unknown>}"
        return 0
    fi

    if _installer_available; then
        if command -v dialog >/dev/null 2>&1 &&
           [ -r /dev/tty ] && [ -w /dev/tty ]; then
            if dialog --clear \
                --backtitle "BFS Linux Bootstrap" \
                --title "Full Bootstrap Complete" \
                --yes-label "Launch installer" \
                --no-label "Done" \
                --defaultno \
                --yesno \
                "Stages 1 through 5 completed successfully.\n\nBase archive:\n${archive:-<unknown>}\n\nLaunch the BFSOS installer now?" \
                17 82 </dev/tty >/dev/tty 2>&1; then
                status=0
            else
                status=$?
            fi
            _reset_terminal_ui
            if [ "$status" -eq 0 ]; then
                _launch_bfs_installer
                return $?
            fi
            return 0
        fi

        printf '\nFull Bootstrap completed successfully.\n'
        printf 'Base archive: %s\n' "${archive:-<unknown>}"
        printf 'Launch the BFSOS installer now? [y/N]: '
        read -r answer </dev/tty 2>/dev/null || read -r answer || true
        case "$answer" in
            y|Y|yes|YES|Yes) _launch_bfs_installer ;;
            *) return 0 ;;
        esac
        return $?
    fi

    _show_menu_success "Full Bootstrap Complete" \
        "Stages 1 through 5 completed successfully.\n\nBase archive:\n${archive:-<unknown>}\n\nNo usable installer is currently available, so Bootstrap will return to the main menu."
    return 0
}

_run_full_bootstrap() {
    local stage=0 status=0 label=""

    if [ "$(id -u)" -eq 0 ]; then
        echo "ERROR: Full Bootstrap must be started as a regular user because Stage 1 must not run as root." >&2
        return 1
    fi

    _confirm_full_bootstrap || return 0

    command -v sudo >/dev/null 2>&1 || {
        echo "ERROR: Full Bootstrap requires sudo for clean-start and root stages." >&2
        return 1
    }
    if ! sudo -v; then
        echo "ERROR: sudo authentication failed; Full Bootstrap was not started." >&2
        return 1
    fi

    echo
    echo "========================================"
    echo " BFS FULL BOOTSTRAP: STAGES 1 -> 5"
    echo "========================================"
    echo "Stage 3 final-toolchain rebuild is included."
    echo "Any failure stops the workflow immediately."
    echo

    for stage in 1 2 3 4 5; do
        case "$stage" in
            1) label="Temporary toolchain" ;;
            2) label="Base system" ;;
            3) label="Final-toolchain rebuild" ;;
            4) label="Base verification" ;;
            5) label="Base archive compression" ;;
        esac

        STAGE_OPERATION_STARTED_EPOCH="$(date +%s)"
        LAST_FAILED_LOG_FILE=""

        _show_menu_progress "Full Bootstrap - Stage $stage of 5" \
            "Running Stage $stage: $label\n\nThe workflow will continue automatically after this stage passes."
        _reset_terminal_ui

        case "$stage" in
            1)
                if BFS_FULL_BOOTSTRAP=yes BFS_MENU_STAGE=yes _buildtoolchain; then
                    status=0
                else
                    status=$?
                fi
                ;;
            2|3|4|5)
                if BFS_FULL_BOOTSTRAP=yes BFS_MENU_STAGE=yes _run_root_stage "$stage"; then
                    status=0
                else
                    status=$?
                fi
                ;;
        esac

        if [ "$status" -ne 0 ]; then
            echo
            echo "Full Bootstrap stopped: Stage $stage ($label) failed with status $status." >&2
            _show_stage_failure_dialog "$stage" "$status"
            return "$status"
        fi

        echo
        echo "Full Bootstrap: Stage $stage ($label) PASSED."
        echo
    done

    _reset_terminal_ui
    _finish_full_bootstrap
}

_next_resume_full_stage() {
    if _rootfs_archive_complete; then
        printf '%s\n' 6
    elif _verification_complete; then
        printf '%s\n' 5
    elif _base_stage3_complete; then
        printf '%s\n' 4
    elif _base_stage2_complete; then
        printf '%s\n' 3
    elif _toolchain_complete; then
        printf '%s\n' 2
    else
        printf '%s\n' 1
    fi
}

_run_resume_full_bootstrap() {
    local start=0 stage=0 status=0 label="" answer=""

    if [ "$(id -u)" -eq 0 ]; then
        echo "ERROR: Resume Full Bootstrap must be started as a regular user; root stages are elevated internally." >&2
        return 1
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        echo "ERROR: Resume Full Bootstrap requires sudo for root stages." >&2
        return 1
    fi
    if ! sudo -v; then
        echo "ERROR: sudo authentication failed; resume was not started." >&2
        return 1
    fi

    start="$(_next_resume_full_stage)"
    if [ "$start" -eq 1 ]; then
        echo "ERROR: No completed Stage-1 toolchain archive was found. Use Full Bootstrap for a clean 1 -> 5 build." >&2
        return 1
    fi
    if [ "$start" -gt 5 ]; then
        echo "Full Bootstrap is already complete; a base archive exists."
        _finish_full_bootstrap
        return $?
    fi

    if [ "${BFS_FULL_BOOTSTRAP_ASSUME_YES:-no}" != yes ]; then
        if command -v dialog >/dev/null 2>&1 && [ -r /dev/tty ] && [ -w /dev/tty ]; then
            if ! dialog --clear \
                --backtitle "BFS Linux Bootstrap" \
                --title "Resume Full Bootstrap" \
                --yes-label "Resume" --no-label "Cancel" --defaultno \
                --yesno "Resume the existing build at Stage $start and continue automatically through Stage 5?\n\nExisting successful work will be preserved. The workflow stops on the first failure." \
                14 78 </dev/tty >/dev/tty 2>&1; then
                return 0
            fi
        else
            printf 'Resume existing build at Stage %s and continue through Stage 5? [y/N]: ' "$start"
            read -r answer </dev/tty 2>/dev/null || read -r answer || true
            case "$answer" in y|Y|yes|YES|Yes) ;; *) return 0 ;; esac
        fi
    fi

    for ((stage=start; stage<=5; stage++)); do
        case "$stage" in
            2) label="Base system" ;;
            3) label="Final-toolchain rebuild" ;;
            4) label="Base verification" ;;
            5) label="Base archive compression" ;;
        esac

        STAGE_OPERATION_STARTED_EPOCH="$(date +%s)"
        LAST_FAILED_LOG_FILE=""
        _show_menu_progress "Resume Full Bootstrap - Stage $stage of 5" \
            "Running Stage $stage: $label\n\nExisting successful work is being preserved."
        _reset_terminal_ui

        if BFS_FULL_BOOTSTRAP=yes BFS_MENU_STAGE=yes _run_root_stage "$stage"; then
            status=0
        else
            status=$?
        fi

        if [ "$status" -ne 0 ]; then
            echo "Resume Full Bootstrap stopped: Stage $stage ($label) failed with status $status." >&2
            _show_stage_failure_dialog "$stage" "$status"
            return "$status"
        fi
        echo "Resume Full Bootstrap: Stage $stage ($label) PASSED."
    done

    _reset_terminal_ui
    _finish_full_bootstrap
}

_stage_complete_text() {
    if "$@"; then
        printf '%sCOMPLETE%s' "$COLOR_GREEN" "$COLOR_RESET"
    else
        printf '%sPENDING%s' "$COLOR_RED" "$COLOR_RESET"
    fi
}

_toolchain_complete() {
    _latest_archive "$TOOLCHAIN_ARCHIVE_DIR" 'bfs-toolchain-*.tar.xz' >/dev/null 2>&1
}

_base_stage2_complete() {
    [ -f "$LFS/.bfs-stage2-complete" ]
}

_base_stage3_complete() {
    [ -f "$LFS/.bfs-stage3-complete" ]
}

_verification_complete() {
    [ -f "$LFS/.bfs-verified" ]
}


_rootfs_archive_complete() {
    _latest_rootfs_archive >/dev/null 2>&1
}

_rootfs_restore_complete() {
    [ -f "$LFS/.bfs-rootfs-restored" ]
}

_toolchain_restore_complete() {
    [ -f "$LFS/.bfs-toolchain-restored" ]
}

_chroot_available() {
    # Chroot is usable whenever a real BFSOS rootfs exists with a working shell.
    # A freshly built Stage 2/3/4 rootfs should not require an archive restore
    # marker before Stage 8 becomes available.
    {
        [ -f "$LFS/.bfs-stage2-complete" ] ||
        [ -f "$LFS/.bfs-stage3-complete" ] ||
        [ -f "$LFS/.bfs-verified" ] ||
        [ -f "$LFS/.bfs-rootfs-restored" ] ||
        [ -f "$LFS/.bfs-toolchain-restored" ]
    } &&
    {
        [ -x "$LFS/usr/bin/bash" ] ||
        [ -x "$LFS/bin/bash" ]
    }
}

_pause_menu() {
    printf '\n'
    read -r -p "Press Enter to return to the menu..." _
}

_show_stage5_archive_dialog() {
    if command -v dialog >/dev/null 2>&1 &&
       [ -r /dev/tty ] && [ -w /dev/tty ]; then
        dialog --clear \
            --backtitle "BFS Linux Bootstrap" \
            --title "Create base rootfs archive" \
            --msgbox \
            "BFSOS will now create and verify the base rootfs archive.\n\nThis can take several minutes depending on system speed and compression workload.\n\nPress OK to begin." \
            12 68 </dev/tty >/dev/tty 2>&1 || return 1
        clear 2>/dev/null || true
    fi
    return 0
}

_latest_failure_log() {
    local stage="${1:-}" directory="" newest="" started="${STAGE_OPERATION_STARTED_EPOCH:-0}"

    case "$stage" in
        1) directory="$TOOLCHAIN_LOG_DIR" ;;
        2|3|4|5) directory="$BASE_LOG_DIR" ;;
        *) directory="$LOG_DIR" ;;
    esac

    [ -d "$directory" ] || return 1

    if [ -n "${LAST_FAILED_LOG_FILE:-}" ] && [ -r "$LAST_FAILED_LOG_FILE" ]; then
        printf '%s\n' "$LAST_FAILED_LOG_FILE"
        return 0
    fi

    newest="$(
        find "$directory" -type f -name '*.log' -printf '%T@ %p
' 2>/dev/null |
            awk -v started="$started" '$1 >= started { $1=""; sub(/^ /,""); print }' |
            while IFS= read -r path; do
                [ -n "$path" ] || continue
                printf '%s %s
' "$(stat -c '%Y' "$path" 2>/dev/null || printf 0)" "$path"
            done |
            sort -nr |
            head -n1 |
            cut -d' ' -f2-
    )"

    [ -n "$newest" ] || return 1
    printf '%s
' "$newest"
}

_show_stage_failure_dialog() {
    local stage="$1" status="$2" logfile="" details="" failed_url=""
    logfile="$(_latest_failure_log "$stage" 2>/dev/null || true)"
    if [ -z "$logfile" ] && [ -n "${STAGE_PREFLIGHT_LOG:-}" ] && [ -r "$STAGE_PREFLIGHT_LOG" ]; then
        logfile="$STAGE_PREFLIGHT_LOG"
    fi
    if [ -n "$logfile" ] && [ -r "$logfile" ]; then
        details="$(tail -n 18 "$logfile" 2>/dev/null || true)"
        failed_url="$(grep -Eo 'https?://[^[:space:]'\"'<>]+' "$logfile" 2>/dev/null | tail -n1 || true)"
    fi
    [ -n "$details" ] || details="No package log excerpt was available."

    local message="Bootstrap stage $stage failed with exit status $status."
    [ -z "$failed_url" ] || message="$message\n\nLast URL seen:\n$failed_url"
    [ -z "$logfile" ] || message="$message\n\nLog:\n$logfile"
    message="$message\n\nLast output:\n$details"

    if command -v dialog >/dev/null 2>&1 && [ -r /dev/tty ] && [ -w /dev/tty ]; then
        # Package/build output is streamed live while a stage runs.  Once a
        # handled failure occurs, clear that terminal output before drawing the
        # failure dialog so the same error is not presented both as raw text
        # and again inside the Dialog UI.
        _reset_terminal_ui
        dialog --clear --backtitle "BFS Linux Bootstrap" \
            --title "Bootstrap operation failed" --ok-label "Continue" \
            --msgbox "$message" 24 96 </dev/tty >/dev/tty 2>&1 || true
        _reset_terminal_ui
    else
        printf '\n%s\n' "$message" >&2
        _pause_menu
    fi
}

_menu_dialog_available() {
    [ "${BFS_MENU_STAGE:-no}" = yes ] &&
    command -v dialog >/dev/null 2>&1 &&
    [ -r /dev/tty ] && [ -w /dev/tty ]
}

_show_menu_progress() {
    local title="$1" message="$2"
    if _menu_dialog_available; then
        _reset_terminal_ui
        dialog --clear --backtitle "BFS Linux Bootstrap" \
            --title "$title" --infobox "$message" 8 72 \
            </dev/tty >/dev/tty 2>&1 || true
    else
        printf '\n%s\n' "$message"
    fi
}

_show_menu_success() {
    local title="$1" message="$2"
    if _menu_dialog_available; then
        _reset_terminal_ui
        dialog --clear --backtitle "BFS Linux Bootstrap" \
            --title "$title" --ok-label "Continue" --msgbox "$message" 12 82 \
            </dev/tty >/dev/tty 2>&1 || true
        _reset_terminal_ui
    else
        printf '\n%s\n' "$message"
    fi
}

_run_root_stage() {
    local stage="$1"

    if [ "$(id -u)" -eq 0 ]; then
        BFS_SKIP_TIME_SYNC=yes \
            BFS_FULL_BOOTSTRAP="${BFS_FULL_BOOTSTRAP:-no}" \
            "$0" "$stage"
        return $?
    fi

    command -v sudo >/dev/null 2>&1 || {
        echo "ERROR: sudo is required to run stage $stage." >&2
        return 1
    }

    if [ "${BFS_MENU_STAGE:-no}" != yes ] || ! command -v dialog >/dev/null 2>&1; then
        echo
        echo "Stage $stage requires root privileges."
        echo "Running: sudo $0 $stage"
        echo
    fi

    sudo -- env \
        BFS_SKIP_TIME_SYNC=yes \
        BFS_MENU_STAGE="${BFS_MENU_STAGE:-no}" \
        BFS_FULL_BOOTSTRAP="${BFS_FULL_BOOTSTRAP:-no}" \
        "$0" "$stage"
}

_enter_bfs_chroot() {
    if [ "$(id -u)" != 0 ]; then
        echo "ERROR: Chroot must be entered as root." >&2
        return 1
    fi

    if ! _chroot_available; then
        echo "ERROR: No usable BFS root filesystem exists at:" >&2
        echo "  $LFS" >&2
        return 1
    fi

    echo
    echo "Mounting virtual filesystems..."
    mountfs

    echo
    echo "Entering BFS chroot."
    echo "Type exit to return to the bootstrap menu."
    echo

    set +e
    chroot "$LFS" \
        env -i \
        HOME=/root \
        TERM="${TERM:-linux}" \
        LANG=C \
        LC_ALL=C \
        LANGUAGE=C \
        PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        /bin/bash --login
    local status=$?
    set -e

    umountfs
    return "$status"
}


_required_stage_complete() {
    local check="$1"
    "$check" || _rootfs_archive_complete
}

_dialog_required_status() {
    local check="$1"
    if _required_stage_complete "$check"; then
        printf '%s' '\Z2COMPLETE\Zn'
    else
        printf '%s' '\Z1PENDING\Zn'
    fi
}

_dialog_stage3_status() {
    if _base_stage3_complete; then
        printf '%s' '\Z2COMPLETE\Zn'
    elif _base_stage2_complete; then
        printf '%s' '\Zb\Z3AVAILABLE\Zn'
    else
        printf '%s' '\Z1PENDING\Zn'
    fi
}

_dialog_verification_status() {
    if _required_stage_complete _verification_complete; then
        printf '%s' '\Zb\Z7PASSED!\Zn'
    else
        printf '%s' '\Z1PENDING\Zn'
    fi
}

_dialog_action_status() {
    if "$@"; then
        printf '%s' '\Zb\Z3AVAILABLE\Zn'
    else
        printf '%s' '\Z1PENDING\Zn'
    fi
}


_show_bootstrap_menu() {
    clear 2>/dev/null || printf '\033[2J\033[H'
    printf '%s\n' '============================================================' \
        '                  BFS Linux Bootstrap' \
        '============================================================' ''

    _txt_status() { "$1" && printf '%s%s%s' "$COLOR_GREEN" "$2" "$COLOR_RESET" || printf '%sPENDING%s' "$COLOR_RED" "$COLOR_RESET"; }

    printf '  %s1)%s %-54s [%s]\n' "$COLOR_CYAN" "$COLOR_RESET" \
        'Build temporary toolchain (required)' "$(_required_stage_complete _toolchain_complete && printf '%sCOMPLETE%s' "$COLOR_GREEN" "$COLOR_RESET" || printf '%sPENDING%s' "$COLOR_RED" "$COLOR_RESET")"
    printf '  %s2)%s %-54s [%s]\n' "$COLOR_CYAN" "$COLOR_RESET" \
        'Build base system with temporary toolchain (required)' "$(_required_stage_complete _base_stage2_complete && printf '%sCOMPLETE%s' "$COLOR_GREEN" "$COLOR_RESET" || printf '%sPENDING%s' "$COLOR_RED" "$COLOR_RESET")"
    printf '  %s3)%s %-54s [%s]\n' "$COLOR_CYAN" "$COLOR_RESET" \
        'Rebuild base system with final toolchain (optional)' "$(_base_stage3_complete && printf '%sCOMPLETE%s' "$COLOR_GREEN" "$COLOR_RESET" || { _base_stage2_complete && printf '%sAVAILABLE%s' "$COLOR_YELLOW" "$COLOR_RESET" || printf '%sPENDING%s' "$COLOR_RED" "$COLOR_RESET"; })"
    printf '  %s4)%s %-54s [%s]\n' "$COLOR_CYAN" "$COLOR_RESET" \
        'Verify completed base system (required)' "$(_required_stage_complete _verification_complete && printf '%sPASSED!%s' "$COLOR_BOLD_WHITE" "$COLOR_RESET" || printf '%sPENDING%s' "$COLOR_RED" "$COLOR_RESET")"
    printf '  %s5)%s %-54s [%s]\n' "$COLOR_CYAN" "$COLOR_RESET" \
        'Create/compress base rootfs archive (required)' "$(_rootfs_archive_complete && printf '%sCOMPLETE%s' "$COLOR_GREEN" "$COLOR_RESET" || printf '%sPENDING%s' "$COLOR_RED" "$COLOR_RESET")"
    printf '  %s6)%s %-54s [%s]\n' "$COLOR_CYAN" "$COLOR_RESET" \
        'Restore newest base rootfs archive' "$(_rootfs_archive_complete && printf '%sAVAILABLE%s' "$COLOR_YELLOW" "$COLOR_RESET" || printf '%sPENDING%s' "$COLOR_RED" "$COLOR_RESET")"
    printf '  %s7)%s %-54s [%s]\n' "$COLOR_CYAN" "$COLOR_RESET" \
        'Restore newest temporary toolchain archive' "$(_toolchain_complete && printf '%sAVAILABLE%s' "$COLOR_YELLOW" "$COLOR_RESET" || printf '%sPENDING%s' "$COLOR_RED" "$COLOR_RESET")"
    printf '  %s8)%s %-54s [%s]\n' "$COLOR_CYAN" "$COLOR_RESET" \
        'Chroot into BFS rootfs (sudo/root)' "$(_chroot_available && printf '%sAVAILABLE%s' "$COLOR_YELLOW" "$COLOR_RESET" || printf '%sNOT AVAILABLE%s' "$COLOR_RED" "$COLOR_RESET")"
    printf '  %s9)%s %-54s [%s]\n' "$COLOR_CYAN" "$COLOR_RESET" \
        'Launch BFSOS installer' "$(_installer_available && printf '%sAVAILABLE%s' "$COLOR_YELLOW" "$COLOR_RESET" || printf '%sPENDING%s' "$COLOR_RED" "$COLOR_RESET")"
    printf '  %s10)%s %-54s [%s]\n' "$COLOR_CYAN" "$COLOR_RESET" \
        'Run Full Bootstrap (Stages 1 -> 2 -> 3 -> 4 -> 5)' "$(printf '%sAVAILABLE%s' "$COLOR_YELLOW" "$COLOR_RESET")"
    printf '  %s11)%s %-54s [%s]\n' "$COLOR_CYAN" "$COLOR_RESET" \
        'Build BFSOS bootable ISO' "$(printf '%sAVAILABLE%s' "$COLOR_YELLOW" "$COLOR_RESET")"
    printf '  %s12)%s %s\n' "$COLOR_CYAN" "$COLOR_RESET" 'Settings'
    printf '  %s13)%s %s\n\n' "$COLOR_CYAN" "$COLOR_RESET" 'Quit'
}


_dialog_stage_status() {
    if "$@"; then
        printf '%s' '\Z2COMPLETE\Zn'
    else
        printf '%s' '\Z1PENDING\Zn'
    fi
}

_dialog_chroot_status() {
    if _chroot_available; then
        printf '%s' '\Zb\Z3AVAILABLE\Zn'
    else
        printf '%s' '\Z1NOT AVAILABLE\Zn'
    fi
}

_dialog_menu_description() {
    local label="$1"
    local status="$2"

    printf '%-57s [%s]' "$label" "$status"
}


_select_bootstrap_menu_choice() {
    local choice="" dialog_status=0
    if command -v dialog >/dev/null 2>&1 &&
       [ -r /dev/tty ] && [ -w /dev/tty ]; then
        set +e
        choice="$(
            dialog --clear --colors --no-collapse \
                --backtitle "BFS Linux Bootstrap" \
                --title "Bootstrap menu" \
                --ok-label "Select" \
                --extra-button --extra-label "Settings" \
                --cancel-label "Quit" \
                --menu \
                "Manual path: 1 -> 2 -> 4 -> 5; Stage 3 is optional.\nFull Bootstrap runs 1 -> 2 -> 3 -> 4 -> 5 automatically and stops on the first failure.\n\nA valid existing base archive satisfies installer readiness automatically." \
                28 104 15 \
                1 "$(_dialog_menu_description 'Build temporary toolchain (required)' "$(_dialog_required_status _toolchain_complete)")" \
                2 "$(_dialog_menu_description 'Build base system with temporary toolchain (required)' "$(_dialog_required_status _base_stage2_complete)")" \
                3 "$(_dialog_menu_description 'Rebuild base system with final toolchain (optional)' "$(_dialog_stage3_status)")" \
                4 "$(_dialog_menu_description 'Verify completed base system (required)' "$(_dialog_verification_status)")" \
                5 "$(_dialog_menu_description 'Create/compress base rootfs archive (required)' "$(_dialog_stage_status _rootfs_archive_complete)")" \
                6 "$(_dialog_menu_description 'Restore newest base rootfs archive' "$(_dialog_action_status _rootfs_archive_complete)")" \
                7 "$(_dialog_menu_description 'Restore newest temporary toolchain archive' "$(_dialog_action_status _toolchain_complete)")" \
                8 "$(_dialog_menu_description 'Chroot into BFS rootfs' "$(_dialog_chroot_status)")" \
                9 "$(_dialog_menu_description 'Launch BFSOS installer' "$(_dialog_action_status _installer_available)")" \
                10 "$(_dialog_menu_description 'Run Full Bootstrap (Stages 1 -> 2 -> 3 -> 4 -> 5)' '\Zb\Z3AVAILABLE\Zn')" \
                11 "$(_dialog_menu_description 'Build BFSOS bootable ISO' '\Zb\Z3AVAILABLE\Zn')" \
                13 "$(_dialog_menu_description 'Quit' '\Z3EXIT\Zn')" \
                --stdout </dev/tty 2>/dev/tty
        )"
        dialog_status=$?
        set -e
        clear </dev/tty >/dev/tty 2>/dev/null || true
        case "$dialog_status" in
            0) printf '%s\n' "$choice" ;;
            3) printf '%s\n' 12 ;;
            *) printf '%s\n' 13 ;;
        esac
        return 0
    fi
    _show_bootstrap_menu >&2
    printf '%sChoose [1-13]: %s' "$COLOR_YELLOW" "$COLOR_RESET" >&2
    read -r choice </dev/tty 2>/dev/null || read -r choice
    case "$choice" in q|Q|quit|Quit|QUIT) choice=13 ;; esac
    printf '%s\n' "$choice"
}


_bootstrap_menu() {
    local choice="" status=0
    while true; do
        choice="$(_select_bootstrap_menu_choice)"
        status=0

        # Limit failure-dialog log discovery to this operation.  If a stage fails
        # during preflight before opening a new package log, do not display an
        # unrelated log from an earlier failure.
        STAGE_OPERATION_STARTED_EPOCH="$(date +%s)"
        LAST_FAILED_LOG_FILE=""

        case "$choice" in
            1) set +e; BFS_MENU_STAGE=yes _buildtoolchain; status=$?; set -e ;;
            2) set +e; BFS_MENU_STAGE=yes _run_root_stage 2; status=$?; set -e ;;
            3) set +e; BFS_MENU_STAGE=yes _run_root_stage 3; status=$?; set -e ;;
            4) set +e; BFS_MENU_STAGE=yes _run_root_stage 4; status=$?; set -e ;;
            5)
                _show_stage5_archive_dialog || continue
                set +e; BFS_MENU_STAGE=yes _run_root_stage 5; status=$?; set -e
                ;;
            6) set +e; BFS_MENU_STAGE=yes _run_root_stage 6; status=$?; set -e ;;
            7) set +e; _restore_toolchain; status=$?; set -e ;;
            8)
                # A normal `exit` from the chroot is success. Return directly
                # to the bootstrap menu; only pause when chroot actually fails.
                set +e
                BFS_MENU_STAGE=yes _run_root_stage 8
                status=$?
                set -e
                if [ "$status" -ne 0 ]; then
                    echo
                    echo "Chroot exited with failure status: $status"
                    _pause_menu
                fi
                # Do not fall through to the generic operation-success/pause
                # block after a normal chroot exit.
                continue
                ;;
            9)
                # The installer owns its own UI/result handling. When it exits,
                # restore the terminal and immediately redraw bootstrap.
                set +e; _launch_bfs_installer; status=$?; set -e
                _reset_terminal_ui
                continue
                ;;
            10)
                # Full Bootstrap owns its per-stage failure handling and final
                # Done/Launch-installer prompt.  It deliberately includes the
                # otherwise-optional Stage 3 final-toolchain rebuild.
                set +e
                BFS_MENU_STAGE=yes _run_full_bootstrap
                status=$?
                set -e
                _reset_terminal_ui
                continue
                ;;
            11)
                set +e
                _launch_iso_builder
                status=$?
                set -e
                _reset_terminal_ui
                ;;
            12) bootstrap_settings_menu; continue ;;
            13|q|Q|quit|Quit|QUIT) echo "BFS bootstrap exited."; return 0 ;;
            *) echo "Invalid selection."; sleep 1; continue ;;
        esac
        # Stages 2, 3, and 5 already report their successful result.  Return
        # directly to the main menu instead of adding a redundant success pause.
        if [ "$status" -eq 0 ]; then
            case "$choice" in
                1|2|3|4|5) continue ;;
            esac
            echo
            echo "Operation completed successfully."
            _pause_menu
        else
            _show_stage_failure_dialog "$choice" "$status"
            continue
        fi
    done
}

_stop_bootstrap() {
    local pid=""
    local pgid=""

    if [ -f "$PID_FILE" ]; then
        read -r pid pgid < "$PID_FILE" || true
    fi

    if [ -z "$pid" ] || [ -z "$pgid" ]; then
        echo "No recorded BFS bootstrap process is running."
        rm -f "$PID_FILE"
        return 0
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
        echo "Recorded BFS bootstrap process is no longer running."
        rm -f "$PID_FILE"
        return 0
    fi

    echo "Stopping BFS bootstrap process group $pgid..."

    kill -TERM -- "-$pgid" 2>/dev/null || true

    for _ in 1 2 3 4 5; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
    done

    if kill -0 "$pid" 2>/dev/null; then
        echo "Processes did not stop normally; forcing termination..."
        kill -KILL -- "-$pgid" 2>/dev/null || true
    fi

    rm -f "$PID_FILE"
    echo "BFS bootstrap stopped."
}

# The stop command must run outside the build's process group.
case "${1:-}" in
    0|stop|kill)
        _stop_bootstrap
        exit 0
        ;;
esac

# Run every bootstrap stage in its own process group. This makes Ctrl+C and
# the stop command terminate pkgmk, make, gcc, tar, and other descendants too.
CURRENT_PGID="$(ps -o pgid= -p "$$" | tr -d '[:space:]')"

if [ "$$" != "$CURRENT_PGID" ]; then
    if { : </dev/tty; } 2>/dev/null; then
        exec setsid --ctty "$0" "$@"
    else
        exec setsid "$0" "$@"
    fi
fi

printf '%s %s\n' "$$" "$CURRENT_PGID" > "$PID_FILE"

_reset_terminal_ui() {
    if { : </dev/tty; } 2>/dev/null; then
        printf '\033[0m\033[?25h\033[2J\033[H' >/dev/tty 2>/dev/null || true
        if command -v clear >/dev/null 2>&1; then
            TERM="${TERM:-linux}" clear </dev/tty >/dev/tty 2>/dev/null || true
        fi
    else
        printf '\033[0m\033[?25h\033[2J\033[H' 2>/dev/null || true
    fi
}

_cleanup_on_exit() {
    local status=$?

    trap - EXIT INT TERM HUP

    if declare -F _close_active_package_log >/dev/null 2>&1; then
        _close_active_package_log "$status" 2>/dev/null || true
    fi

    if declare -F umountfs >/dev/null 2>&1; then
        umountfs 2>/dev/null || true
    fi

    rm -f "$PID_FILE"

    if [ -n "$DIALOGRC_FILE" ]; then
        rm -f "$DIALOGRC_FILE"
    fi

    if [ -n "$ORIGINAL_DIALOGRC" ]; then
        export DIALOGRC="$ORIGINAL_DIALOGRC"
    else
        unset DIALOGRC
    fi

    _reset_terminal_ui
    exit "$status"
}

_interrupt_bootstrap() {
    echo
    echo "Bootstrap interrupted. Stopping all child processes..."

    trap - INT TERM HUP

    # Kill every remaining process in this bootstrap process group except
    # this shell, which will exit through the EXIT cleanup trap.
    kill -TERM -- "-$$" 2>/dev/null || true
    sleep 1
    kill -KILL -- "-$$" 2>/dev/null || true
}

trap _interrupt_bootstrap INT TERM HUP
trap _cleanup_on_exit EXIT

# BFS release. The VERSION file is authoritative when present.
if [ -f "$SCRIPT_DIR/VERSION" ]; then
    BFS_VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION")"
else
    BFS_VERSION="0.9.0-rc1"
fi

BUILD_DATE="$(date +%Y%m%d)"

ARCHIVE_DIR="$SCRIPT_DIR/archives"
TOOLCHAIN_ARCHIVE_DIR="$ARCHIVE_DIR/toolchain"
BASE_ARCHIVE_DIR="$ARCHIVE_DIR/base"

_ensure_archive_dirs() {
    mkdir -p "$TOOLCHAIN_ARCHIVE_DIR" "$BASE_ARCHIVE_DIR"
}

_find_port_dir() {
    local package="$1"
    local normalized="${package%-pass*}"
    local match=""
    local -a matches=()

    while IFS= read -r match; do
        [ -n "$match" ] && matches+=("$match")
    done < <(
        find "$SCRIPT_DIR/ports" \
            -mindepth 2 \
            -maxdepth 2 \
            -type d \
            -name "$normalized" \
            -exec test -f '{}/Pkgfile' ';' \
            -print 2>/dev/null |
        sort
    )

    case "${#matches[@]}" in
        0)
            echo "ERROR: Port not found in any collection: $normalized" >&2
            return 1
            ;;
        1)
            printf '%s\n' "${matches[0]}"
            ;;
        *)
            echo "ERROR: Port exists in more than one collection: $normalized" >&2
            printf '  %s\n' "${matches[@]}" >&2
            return 1
            ;;
    esac
}

_validate_package_ports() {
    local package=""
    local port_dir=""

    for package in "$@"; do
        port_dir="$(_find_port_dir "$package")" || return 1
        printf '  %-28s %s\n' "$package" "${port_dir#$SCRIPT_DIR/}"
    done
}

_clean_start() {
    local answer

    echo
    echo "Start a completely clean BFS build?"
    echo
    echo "This will permanently delete:"
    echo "  /tmp/lfs*"
    echo "  $packagedir/*"
    echo "  $buildworkdir/*"
    echo "  $TOOLCHAIN_ARCHIVE_DIR/bfs-toolchain-*.tar.xz"
    echo "  $BASE_ARCHIVE_DIR/bfs-rootfs-*.tar.xz"
    echo

    if [ "${BFS_FULL_BOOTSTRAP:-no}" = yes ]; then
        # The Full Bootstrap workflow is explicitly a from-scratch 1->5 run.
        # Do not drop from Dialog into an easy-to-miss raw-terminal YES prompt:
        # the Full Bootstrap confirmation already authorizes this cleanup.
        answer=YES
        echo "Full Bootstrap: clean start confirmed; removing prior build state."
    else
        printf "Type YES to continue, or press Enter to keep existing files: "
        read -r answer
    fi

    if [ "$answer" != "YES" ]; then
        echo
        echo "Keeping existing build files."
        return 0
    fi

    case "$LFS" in
        /tmp/lfs-rootfs)
            ;;
        *)
            echo "ERROR: Refusing to remove unexpected LFS path: $LFS" >&2
            exit 1
            ;;
    esac

    case "$TOOLS" in
        /tmp/lfs-tools)
            ;;
        *)
            echo "ERROR: Refusing to remove unexpected tools path: $TOOLS" >&2
            exit 1
            ;;
    esac

    echo
    echo "Removing old BFS build files..."

    # A previous Stage 2/3/chroot or interrupted run can leave bind/proc/sys/tmpfs
    # mounts below $LFS.  rm -rf cannot remove a mount point and historically the
    # script continued anyway, leaving a split/stale toolchain tree behind.
    #
    # Unmount every BFS mount deepest-first before deleting /tmp/lfs*.
    _clean_start_unmount_tree() {
        local root="$1"
        local target=""

        [ -e "$root" ] || [ -L "$root" ] || return 0

        while IFS= read -r target; do
            [ -n "$target" ] || continue
            echo "Unmounting stale BFS mount: $target"

            if ! sudo umount -- "$target" 2>/dev/null; then
                # A stale/busy bind can survive an interrupted build. Lazy
                # unmount is safe here because the user explicitly requested a
                # completely clean build and the tree is about to be deleted.
                sudo umount -l -- "$target" || {
                    echo "ERROR: Unable to unmount stale BFS mount: $target" >&2
                    return 1
                }
            fi
        done < <(
            findmnt -Rrn -o TARGET --target "$root" 2>/dev/null |
                awk -v root="$root" '$0 == root || index($0, root "/") == 1 { print }' |
                awk '{ depth=gsub("/", "/"); print depth "\t" $0 }' |
                sort -rn |
                cut -f2-
        )

        if mountpoint -q "$root" 2>/dev/null; then
            echo "ERROR: $root is still mounted after cleanup." >&2
            return 1
        fi
    }

    _clean_start_unmount_tree "$TOOLS" || return 1
    _clean_start_unmount_tree "$LFS" || return 1

    # Delete the two known BFS trees explicitly.  Do not use a broad /tmp/lfs*
    # removal as the primary cleanup path, and do not continue after rm errors.
    sudo rm -rf -- "$TOOLS" "$LFS" || {
        echo "ERROR: Failed to remove old BFS build trees." >&2
        return 1
    }

    if [ -e "$TOOLS" ] || [ -L "$TOOLS" ] || [ -e "$LFS" ] || [ -L "$LFS" ]; then
        echo "ERROR: Old BFS build trees still exist after cleanup." >&2
        return 1
    fi

    sudo mkdir -p "$packagedir" "$buildworkdir"

    sudo find "$packagedir" \
        -mindepth 1 \
        -maxdepth 1 \
        -print \
        -exec rm -rf -- {} +

    sudo find "$buildworkdir" \
        -mindepth 1 \
        -maxdepth 1 \
        -print \
        -exec rm -rf -- {} +

    _ensure_archive_dirs

    sudo find "$TOOLCHAIN_ARCHIVE_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        -type f \
        -name 'bfs-toolchain-*.tar.xz' \
        -print \
        -delete

    sudo find "$BASE_ARCHIVE_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        -type f \
        -name 'bfs-rootfs-*.tar.xz' \
        -print \
        -delete

    echo
    echo "Clean start completed."
}

_latest_archive() {
    local directory="$1"
    local pattern="$2"
    local latest

    latest="$(
        find "$directory" -maxdepth 1 -type f -name "$pattern" -printf '%f\n' 2>/dev/null |
            sort -V |
            tail -n 1
    )"

    [ -n "$latest" ] || return 1

    printf '%s/%s\n' "$directory" "$latest"
}

_clear_rootfs() {
    case "$LFS" in
        /tmp/lfs-rootfs)
            ;;
        *)
            echo "ERROR: Refusing to clear unexpected LFS path: $LFS" >&2
            exit 1
            ;;
    esac

    /usr/bin/mkdir -p "$LFS"
    /usr/bin/find "$LFS" -mindepth 1 -maxdepth 1 -exec /usr/bin/rm -rf -- {} +
}

_restore_toolchain() {
    local archive
    local restored_tools="${LFS}${TOOLS}"
    local listing_file
    local toolchain_member=""

    archive="$(
        _latest_archive \
            "$TOOLCHAIN_ARCHIVE_DIR" \
            'bfs-toolchain-*.tar.xz'
    )" || {
        echo "ERROR: No toolchain archive found in:" >&2
        echo "  $TOOLCHAIN_ARCHIVE_DIR" >&2
        exit 1
    }

    echo "Restoring newest toolchain archive:"
    echo "  $archive"
    echo

    case "$restored_tools" in
        /tmp/lfs-rootfs/tmp/lfs-tools)
            ;;
        *)
            echo "ERROR: Refusing to replace unexpected toolchain path:" >&2
            echo "  $restored_tools" >&2
            exit 1
            ;;
    esac

    # List the archive once. Some tar versions print members with a leading
    # "./" and others do not, so stage 7 must accept either representation.
    listing_file="$(/usr/bin/mktemp /tmp/bfs-toolchain-list.XXXXXX)"

    if ! /usr/bin/nice -n 19 /bin/tar -tJf "$archive" > "$listing_file"; then
        /usr/bin/rm -f "$listing_file"
        echo "ERROR: Toolchain archive is unreadable or damaged." >&2
        exit 1
    fi

    if grep -qx './tmp/lfs-tools' "$listing_file"; then
        toolchain_member='./tmp/lfs-tools'
    elif grep -qx 'tmp/lfs-tools' "$listing_file"; then
        toolchain_member='tmp/lfs-tools'
    elif grep -q '^\./tmp/lfs-tools/' "$listing_file"; then
        toolchain_member='./tmp/lfs-tools'
    elif grep -q '^tmp/lfs-tools/' "$listing_file"; then
        toolchain_member='tmp/lfs-tools'
    fi

    if [ -z "$toolchain_member" ]; then
        echo "ERROR: Toolchain archive does not contain the temporary toolchain:" >&2
        echo "  tmp/lfs-tools" >&2
        echo >&2
        echo "Toolchain-like entries found:" >&2
        grep -E '(^|/)lfs-tools(/|$)' "$listing_file" | head -20 >&2 || true
        /usr/bin/rm -f "$listing_file"
        exit 1
    fi

    # Do not require one exact archive spelling for gcc. Verify that the
    # archive contains the toolchain tree, extract it, and then test the
    # restored executable paths directly.
    /usr/bin/rm -f "$listing_file"

    # Stage 7 preserves an existing base rootfs and replaces only its
    # temporary toolchain.
    #
    # PATH begins with /tmp/lfs-tools/bin. Once that symlink or directory is
    # removed, unqualified commands may disappear mid-restore. Use the live
    # system's absolute command paths during replacement and extraction.
    /usr/bin/mkdir -p "$LFS/tmp"

    # Remove the host-side convenience symlink before replacing its target.
    /usr/bin/rm -f "$TOOLS"
    /usr/bin/rm -rf "$restored_tools"

    if ! /usr/bin/nice -n 19 /bin/tar -xJpf "$archive" \
        -C "$LFS" \
        "$toolchain_member"
    then
        echo "ERROR: Failed to extract the temporary toolchain." >&2
        exit 1
    fi

    # Recreate:
    # /tmp/lfs-tools -> /tmp/lfs-rootfs/tmp/lfs-tools
    /usr/bin/ln -s "$restored_tools" "$TOOLS"

    if [ ! -x "$TOOLS/bin/gcc" ] ||
        [ ! -x "$TOOLS/bin/ld" ] ||
        [ ! -x "$TOOLS/bin/pkgmk" ]
    then
        echo "ERROR: Restored toolchain failed verification." >&2
        echo >&2
        echo "Expected executable files:" >&2
        echo "  $TOOLS/bin/gcc" >&2
        echo "  $TOOLS/bin/ld" >&2
        echo "  $TOOLS/bin/pkgmk" >&2
        echo >&2
        echo "Available compiler/linker entries:" >&2
        /usr/bin/find "$TOOLS/bin" -maxdepth 1 \
            \( -name '*gcc*' -o -name 'cc' -o -name 'ld*' -o -name 'pkgmk' \) \
            -printf '  %f -> %l\n' 2>/dev/null | /usr/bin/sort >&2 || true
        exit 1
    fi

    touch "$LFS/.bfs-toolchain-restored"

    echo "Toolchain restored successfully."
    echo

    if [ -x "$LFS/usr/bin/bash" ] &&
        [ -x "$LFS/usr/bin/pkgmk" ] &&
        [ -f "$LFS/var/lib/pkg/db" ]
    then
        echo "Existing base rootfs was preserved."
        echo "Continue with:"
        echo "  sudo $0 3"
    else
        echo "No completed base rootfs was detected."
        echo "Continue with:"
        echo "  sudo $0 2"
    fi
}

_restore_rootfs() {
    local archive

    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: Stage 6 base rootfs restore must run as root." >&2
        return 1
    fi

    archive="$(
        _latest_archive \
            "$BASE_ARCHIVE_DIR" \
            'bfs-rootfs-*.tar.xz'
    )" || {
        echo "ERROR: No base rootfs archive found in:" >&2
        echo "  $BASE_ARCHIVE_DIR" >&2
        exit 1
    }

    echo "Restoring newest base rootfs archive:"
    echo "  $archive"

    # Stage 6 destroys the current rootfs, including any temporary toolchain
    # living below it. Never use commands resolved through $TOOLS during this
    # operation; use the live system's absolute command paths throughout.
    if ! /bin/tar -tJf "$archive" >/dev/null; then
        echo "ERROR: Base rootfs archive is unreadable or damaged." >&2
        exit 1
    fi

    # Stage 6 is destructive. Make sure no bootstrap bind/virtual filesystem
    # remains mounted below the rootfs before clearing or extracting it.
    if ! umountfs; then
        echo "ERROR: Could not unmount all bootstrap filesystems before restore." >&2
        return 1
    fi

    _clear_rootfs

    if ! /bin/tar -xJpf "$archive" -C "$LFS"; then
        echo "ERROR: Failed to extract base rootfs archive." >&2
        exit 1
    fi

    for link in bin lib sbin; do
        if [ ! -e "$LFS/$link" ]; then
            /usr/bin/ln -s "usr/$link" "$LFS/$link"
        fi
    done

    if [ -d "$LFS/usr/lib32" ] && [ ! -e "$LFS/lib32" ]; then
        /usr/bin/ln -s usr/lib32 "$LFS/lib32"
    fi


    /usr/bin/mkdir -p \
        "$LFS/dev/pts" \
        "$LFS/proc" \
        "$LFS/run" \
        "$LFS/sys" \
        "$LFS/tmp"

    # A base-rootfs archive intentionally does not require the temporary
    # bootstrap toolchain. Remove any stale host-side convenience symlink.
    /usr/bin/rm -f "$TOOLS"

    if [ ! -x "$LFS/usr/bin/bash" ] ||
        [ ! -x "$LFS/usr/bin/gcc" ] ||
        [ ! -f "$LFS/var/lib/pkg/db" ]
    then
        echo "ERROR: Restored base rootfs failed basic verification." >&2
        exit 1
    fi

    touch "$LFS/.bfs-rootfs-restored"

    echo
    echo "Base rootfs restored successfully."
    echo "Verify the restored system with:"
    echo "  sudo $0 4"
}

_verify_toolchain_multilib() {
    local failed=0
    local test_c="/tmp/bfs-toolchain-test.c"
    local test_cpp="/tmp/bfs-toolchain-test.cpp"
    local test64="/tmp/bfs-toolchain-test64"
    local test32="/tmp/bfs-toolchain-test32"
    local testcpp64="/tmp/bfs-toolchain-testcpp64"
    local testcpp32="/tmp/bfs-toolchain-testcpp32"
    local crt64=""
    local crt32=""
    local lib32_target=""
    local summary=""
    local log_file="$TOOLCHAIN_LOG_DIR/toolchain-verification-$(date +%Y%m%d-%H%M%S).log"

    rm -f \
        "$test_c" "$test_cpp" \
        "$test64" "$test32" \
        "$testcpp64" "$testcpp32"

    cat > "$test_c" <<'EOF_C'
#include <stdio.h>
int main(void) {
    puts("BFS C toolchain test OK");
    return 0;
}
EOF_C

    cat > "$test_cpp" <<'EOF_CPP'
#include <iostream>
int main() {
    std::cout << "BFS C++ toolchain test OK\n";
    return 0;
}
EOF_CPP

    {
        echo "========================================"
        echo " BFS TEMPORARY TOOLCHAIN VERIFICATION"
        echo "========================================"
        echo

        echo "Checking 64-bit C compile/link/run..."
        if "$TOOLS/bin/$LFS_TGT-gcc" "$test_c" -o "$test64" &&
           file "$test64" | grep -q 'ELF 64-bit' &&
           "$test64" >/dev/null 2>&1
        then
            echo "  [PASS] 64-bit C compile/link/run"
        else
            echo "  [FAIL] 64-bit C compile/link/run"
            failed=1
        fi

        echo "Checking 32-bit C compile/link/run..."
        if "$TOOLS/bin/$LFS_TGT-gcc" -m32 "$test_c" -o "$test32" &&
           file "$test32" | grep -q 'ELF 32-bit' &&
           "$test32" >/dev/null 2>&1
        then
            echo "  [PASS] 32-bit C compile/link/run"
        else
            echo "  [FAIL] 32-bit C compile/link/run"
            failed=1
        fi

        echo "Checking 64-bit C++ compile/link/run..."
        if "$TOOLS/bin/$LFS_TGT-g++" "$test_cpp" -o "$testcpp64" &&
           file "$testcpp64" | grep -q 'ELF 64-bit' &&
           "$testcpp64" >/dev/null 2>&1
        then
            echo "  [PASS] 64-bit C++ compile/link/run"
        else
            echo "  [FAIL] 64-bit C++ compile/link/run"
            failed=1
        fi

        echo "Checking 32-bit C++ compile/link/run..."
        if "$TOOLS/bin/$LFS_TGT-g++" -m32 "$test_cpp" -o "$testcpp32" &&
           file "$testcpp32" | grep -q 'ELF 32-bit' &&
           "$testcpp32" >/dev/null 2>&1
        then
            echo "  [PASS] 32-bit C++ compile/link/run"
        else
            echo "  [FAIL] 32-bit C++ compile/link/run"
            failed=1
        fi

        echo "Checking 64-bit startup files..."
        crt64="$("$TOOLS/bin/$LFS_TGT-gcc" -print-file-name=crt1.o 2>/dev/null || true)"
        if [ -n "$crt64" ] &&
           [ "$crt64" != "crt1.o" ] &&
           [ -e "$crt64" ]
        then
            echo "  [PASS] 64-bit crt1.o: $crt64"
        else
            echo "  [FAIL] 64-bit crt1.o was not resolved"
            failed=1
        fi

        echo "Checking 32-bit startup files..."
        crt32="$("$TOOLS/bin/$LFS_TGT-gcc" -m32 -print-file-name=crt1.o 2>/dev/null || true)"
        if [ -n "$crt32" ] &&
           [ "$crt32" != "crt1.o" ] &&
           [ -e "$crt32" ]
        then
            echo "  [PASS] 32-bit crt1.o: $crt32"
        else
            echo "  [FAIL] 32-bit crt1.o was not resolved"
            failed=1
        fi

        echo "Checking lib32 compatibility link..."
        lib32_target="$(readlink -f "$TOOLS/$LFS_TGT/lib32" 2>/dev/null || true)"
        if [ "$lib32_target" = "$TOOLS/lib32" ]; then
            echo "  [PASS] $TOOLS/$LFS_TGT/lib32 -> $TOOLS/lib32"
        else
            echo "  [FAIL] lib32 compatibility link is missing or incorrect"
            echo "         resolved target: ${lib32_target:-<none>}"
            failed=1
        fi

        echo
        if [ "$failed" -eq 0 ]; then
            echo "RESULT: PASS"
        else
            echo "RESULT: FAIL"
        fi
    } | tee "$log_file"

    rm -f \
        "$test_c" "$test_cpp" \
        "$test64" "$test32" \
        "$testcpp64" "$testcpp32"

    if [ "$failed" -eq 0 ]; then
        summary="64-bit C: PASS\n32-bit C: PASS\n64-bit C++: PASS\n32-bit C++: PASS\nStartup files: PASS\nlib32 link: PASS\n\nTemporary toolchain verification PASSED."
        if [ "${BFS_FULL_BOOTSTRAP:-no}" = yes ]; then
            printf '\n%s\n' "Temporary toolchain verification PASSED."
        elif command -v dialog >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ]; then
            dialog \
                --clear \
                --backtitle "BFS Linux Bootstrap" \
                --title "Toolchain verification PASSED" \
                --msgbox "$summary" 14 68
            clear 2>/dev/null || true
        else
            printf '\n%s\n' "Temporary toolchain verification PASSED."
        fi
        return 0
    fi

    summary="One or more 32/64-bit toolchain checks FAILED.\n\nSee:\n$log_file\n\nStep 1 will not be archived or marked successful."
    if [ "${BFS_FULL_BOOTSTRAP:-no}" = yes ]; then
        printf '\nERROR: Temporary toolchain verification FAILED.\n' >&2
        printf 'See: %s\n' "$log_file" >&2
    elif command -v dialog >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ]; then
        dialog \
            --clear \
            --backtitle "BFS Linux Bootstrap" \
            --title "Toolchain verification FAILED" \
            --msgbox "$summary" 12 72
        clear 2>/dev/null || true
    else
        printf '\nERROR: Temporary toolchain verification FAILED.\n' >&2
        printf 'See: %s\n' "$log_file" >&2
    fi

    return 1
}

_buildtoolchain() {
    _ensure_archive_dirs
    _start_stage_preflight_log 1 || {
        echo "ERROR: Could not create the Stage-1 preflight log." >&2
        return 1
    }

    if [ "$(id -u)" = 0 ]; then
        _stage_preflight_note "ERROR: Temporary toolchain needs to be built as a regular user."
        return 1
    fi

    if ! _clean_start; then
        _stage_preflight_note "ERROR: Stage-1 clean-start preparation failed."
        return 1
    fi

    # Full-bootstrap clean-start can remove a previously populated /tmp/lfs-tools
    # while Bash still has commands from that directory cached in its hash table.
    # Flush those stale command paths before Stage 1 recreates the toolchain.
    hash -r

    export PATCH="$SCRIPT_DIR/sources/"
    export BOOTSTRAP=1
    export LFS_TGT=x86_64-lfs-linux-gnu
    export LFS_TGT32=i686-lfs-linux-gnu

    # The temporary toolchain must physically live inside the BFS rootfs:
    #
    #   /tmp/lfs-tools -> /tmp/lfs-rootfs/tmp/lfs-tools
    #
    # Do not use `rm -f` here.  If /tmp/lfs-tools already exists as a
    # directory, `ln -sf TARGET /tmp/lfs-tools` creates a nested
    # /tmp/lfs-tools/lfs-tools symlink instead of replacing the directory.
    case "$TOOLS" in
        /tmp/lfs-tools)
            ;;
        *)
            _stage_preflight_note "ERROR: Refusing to replace unexpected tools path: $TOOLS"
            return 1
            ;;
    esac

    case "${LFS}${TOOLS}" in
        /tmp/lfs-rootfs/tmp/lfs-tools)
            ;;
        *)
            _stage_preflight_note "ERROR: Unexpected rooted toolchain path: ${LFS}${TOOLS}"
            return 1
            ;;
    esac

    # A prior root-stage or interrupted build can leave /tmp/lfs-tools owned
    # by root.  Stage 1 itself must still build as the regular user, but removing
    # the stale link/directory may require sudo.
    if [ -e "$TOOLS" ] || [ -L "$TOOLS" ]; then
        if ! /usr/bin/rm -rf -- "$TOOLS" 2>>"$STAGE_PREFLIGHT_LOG"; then
            _stage_preflight_note "Stage 1: regular-user removal of $TOOLS failed; retrying cleanup with sudo."
            if ! sudo /usr/bin/rm -rf -- "$TOOLS" >>"$STAGE_PREFLIGHT_LOG" 2>&1; then
                _stage_preflight_note "ERROR: Could not remove stale toolchain path: $TOOLS"
                return 1
            fi
        fi
    fi

    if ! /usr/bin/mkdir -p "${LFS}${TOOLS}" "$sourcedir" 2>>"$STAGE_PREFLIGHT_LOG"; then
        _stage_preflight_note "ERROR: Could not create Stage-1 toolchain directories."
        _stage_preflight_note "       If $LFS survived an older root build, use Full Bootstrap clean-start or remove that stale tree with sudo."
        return 1
    fi
    if ! /usr/bin/ln -s "${LFS}${TOOLS}" "$TOOLS" 2>>"$STAGE_PREFLIGHT_LOG"; then
        _stage_preflight_note "ERROR: Could not create $TOOLS -> ${LFS}${TOOLS}."
        return 1
    fi

    if [ ! -L "$TOOLS" ]; then
        _stage_preflight_note "ERROR: $TOOLS was not created as a symlink."
        return 1
    fi

    if [ "$(/usr/bin/readlink -f "$TOOLS")" != "${LFS}${TOOLS}" ]; then
        _stage_preflight_note "ERROR: $TOOLS points to the wrong location."
        _stage_preflight_note "  Expected: ${LFS}${TOOLS}"
        _stage_preflight_note "  Actual:   $(/usr/bin/readlink -f "$TOOLS" 2>/dev/null || echo '<unresolved>')"
        return 1
    fi

    # The toolchain directory now exists again. Flush command hashing once more
    # so early Stage-1 orchestration falls back to host tools until each target
    # utility is actually built into $TOOLS/bin.
    hash -r

    echo "Temporary toolchain path verified:"
    echo "  $TOOLS -> ${LFS}${TOOLS}"

    cat > /tmp/bootstrap.conf <<EOF
# Do not override LC_ALL here.
# The temporary pkgmk dynamically selects C.UTF-8/C.utf8 when available
# so libarchive can extract UTF-8 source pathnames, falling back to C
# only when the host has no UTF-8 C locale.
export MAKEFLAGS=-j$(nproc)

# Stage 1 temporary toolchain is deliberately uncached.  Never inherit a
# live-host /usr/lib/ccache wrapper path into the bootstrap compiler chain.
export BFS_CCACHE=no

# Keep the Stage-1 source cache in the same package-namespaced layout used
# by the installed BFSOS pkgmk configuration.  Later bootstrap stages bind
# this same root at /var/cache/pkg/sources, so unchanged archives are reused
# instead of being downloaded again merely because the cache layout changed.
PKGMK_SOURCE_ROOT="$sourcedir"
PKGMK_SOURCE_DIR="\$PKGMK_SOURCE_ROOT/\$name"
mkdir -p "\$PKGMK_SOURCE_DIR" || exit 1
PKGMK_PACKAGE_DIR=/tmp/lfs-pkg

. $PWD/files/pkgmk.bootstrap
EOF

    if [ ! "$(PATH=$TOOLS/bin command -v pkgmk)" ]; then
        # The first pkgutils build happens before pkgmk exists, so seed its
        # source into the same package namespace normal pkgmk will use later.
        mkdir -p "$sourcedir/pkgutils" || return 1
        if [ ! -f "$sourcedir/pkgutils/pkgutils-5.40.12.tar.xz" ]; then
            curl --fail --location --retry 3 \
                -o "$sourcedir/pkgutils/pkgutils-5.40.12.tar.xz" \
                https://crux.nu/files/pkgutils-5.40.12.tar.xz || return 1
        fi

        rm -rf /tmp/pkgutils-5.40.12
        tar -xf "$sourcedir/pkgutils/pkgutils-5.40.12.tar.xz" -C /tmp || return 1

        # The initial pkgutils bootstrap bypasses ports/core/pkgutils/Pkgfile.
        # Prefer a UTF-8 C locale when the live host provides one (GCC 16.2
        # contains UTF-8 pathnames), but fall back to plain C when it does not.
        sed -i '/^export LC_ALL=C\.UTF-8$/c\
_bfs_utf8_locale=""\
_bfs_locale_cmd=""\
_bfs_pkgmk_path="$(readlink -f "$0" 2>/dev/null || printf "%s" "$0")"\
case "$_bfs_pkgmk_path" in\
    */tmp/lfs-tools/*) [ -x /tmp/lfs-tools/bin/locale ] && _bfs_locale_cmd=/tmp/lfs-tools/bin/locale ;;\
    *) [ -x /usr/bin/locale ] && _bfs_locale_cmd=/usr/bin/locale ;;\
esac\
[ -n "$_bfs_locale_cmd" ] || [ ! -x /usr/bin/locale ] || _bfs_locale_cmd=/usr/bin/locale\
[ -n "$_bfs_locale_cmd" ] || _bfs_locale_cmd="$(command -v locale 2>/dev/null || true)"\
for _bfs_locale in C.UTF-8 C.utf8; do\
    if [ -n "$_bfs_locale_cmd" ] && \
       "$_bfs_locale_cmd" -a 2>/dev/null | grep -Fxiq "$_bfs_locale" && \
       LC_ALL="$_bfs_locale" "$_bfs_locale_cmd" charmap 2>/dev/null | grep -Fxiq UTF-8; then\
        _bfs_utf8_locale="$_bfs_locale"\
        break\
    fi\
done\
if [ -n "$_bfs_utf8_locale" ]; then\
    export LC_ALL="$_bfs_utf8_locale"\
else\
    export LC_ALL=C\
fi\
unset _bfs_utf8_locale _bfs_locale _bfs_locale_cmd _bfs_pkgmk_path' \
            /tmp/pkgutils-5.40.12/pkgmk.in

        sed -i \
            -e 's/ --static//' \
            -e 's/ -static//' \
            /tmp/pkgutils-5.40.12/Makefile

        make -j"$(nproc)" -C /tmp/pkgutils-5.40.12

        make -j"$(nproc)" \
            -C /tmp/pkgutils-5.40.12 \
            BINDIR="$TOOLS/bin" \
            MANDIR="$TOOLS/man" \
            ETCDIR="$TOOLS/etc" \
            install

        rm -rf /tmp/pkgutils-5.40.12
    fi

    echo
    echo "Resolving temporary-toolchain ports across all collections..."
    # shellcheck disable=SC2086
    if ! _validate_package_ports $toolchainpkg 2> >(tee -a "$STAGE_PREFLIGHT_LOG" >&2); then
        _stage_preflight_note "ERROR: Temporary-toolchain port validation failed before the first package build."
        return 1
    fi
    echo

    for i in $toolchainpkg; do
        local port_dir=""

        [ -f "$TOOLS/$i" ] && continue

        export tcpkg="$i"
        port_dir="$(_find_port_dir "$i")"

        cd "$port_dir"

        mkdir -p /tmp/lfs-pkg

        _start_package_log toolchain "$i"

        if pkgmk -d -is -if -cf /tmp/bootstrap.conf; then
            status=0
        else
            status=$?
        fi

        _close_active_package_log "$status"

        if [ "$status" -ne 0 ]; then
            rm -rf /tmp/lfs-pkg
            cd "$SCRIPT_DIR"
            unset tcpkg
            return "$status"
        fi

        rm -rf /tmp/lfs-pkg

        cd "$SCRIPT_DIR"

        touch "$TOOLS/$i"

        unset tcpkg
    done

    rm -f /tmp/bootstrap.conf

    echo
    echo "Verifying temporary-toolchain UTF-8 locale..."
    if [ ! -s "$TOOLS/lib/locale/locale-archive" ]; then
        echo "ERROR: Temporary glibc locale archive is missing: $TOOLS/lib/locale/locale-archive" >&2
        return 1
    fi
    if ! LC_ALL=C.utf8 "$TOOLS/bin/locale" charmap 2>/dev/null | grep -Fxiq UTF-8; then
        echo "ERROR: Temporary glibc cannot use C.utf8." >&2
        return 1
    fi

    echo
    echo "Running 32-bit and 64-bit temporary-toolchain verification..."
    if ! _verify_toolchain_multilib; then
        return 1
    fi

    local toolchain_archive

    _ensure_archive_dirs

    toolchain_archive="$TOOLCHAIN_ARCHIVE_DIR/bfs-toolchain-${BFS_VERSION}-${BUILD_DATE}.tar.xz"

    rm -f "$toolchain_archive"

    _show_menu_progress "Creating toolchain archive"         "Compressing verified temporary toolchain archive..."

    if ! (
        cd "$LFS"
        XZ_DEFAULTS='-T0' tar -cJpf "$toolchain_archive" .
    ); then
        rm -f "$toolchain_archive"
        echo "ERROR: Temporary toolchain archive creation failed." >&2
        return 1
    fi

    if ! tar -tJf "$toolchain_archive" >/dev/null; then
        rm -f "$toolchain_archive"
        echo "ERROR: Temporary toolchain archive verification failed." >&2
        return 1
    fi

    # A readable tarball is not enough: verify the expected toolchain payload.
    if ! tar -tJf "$toolchain_archive" |
        grep -Eq '^\./tmp/lfs-tools/bin/(gcc|x86_64-lfs-linux-gnu-gcc)$'
    then
        rm -f "$toolchain_archive"
        echo "ERROR: Temporary toolchain archive is missing the compiler." >&2
        return 1
    fi

    if ! tar -tJf "$toolchain_archive" | grep -Eq '^\./tmp/lfs-tools/bin/(ld|ld\.bfd)$'; then
        rm -f "$toolchain_archive"
        echo "ERROR: Temporary toolchain archive is missing the linker." >&2
        return 1
    fi

    if ! tar -tJf "$toolchain_archive" | grep -q '^\./tmp/lfs-tools/bin/pkgmk$'; then
        rm -f "$toolchain_archive"
        echo "ERROR: Temporary toolchain archive is missing pkgmk." >&2
        return 1
    fi

    if ! tar -tJf "$toolchain_archive" | grep -q '^\./tmp/lfs-tools/lib/locale/locale-archive$'; then
        rm -f "$toolchain_archive"
        echo "ERROR: Temporary toolchain archive is missing the UTF-8 locale archive." >&2
        return 1
    fi

    # Return directly to the main menu after the archive passes validation.
}

_finalize_account_database() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: Account-database finalization must be run as root." >&2
        return 1
    fi

    for account_file in "$LFS/etc/passwd" "$LFS/etc/group"; do
        if [ ! -f "$account_file" ]; then
            echo "ERROR: Cannot finalize account database; missing: $account_file" >&2
            return 1
        fi
    done

    if [ ! -x "$LFS/usr/sbin/pwconv" ] || [ ! -x "$LFS/usr/sbin/grpconv" ]; then
        echo "ERROR: Shadow account-conversion tools are missing from the target root." >&2
        echo "Expected:" >&2
        echo "  $LFS/usr/sbin/pwconv" >&2
        echo "  $LFS/usr/sbin/grpconv" >&2
        return 1
    fi

    echo "Finalizing shadow password/group databases..."

    # Shadow's pwconv/grpconv expect the destination files to exist.  The base
    # bootstrap seeds /etc/passwd and /etc/group before shadow is installed, so
    # create the protected databases explicitly before converting the completed
    # target account database.  Never run these target-finalization commands from
    # the shadow package build itself.
    touch "$LFS/etc/shadow" "$LFS/etc/gshadow"
    chown 0:0 "$LFS/etc/shadow" "$LFS/etc/gshadow"
    chmod 0600 "$LFS/etc/shadow" "$LFS/etc/gshadow"

    chroot "$LFS" \
        /usr/bin/env -i \
        HOME=/root \
        TERM="${TERM:-dumb}" \
        LANG=C \
        LC_ALL=C \
        LANGUAGE=C \
        PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        /usr/sbin/pwconv || {
            echo "ERROR: pwconv failed while finalizing the BFSOS target root." >&2
            return 1
        }

    chroot "$LFS" \
        /usr/bin/env -i \
        HOME=/root \
        TERM="${TERM:-dumb}" \
        LANG=C \
        LC_ALL=C \
        LANGUAGE=C \
        PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        /usr/sbin/grpconv || {
            echo "ERROR: grpconv failed while finalizing the BFSOS target root." >&2
            return 1
        }

    chown 0:0 "$LFS/etc/shadow" "$LFS/etc/gshadow"
    chmod 0600 "$LFS/etc/shadow" "$LFS/etc/gshadow"

    if ! grep -q '^root:' "$LFS/etc/shadow"; then
        echo "ERROR: /etc/shadow was created without a root entry." >&2
        return 1
    fi
    if ! grep -q '^root:' "$LFS/etc/gshadow"; then
        echo "ERROR: /etc/gshadow was created without a root entry." >&2
        return 1
    fi

    echo "Shadow account databases finalized successfully."
}

_verifybase() {
    local marker="$LFS/.bfs-verified"
    local failed=0

    if [ "$(id -u)" != 0 ]; then
        echo "ERROR: Base verification must be run as root." >&2
        exit 1
    fi

    echo
    echo "========================================"
    echo " BFS BASE SYSTEM VERIFICATION"
    echo "========================================"
    echo

    # Never leave a stale success marker behind after a failed verification.
    rm -f "$marker"

    # Finalize the completed target account database before validating or
    # archiving it.  A base with passwd/group but no shadow/gshadow cannot
    # authenticate users and must never receive a verification marker.
    if ! _finalize_account_database; then
        echo "ERROR: Base account-database finalization failed." >&2
        return 1
    fi

    _verify_path() {
        if [ -e "$1" ] || [ -L "$1" ]; then
            printf '  [PASS] %s\n' "$1"
        else
            printf '  [FAIL] %s is missing\n' "$1" >&2
            failed=1
        fi
    }

    echo "Checking base filesystem..."
    _verify_path "$LFS/usr/bin/bash"
    _verify_path "$LFS/usr/bin/gcc"
    _verify_path "$LFS/usr/bin/g++"
    _verify_path "$LFS/usr/bin/ld"
    _verify_path "$LFS/usr/bin/make"
    _verify_path "$LFS/usr/bin/pkgmk"
    _verify_path "$LFS/var/lib/pkg/db"
    _verify_path "$LFS/etc/passwd"
    _verify_path "$LFS/etc/group"
    _verify_path "$LFS/etc/shadow"
    _verify_path "$LFS/etc/gshadow"
    _verify_path "$LFS/etc"
    _verify_path "$LFS/var"
    _verify_path "$LFS/usr"

    if [ "$failed" -ne 0 ]; then
        echo
        echo "ERROR: Base filesystem verification failed." >&2
        return 1
    fi

    echo
    echo "Mounting virtual filesystems for chroot tests..."
    mountfs

    if ! chroot "$LFS" \
        env -i \
        HOME=/root \
        TERM="${TERM:-dumb}" \
        LANG=C \
        LC_ALL=C \
        LANGUAGE=C \
        PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        /bin/bash -c '
            set -eu

            pass() {
                printf "  [PASS] %s\\n" "$1"
            }

            fail() {
                printf "  [FAIL] %s\\n" "$1" >&2
                exit 1
            }

            echo "Checking final toolchain..."
            for cmd in gcc g++ ld make pkg-config pkgmk pkgadd pkginfo; do
                command -v "$cmd" >/dev/null 2>&1 || fail "$cmd is not available"
                pass "$cmd"
            done

            echo
            echo "Checking shell and runtime linker..."
            [ -x /bin/bash ] || fail "/bin/bash is not executable"
            [ -e /bin/sh ] || fail "/bin/sh is missing"
            readlink -e /bin/sh >/dev/null 2>&1 || fail "/bin/sh is a broken link"
            pass "/bin/sh"

            command -v ldconfig >/dev/null 2>&1 || fail "ldconfig is not available"
            ldconfig -p >/dev/null 2>&1 || fail "ldconfig cache cannot be read"
            pass "ldconfig"

            ldd /bin/bash >/dev/null 2>&1 || fail "/bin/bash dynamic libraries cannot be resolved"
            pass "/bin/bash dynamic libraries"

            echo
            echo "Checking for temporary-toolchain leakage..."
            if gcc -dumpspecs | grep -Fq /tmp/lfs-tools; then
                fail "GCC specs still reference /tmp/lfs-tools"
            fi
            pass "GCC specs contain no /tmp/lfs-tools references"

            if gcc -print-search-dirs | grep -Fq /tmp/lfs-tools; then
                fail "GCC search paths still reference /tmp/lfs-tools"
            fi
            pass "GCC search paths contain no /tmp/lfs-tools references"

            echo
            echo "Checking package database..."
            pkginfo -i >/dev/null 2>&1 || fail "package database is not readable"
            pass "package database"

            echo
            echo "Checking account databases..."
            for file in /etc/passwd /etc/group /etc/shadow /etc/gshadow; do
                [ -f "$file" ] || fail "$file is missing"
                pass "$file"
            done
            grep -q "^root:" /etc/passwd || fail "/etc/passwd has no root entry"
            grep -q "^root:" /etc/group || fail "/etc/group has no root entry"
            grep -q "^root:" /etc/shadow || fail "/etc/shadow has no root entry"
            grep -q "^root:" /etc/gshadow || fail "/etc/gshadow has no root entry"
            [ "$(stat -c %a /etc/shadow)" = 600 ] || fail "/etc/shadow mode is not 0600"
            [ "$(stat -c %a /etc/gshadow)" = 600 ] || fail "/etc/gshadow mode is not 0600"
            [ "$(grep "^root:" /etc/passwd | cut -d: -f2)" = x ] ||
                fail "/etc/passwd root password field is not shadowed"
            pass "shadow account database"

            echo
            echo "Compiling and running a C test..."
            cat > /tmp/bfs-verify.c <<"EOF_C"
#include <stdio.h>
int main(void) {
    puts("BFS C compiler test passed");
    return 0;
}
EOF_C
            gcc /tmp/bfs-verify.c -o /tmp/bfs-verify-c || fail "C compilation failed"
            /tmp/bfs-verify-c >/dev/null || fail "compiled C program failed to run"
            pass "C compile and run"

            echo
            echo "Compiling and running a C++ test..."
            cat > /tmp/bfs-verify.cpp <<"EOF_CPP"
#include <iostream>
int main() {
    std::cout << "BFS C++ compiler test passed\\n";
    return 0;
}
EOF_CPP
            g++ /tmp/bfs-verify.cpp -o /tmp/bfs-verify-cpp || fail "C++ compilation failed"
            /tmp/bfs-verify-cpp >/dev/null || fail "compiled C++ program failed to run"
            pass "C++ compile and run"

            rm -f \
                /tmp/bfs-verify.c \
                /tmp/bfs-verify.cpp \
                /tmp/bfs-verify-c \
                /tmp/bfs-verify-cpp
        '
    then
        failed=1
    fi

    umountfs

    if [ "$failed" -ne 0 ]; then
        rm -f "$marker"
        echo
        echo "========================================" >&2
        echo " BFS BASE SYSTEM VERIFICATION FAILED" >&2
        echo "========================================" >&2
        return 1
    fi

    cat > "$marker" << EOF
BFS_VERSION=$BFS_VERSION
BUILD_DATE=$BUILD_DATE
VERIFIED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

    echo
    echo "Verification marker created:"
    echo "  $marker"
    echo
    echo "========================================"
    echo " BFS BASE SYSTEM VERIFICATION PASSED"
    echo "========================================"
}

_compressrootfs() {
    local rootfs_archive
    local owner_uid=""
    local owner_gid=""

    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: Stage 5 base archive creation must run as root." >&2
        return 1
    fi

    if [ ! -f "$LFS/.bfs-verified" ]; then
        echo "ERROR: Base system has not passed stage 4 verification." >&2
        echo "Run:" >&2
        echo "  sudo $0 4" >&2
        return 1
    fi

    # Defense in depth: never archive a base whose account databases became
    # incomplete after Stage 4.  Stage 4 performs the conversion; Stage 5 only
    # verifies the invariant before creating the release artifact.
    for account_file in passwd group shadow gshadow; do
        if [ ! -f "$LFS/etc/$account_file" ]; then
            echo "ERROR: Refusing to archive base with missing /etc/$account_file." >&2
            rm -f "$LFS/.bfs-verified"
            return 1
        fi
    done
    if ! grep -q '^root:' "$LFS/etc/shadow" || ! grep -q '^root:' "$LFS/etc/gshadow"; then
        echo "ERROR: Refusing to archive incomplete shadow account databases." >&2
        rm -f "$LFS/.bfs-verified"
        return 1
    fi

    # Never archive active bootstrap bind mounts.  In particular, sources,
    # packages, and build-work are bind-mounted during Stages 2/3.
    if ! umountfs; then
        echo "ERROR: Could not unmount all bootstrap filesystems before archiving." >&2
        return 1
    fi

    for mount_path in \
        "$LFS/dev/pts" \
        "$LFS/dev" \
        "$LFS/run" \
        "$LFS/proc" \
        "$LFS/sys" \
        "$LFS/$pkgmkwork" \
        "$LFS/$pkgmkpkg" \
        "$LFS/$pkgmksrc"
    do
        if mountpoint -q "$mount_path"; then
            echo "ERROR: Refusing to archive while a bootstrap mount is still active:" >&2
            echo "  $mount_path" >&2
            return 1
        fi
    done

    # Source-cache retention is an explicit base-build policy. During normal
    # stages this path is a bind mount, so materialize it only after unmounting.
    rm -rf "$LFS/$pkgmksrc"
    mkdir -p "$LFS/$pkgmksrc"
    if [ "${BFS_KEEP_SOURCE_ARCHIVES:-no}" = yes ]; then
        echo "Including downloaded package source archives in the base rootfs..."
        cp -a "$sourcedir"/. "$LFS/$pkgmksrc"/
        du -sh "$LFS/$pkgmksrc" 2>/dev/null || true
    else
        echo "Excluding downloaded package source archives from the base rootfs (default)."
    fi

    _ensure_archive_dirs

    rootfs_archive="$BASE_ARCHIVE_DIR/bfs-rootfs-${BFS_VERSION}-${BUILD_DATE}.tar.xz"
    rm -f "$rootfs_archive"

    _show_menu_progress "Creating base archive"         "Compressing verified base rootfs archive..."

    if ! (
        cd "$LFS"
        XZ_DEFAULTS='-T0' tar \
            --exclude='./var/lib/pkg/rejected' \
            --exclude=".$TOOLS" \
            --exclude='./tmp/*' \
            --exclude='./dev/*' \
            --exclude='./sys/*' \
            --exclude='./proc/*' \
            --exclude='./run/*' \
            --exclude='./root/.cache' \
            -cJpf "$rootfs_archive" .
    ); then
        rm -f "$rootfs_archive"
        echo "ERROR: Base rootfs archive creation failed." >&2
        echo "No archive was kept." >&2
        return 1
    fi

    if ! tar -tJf "$rootfs_archive" >/dev/null; then
        rm -f "$rootfs_archive"
        echo "ERROR: Base rootfs archive verification failed." >&2
        echo "No archive was kept." >&2
        return 1
    fi

    # Sanity-check a few files required for any usable BFSOS base system.
    if ! tar -tJf "$rootfs_archive" | grep -q '^\./usr/bin/bash$' ||
       ! tar -tJf "$rootfs_archive" | grep -q '^\./usr/bin/pkgmk$' ||
       ! tar -tJf "$rootfs_archive" | grep -q '^\./etc/os-release$'
    then
        rm -f "$rootfs_archive"
        echo "ERROR: Base rootfs archive is readable but missing required files." >&2
        echo "No archive was kept." >&2
        return 1
    fi

    # Stage 5 runs through sudo from the interactive menu.  Return ownership of
    # the release artifact to the invoking user so it can be managed normally.
    if [ -n "${SUDO_UID:-}" ] && [ -n "${SUDO_GID:-}" ]; then
        owner_uid="$SUDO_UID"
        owner_gid="$SUDO_GID"
        chown "$owner_uid:$owner_gid" "$rootfs_archive" 2>/dev/null || true
    fi

    if [ "${BFS_FULL_BOOTSTRAP:-no}" = yes ]; then
        printf '\nBase rootfs compressed successfully.\nArchive created and verified:\n  %s\n' "$rootfs_archive"
    else
        _show_menu_success "Base archive complete" \
            "Base rootfs compressed successfully.\n\nArchive created and verified:\n$rootfs_archive"
    fi
}

_buildbase() {
    if [ "$(id -u)" != 0 ]; then
        echo "ERROR: Stages 2 and 3 must be run as root." >&2
        return 1
    fi

    # Any Stage 2/3 build changes the rootfs. Require Stage 4 to verify it again
    # before a new release archive can be created.
    rm -f         "$LFS/.bfs-verified"         "$LFS/.bfs-rootfs-restored"

    echo
    echo "Resolving base-system ports across all collections..."
    # shellcheck disable=SC2086
    _validate_package_ports $basepkg
    echo

    if [ ! -f "$LFS/var/lib/pkg/db" ]; then
        mkdir -pv "$LFS"/{etc,var} "$LFS"/usr/{bin,lib,sbin} "$LFS/dev"

        for i in bash cat chmod dd echo ln mkdir pwd rm stty; do
            ln -svf "$TOOLS/bin/$i" "$LFS/usr/bin"
        done

        for i in env install perl printf touch; do
            ln -svf "$TOOLS/bin/$i" "$LFS/usr/bin"
        done

        for i in bin lib sbin; do
            ln -sv "usr/$i" "$LFS/$i"
        done

        case $(uname -m) in
            x86_64)
                mkdir -pv "$LFS/lib64"
                ;;
        esac

        mkdir -pv "$LFS/usr/lib32"

        ln -sv usr/lib32 "$LFS/lib32"

        ln -svf \
            "$TOOLS/lib/libgcc_s.so" \
            "$TOOLS/lib/libgcc_s.so.1" \
            "$LFS/usr/lib"

        ln -svf \
            "$TOOLS/lib/libstdc++.a" \
            "$TOOLS/lib/libstdc++.so" \
            "$TOOLS/lib/libstdc++.so.6" \
            "$LFS/usr/lib"

        ln -svf bash "$LFS/bin/sh"

        ln -svf /proc/self/mounts "$LFS/etc/mtab"

        cat ports/core/aaa_filesystem/passwd > "$LFS/etc/passwd"
        cat ports/core/aaa_filesystem/group > "$LFS/etc/group"

        mkdir -p "$LFS/var/lib/pkg"
        touch "$LFS/var/lib/pkg/db"

        mkdir -p "$LFS/$pkgmkpkg"
        mkdir -p "$LFS/$pkgmksrc"
        mkdir -p "$packagedir"
    fi

    rm -rf "$LFS/usr/ports/"

    cp -r ports/ "$LFS/usr/"

    # Apply the selected non-systemd recipe overlay after importing the
    # upstream Pkgfile tree. The systemd profile intentionally uses the
    # upstream recipes unchanged.
    if [ "$BFS_INIT_SYSTEM" != systemd ] &&
       [ -d "$SCRIPT_DIR/profiles/init/overlays/$BFS_INIT_SYSTEM" ]; then
        cp -a "$SCRIPT_DIR/profiles/init/overlays/$BFS_INIT_SYSTEM/." \
            "$LFS/usr/ports/"
    fi

    mkdir -p "$LFS/tmp/lfs-tools/bin"
    cp files/pkgin "$LFS/tmp/lfs-tools/bin/pkgin"
    chmod +x "$LFS/tmp/lfs-tools/bin/pkgin"

    mkdir -p "$LFS/var/lib/pkgmk"
    mkdir -p "$buildworkdir"

    echo "Stage 2/3 package work directory:"
    echo "  $buildworkdir"

    cp ports/core/pkgutils/extension \
        "$LFS/var/lib/pkgmk"

    # Create the target ccache configuration now.  During Stage 2 the compiler
    # wrapper path remains inactive until the BFSOS ccache package is actually
    # installed.  Stage 3 can use the already-installed target ccache from its
    # first normal package build.
    _prepare_target_ccache

    resolved_ccache_size="$(_resolve_ccache_size)"

    cat > "$LFS/tmp/pkgmk.conf" <<EOF
# Do not force LC_ALL=C here.
# pkgmk selects a UTF-8-capable C locale when available so libarchive can
# extract source archives containing UTF-8 pathnames.

export CPPFLAGS="-I/usr/include"
export CFLAGS="$CFLAGS"
export CXXFLAGS="\${CFLAGS}"
export LDFLAGS="-L/usr/lib -Wl,-rpath-link,/usr/lib"
export LIBRARY_PATH="/usr/lib"

export PKG_CONFIG_PATH="/usr/lib/pkgconfig:/usr/share/pkgconfig"
export PKG_CONFIG_LIBDIR="/usr/lib/pkgconfig:/usr/share/pkgconfig"

# BFSOS X.Org build policy. Do not rely on login-shell profile.d loading.
export XORG_PREFIX="/usr"
export XORG_CONFIG="--prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-static"

export JOBS=${BFS_BUILD_JOBS/auto/$(nproc)}
export MAKEFLAGS="-j \$JOBS"

# Bootstrap-safe ccache policy.  The live host is never used.  This condition
# becomes true only after the BFSOS ccache package has installed both ccache
# itself and its compiler-wrapper directory inside the target rootfs.
export BFS_CCACHE="$BFS_CCACHE"
export BFS_CCACHE_SIZE="$resolved_ccache_size"
export CCACHE_DIR="/var/cache/ccache"
if [ "\$BFS_CCACHE" = yes ] &&
   [ -x /usr/bin/ccache ] &&
   [ -x /usr/lib/ccache/gcc ]; then
    export PATH="/usr/lib/ccache:\$PATH"
fi

PKGMK_SOURCE_ROOT="/$pkgmksrc"
PKGMK_SOURCE_DIR="\$PKGMK_SOURCE_ROOT/\$name"
mkdir -p "\$PKGMK_SOURCE_DIR" || exit 1
PKGMK_PACKAGE_DIR="/$pkgmkpkg"
PKGMK_WORK_DIR="/$pkgmkwork/pkgmk-\$name"

# Bootstrap integrity policy. All checks default to enabled; development
# bypasses require an explicit settings change and are visible in this file/log.
PKGMK_IGNORE_MD5SUM="$([ "$BFS_VERIFY_MD5" = yes ] && echo no || echo yes)"
PKGMK_IGNORE_SIGNATURE="$([ "$BFS_VERIFY_SIGNATURE" = yes ] && echo no || echo yes)"
PKGMK_IGNORE_FOOTPRINT="$([ "$BFS_VERIFY_FOOTPRINT" = yes ] && echo no || echo yes)"

# Match the installed BFSOS downloader policy during Stage 2/3: go directly
# to Pkgfile sources, resume partial downloads, and detect dead/stalled links.
PKGMK_SOURCE_MIRRORS=()
PKGMK_SOURCE_FLAT_FALLBACKS=(
    "https://mirror.math.princeton.edu/pub/redcorelinux/amd64/distfiles"
)
PKGMK_SOURCE_FALLBACKS=(
    "https://xorg.freedesktop.org/releases/|https://www.x.org/archive/"
    "https://www.x.org/releases/|https://www.x.org/archive/"
    "https://ftp.gnu.org/gnu/|https://ftpmirror.gnu.org/"
    "https://download.savannah.gnu.org/releases/|https://mirror.fi.ossplanet.net/nongnu/"
    "https://cdn.kernel.org/pub/|https://mirrors.edge.kernel.org/pub/"
    "https://www.kernel.org/pub/|https://mirrors.edge.kernel.org/pub/"
)
PKGMK_DOWNLOAD_PROG="curl"
PKGMK_CURL_OPTS="--fail --location --continue-at - --connect-timeout 10 --speed-limit 1024 --speed-time 30 --retry 3 --retry-delay 2 --retry-max-time 180 --retry-connrefused"

. /var/lib/pkgmk/extension
EOF

    # Keep the installed/final pkgmk configuration on the external build-work
    # bind mount too. Stage 3 uses the installed pkgmk configuration for its
    # exact-package rebuilds, so without this it falls back to
    # /var/cache/pkg/work inside the small
    # LiveGUI-backed rootfs and GCC can exhaust that filesystem.
    if [ -f "$LFS/etc/pkgmk.conf" ]; then
        if [ "$BFS_BUILD_SETTINGS_CHANGED" = yes ]; then
            jobs="$BFS_BUILD_JOBS"; [ "$jobs" = auto ] && jobs="$(nproc)"
            sed -i -e "s|^export CFLAGS=.*|export CFLAGS=\"$CFLAGS\"|" \
                   -e "s|^export CXXFLAGS=.*|export CXXFLAGS=\"\${CFLAGS}\"|" \
                   -e "s|^export JOBS=.*|export JOBS=$jobs|" \
                   -e "s|^export MAKEFLAGS=.*|export MAKEFLAGS=\"-j \$JOBS\"|" \
                   "$LFS/etc/pkgmk.conf"
            # Replace the BFSOS bootstrap-managed ccache block rather than
            # appending duplicate settings on every Stage 2/3 run.
            sed -i '/^# BEGIN BFSOS BOOTSTRAP CCACHE$/,/^# END BFSOS BOOTSTRAP CCACHE$/d' \
                "$LFS/etc/pkgmk.conf"
            cat >> "$LFS/etc/pkgmk.conf" <<EOF_INSTALLED_CCACHE

# BEGIN BFSOS BOOTSTRAP CCACHE
export BFS_CCACHE="$BFS_CCACHE"
export BFS_CCACHE_SIZE="$resolved_ccache_size"
export CCACHE_DIR="/var/cache/ccache"
if [ "\$BFS_CCACHE" = yes ] &&
   [ -x /usr/bin/ccache ] &&
   [ -x /usr/lib/ccache/gcc ]; then
    export PATH="/usr/lib/ccache:\$PATH"
fi
# END BFSOS BOOTSTRAP CCACHE
EOF_INSTALLED_CCACHE
        fi
        # Ensure an existing installed pkgmk.conf has the target-only ccache
        # policy even when build settings were left at their saved/default values.
        if ! grep -q '^# BEGIN BFSOS BOOTSTRAP CCACHE$' "$LFS/etc/pkgmk.conf"; then
            cat >> "$LFS/etc/pkgmk.conf" <<EOF_INSTALLED_CCACHE_DEFAULT

# BEGIN BFSOS BOOTSTRAP CCACHE
export BFS_CCACHE="$BFS_CCACHE"
export BFS_CCACHE_SIZE="$resolved_ccache_size"
export CCACHE_DIR="/var/cache/ccache"
if [ "\$BFS_CCACHE" = yes ] &&
   [ -x /usr/bin/ccache ] &&
   [ -x /usr/lib/ccache/gcc ]; then
    export PATH="/usr/lib/ccache:\$PATH"
fi
# END BFSOS BOOTSTRAP CCACHE
EOF_INSTALLED_CCACHE_DEFAULT
        fi

        sed -i '/^# BEGIN BFSOS BOOTSTRAP INTEGRITY$/,/^# END BFSOS BOOTSTRAP INTEGRITY$/d' \
            "$LFS/etc/pkgmk.conf"
        cat >> "$LFS/etc/pkgmk.conf" <<EOF_INSTALLED_INTEGRITY

# BEGIN BFSOS BOOTSTRAP INTEGRITY
PKGMK_IGNORE_MD5SUM="$([ "$BFS_VERIFY_MD5" = yes ] && echo no || echo yes)"
PKGMK_IGNORE_SIGNATURE="$([ "$BFS_VERIFY_SIGNATURE" = yes ] && echo no || echo yes)"
PKGMK_IGNORE_FOOTPRINT="$([ "$BFS_VERIFY_FOOTPRINT" = yes ] && echo no || echo yes)"
# END BFSOS BOOTSTRAP INTEGRITY
EOF_INSTALLED_INTEGRITY

        # Never point pkgmk at the bind-mount root itself.  pkgmk removes its
        # work directory during cleanup; using the mount point directly causes
        # "Device or resource busy".  Give each port a removable child dir.
        if grep -q '^# *PKGMK_WORK_DIR=' "$LFS/etc/pkgmk.conf"; then
            sed -i 's|^# *PKGMK_WORK_DIR=.*|PKGMK_WORK_DIR="/var/cache/pkg/build-work/pkgmk-$name"|'                 "$LFS/etc/pkgmk.conf"
        elif grep -q '^PKGMK_WORK_DIR=' "$LFS/etc/pkgmk.conf"; then
            sed -i 's|^PKGMK_WORK_DIR=.*|PKGMK_WORK_DIR="/var/cache/pkg/build-work/pkgmk-$name"|'                 "$LFS/etc/pkgmk.conf"
        else
            printf '\nPKGMK_WORK_DIR="/var/cache/pkg/build-work/pkgmk-$name"\n'                 >> "$LFS/etc/pkgmk.conf"
        fi

        echo "Final pkgmk work directory configured:"
        grep '^PKGMK_WORK_DIR=' "$LFS/etc/pkgmk.conf" || true
    fi

    cat > "$LFS/tmp/pkgmk.systemd-bootstrap.conf" <<EOF
# Do not force LC_ALL=C here.
# Preserve pkgmk's archive-safe locale selection.

# systemd needs these before final util-linux exists.
export CFLAGS="-O2 -march=x86-64 -pipe"
export CXXFLAGS="\${CFLAGS}"
export LDFLAGS="-L/usr/lib -Wl,-rpath-link,/usr/lib"

# Expose only the temporary util-linux libraries to systemd.
# All other dependencies must come from the Stage-2 BFS system.
export PKG_CONFIG_PATH="/tmp/systemd-util-linux-pc:/usr/lib/pkgconfig:/usr/share/pkgconfig"
export PKG_CONFIG_LIBDIR="/tmp/systemd-util-linux-pc:/usr/lib/pkgconfig:/usr/share/pkgconfig"

export JOBS=$(nproc)
export MAKEFLAGS="-j \$JOBS"

# Keep the special systemd bootstrap transaction uncached.
export BFS_CCACHE=no
export CCACHE_DISABLE=1

PKGMK_SOURCE_ROOT="/$pkgmksrc"
PKGMK_SOURCE_DIR="\$PKGMK_SOURCE_ROOT/\$name"
mkdir -p "\$PKGMK_SOURCE_DIR" || exit 1
PKGMK_PACKAGE_DIR="/$pkgmkpkg"
PKGMK_WORK_DIR="/$pkgmkwork/pkgmk-\$name"

PKGMK_SOURCE_MIRRORS=()
PKGMK_SOURCE_FLAT_FALLBACKS=(
    "https://mirror.math.princeton.edu/pub/redcorelinux/amd64/distfiles"
)
PKGMK_SOURCE_FALLBACKS=(
    "https://xorg.freedesktop.org/releases/|https://www.x.org/archive/"
    "https://www.x.org/releases/|https://www.x.org/archive/"
    "https://ftp.gnu.org/gnu/|https://ftpmirror.gnu.org/"
    "https://download.savannah.gnu.org/releases/|https://mirror.fi.ossplanet.net/nongnu/"
    "https://cdn.kernel.org/pub/|https://mirrors.edge.kernel.org/pub/"
    "https://www.kernel.org/pub/|https://mirrors.edge.kernel.org/pub/"
)
PKGMK_DOWNLOAD_PROG="curl"
PKGMK_CURL_OPTS="--fail --location --continue-at - --connect-timeout 10 --speed-limit 1024 --speed-time 30 --retry 3 --retry-delay 2 --retry-max-time 180 --retry-connrefused"

. /var/lib/pkgmk/extension
EOF

    # Provide systemd with only the temporary util-linux pkg-config files.
    mkdir -p "$LFS/tmp/systemd-util-linux-pc"

    for pc in uuid blkid mount; do
        cp "$LFS/tmp/lfs-tools/lib/pkgconfig/$pc.pc"             "$LFS/tmp/systemd-util-linux-pc/$pc.pc"
    done

    LFSPATH=/bin:/usr/bin:/sbin:/usr/sbin

    if [ "${1:-}" != rebuild ]; then
        LFSPATH=$LFSPATH:$TOOLS/bin
    fi

    STAGE_BUILD_PATH="$LFSPATH"
    if [ "${1:-}" = rebuild ] && [ "${BFS_CCACHE:-yes}" = yes ]; then
        STAGE_BUILD_PATH="/usr/lib/ccache:$LFSPATH"
        echo "Stage 3 ccache preflight..."
        if ! chroot "$LFS" env -i HOME=/root PATH=/usr/bin:/usr/sbin:/bin:/sbin \
                /bin/sh -c 'test -x /usr/bin/ccache && test -x /usr/lib/ccache/gcc && test -x /usr/lib/ccache/g++'; then
            echo "ERROR: Stage 3 is configured to use ccache, but the BFSOS ccache binary/compiler wrappers are missing." >&2
            return 1
        fi
        echo "Stage 3 ccache statistics before rebuild:"
        chroot "$LFS" env -i HOME=/root PATH=/usr/bin:/usr/sbin:/bin:/sbin \
                CCACHE_DIR=/var/cache/ccache /usr/bin/ccache -s 2>/dev/null || true
    fi

    mountfs

    # Stage 3 is an exact rebuild pass. Stage 2 has already established the
    # base package set, so Stage 3 must never resolve or install newly declared
    # dependencies. Normal prt-get update dependency refresh remains useful on
    # an installed BFSOS system, but it is intentionally bypassed here.

    for i in $basepkg; do
        if [ "${1:-}" != rebuild ]; then
            pkginfo -i -r "$LFS" |
                awk '{print $1}' |
                grep -qx "$i" &&
                continue

            _start_package_log base "$i"

            unset _force

            case $i in
                aaa_filesystem|gcc|bash|dash|perl|coreutils|pkgutils)
                    _force=-f
                    ;;
            esac

            pkgmk_conf=/tmp/pkgmk.conf

            if [ "${1:-}" != rebuild ] && [ "$i" = systemd ]; then
                pkgmk_conf=/tmp/pkgmk.systemd-bootstrap.conf
                echo "Using temporary util-linux libraries for systemd bootstrap."
            fi

            integrity_opts=""
            [ "$BFS_VERIFY_SIGNATURE" = yes ] || integrity_opts="$integrity_opts -is"
            [ "$BFS_VERIFY_FOOTPRINT" = yes ] || integrity_opts="$integrity_opts -if"
            [ "$BFS_VERIFY_MD5" = yes ] || integrity_opts="$integrity_opts -im"
            if [ -n "$integrity_opts" ]; then
                echo "WARNING: development integrity bypass active:$integrity_opts"
            fi

            chroot "$LFS" \
                env -i \
                HOME=/root \
                TERM="${TERM:-dumb}" \
                PATH="$LFSPATH" \
                pkgin -d "$i" $integrity_opts -cf "$pkgmk_conf" \
                || {
                    status=$?
                    _close_active_package_log "$status"
                    umountfs
                    return "$status"
                }

            pkgadd -r "$LFS" ${_force:-} -f \
                "$(ls -1 "$packagedir/$i#"* | tail -n1)" \
                || {
                    status=$?
                    _close_active_package_log "$status"
                    umountfs
                    return "$status"
                }

            case "$i" in
                ca-certificates)
                    if ! chroot "$LFS" /bin/sh -c 'test -s /etc/pki/tls/certs/ca-bundle.crt'; then
                        echo "ERROR: ca-certificates did not create a non-empty canonical CA bundle." >&2
                        _close_active_package_log 1
                        umountfs
                        return 1
                    fi
                    echo "CA trust-store canonical bundle initialized."
                    ;;
                curl)
                    if ! chroot "$LFS" env -i HOME=/root PATH=/usr/bin:/usr/sbin:/bin:/sbin \
                        /usr/bin/curl -fsSI --connect-timeout 10 https://kernel.org/ >/dev/null; then
                        echo "ERROR: final BFSOS curl failed HTTPS trust-store sanity check." >&2
                        _close_active_package_log 1
                        umountfs
                        return 1
                    fi
                    echo "Final BFSOS curl HTTPS trust-store sanity check passed."
                    ;;
            esac

            case $i in
                glibc)
                    echo "Generating target C.UTF-8 locale before later package extraction..."
                    if chroot "$LFS" \
                        env -i \
                        HOME=/root \
                        TERM="${TERM:-dumb}" \
                        PATH="$LFSPATH" \
                        /bin/sh -c 'mkdir -p /usr/lib/locale && /usr/bin/localedef -i C -f UTF-8 C.UTF-8 && LC_ALL=C.utf8 /usr/bin/locale charmap | grep -Fxiq UTF-8'
                    then
                        :
                    else
                        status=$?
                        echo "ERROR: Failed to generate/validate the target C.UTF-8 locale after glibc installation." >&2
                        _close_active_package_log "$status"
                        umountfs
                        return "$status"
                    fi

                    cat << EOF > "$LFS/tmp/glibc-postinstall"
#!/bin/sh
set -e

export LANG=C
export LC_ALL=C
export LANGUAGE=C

TOOLS="$TOOLS"
HOST_TRIPLET="\$(uname -m)-pc-linux-gnu"
REAL_LD=""
SAVED_LD="/tmp/ld-real.\$\$"

cleanup() {
    rm -f "\$SAVED_LD"
}

trap cleanup EXIT HUP INT TERM

echo "Adjusting GCC and binutils after glibc"

for candidate in \
    "\$TOOLS/bin/ld.bfd" \
    "\$TOOLS/\$HOST_TRIPLET/bin/ld.bfd" \
    "\$TOOLS/bin/ld-new" \
    "\$TOOLS/\$HOST_TRIPLET/bin/ld-new" \
    "\$TOOLS/bin/ld" \
    "\$TOOLS/\$HOST_TRIPLET/bin/ld"
do
    if [ -f "\$candidate" ] &&
        file "\$candidate" 2>/dev/null | grep -q 'ELF'
    then
        REAL_LD="\$candidate"
        break
    fi
done

if [ -z "\$REAL_LD" ]; then
    echo "ERROR: No real ELF ld executable found."

    echo
    echo "Available linker candidates:"

    for candidate in \
        "\$TOOLS/bin/ld.bfd" \
        "\$TOOLS/\$HOST_TRIPLET/bin/ld.bfd" \
        "\$TOOLS/bin/ld-new" \
        "\$TOOLS/\$HOST_TRIPLET/bin/ld-new" \
        "\$TOOLS/bin/ld" \
        "\$TOOLS/\$HOST_TRIPLET/bin/ld"
    do
        if [ -e "\$candidate" ]; then
            file "\$candidate"
        fi
    done

    return 1
fi

echo "Using linker: \$REAL_LD"

# Save the real linker before renaming any path that may refer to it.
cp -av "\$REAL_LD" "\$SAVED_LD"

if [ -e "\$TOOLS/bin/ld" ] &&
    [ ! -e "\$TOOLS/bin/ld-old" ]
then
    mv -v "\$TOOLS/bin/ld" "\$TOOLS/bin/ld-old"
fi

if [ -e "\$TOOLS/\$HOST_TRIPLET/bin/ld" ] &&
    [ ! -e "\$TOOLS/\$HOST_TRIPLET/bin/ld-old" ]
then
    mv -v \
        "\$TOOLS/\$HOST_TRIPLET/bin/ld" \
        "\$TOOLS/\$HOST_TRIPLET/bin/ld-old"
fi

install -m 0755 "\$SAVED_LD" "\$TOOLS/bin/ld"
install -m 0755 \
    "\$SAVED_LD" \
    "\$TOOLS/\$HOST_TRIPLET/bin/ld"

gcc -dumpspecs | sed \
    -e "s@\$TOOLS@@g" \
    -e "/\*startfile_prefix_spec:/{n;s@.*@/usr/lib/ @}" \
    -e '/\*cpp:/{n;s@\$@ -isystem /usr/include@}' \
    > "\$(dirname "\$(gcc --print-libgcc-file-name)")/specs"

echo 'int main(void) { return 0; }' > dummy.c

cc -c dummy.c -o dummy.o

rm -f dummy.c dummy.o

echo 'int main(void) { return 0; }' > dummy.c

cc dummy.c -v -Wl,--verbose > dummy.log 2>&1

readelf -l a.out | grep ': /lib' \
    > /tmp/adjusttoolchainresult || true

grep -o '/usr/lib.*/crt[1in].*succeeded' dummy.log \
    >> /tmp/adjusttoolchainresult || true

grep -B1 '^ /usr/include' dummy.log \
    >> /tmp/adjusttoolchainresult || true

grep 'SEARCH.*/usr/lib' dummy.log |
    sed 's|; |\n|g' \
    >> /tmp/adjusttoolchainresult || true

grep "/lib.*/libc.so.6 " dummy.log \
    >> /tmp/adjusttoolchainresult || true

grep found dummy.log \
    >> /tmp/adjusttoolchainresult || true

rm -fv dummy.c dummy.o a.out dummy.log
EOF

                    chroot "$LFS" \
                        env -i \
                        HOME=/root \
                        TERM="${TERM:-dumb}" \
                        LANG=C \
                        LC_ALL=C \
                        LANGUAGE=C \
                        PATH="$LFSPATH" \
                        sh /tmp/glibc-postinstall

                    rm -f "$LFS/tmp/glibc-postinstall"
                    ;;
            esac

            _close_active_package_log 0
        else
            _start_package_log base "$i"

            integrity_opts=""
            [ "$BFS_VERIFY_SIGNATURE" = yes ] || integrity_opts="$integrity_opts -is"
            [ "$BFS_VERIFY_FOOTPRINT" = yes ] || integrity_opts="$integrity_opts -if"
            [ "$BFS_VERIFY_MD5" = yes ] || integrity_opts="$integrity_opts -im"
            if [ -n "$integrity_opts" ]; then
                echo "WARNING: development integrity bypass active:$integrity_opts"
            fi

            # Stage 3 may only rebuild packages that Stage 2 already installed.
            # If basepkg changed after Stage 2, stop and require Stage 2 again
            # instead of silently growing the base through dependency resolution.
            if ! chroot "$LFS" \
                env -i \
                HOME=/root \
                PATH=/usr/bin:/usr/sbin:/bin:/sbin \
                /usr/bin/pkginfo -i | awk '{print $1}' | grep -qx "$i"
            then
                echo "ERROR: Stage 3 expected '$i' to already be installed by Stage 2." >&2
                echo "ERROR: Re-run Stage 2 before Stage 3; Stage 3 will not install new base packages." >&2
                _close_active_package_log 1
                umountfs
                return 1
            fi

            # Rebuild exactly this base package with the final BFSOS toolchain.
            # Stage 2 left its package archive in the shared package cache, so
            # remove cached copies first; otherwise pkgmk may consider the package
            # already built and Stage 3 would not actually recompile it.
            rm -f "$packagedir/$i#"*

            # Use pkgin only as the single-port pkgmk wrapper, exactly as Stage 2
            # does; do not invoke prt-get here because current prt-get update
            # intentionally discovers and installs newly required dependencies.
            chroot "$LFS" \
                env -i \
                HOME=/root \
                TERM="${TERM:-dumb}" \
                LANG=C \
                LC_ALL=C \
                LANGUAGE=C \
                PATH="$STAGE_BUILD_PATH" \
                CCACHE_DIR=/var/cache/ccache \
                /tmp/lfs-tools/bin/pkgin -d "$i" $integrity_opts -cf /etc/pkgmk.conf \
                || {
                    status=$?
                    _close_active_package_log "$status"
                    umountfs
                    return "$status"
                }

            package_file="$(ls -1 "$packagedir/$i#"* 2>/dev/null | tail -n1)"
            if [ -z "$package_file" ] || [ ! -f "$package_file" ]; then
                echo "ERROR: Stage 3 rebuilt $i but no package archive was found in $packagedir." >&2
                _close_active_package_log 1
                umountfs
                return 1
            fi

            echo "Stage 3: reinstalling exact rebuilt package: $(basename "$package_file")"
            chroot "$LFS" \
                env -i \
                HOME=/root \
                PATH=/usr/bin:/usr/sbin:/bin:/sbin \
                /usr/bin/pkgadd -u -f "/$pkgmkpkg/$(basename "$package_file")" \
                || {
                    status=$?
                    _close_active_package_log "$status"
                    umountfs
                    return "$status"
                }

            _close_active_package_log 0
        fi
    done

    if [ "${1:-}" != rebuild ]; then
        _copy_base_logs_into_rootfs
    fi

    if [ "${1:-}" = rebuild ] && [ "${BFS_CCACHE:-yes}" = yes ]; then
        echo "Stage 3 ccache statistics after rebuild:"
        chroot "$LFS" env -i HOME=/root PATH=/usr/bin:/usr/sbin:/bin:/sbin \
                CCACHE_DIR=/var/cache/ccache /usr/bin/ccache -s 2>/dev/null || true
    fi

    umountfs

    if [ "${1:-}" = rebuild ]; then
        touch "$LFS/.bfs-stage3-complete"
    else
        touch "$LFS/.bfs-stage2-complete"
        rm -f "$LFS/.bfs-stage3-complete"
    fi

    echo
    echo "base system build completed"
}

mountfs() {
    umountfs

    mkdir -p "$LFS/dev" "$LFS/run" "$LFS/proc" "$LFS/sys"

    mount --bind /dev "$LFS/dev"

    mount -t devpts devpts \
        "$LFS/dev/pts" \
        -o gid=5,mode=620

    mount -t proc proc "$LFS/proc"
    mount -t sysfs sysfs "$LFS/sys"
    mount -t tmpfs tmpfs "$LFS/run"

    if [ -h "$LFS/dev/shm" ]; then
        mkdir -p "$LFS/$(readlink "$LFS/dev/shm")"
    fi

    mkdir -p "$LFS/$pkgmksrc"
    mkdir -p "$LFS/$pkgmkpkg"
    mkdir -p "$LFS/$pkgmkwork"

    mkdir -p "$sourcedir" "$packagedir" "$buildworkdir"

    mount --bind "$sourcedir" "$LFS/$pkgmksrc"
    mount --bind "$packagedir" "$LFS/$pkgmkpkg"
    mount --bind "$buildworkdir" "$LFS/$pkgmkwork"
}

umountfs() {
    unmount "$LFS/dev/pts"
    unmount "$LFS/dev"
    unmount "$LFS/run"
    unmount "$LFS/proc"
    unmount "$LFS/sys"
    unmount "$LFS/$pkgmkwork"
    unmount "$LFS/$pkgmkpkg"
    unmount "$LFS/$pkgmksrc"
}

unmount() {
    while mountpoint -q "$1"; do
        if ! umount "$1" 2>/dev/null; then
            echo "ERROR: Could not unmount busy bootstrap mount: $1" >&2
            return 1
        fi
    done
    return 0
}

export LFS=/tmp/lfs-rootfs
export TOOLS=/tmp/lfs-tools

export PATH=$TOOLS/bin:$PATH

toolchainpkg="
binutils-pass1
gmp
mpfr
mpc
gcc-pass1
linux-headers
glibc
gcc-pass2
binutils-pass2
libxcrypt
gcc-pass3
m4
ncurses
bash
bash-completion
bison
bzip2
coreutils
diffutils
file
findutils
gawk
gettext
grep
gzip
make
patch
perl
zlib
xz
libtirpc
libnsl
python3
sed
tar
texinfo
openssl
ca-certificates
curl
libarchive
util-linux
"
# pkgconf 3.x builds with Meson, and Meson requires Ninja.
# Keep Ninja before pkgconf in Stage 2.  Do not place comments inside the
# quoted basepkg list because they become package names during word splitting.
basepkg="
aaa_filesystem
linux-headers
man-pages
glibc
autoconf
zlib
bzip2
xz
file
ncurses
readline
m4
bc
binutils
ninja
pkgconf
libxcrypt
gmp
mpfr
mpc
attr
acl
gcc
libcap
psmisc
sed
tzdata
iana-etc
bison
flex
pcre2
grep
bash
bash-completion
libtool
gdbm
gperf
expat
inetutils
perl
perl-class-inspector
perl-file-sharedir-install
perl-file-sharedir
perl-xml-parser
intltool
automake
openssl
ca-certificates
curl
libtasn1
gettext
elfutils
libffi
sqlite
python3
coreutils
check
diffutils
gawk
findutils
groff
less
gzip
zstd
iptables
libtirpc
iproute2
kbd
libpipeline
make
patch
man-db
tar
texinfo
python3-setuptools
python3-pip
python3-flit-core
python3-packaging
python3-installer
python3-build
python3-pyproject-hooks
python3-wheel
libuv
libarchive
cmake
fmt
xxhash
ccache
boost
meson
p11-kit
make-ca
kmod
cracklib
linux-pam
libpwquality
shadow
libpng
which
freetype
fuse
grub
popt
mandoc
efivar
efibootmgr
grub-efi
vim
nano
python3-markupsafe
python3-tomli
python3-pytz
python3-babel
python3-jinja2
systemd
util-linux
dbus
procps-ng
e2fsprogs
fakeroot
pkgutils
dialog
prt-get
git
httpup
ports
prt-utils
pciutils
lzo
btrfs-progs
dosfstools
exfatprogs
f2fs-tools
mdadm
libaio
lvm2
inih
liburcu
xfsprogs
openssh
genfstab
rsync
traceroute
signify
"

case "$BFS_INIT_SYSTEM" in
    systemd)
        ;;
    openrc)
        basepkg="$(printf '%s\n' "$basepkg" | sed '/^systemd$/d')
openrc
openrc-init-scripts"
        ;;
    sysvinit)
        basepkg="$(printf '%s\n' "$basepkg" | sed '/^systemd$/d')
sysvinit
lfs-bootscripts"
        ;;
    *)
        echo "ERROR: Unsupported BFS_INIT_SYSTEM: $BFS_INIT_SYSTEM" >&2
        echo "Choose systemd, openrc, or sysvinit." >&2
        exit 2
        ;;
esac

sourcedir="$PWD/sources"
packagedir="$PWD/packages"

# Stage 2/3 pkgmk build trees can be several GiB (especially GCC multilib).
# Keep them on the same filesystem as the BFS repository rather than the
# LiveGUI /tmp overlay, which may be very small.
buildworkdir="$PWD/build-work"

pkgmkpkg="var/cache/pkg/packages"
pkgmksrc="var/cache/pkg/sources"
pkgmkwork="var/cache/pkg/build-work"



case "${1:-menu}" in
    menu|"")
        _bootstrap_menu
        ;;
    1|toolchain|build-toolchain)
        _buildtoolchain
        ;;
    2|base|build-base)
        _buildbase
        ;;
    3|rebuild|rebuild-base)
        _buildbase rebuild
        ;;
    4|verify|verify-base)
        _verifybase
        ;;
    5|archive|archive-base)
        _compressrootfs
        ;;
    6|restore-base)
        _restore_rootfs
        ;;
    7|restore-toolchain)
        _restore_toolchain
        ;;
    settings|build-settings)
        compiler_build_settings_menu
        ;;
    iso|build-iso|create-iso)
        _launch_iso_builder "${@:2}"
        ;;
    8|chroot)
        _enter_bfs_chroot
        ;;
    9|install|installer)
        _launch_bfs_installer
        ;;
    full|full-bootstrap|all)
        _run_full_bootstrap
        ;;
    resume-full|resume-bootstrap|continue-full)
        _run_resume_full_bootstrap
        ;;
    0|stop|kill)
        _stop_bootstrap
        ;;
    -h|--help|help)
        cat <<EOF
Usage:
  $0             Open the interactive bootstrap menu
  $0 menu        Open the interactive bootstrap menu
  $0 1-7         Run a bootstrap stage directly
  $0 toolchain|build-toolchain
  $0 base|build-base
  $0 rebuild|rebuild-base
  $0 verify|verify-base
  $0 archive|archive-base
  $0 restore-base|restore-toolchain
  $0 settings|build-settings
  $0 iso|build-iso|create-iso
                  Reuse a verified base (or build one if needed) and create bootable ISO media
  $0 8|chroot    Enter the BFS chroot
  $0 9|installer Launch the newest BFSOS installer from scripts/
  $0 full|full-bootstrap|all
                  Run the complete build, verify, and archive workflow
  $0 resume-full|continue-full
                  Resume at the first incomplete stage and continue through Stage 5
  $0 0|stop|kill Stop a running bootstrap process group
EOF
        ;;
    *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
esac

exit 0
