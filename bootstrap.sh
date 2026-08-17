#!/bin/bash -e

# BFSOS bootstrap r55 - RC tracker consolidated fixes

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

BFS_BUILD_JOBS="auto"
BFS_BUILD_OPT="portable"
BFS_CCACHE="yes"
BFS_CCACHE_SIZE="auto"
BFS_BUILD_SETTINGS_CHANGED="no"

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
    if [ "$BFS_CCACHE" = yes ]; then export PATH="/usr/lib/ccache:$PATH"; fi
}

load_bootstrap_settings() {
    BFS_THEME="${BFS_BOOTSTRAP_THEME:-slackware}"
    if [ -r "$BOOTSTRAP_SETTINGS_FILE" ]; then
        # shellcheck disable=SC1090
        . "$BOOTSTRAP_SETTINGS_FILE"
    fi
    _apply_build_settings
}

save_bootstrap_settings() {
    cat > "$BOOTSTRAP_SETTINGS_FILE" <<EOF_SETTINGS
BFS_BUILD_JOBS='$BFS_BUILD_JOBS'
BFS_BUILD_OPT='$BFS_BUILD_OPT'
BFS_CCACHE='$BFS_CCACHE'
BFS_CCACHE_SIZE='$BFS_CCACHE_SIZE'
BFS_BUILD_SETTINGS_CHANGED='$BFS_BUILD_SETTINGS_CHANGED'
EOF_SETTINGS
    _apply_build_settings
}

compiler_build_settings_menu() {
    local jobs opt cache size
    printf '\nCompiler / Build Settings\n=========================\n'
    printf 'Jobs [auto or number] (current %s): ' "$BFS_BUILD_JOBS"; read -r jobs; [ -z "$jobs" ] || BFS_BUILD_JOBS="$jobs"
    printf 'Optimization [portable/native/custom] (current %s): ' "$BFS_BUILD_OPT"; read -r opt
    case "$opt" in
        native) BFS_BUILD_OPT=native ;;
        portable) BFS_BUILD_OPT=portable ;;
        custom) printf 'CFLAGS: '; read -r opt; [ -z "$opt" ] || BFS_BUILD_OPT="custom:$opt" ;;
        '') ;;
    esac
    printf 'ccache [yes/no] (current %s): ' "$BFS_CCACHE"; read -r cache; case "$cache" in yes|no) BFS_CCACHE="$cache";; esac
    printf 'ccache size [auto/20G/etc.] (current %s): ' "$BFS_CCACHE_SIZE"; read -r size; [ -z "$size" ] || BFS_CCACHE_SIZE="$size"
    BFS_BUILD_SETTINGS_CHANGED=yes
    save_bootstrap_settings
    echo "Build settings saved; customized values will carry into the base pkgmk.conf."
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
    local choice=""
    while true; do
        echo
        echo "Bootstrap Settings"
        echo "  1) Interface theme"
        echo "  2) Compiler / build settings"
        echo "  3) Back"
        printf "Choose [1-3]: "
        read -r choice </dev/tty 2>/dev/null || read -r choice
        case "$choice" in
            1) bootstrap_theme_settings_menu ;;
            2) compiler_build_settings_menu ;;
            3|"") return 0 ;;
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

mkdir -p "$TOOLCHAIN_LOG_DIR" "$BASE_LOG_DIR"

if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ]; then
    COLOR_RED=$'\033[1;31m'
    COLOR_GREEN=$'\033[1;32m'
    COLOR_YELLOW=$'\033[1;33m'
    COLOR_CYAN=$'\033[1;36m'
    COLOR_RESET=$'\033[0m'
else
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_CYAN=""
    COLOR_RESET=""
fi

_sanitize_log_name() {
    local name="$1"

    name="${name//[^a-zA-Z0-9_.+-]/-}"
    printf '%s\n' "$name"
}

_close_active_package_log() {
    local status="${1:-0}"

    [ -n "$ACTIVE_LOG_FILE" ] || return 0

    printf '\nBuild finished: %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
    printf 'Exit status: %s\n' "$status"

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
    local dir="$SCRIPT_DIR/scripts" file="" best=""
    [ -d "$dir" ] || return 1
    while IFS= read -r file; do
        [ -f "$file" ] && [ -x "$file" ] || continue
        case "$(basename "$file")" in *backup*|*old*|*disabled*|*~) continue ;; esac
        best="$file"
    done < <(find "$dir" -maxdepth 1 -type f -name 'install-bfs-menu-v*.sh' -print 2>/dev/null | sort -V)
    [ -n "$best" ] || return 1
    printf '%s\n' "$best"
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
    echo
    echo "Launching BFSOS installer:"
    echo "  Installer: $installer"
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
        BFS_SKIP_TIME_SYNC=yes "$0" "$stage"
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

    sudo -- env BFS_SKIP_TIME_SYNC=yes BFS_MENU_STAGE="${BFS_MENU_STAGE:-no}" "$0" "$stage"
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
        printf '%s' '\Z2AVAILABLE\Zn'
    else
        printf '%s' '\Z1PENDING\Zn'
    fi
}

_dialog_action_status() {
    if "$@"; then
        printf '%s' '\Z2AVAILABLE\Zn'
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
        'Rebuild base system with final toolchain (optional)' "$(_base_stage3_complete && printf '%sCOMPLETE%s' "$COLOR_GREEN" "$COLOR_RESET" || { _base_stage2_complete && printf '%sAVAILABLE%s' "$COLOR_GREEN" "$COLOR_RESET" || printf '%sPENDING%s' "$COLOR_RED" "$COLOR_RESET"; })"
    printf '  %s4)%s %-54s [%s]\n' "$COLOR_CYAN" "$COLOR_RESET" \
        'Verify completed base system (required)' "$(_required_stage_complete _verification_complete && printf '%sCOMPLETE%s' "$COLOR_GREEN" "$COLOR_RESET" || printf '%sPENDING%s' "$COLOR_RED" "$COLOR_RESET")"
    printf '  %s5)%s %-54s [%s]\n' "$COLOR_CYAN" "$COLOR_RESET" \
        'Create/compress base rootfs archive (required)' "$(_rootfs_archive_complete && printf '%sCOMPLETE%s' "$COLOR_GREEN" "$COLOR_RESET" || printf '%sPENDING%s' "$COLOR_RED" "$COLOR_RESET")"
    printf '  %s6)%s %-54s [%s]\n' "$COLOR_CYAN" "$COLOR_RESET" \
        'Restore newest base rootfs archive' "$(_rootfs_archive_complete && printf '%sAVAILABLE%s' "$COLOR_GREEN" "$COLOR_RESET" || printf '%sPENDING%s' "$COLOR_RED" "$COLOR_RESET")"
    printf '  %s7)%s %-54s [%s]\n' "$COLOR_CYAN" "$COLOR_RESET" \
        'Restore newest temporary toolchain archive' "$(_toolchain_complete && printf '%sAVAILABLE%s' "$COLOR_GREEN" "$COLOR_RESET" || printf '%sPENDING%s' "$COLOR_RED" "$COLOR_RESET")"
    printf '  %s8)%s %-54s [%s]\n' "$COLOR_CYAN" "$COLOR_RESET" \
        'Chroot into BFS rootfs (sudo/root)' "$(_chroot_available && printf '%sAVAILABLE%s' "$COLOR_GREEN" "$COLOR_RESET" || printf '%sNOT AVAILABLE%s' "$COLOR_RED" "$COLOR_RESET")"
    printf '  %s9)%s %-54s [%s]\n' "$COLOR_CYAN" "$COLOR_RESET" \
        'Launch BFSOS installer' "$(_installer_available && printf '%sAVAILABLE%s' "$COLOR_GREEN" "$COLOR_RESET" || printf '%sPENDING%s' "$COLOR_RED" "$COLOR_RESET")"
    printf '  %s10)%s %s\n' "$COLOR_CYAN" "$COLOR_RESET" 'Settings' 
    printf '  %s11)%s %s\n\n' "$COLOR_CYAN" "$COLOR_RESET" 'Quit'
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
        printf '%s' '\Z2AVAILABLE\Zn'
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
                "Required normal path: 1 -> 2 -> 4 -> 5. Stage 3 is optional.\n\nA valid existing base archive satisfies installer readiness automatically." \
                26 100 14 \
                1 "$(_dialog_menu_description 'Build temporary toolchain (required)' "$(_dialog_required_status _toolchain_complete)")" \
                2 "$(_dialog_menu_description 'Build base system with temporary toolchain (required)' "$(_dialog_required_status _base_stage2_complete)")" \
                3 "$(_dialog_menu_description 'Rebuild base system with final toolchain (optional)' "$(_dialog_stage3_status)")" \
                4 "$(_dialog_menu_description 'Verify completed base system (required)' "$(_dialog_required_status _verification_complete)")" \
                5 "$(_dialog_menu_description 'Create/compress base rootfs archive (required)' "$(_dialog_stage_status _rootfs_archive_complete)")" \
                6 "$(_dialog_menu_description 'Restore newest base rootfs archive' "$(_dialog_action_status _rootfs_archive_complete)")" \
                7 "$(_dialog_menu_description 'Restore newest temporary toolchain archive' "$(_dialog_action_status _toolchain_complete)")" \
                8 "$(_dialog_menu_description 'Chroot into BFS rootfs' "$(_dialog_chroot_status)")" \
                9 "$(_dialog_menu_description 'Launch BFSOS installer' "$(_dialog_action_status _installer_available)")" \
                11 "$(_dialog_menu_description 'Quit' '\Z3EXIT\Zn')" \
                --stdout </dev/tty 2>/dev/tty
        )"
        dialog_status=$?
        set -e
        clear </dev/tty >/dev/tty 2>/dev/null || true
        case "$dialog_status" in
            0) printf '%s\n' "$choice" ;;
            3) printf '%s\n' 10 ;;
            *) printf '%s\n' 11 ;;
        esac
        return 0
    fi
    _show_bootstrap_menu >&2
    printf '%sChoose [1-11]: %s' "$COLOR_YELLOW" "$COLOR_RESET" >&2
    read -r choice </dev/tty 2>/dev/null || read -r choice
    case "$choice" in q|Q|quit|Quit|QUIT) choice=11 ;; esac
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
            10) bootstrap_settings_menu; continue ;;
            11|q|Q|quit|Quit|QUIT) echo "BFS bootstrap exited."; return 0 ;;
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
    exec setsid "$0" "$@"
fi

printf '%s %s\n' "$$" "$CURRENT_PGID" > "$PID_FILE"

_reset_terminal_ui() {
    if [ -e /dev/tty ] && [ -w /dev/tty ]; then
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
    BFS_VERSION="0.9.0"
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
    printf "Type YES to continue, or press Enter to keep existing files: "
    read -r answer

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
        if command -v dialog >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ]; then
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
    if command -v dialog >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ]; then
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

    if [ "$(id -u)" = 0 ]; then
        echo "temporary toolchain needs to be built as a regular user" >&2
        return 1
    fi

    _clean_start

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
            echo "ERROR: Refusing to replace unexpected tools path: $TOOLS" >&2
            return 1
            ;;
    esac

    case "${LFS}${TOOLS}" in
        /tmp/lfs-rootfs/tmp/lfs-tools)
            ;;
        *)
            echo "ERROR: Unexpected rooted toolchain path: ${LFS}${TOOLS}" >&2
            return 1
            ;;
    esac

    rm -rf -- "$TOOLS"
    mkdir -p "${LFS}${TOOLS}" "$sourcedir"
    ln -s "${LFS}${TOOLS}" "$TOOLS"

    if [ ! -L "$TOOLS" ]; then
        echo "ERROR: $TOOLS was not created as a symlink." >&2
        return 1
    fi

    if [ "$(readlink -f "$TOOLS")" != "${LFS}${TOOLS}" ]; then
        echo "ERROR: $TOOLS points to the wrong location." >&2
        echo "  Expected: ${LFS}${TOOLS}" >&2
        echo "  Actual:   $(readlink -f "$TOOLS" 2>/dev/null || echo '<unresolved>')" >&2
        return 1
    fi

    echo "Temporary toolchain path verified:"
    echo "  $TOOLS -> ${LFS}${TOOLS}"

    cat > /tmp/bootstrap.conf <<EOF
export LANG=C
export LC_ALL=C
export LANGUAGE=C
export MAKEFLAGS=-j$(nproc)

PKGMK_SOURCE_DIR=$sourcedir
PKGMK_PACKAGE_DIR=/tmp/lfs-pkg

. $PWD/files/pkgmk.bootstrap
EOF

    if [ ! "$(PATH=$TOOLS/bin command -v pkgmk)" ]; then
        if [ ! -f "$sourcedir/pkgutils-5.40.12.tar.xz" ]; then
            curl -o "$sourcedir/pkgutils-5.40.12.tar.xz" \
                https://crux.nu/files/pkgutils-5.40.12.tar.xz
        fi

        rm -rf /tmp/pkgutils-5.40.12
        tar -xf "$sourcedir/pkgutils-5.40.12.tar.xz" -C /tmp

        # The initial pkgutils bootstrap bypasses ports/core/pkgutils/Pkgfile.
        # Prefer a UTF-8 C locale when the live host provides one (GCC 16.2
        # contains UTF-8 pathnames), but fall back to plain C when it does not.
        sed -i '/^export LC_ALL=C\.UTF-8$/c\
_bfs_utf8_locale=""\
for _bfs_locale in C.UTF-8 C.utf8; do\
    if locale -a 2>/dev/null | grep -Fxiq "$_bfs_locale"; then\
        _bfs_utf8_locale="$_bfs_locale"\
        break\
    fi\
done\
if [ -n "$_bfs_utf8_locale" ]; then\
    export LC_ALL="$_bfs_utf8_locale"\
else\
    export LC_ALL=C\
fi\
unset _bfs_utf8_locale _bfs_locale' \
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
    _validate_package_ports $toolchainpkg
    echo

    for i in $toolchainpkg; do
        local port_dir=""

        [ -f "$TOOLS/$i" ] && continue

        export tcpkg="$i"
        port_dir="$(_find_port_dir "$i")"

        cd "$port_dir"

        mkdir -p /tmp/lfs-pkg

        _start_package_log toolchain "$i"

        set +e
        pkgmk -d -is -if -cf /tmp/bootstrap.conf
        status=$?
        set -e

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

    _show_menu_success "Toolchain build complete"         "Toolchain build completed.\n\nArchive created and verified:\n$toolchain_archive"
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

    _show_menu_success "Base archive complete"         "Base rootfs compressed successfully.\n\nArchive created and verified:\n$rootfs_archive"
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

    mkdir -p "$LFS/tmp/lfs-tools/bin"
    cp files/pkgin "$LFS/tmp/lfs-tools/bin/pkgin"
    chmod +x "$LFS/tmp/lfs-tools/bin/pkgin"

    mkdir -p "$LFS/var/lib/pkgmk"
    mkdir -p "$buildworkdir"

    echo "Stage 2/3 package work directory:"
    echo "  $buildworkdir"

    cp ports/core/pkgutils/extension \
        "$LFS/var/lib/pkgmk"

    cat > "$LFS/tmp/pkgmk.conf" <<EOF
export LANG=C
export LC_ALL=C
export LANGUAGE=C

export CPPFLAGS="-I/usr/include"
export CFLAGS="$CFLAGS"
export CXXFLAGS="\${CFLAGS}"
export LDFLAGS="-L/usr/lib -Wl,-rpath-link,/usr/lib"
export LIBRARY_PATH="/usr/lib"

export PKG_CONFIG_PATH="/usr/lib/pkgconfig:/usr/share/pkgconfig"
export PKG_CONFIG_LIBDIR="/usr/lib/pkgconfig:/usr/share/pkgconfig"

export JOBS=${BFS_BUILD_JOBS/auto/$(nproc)}
export MAKEFLAGS="-j \$JOBS"

PKGMK_SOURCE_DIR="/$pkgmksrc"
PKGMK_PACKAGE_DIR="/$pkgmkpkg"
PKGMK_WORK_DIR="/$pkgmkwork/pkgmk-\$name"

. /var/lib/pkgmk/extension
EOF

    # Keep the installed/final pkgmk configuration on the external build-work
    # bind mount too. Stage 3 uses the installed pkgmk/prt-get configuration,
    # so without this it falls back to /var/cache/pkg/work inside the small
    # LiveGUI-backed rootfs and GCC can exhaust that filesystem.
    if [ -f "$LFS/etc/pkgmk.conf" ]; then
        if [ "$BFS_BUILD_SETTINGS_CHANGED" = yes ]; then
            jobs="$BFS_BUILD_JOBS"; [ "$jobs" = auto ] && jobs="$(nproc)"
            sed -i -e "s|^export CFLAGS=.*|export CFLAGS=\"$CFLAGS\"|" \
                   -e "s|^export CXXFLAGS=.*|export CXXFLAGS=\"\${CFLAGS}\"|" \
                   -e "s|^export JOBS=.*|export JOBS=$jobs|" \
                   -e "s|^export MAKEFLAGS=.*|export MAKEFLAGS=\"-j \$JOBS\"|" \
                   "$LFS/etc/pkgmk.conf"
            printf '\n# BFSOS inherited build settings\nexport BFS_CCACHE=%s\nexport BFS_CCACHE_SIZE=%s\n' \
                "$BFS_CCACHE" "$BFS_CCACHE_SIZE" >> "$LFS/etc/pkgmk.conf"
        fi
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
export LANG=C
export LC_ALL=C
export LANGUAGE=C

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

PKGMK_SOURCE_DIR="/$pkgmksrc"
PKGMK_PACKAGE_DIR="/$pkgmkpkg"
PKGMK_WORK_DIR="/$pkgmkwork/pkgmk-\$name"

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

    mountfs

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

            chroot "$LFS" \
                env -i \
                HOME=/root \
                TERM="${TERM:-dumb}" \
                LANG=C \
                LC_ALL=C \
                LANGUAGE=C \
                PATH="$LFSPATH" \
                pkgin -d "$i" -is -if -im -cf "$pkgmk_conf" \
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

            case $i in
                glibc)
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

            chroot "$LFS" \
                env -i \
                HOME=/root \
                TERM="${TERM:-dumb}" \
                LANG=C \
                LC_ALL=C \
                LANGUAGE=C \
                PATH="$LFSPATH" \
                prt-get update -im -fr -if -fi "$i" \
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
libtool
gdbm
gperf
expat
inetutils
perl
perl-xml-parser
intltool
automake
openssl
ca-certificates
curl
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
kmod
linux-pam
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
httpup
ports
prt-utils
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
signify
"
sourcedir="$PWD/sources"
packagedir="$PWD/packages"

# Stage 2/3 pkgmk build trees can be several GiB (especially GCC multilib).
# Keep them on the same filesystem as the BFS repository rather than the
# LiveGUI /tmp overlay, which may be very small.
buildworkdir="$PWD/build-work"

pkgmkpkg="var/cache/pkg/packages"
pkgmksrc="var/cache/pkg/sources"
pkgmkwork="var/cache/pkg/build-work"


bootstrap_settings_menu() {
    local choice=""
    while true; do
        echo
        echo "Bootstrap Settings"
        echo "  1) Interface theme"
        echo "  2) Compiler / build settings"
        echo "  3) Back"
        printf "Choose [1-3]: "
        read -r choice </dev/tty 2>/dev/null || read -r choice
        case "$choice" in
            1) bootstrap_theme_settings_menu ;;
            2) compiler_build_settings_menu ;;
            3|"") return 0 ;;
        esac
    done
}

case "${1:-menu}" in
    menu|"")
        _bootstrap_menu
        ;;
    1)
        _buildtoolchain
        ;;
    2)
        _buildbase
        ;;
    3)
        _buildbase rebuild
        ;;
    4)
        _verifybase
        ;;
    5)
        _compressrootfs
        ;;
    6)
        _restore_rootfs
        ;;
    7)
        _restore_toolchain
        ;;
    8|chroot)
        _enter_bfs_chroot
        ;;
    9|install|installer)
        _launch_bfs_installer
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
  $0 8|chroot    Enter the BFS chroot
  $0 9|installer Launch the newest BFSOS installer from scripts/
  $0 0|stop|kill Stop a running bootstrap process group
EOF
        ;;
    *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
esac

exit 0
