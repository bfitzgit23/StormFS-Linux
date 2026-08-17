#!/usr/bin/env bash
# BFSOS installer r43 - tracker consolidation / Dracut RAID / resume fixes
set -Eeuo pipefail


# The live environment may advertise a UTF-8 locale that is not generated
# inside the installer or target chroot. Use the guaranteed POSIX locale for
# installer execution while keeping BFS_LOCALE as the locale selected for the
# installed system.
force_posix_locale() {
        unset LC_ALL
        unset LC_ADDRESS
        unset LC_COLLATE
        unset LC_CTYPE
        unset LC_IDENTIFICATION
        unset LC_MEASUREMENT
        unset LC_MESSAGES
        unset LC_MONETARY
        unset LC_NAME
        unset LC_NUMERIC
        unset LC_PAPER
        unset LC_TELEPHONE
        unset LC_TIME

        export LANG=C
        export LC_ALL=C
        export LANGUAGE=C
}

force_posix_locale

# Synchronize the live environment clock before logs, archive extraction, or
# package builds. Prefer chrony (used by Gentoo LiveGUI), then systemd's time
# synchronization, followed by classic ntpd/ntpdate fallbacks. Failure is
# non-fatal so the installer can still be used in an offline environment.
sync_system_clock() {
        local synced=no
        local i=0

        [[ "${BFS_TIME_SYNC:-yes}" == yes ]] || {
                printf 'Automatic time synchronization disabled (BFS_TIME_SYNC=%s).\n' \
                        "${BFS_TIME_SYNC:-no}"
                return 0
        }

        printf '\nSynchronizing system clock...\n'

        if command -v chronyd >/dev/null 2>&1; then
                if chronyd -q; then
                        synced=yes
                        printf 'System clock synchronized with chronyd.\n'
                fi
        fi

        if [[ "$synced" != yes ]] &&
           command -v timedatectl >/dev/null 2>&1 &&
           [[ -d /run/systemd/system ]]; then
                if timedatectl set-ntp true >/dev/null 2>&1; then
                        for ((i=0; i<15; i++)); do
                                if [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)" == yes ]]; then
                                        synced=yes
                                        printf 'System clock synchronized with systemd time synchronization.\n'
                                        break
                                fi
                                sleep 1
                        done
                fi
        fi

        if [[ "$synced" != yes ]] && command -v ntpd >/dev/null 2>&1; then
                if ntpd -q -g; then
                        synced=yes
                        printf 'System clock synchronized with ntpd.\n'
                fi
        fi

        if [[ "$synced" != yes ]] && command -v ntpdate >/dev/null 2>&1; then
                if ntpdate -u pool.ntp.org; then
                        synced=yes
                        printf 'System clock synchronized with ntpdate.\n'
                fi
        fi

        if [[ "$synced" != yes ]]; then
                printf 'WARNING: Automatic time synchronization was unavailable or failed.\n' >&2
                printf 'WARNING: Verify the clock before building packages: %s\n' "$(date)" >&2
        fi

        return 0
}

# BFSOS installer - v50 tracker fixes r42 (console-font persistence + RC validation)
#
# Assumptions:
#   - Run from a Linux live environment as root.
#   - Partitions already exist; this script can optionally format them.
#   - A completed BFS rootfs archive is available.
#
# The installer resets /mnt/bfs, presents available partitions while each
# filesystem role is selected, optionally formats selected partitions, mounts
# the target layout, extracts BFS, configures the system, and installs GRUB.

TARGET="${BFS_TARGET:-/mnt/bfs}"
ARCHIVE="${BFS_ARCHIVE:-}"
ROOT_DEV="${BFS_ROOT_DEV:-}"
BOOT_DEV="${BFS_BOOT_DEV:-}"
EFI_DEV="${BFS_EFI_DEV:-}"
SWAP_DEV="${BFS_SWAP_DEV:-}"
HOME_DEV="${BFS_HOME_DEV:-}"
HOSTNAME="${BFS_HOSTNAME:-bfs}"
TIMEZONE="${BFS_TIMEZONE:-America/New_York}"
LOCALE="${BFS_LOCALE:-en_US.UTF-8}"
USERNAME="${BFS_USERNAME:-}"
ADDITIONAL_USERS=()
BOOT_MODE="${BFS_BOOT_MODE:-}"
BOOT_DISK="${BFS_BOOT_DISK:-}"
NETWORK_IFACE="${BFS_NETWORK_IFACE:-}"
NETWORK_MAC="${BFS_NETWORK_MAC:-}"
NETWORK_TARGET_NAME="${BFS_NETWORK_TARGET_NAME:-eth0}"

ROOT_FORMAT="keep"
BOOT_FORMAT="keep"
EFI_FORMAT="keep"
SWAP_FORMAT="keep"
HOME_FORMAT="keep"

KERNEL_PACKAGE="${BFS_KERNEL_PACKAGE:-linux}"
INSTALL_GRUB="${BFS_INSTALL_GRUB:-yes}"
SAVE_BASE_ARCHIVE="${BFS_SAVE_BASE_ARCHIVE:-yes}"
BASE_ARCHIVE_DIR="${BFS_BASE_ARCHIVE_DIR:-/var/cache/bfs/archives/base}"
ENABLE_OPENSSH="${BFS_ENABLE_OPENSSH:-${BFS_INSTALL_OPENSSH:-yes}}"
INSTALL_GIT="${BFS_INSTALL_GIT:-yes}"
INSTALL_SUDO="${BFS_INSTALL_SUDO:-yes}"
SUDO_MODE="${BFS_SUDO_MODE:-password}"  # default: authenticate with invoking user password
INSTALL_WGET="${BFS_INSTALL_WGET:-yes}"
INSTALL_WPA_SUPPLICANT="${BFS_INSTALL_WPA_SUPPLICANT:-no}"
INSTALL_WIRELESS_TOOLS="${BFS_INSTALL_WIRELESS_TOOLS:-no}"
INSTALL_GPM="${BFS_INSTALL_GPM:-no}"
INSTALL_NETWORKMANAGER="${BFS_INSTALL_NETWORKMANAGER:-no}"
# cryptsetup is installer-managed. It is installed automatically when the
# final selected storage topology contains a LUKS/crypt layer.
INSTALL_CRYPTSETUP=no
AUTO_CRYPTSETUP=no
AUTO_LVM2=no
AUTO_MDADM=no
KEEP_MOUNTS="${BFS_KEEP_MOUNTS:-no}"
FINAL_CHROOT="${BFS_FINAL_CHROOT:-no}"
GRUB_FALLBACK="${BFS_GRUB_FALLBACK:-no}"
ZRAM_SWAP="${BFS_ZRAM_SWAP:-no}"
ZRAM_SIZE_SPEC="${BFS_ZRAM_SIZE_SPEC:-200%}"
BUILD_JOBS="${BFS_BUILD_JOBS:-inherited}"
BUILD_OPT="${BFS_BUILD_OPT:-inherited}"
BUILD_CCACHE="${BFS_CCACHE:-inherited}"
BUILD_CCACHE_SIZE="${BFS_CCACHE_SIZE:-inherited}"
CONSOLE_VIDEO_MODE="${BFS_CONSOLE_VIDEO_MODE:-1920x1080@60}"
CONSOLE_VIDEO_ARG=""
CLEAR_PACKAGE_CACHE="${BFS_CLEAR_PACKAGE_CACHE:-ask}"

DISKS_CONFIGURED=no
ARCHIVE_CONFIGURED=no
SYSTEM_CONFIGURED=no
USERS_CONFIGURED=no
KERNEL_CONFIGURED=no
NETWORK_CONFIGURED=no
PACKAGES_CONFIGURED=optional
SUDO_CONFIGURED=default
BOOTLOADER_CONFIGURED=no
PARTITIONING_VISITED=optional

LOG_ENABLED="${BFS_LOG_ENABLED:-yes}"
LOG_FILE="${BFS_LOG_FILE:-}"
LOG_FIFO=""
LOG_TEE_PID=""
LOG_STDOUT_FD=3
LOG_STDERR_FD=4

MOUNTED_BY_SCRIPT=()
OPENED_LUKS_BY_SCRIPT=()
ACTIVATED_VGS_BY_SCRIPT=()
USED_DEVICES=()
EXTRA_DEVICES=()
EXTRA_MOUNTPOINTS=()
EXTRA_FORMATS=()
STORAGE_DEVICES=()
STORAGE_FORMATS=()
STORAGE_MOUNTPOINTS=()
BTRFS_DEVICES=()
BTRFS_MOUNTPOINTS=()
BTRFS_SUBVOLUMES=()
BTRFS_SNAPSHOT_SUBVOLUMES=()
BTRFS_CONFIG_NAMES=()
AVAILABLE_PATHS=()
AVAILABLE_TYPES=()
AVAILABLE_SIZES=()
AVAILABLE_FSTYPES=()
AVAILABLE_LABELS=()
AVAILABLE_MOUNTPOINTS=()
AVAILABLE_NICS=()
AVAILABLE_NIC_MACS=()
AVAILABLE_NIC_STATES=()
AVAILABLE_NIC_DRIVERS=()
CHROOT_INSTALLER="/root/.bfs-install-chroot.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Keep installer logs beside the bootstrap logs, even when this script is
# stored in BFSOS/scripts/.
if [[ "$(basename "$SCRIPT_DIR")" == scripts ]]; then
        PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
        PROJECT_DIR="$SCRIPT_DIR"
fi

INSTALLER_LOG_DIR="$PROJECT_DIR/logs/installer"
INSTALLER_SETTINGS_FILE="$SCRIPT_DIR/.bfs-installer-settings"
INSTALLER_PROFILE_FILE="${BFS_INSTALLER_PROFILE:-$SCRIPT_DIR/bfs-installer-profile.conf}"
LOG_STARTED_EPOCH=""
LOG_CLOSED=no

mkdir -p "$INSTALLER_LOG_DIR"
DIALOGRC_FILE=""
ORIGINAL_DIALOGRC="${DIALOGRC-}"
BFS_THEME="${BFS_INSTALLER_THEME:-slackware}"
CONSOLE_FONT_PREFERENCE="default"
CONSOLE_FONT_SIZE="default"
CONSOLE_FONT_OVERRIDE="${BFS_CONSOLE_FONT:-}"
INSTALL_CONSOLE_FONT="${BFS_INSTALL_CONSOLE_FONT:-no}"
SELECTED_MENU_CHOICE=""
INSTALL_CONFIRMED=no

load_installer_settings() {
        [[ -f "$INSTALLER_SETTINGS_FILE" ]] || return 0

        while IFS='=' read -r key value; do
                case "$key" in
                        BFS_THEME) BFS_THEME="$value" ;;
                        CONSOLE_FONT_PREFERENCE) CONSOLE_FONT_PREFERENCE="$value" ;;
                        INSTALL_CONSOLE_FONT) INSTALL_CONSOLE_FONT="$value" ;;
                        LOG_ENABLED) LOG_ENABLED="$value" ;;
                        BUILD_JOBS) BUILD_JOBS="$value" ;;
                        BUILD_OPT) BUILD_OPT="$value" ;;
                        BUILD_CCACHE) BUILD_CCACHE="$value" ;;
                        BUILD_CCACHE_SIZE) BUILD_CCACHE_SIZE="$value" ;;
                esac
        done < "$INSTALLER_SETTINGS_FILE"
}

save_installer_settings() {
        cat > "$INSTALLER_SETTINGS_FILE" <<EOF_SETTINGS
BFS_THEME=$BFS_THEME
CONSOLE_FONT_PREFERENCE=$CONSOLE_FONT_PREFERENCE
INSTALL_CONSOLE_FONT=$INSTALL_CONSOLE_FONT
LOG_ENABLED=$LOG_ENABLED
BUILD_JOBS=$BUILD_JOBS
BUILD_OPT=$BUILD_OPT
BUILD_CCACHE=$BUILD_CCACHE
BUILD_CCACHE_SIZE=$BUILD_CCACHE_SIZE
EOF_SETTINGS
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

setup_installer_theme() {
        [[ -z "$DIALOGRC_FILE" ]] || rm -f "$DIALOGRC_FILE"
        DIALOGRC_FILE="$(mktemp /tmp/bfs-installer-dialogrc.XXXXXX)"

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

reset_terminal_ui() {
        # dialog can leave its full-screen background/colors painted on the
        # controlling terminal. Restore attributes, make the cursor visible,
        # and clear/redraw the terminal before returning to the shell.
        if [[ -e /dev/tty && -w /dev/tty ]]; then
                printf '\033[0m\033[?25h\033[2J\033[H' >/dev/tty 2>/dev/null || true
                command -v clear >/dev/null 2>&1 &&
                        TERM="${TERM:-linux}" clear </dev/tty >/dev/tty 2>/dev/null || true
        else
                printf '\033[0m\033[?25h\033[2J\033[H' 2>/dev/null || true
        fi
}

report_installer_interface_mode() {
        local -a reasons=()

        if ! command -v dialog >/dev/null 2>&1; then
                reasons+=("dialog command is not installed or not in PATH")
        fi

        if [[ ! -e /dev/tty ]]; then
                reasons+=("/dev/tty does not exist")
        else
                [[ -r /dev/tty ]] || reasons+=("/dev/tty is not readable")
                [[ -w /dev/tty ]] || reasons+=("/dev/tty is not writable")
        fi

        if ((${#reasons[@]} == 0)); then
                printf '\nInstaller interface: dialog mode (%s theme)\n' \
                        "$(theme_display_name)"
                return 0
        fi

        printf '\nWARNING: Dialog interface unavailable.\n' >&2
        printf 'Reason(s):\n' >&2

        local reason
        for reason in "${reasons[@]}"; do
                printf '  - %s\n' "$reason" >&2
        done

        printf 'Continuing with the text-based installer interface.\n\n' >&2
        return 0
}

console_font_patterns_for_size() {
        local size="$1"
        case "$size" in
                # Prefer the exact fonts shipped by the BFSOS base system first.
                16) printf '%s\n' 'Lat2-Terminus16*' 'LatGrkCyr-8x16*' 'Uni2-Terminus16*' 'ter-v16n*' '*Terminus*16*' '*16*.psf*' ;;
                # BFSOS currently ships LatGrkCyr-12x22 as its practical ~20px font.
                # Put it first so a generic/wrong 16px fallback can never win.
                20) printf '%s\n' 'LatGrkCyr-12x22*' 'Lat2-Terminus20*' 'Uni2-Terminus20*' 'ter-v20n*' 'LatArCyrHeb-19*' 'lat4-19*' '*Terminus*20*' '*22*.psf*' '*20*.psf*' '*19*.psf*' ;;
                32) printf '%s\n' 'latarcyrheb-sun32*' '*sun32*' '*32*.psf*' ;;
                *) return 1 ;;
        esac
}

find_console_font_for_size() {
        local size="$1" dir="" candidate=""
        local -a dirs=(/usr/share/consolefonts /usr/share/kbd/consolefonts /lib/kbd/consolefonts)
        local -a patterns=()

        mapfile -t patterns < <(console_font_patterns_for_size "$size") || return 1
        for dir in "${dirs[@]}"; do
                [[ -d "$dir" ]] || continue
                for candidate in "${patterns[@]}"; do
                        find "$dir" -maxdepth 1 -type f -name "$candidate" -print -quit 2>/dev/null
                done
        done | head -n1
}

apply_console_font() {
        local size="${1:-$CONSOLE_FONT_SIZE}" font=""

        command -v setfont >/dev/null 2>&1 || {
                [[ "$size" == default ]] || warn "setfont is unavailable; console font size was not changed."
                return 0
        }

        case "$size" in
                default)
                        setfont >/dev/tty 2>/dev/tty || true
                        ;;
                16|20|32)
                        font="$(find_console_font_for_size "$size" || true)"
                        if [[ -z "$font" ]]; then
                                warn "No ${size}-pixel console font was found; keeping the current console font."
                                return 0
                        fi
                        if ! setfont "$font" >/dev/tty 2>/dev/tty; then
                                warn "Could not apply $font. This is normal over SSH or inside a graphical terminal."
                        fi
                        ;;
        esac
}

console_font_display_name() {
        case "$CONSOLE_FONT_SIZE" in
                default) printf '%s' "Default" ;;
                16) printf '%s' "Large 16" ;;
                20) printf '%s' "Large ~20" ;;
                32) printf '%s' "Extra Large 32" ;;
                *) printf '%s' "$CONSOLE_FONT_SIZE" ;;
        esac
}

select_console_font_size() {
        local choice="" status=0
        themed_menu choice "Console Font Size" \
                "Choose the Linux virtual-console font size for this installer session.\n\nLarge fonts are most useful on high-DPI/4K displays." \
                19 78 7 \
                default "Default console font" \
                16 "Large 16-pixel font" \
                20 "Large ~20-pixel font (19/20/22 fallback)" \
                32 "Extra Large 32-pixel font (recommended for high-DPI)"
        [[ -n "$choice" ]] || return 0
        CONSOLE_FONT_PREFERENCE="$choice"
        CONSOLE_FONT_SIZE="$choice"
        if [[ "$choice" == default ]]; then
                INSTALL_CONSOLE_FONT=no
        else
                INSTALL_CONSOLE_FONT=yes
        fi
        apply_console_font "$choice"
        save_installer_settings

        # Make the chosen/persistent value explicit so a mistaken selection is
        # visible immediately instead of being discovered only after reboot.
        if [[ "$choice" == default ]]; then
                dialog_message "Console font"                         "Console font selection: Default\n\nNo custom large-font selection will be persisted."
        else
                local selected_font=""
                selected_font="$(find_console_font_for_size "$choice" || true)"
                if [[ -n "$selected_font" ]]; then
                        dialog_message "Console font"                                 "Selected size: $(console_font_display_name)\nFont found: $(basename "$selected_font")\n\nThis size will be persisted to the installed system."
                else
                        dialog_message "Console font"                                 "Selected size: $(console_font_display_name)\n\nNo matching font was found in the live environment. The installed-system step will check again and warn if unavailable."
                fi
        fi
}

select_installer_theme() {
        local choice="" status=0

        if command -v dialog >/dev/null 2>&1 &&
           [[ -r /dev/tty && -w /dev/tty ]]; then
                if choice="$(
                        dialog --stdout --clear \
                                --backtitle "BFS Linux Installer" \
                                --title "Interface Theme" \
                                --cancel-label "Back" \
                                --radiolist \
                                "Choose the installer theme." \
                                20 82 7 \
                                Slackware "Classic Slackware setup-style cyan theme (default)" \
                                        "$([[ "$BFS_THEME" == slackware ]] && echo on || echo off)" \
                                Debian "Classic Debian installer/newt-style theme" \
                                        "$([[ "$BFS_THEME" == classic ]] && echo on || echo off)" \
                                Monochrome "Best compatibility for SSH and unusual palettes" \
                                        "$([[ "$BFS_THEME" == monochrome ]] && echo on || echo off)" \
                                Midnight "Midnight Commander-style theme" \
                                        "$([[ "$BFS_THEME" == midnight ]] && echo on || echo off)" \
                                Light "Black text on a light background" \
                                        "$([[ "$BFS_THEME" == light ]] && echo on || echo off)" \
                                </dev/tty
                )"; then
                        status=0
                else
                        status=$?
                fi
                [[ "$status" -eq 0 && -n "$choice" ]] || return 0
                case "$choice" in
                        Slackware) choice=slackware ;;
                        Debian) choice=classic ;;
                        Monochrome) choice=monochrome ;;
                        Midnight) choice=midnight ;;
                        Light) choice=light ;;
                esac
        else
                echo "  1) Slackware (Classic Slackware, default)"
                echo "  2) Debian (Classic Debian)"
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
                        *) warn "Invalid theme selection."; return 1 ;;
                esac
        fi

        BFS_THEME="$choice"
        setup_installer_theme
        save_installer_settings
}
profile_quote() { printf '%q' "$1"; }

save_installer_profile() {
        local path="${1:-$INSTALLER_PROFILE_FILE}" i
        {
                echo '# BFSOS installer profile v1 - no passwords or LUKS passphrases are stored.'
                for name in HOSTNAME TIMEZONE LOCALE USERNAME BOOT_MODE BOOT_DISK NETWORK_IFACE NETWORK_MAC NETWORK_TARGET_NAME KERNEL_PACKAGE INSTALL_GRUB GRUB_FALLBACK SAVE_BASE_ARCHIVE BASE_ARCHIVE_DIR ENABLE_OPENSSH INSTALL_GIT INSTALL_SUDO SUDO_MODE INSTALL_WGET INSTALL_WPA_SUPPLICANT INSTALL_WIRELESS_TOOLS INSTALL_GPM INSTALL_NETWORKMANAGER CONSOLE_VIDEO_MODE ZRAM_SIZE_SPEC ARCHIVE ROOT_DEV ROOT_FORMAT BOOT_DEV BOOT_FORMAT EFI_DEV EFI_FORMAT SWAP_DEV SWAP_FORMAT HOME_DEV HOME_FORMAT ZRAM_SWAP; do
                        printf '%s=' "$name"; profile_quote "${!name:-}"; printf '\n'
                done
                for ((i=0;i<${#ADDITIONAL_USERS[@]};i++)); do printf 'ADDITIONAL_USER='; profile_quote "${ADDITIONAL_USERS[$i]}"; printf '\n'; done
                for ((i=0;i<${#STORAGE_DEVICES[@]};i++)); do
                        printf 'STORAGE='; profile_quote "${STORAGE_DEVICES[$i]}|${STORAGE_FORMATS[$i]}|${STORAGE_MOUNTPOINTS[$i]}"; printf '\n'
                done
        } >"$path"
        INSTALLER_PROFILE_FILE="$path"
        dialog_message "Configuration profile" "Saved installer configuration to:\n$path\n\nPasswords and LUKS passphrases were not saved."
}

load_installer_profile() {
        local path="${1:-$INSTALLER_PROFILE_FILE}" line key raw value a b c missing="" dev
        [[ -f "$path" ]] || { dialog_message "Configuration profile" "Profile not found:\n$path"; return 1; }
        ADDITIONAL_USERS=(); STORAGE_DEVICES=(); STORAGE_FORMATS=(); STORAGE_MOUNTPOINTS=()
        while IFS= read -r line || [[ -n "$line" ]]; do
                [[ -z "$line" || "$line" == \#* || "$line" != *=* ]] && continue
                key="${line%%=*}"; raw="${line#*=}"
                # Decode only shell %q produced by this installer; reject command syntax.
                [[ "$raw" != *'$('* && "$raw" != *'`'* ]] || continue
                eval "value=$raw"
                case "$key" in
                        HOSTNAME|TIMEZONE|LOCALE|USERNAME|BOOT_MODE|BOOT_DISK|NETWORK_IFACE|NETWORK_MAC|NETWORK_TARGET_NAME|KERNEL_PACKAGE|INSTALL_GRUB|GRUB_FALLBACK|SAVE_BASE_ARCHIVE|BASE_ARCHIVE_DIR|ENABLE_OPENSSH|INSTALL_GIT|INSTALL_SUDO|SUDO_MODE|INSTALL_WGET|INSTALL_WPA_SUPPLICANT|INSTALL_WIRELESS_TOOLS|INSTALL_GPM|INSTALL_NETWORKMANAGER|CONSOLE_VIDEO_MODE|ZRAM_SIZE_SPEC|ARCHIVE|ROOT_DEV|ROOT_FORMAT|BOOT_DEV|BOOT_FORMAT|EFI_DEV|EFI_FORMAT|SWAP_DEV|SWAP_FORMAT|HOME_DEV|HOME_FORMAT|ZRAM_SWAP) printf -v "$key" '%s' "$value" ;;
                        ADDITIONAL_USER) ADDITIONAL_USERS+=("$value") ;;
                        STORAGE) IFS='|' read -r a b c <<<"$value"; STORAGE_DEVICES+=("$a"); STORAGE_FORMATS+=("$b"); STORAGE_MOUNTPOINTS+=("$c") ;;
                esac
        done <"$path"
        for dev in "${STORAGE_DEVICES[@]}" "$ROOT_DEV" "$BOOT_DEV" "$EFI_DEV" "$SWAP_DEV" "$HOME_DEV"; do
                [[ -z "$dev" || -b "$dev" ]] || missing+="$dev\\n"
        done
        if [[ -n "$missing" ]]; then
                dialog_message "Profile validation" "Loaded profile, but these saved block devices are not currently present:\n\n$missing\nReview Storage before installing."
                DISKS_CONFIGURED=no
        elif ((${#STORAGE_DEVICES[@]})); then
                apply_storage_selections || true
                DISKS_CONFIGURED=yes
        fi
        recalculate_configuration_status
        INSTALLER_PROFILE_FILE="$path"
        dialog_message "Configuration profile" "Loaded installer configuration from:\n$path\n\nReview all selections before installation. Secrets will still be requested when needed."
}

recalculate_configuration_status() {
        # Recompute menu state after loading a profile instead of trusting stale
        # status flags from a previous installer session.
        DISKS_CONFIGURED=no
        if ((${#STORAGE_DEVICES[@]})); then
                apply_storage_selections >/dev/null 2>&1 && DISKS_CONFIGURED=yes || true
        elif [[ -n "$ROOT_DEV" && -b "$ROOT_DEV" ]]; then
                DISKS_CONFIGURED=yes
        fi

        ARCHIVE_CONFIGURED=$([[ -n "$ARCHIVE" && -f "$ARCHIVE" ]] && echo yes || echo no)
        SYSTEM_CONFIGURED=$([[ -n "$HOSTNAME" && -n "$TIMEZONE" && -n "$LOCALE" ]] && echo yes || echo no)
        USERS_CONFIGURED=$([[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] && echo yes || echo no)
        KERNEL_CONFIGURED=$([[ -n "$KERNEL_PACKAGE" ]] && echo yes || echo no)
        NETWORK_CONFIGURED=$([[ -n "$NETWORK_IFACE" && -n "$NETWORK_TARGET_NAME" ]] && echo yes || echo no)
        PACKAGES_CONFIGURED=optional
        SUDO_CONFIGURED=default
        BOOTLOADER_CONFIGURED=$([[ "$INSTALL_GRUB" == yes || "$INSTALL_GRUB" == no ]] && echo yes || echo no)
}

profile_path_dialog() {
        local result_variable="$1" title="$2" value status=0
        value="$INSTALLER_PROFILE_FILE"
        if command -v dialog >/dev/null 2>&1 && [[ -r /dev/tty && -w /dev/tty ]]; then
                value="$(dialog --stdout --clear --backtitle "BFS Linux Installer" --title "$title" --inputbox "Configuration profile path:" 12 82 "$value" </dev/tty)" || status=$?
                ((status==0)) || return 1
        else
                read -r -p "Configuration profile [$value]: " value; value="${value:-$INSTALLER_PROFILE_FILE}"
        fi
        printf -v "$result_variable" '%s' "$value"
}

storage_device_is_protected() {
        local candidate="$1" source="" ancestor=""
        local -a protected_sources=()

        source="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
        [[ -n "$source" ]] && protected_sources+=("$source")
        source="$(findmnt -T "$PROJECT_DIR" -n -o SOURCE 2>/dev/null || true)"
        [[ -n "$source" ]] && protected_sources+=("$source")
        source="$(findmnt -n -o SOURCE /run/initramfs/live 2>/dev/null || true)"
        [[ -n "$source" ]] && protected_sources+=("$source")

        for source in "${protected_sources[@]}"; do
                [[ "$candidate" == "$source" ]] && return 0
                while IFS= read -r ancestor; do
                        [[ "$candidate" == "$ancestor" ]] && return 0
                done < <(lsblk -s -prno PATH "$source" 2>/dev/null || true)
        done
        return 1
}

storage_reset_preview() {
        local tmp="$1"
        {
                echo "BFSOS storage maintenance preview"
                echo "================================"
                echo
                echo "Mounted filesystems below target:"
                findmnt -Rrn -o TARGET,SOURCE "$TARGET" 2>/dev/null || echo "  none"
                echo
                echo "Active swap:"
                swapon --show 2>/dev/null || echo "  none"
                echo
                echo "LVM:"
                pvs 2>/dev/null || true
                vgs 2>/dev/null || true
                lvs 2>/dev/null || true
                echo
                echo "LUKS/device-mapper mappings:"
                lsblk -prno PATH,TYPE,FSTYPE 2>/dev/null | awk '$2=="crypt" || $3=="crypto_LUKS"'
                echo
                echo "MD RAID:"
                cat /proc/mdstat 2>/dev/null || true
                echo
                echo "Detected MD metadata (active or inactive members):"
                if command -v mdadm >/dev/null 2>&1; then
                        mdadm --detail --scan 2>/dev/null || true
                        while IFS= read -r dev; do
                                [[ -b "$dev" ]] || continue
                                if mdadm --examine "$dev" >/dev/null 2>&1; then
                                        printf '  %s  %s\n' "$dev" "$(mdadm --examine "$dev" 2>/dev/null | awk -F: '/Raid Level|Array UUID|Name/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); printf "%s=%s ", $1, $2}')"
                                fi
                        done < <(lsblk -prno PATH,TYPE 2>/dev/null | awk '$2=="part"{print $1}')
                fi
        } >"$tmp"
}

storage_reset_deactivate() {
        umount -R "$TARGET" 2>/dev/null || true
        swapoff -a 2>/dev/null || true
        command -v vgchange >/dev/null 2>&1 && vgchange -an 2>/dev/null || true

        local mapping="" array=""
        if command -v cryptsetup >/dev/null 2>&1; then
                while IFS= read -r mapping; do
                        [[ -n "$mapping" ]] || continue
                        storage_device_is_protected "$mapping" && continue
                        cryptsetup close "${mapping##*/}" 2>/dev/null || true
                done < <(lsblk -prno PATH,TYPE 2>/dev/null | awk '$2=="crypt"{print $1}' | tac)
        fi

        if command -v mdadm >/dev/null 2>&1; then
                while IFS= read -r array; do
                        [[ -n "$array" ]] || continue
                        storage_device_is_protected "$array" && continue
                        mdadm --stop "$array" 2>/dev/null || true
                done < <(awk '$2==":" && $4 ~ /^raid/ {print "/dev/"$1}' /proc/mdstat 2>/dev/null)
        fi
        command -v udevadm >/dev/null 2>&1 && udevadm settle || true
}

storage_reset_destroy_metadata() {
        local -a candidates=()
        local dev="" choice="" status=0
        storage_reset_deactivate

        # Offer only block devices that are not mounted, are not the live root,
        # and are not the filesystem containing the BFSOS project itself.
        local live_root="" project_source=""
        live_root="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
        project_source="$(findmnt -T "$PROJECT_DIR" -n -o SOURCE 2>/dev/null || true)"

        while IFS= read -r dev; do
                [[ -b "$dev" ]] || continue
                storage_device_is_protected "$dev" && continue
                [[ "$dev" != "$live_root" && "$dev" != "$project_source" ]] || continue
                findmnt -rn -S "$dev" >/dev/null 2>&1 && continue

                local size="" fstype="" detail=""
                size="$(lsblk -dnro SIZE "$dev" 2>/dev/null | head -n1)"
                fstype="$(lsblk -dnro FSTYPE "$dev" 2>/dev/null | head -n1)"
                detail="${fstype:-no-filesystem}"

                if command -v mdadm >/dev/null 2>&1 &&
                   mdadm --examine "$dev" >/dev/null 2>&1; then
                        detail="MD RAID member; ${detail}"
                elif command -v pvs >/dev/null 2>&1 &&
                     pvs --noheadings "$dev" >/dev/null 2>&1; then
                        detail="LVM PV; ${detail}"
                elif command -v wipefs >/dev/null 2>&1 &&
                     ! wipefs -n "$dev" 2>/dev/null | grep -q .; then
                        # Do not clutter the destructive checklist with blank,
                        # metadata-free partitions unless they are an MD member.
                        continue
                fi

                candidates+=("$dev" "${size:-?}  $detail")
        done < <(
                {
                        lsblk -prno PATH,TYPE 2>/dev/null |
                                awk '$2=="part" || $2 ~ /^raid/ || $2=="crypt" {print $1}'
                        # Include member partitions of currently assembled arrays
                        # even if lsblk changes their presentation after deactivation.
                        awk '$2==":" && $4 ~ /^raid/ {for(i=5;i<=NF;i++){gsub(/\[[0-9]+\]/,"",$i); if($i ~ /^[[:alnum:]_.+-]+[0-9]+$/) print "/dev/"$i}}' /proc/mdstat 2>/dev/null
                } | sort -u
        )

        ((${#candidates[@]})) || {
                dialog_message "Storage reset" "No safe unmounted storage candidates were found."
                return 0
        }

        if command -v dialog >/dev/null 2>&1 && [[ -r /dev/tty && -w /dev/tty ]]; then
                local -a checklist=()
                local i
                for ((i=0;i<${#candidates[@]};i+=2)); do
                        checklist+=("${candidates[$i]}" "${candidates[$((i+1))]}" off)
                done
                choice="$(dialog --stdout --separate-output --clear \
                        --backtitle "BFS Linux Installer" --title "Destroy storage metadata" \
                        --checklist "Select only devices whose old RAID/LUKS/LVM/filesystem metadata should be erased.\n\nThe live root and BFSOS project filesystem are excluded automatically." \
                        24 110 14 "${checklist[@]}" </dev/tty)" || return 0
        else
                dialog_message "Storage reset" "Destructive metadata reset requires Dialog mode so devices can be selected explicitly."
                return 0
        fi

        [[ -n "$choice" ]] || return 0
        confirm "DESTROY signatures/metadata on these selected devices?\n\n$choice\n\nThis cannot be undone." || return 0

        while IFS= read -r dev; do
                [[ -b "$dev" ]] || continue
                mdadm --zero-superblock --force "$dev" 2>/dev/null || true
                pvremove -ff -y "$dev" 2>/dev/null || true
                wipefs -a "$dev" 2>/dev/null || true
        done <<<"$choice"
        refresh_storage_state
        dialog_message "Storage reset" "Selected storage metadata was removed.\n\nRe-scan with lsblk, /proc/mdstat, and mdadm --examine before starting a new install."
}

storage_reset_menu() {
        local choice="" tmp=""
        tmp="$(mktemp /tmp/bfs-storage-reset-preview.XXXXXX)"
        storage_reset_preview "$tmp"
        if command -v dialog >/dev/null 2>&1 && [[ -r /dev/tty && -w /dev/tty ]]; then
                dialog --clear --backtitle "BFS Linux Installer" --title "Existing storage state" \
                        --textbox "$tmp" 26 116 </dev/tty >/dev/tty 2>/dev/tty || true
        fi
        rm -f "$tmp"

        themed_menu choice "Storage maintenance" \
                "Choose a storage cleanup mode. Nothing destructive runs automatically." \
                17 86 6 \
                1 "Deactivate only — unmount, swapoff, deactivate VGs, close LUKS, stop MD" \
                2 "Destroy selected metadata — explicit device checklist + wipefs" \
                3 "Back"
        case "$choice" in
                1)
                        confirm "Deactivate currently active target storage now?\n\nNo signatures will be erased." || return 0
                        storage_reset_deactivate
                        dialog_message "Storage maintenance" "Storage was deactivated."
                        ;;
                2) storage_reset_destroy_metadata ;;
                *) return 0 ;;
        esac
}

compiler_build_settings_menu() {
        local choice="" value=""
        while true; do
                themed_menu choice "Compiler / Build Settings" \
                        "Inherited keeps Bootstrap/base pkgmk.conf values; installer changes override only the installed system." \
                        22 96 8 \
                        1 "Build jobs: $BUILD_JOBS" \
                        2 "Optimization: $BUILD_OPT" \
                        3 "ccache: $BUILD_CCACHE" \
                        4 "ccache size: $BUILD_CCACHE_SIZE" \
                        5 "Restore inherited Bootstrap/base values" \
                        6 "Back"
                case "$choice" in
                        1) themed_inputbox value "Build jobs" "Enter inherited, auto, or a positive job count." "$BUILD_JOBS" && BUILD_JOBS="$value" ;;
                        2) themed_menu value "Optimization" "Choose installed-system compiler tuning." 18 80 5 1 "inherited" 2 "portable (-O2 -march=x86-64 -pipe)" 3 "native (-O2 -march=native -mtune=native -pipe)" 4 "Back"; case "$value" in 1) BUILD_OPT=inherited;;2) BUILD_OPT=portable;;3) BUILD_OPT=native;;esac ;;
                        3) [[ "$BUILD_CCACHE" == yes ]] && BUILD_CCACHE=no || BUILD_CCACHE=yes ;;
                        4) themed_inputbox value "ccache size" "Enter inherited, auto, 20G, 64G, etc. Auto = 20G in VMs; physical-RAM-sized on bare metal." "$BUILD_CCACHE_SIZE" && BUILD_CCACHE_SIZE="$value" ;;
                        5) BUILD_JOBS=inherited; BUILD_OPT=inherited; BUILD_CCACHE=inherited; BUILD_CCACHE_SIZE=inherited ;;
                        *) save_installer_settings; return 0 ;;
                esac
                save_installer_settings
        done
}

installer_settings_menu() {
        local choice="" status=0 path=""
        while true; do
                themed_menu choice "Installer Settings" \
                        "Configure interface, accessibility, logging, reusable profiles, and storage maintenance." \
                        25 92 11 \
                        1 "Theme: $(theme_display_name)" \
                        2 "Console font: $(console_font_display_name)" \
                        3 "Logging: $LOG_ENABLED" \
                        4 "Compiler / build settings" \
                        5 "Save current configuration" \
                        6 "Save configuration as..." \
                        7 "Load configuration..." \
                        8 "Reset/deactivate existing storage..." \
                        9 "Back to main menu"
                [[ -n "$choice" ]] || return 0
                case "$choice" in
                        1) select_installer_theme ;;
                        2) select_console_font_size ;;
                        3)
                                [[ "$LOG_ENABLED" == yes ]] && LOG_ENABLED=no || LOG_ENABLED=yes
                                save_installer_settings
                                ;;
                        4) compiler_build_settings_menu ;;
                        5) save_installer_profile "$INSTALLER_PROFILE_FILE" ;;
                        6) path=""; profile_path_dialog path "Save configuration as" && save_installer_profile "$path" ;;
                        7) path=""; profile_path_dialog path "Load configuration" && load_installer_profile "$path" ;;
                        8) storage_reset_menu ;;
                        9) return 0 ;;
                        *) warn "Invalid settings selection."; sleep 1 ;;
                esac
        done
}

dialog_status() {
        case "$1" in
                yes) printf '%s' "CONFIGURED" ;;
                optional) printf '%s' "OPTIONAL" ;;
                default) printf '%s' "DEFAULT" ;;
                *) printf '%s' "PENDING" ;;
        esac
}

installer_ready() {
        # Only filesystem/mount-point assignment is required for storage.
        # Visiting cfdisk, RAID, LUKS, or LVM menus is never required.
        [[ "$DISKS_CONFIGURED" == yes &&
           "$ARCHIVE_CONFIGURED" == yes &&
           "$SYSTEM_CONFIGURED" == yes &&
           "$USERS_CONFIGURED" == yes &&
           "$KERNEL_CONFIGURED" == yes &&
           "$NETWORK_CONFIGURED" == yes &&
           "$BOOTLOADER_CONFIGURED" == yes ]]
}

target_chroot_available() {
        [[ -x "$TARGET/bin/bash" || -x "$TARGET/usr/bin/bash" ]]
}

available_status() {
        if "$@"; then
                printf '%s' "AVAILABLE"
        else
                printf '%s' "PENDING"
        fi
}

dialog_menu_description() {
        printf '%-45s [%s]' "$1" "$2"
}

themed_menu() {
        local result_variable="$1"
        local title="$2"
        local prompt="$3"
        local height="$4"
        local width="$5"
        local menu_height="$6"
        shift 6

        # Do not call this local variable "choice". Bash uses dynamic scoping,
        # so a local choice here would hide the caller's choice variable and
        # prevent printf -v from returning the selected menu tag.
        local selected_value="" status=0 index=0
        local -a items=("$@")

        if command -v dialog >/dev/null 2>&1 &&
           [[ -r /dev/tty && -w /dev/tty ]]; then
                if selected_value="$(
                        dialog --stdout --clear \
                                --backtitle "BFS Linux Installer" \
                                --title "$title" \
                                --cancel-label "Back" \
                                --menu "$prompt" \
                                "$height" "$width" "$menu_height" \
                                "${items[@]}" \
                                </dev/tty
                )"; then
                        status=0
                else
                        status=$?
                fi

                if ((status != 0)); then
                        printf -v "$result_variable" '%s' ""
                        return 0
                fi
        else
                clear_screen
                printf '%s\n' "$title"
                printf '%*s\n\n' "${#title}" '' | tr ' ' '='
                printf '%s\n\n' "$prompt"

                for ((index=0; index<${#items[@]}; index+=2)); do
                        printf '  %s) %s\n' \
                                "${items[$index]}" \
                                "${items[$((index + 1))]}"
                done

                printf '\n'
                read -r -p "Choose: " selected_value
        fi

        selected_value="$(
                printf '%s' "$selected_value" |
                        tr -d '\r\n' |
                        sed -e 's/^[[:space:]]*//' \
                            -e 's/[[:space:]]*$//' \
                            -e 's/^"//' \
                            -e 's/"$//'
        )"

        printf -v "$result_variable" '%s' "$selected_value"
        return 0
}

log() { printf '\n==> %s\n' "$*"; }
warn() { printf '\nWARNING: %s\n' "$*" >&2; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

clear_screen() {
        if command -v clear >/dev/null 2>&1; then
                clear
        else
                printf '\033[2J\033[H'
        fi
}

pause_screen() {
        printf '\n'
        read -r -p 'Press Enter to continue...' _
}


dialog_message() {
        local title="$1" message="$2"
        if command -v dialog >/dev/null 2>&1 && [[ -r /dev/tty && -w /dev/tty ]]; then
                dialog --clear --backtitle "BFS Linux Installer" --title "$title" \
                        --msgbox "$message" 18 84 </dev/tty >/dev/tty 2>/dev/tty || true
        else
                printf '\n%s\n%s\n\n%s\n' "$title" "$(printf '%*s' "${#title}" '' | tr ' ' '=')" "$message"
                pause_screen
        fi
}

dialog_password() {
        local result_variable="$1" title="$2" prompt="$3" value="" status=0
        if command -v dialog >/dev/null 2>&1 && [[ -r /dev/tty && -w /dev/tty ]]; then
                set +e
                value="$(dialog --stdout --clear --insecure --backtitle "BFS Linux Installer" \
                        --title "$title" --cancel-label "Back" --passwordbox "$prompt" 12 72 </dev/tty)"
                status=$?
                set -e
                ((status == 0)) || return 1
        else
                read -r -s -p "$prompt: " value </dev/tty
                printf '\n' >/dev/tty
        fi
        printf -v "$result_variable" '%s' "$value"
}

run_on_tty() {
        local status=0

        clear
        reset
        stty sane </dev/tty

        set +e
        "$@" </dev/tty >/dev/tty 2>/dev/tty
        status=$?
        set -e

        clear
        reset
        stty sane </dev/tty

        return "$status"
}

ask() {
        local variable="$1"
        local prompt="$2"
        local default="${3:-}"
        local answer=""
        local status=0

        [[ -n "${!variable:-}" ]] && return 0

        if command -v dialog >/dev/null 2>&1 &&
           [[ -r /dev/tty && -w /dev/tty ]]; then
                if answer="$(
                        dialog --stdout --clear \
                                --backtitle "BFS Linux Installer" \
                                --title "BFS configuration" \
                                --cancel-label "Back" \
                                --inputbox "$prompt" \
                                12 72 "$default" \
                                </dev/tty
                )"; then
                        status=0
                else
                        status=$?
                fi
                ((status == 0)) || return 1
        else
                if [[ -n "$default" ]]; then
                        read -r -p "$prompt [$default]: " answer
                        answer="${answer:-$default}"
                else
                        read -r -p "$prompt: " answer
                fi
        fi

        printf -v "$variable" '%s' "$answer"
}

ask_default() {
        local variable="$1"
        local prompt="$2"
        local default="$3"
        local answer=""
        local status=0

        if command -v dialog >/dev/null 2>&1 &&
           [[ -r /dev/tty && -w /dev/tty ]]; then
                if answer="$(
                        dialog --stdout --clear \
                                --backtitle "BFS Linux Installer" \
                                --title "BFS configuration" \
                                --cancel-label "Back" \
                                --inputbox "$prompt" \
                                12 72 "$default" \
                                </dev/tty
                )"; then
                        status=0
                else
                        status=$?
                fi
                ((status == 0)) || return 1
        else
                read -r -p "$prompt [$default]: " answer
                answer="${answer:-$default}"
        fi

        printf -v "$variable" '%s' "${answer:-$default}"
}

ask_yes_no() {
        local variable="$1"
        local prompt="$2"
        local default="${3:-no}"
        local answer=""
        local status=0

        if command -v dialog >/dev/null 2>&1 &&
           [[ -r /dev/tty && -w /dev/tty ]]; then
                local -a default_button=()
                [[ "$default" == no ]] && default_button=(--defaultno)

                if dialog --clear \
                        --backtitle "BFS Linux Installer" \
                        --title "BFS configuration" \
                        "${default_button[@]}" \
                        --yesno "$prompt" \
                        11 72 \
                        </dev/tty >/dev/tty 2>/dev/tty; then
                        printf -v "$variable" '%s' yes
                else
                        status=$?
                        case "$status" in
                                1) printf -v "$variable" '%s' no ;;
                                255) return 1 ;;
                                *) return 1 ;;
                        esac
                fi
        else
                local suffix="[y/N]"
                [[ "$default" == yes ]] && suffix="[Y/n]"
                read -r -p "$prompt $suffix: " answer
                answer="${answer,,}"
                if [[ -z "$answer" ]]; then
                        printf -v "$variable" '%s' "$default"
                elif [[ "$answer" == y || "$answer" == yes ]]; then
                        printf -v "$variable" '%s' yes
                else
                        printf -v "$variable" '%s' no
                fi
        fi
}

confirm() {
        local prompt="$1"
        local answer=""

        if command -v dialog >/dev/null 2>&1 &&
           [[ -r /dev/tty && -w /dev/tty ]]; then
                dialog --clear \
                        --backtitle "BFS Linux Installer" \
                        --title "Confirm" \
                        --defaultno \
                        --yesno "$prompt" \
                        11 76 \
                        </dev/tty >/dev/tty 2>/dev/tty
                return $?
        fi

        read -r -p "$prompt [y/N]: " answer
        [[ "${answer,,}" == y || "${answer,,}" == yes ]]
}

confirm_continue() {
        local prompt="$1" answer=""
        if command -v dialog >/dev/null 2>&1 && [[ -r /dev/tty && -w /dev/tty ]]; then
                dialog --clear \
                        --backtitle "BFS Linux Installer" \
                        --title "Ready to install" \
                        --yes-label "Continue" \
                        --no-label "Back" \
                        --defaultno \
                        --yesno "$prompt" 11 76 \
                        </dev/tty >/dev/tty 2>/dev/tty
                return $?
        fi
        read -r -p "$prompt [y/N]: " answer
        [[ "${answer,,}" == y || "${answer,,}" == yes ]]
}

usage() {
        cat <<'USAGE'
Usage: install-bfs-menu-v50.sh [options]

The installer may be started as a regular user. It authenticates with sudo
once, then re-executes the full installer as root.

Options:
  --log                  Enable automatic logging (default)
  --no-log               Disable automatic logging
  --log-file PATH        Use PATH for the live-environment log
  --large-console        Use a 20-pixel console font for this run only
  --console-font SIZE    Runtime console font: default, 16, or 20
  --console-font=SIZE    Same as above
  -h, --help             Show this help
USAGE
}

parse_arguments() {
        while (($#)); do
                case "$1" in
                        --log)
                                LOG_ENABLED=yes
                                shift
                                ;;
                        --no-log)
                                LOG_ENABLED=no
                                shift
                                ;;
                        --log-file)
                                (($# >= 2)) || die "--log-file requires a path."
                                LOG_ENABLED=yes
                                LOG_FILE="$2"
                                shift 2
                                ;;
                        --large-console)
                                CONSOLE_FONT_OVERRIDE=20
                                shift
                                ;;
                        --console-font)
                                (($# >= 2)) || die "--console-font requires default, 16, or 20."
                                case "$2" in default|16|20) CONSOLE_FONT_OVERRIDE="$2" ;; *) die "Invalid console font size: $2" ;; esac
                                shift 2
                                ;;
                        --console-font=*)
                                case "${1#*=}" in default|16|20) CONSOLE_FONT_OVERRIDE="${1#*=}" ;; *) die "Invalid console font size: ${1#*=}" ;; esac
                                shift
                                ;;
                        -h|--help)
                                usage
                                exit 0
                                ;;
                        *)
                                die "Unknown option: $1"
                                ;;
                esac
        done
}

setup_logging() {
        [[ "$LOG_ENABLED" == yes ]] || return 0

        mkdir -p "$INSTALLER_LOG_DIR"

        if [[ -z "$LOG_FILE" ]]; then
                LOG_FILE="$INSTALLER_LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
        elif [[ "$LOG_FILE" != /* ]]; then
                LOG_FILE="$INSTALLER_LOG_DIR/$LOG_FILE"
        fi

        mkdir -p "$(dirname "$LOG_FILE")"
        : > "$LOG_FILE"

        LOG_STARTED_EPOCH="$(date +%s)"
        LOG_CLOSED=no

        LOG_FIFO="$(mktemp -u /tmp/bfs-install-log.XXXXXX)"
        mkfifo "$LOG_FIFO"

        exec 3>&1 4>&2
        tee -a "$LOG_FILE" < "$LOG_FIFO" >&3 &
        LOG_TEE_PID=$!
        exec > "$LOG_FIFO" 2>&1

        printf '%s\n' '============================================================'
        printf '%s\n' 'BFS Linux Installer'
        printf 'Started:        %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
        printf 'Script:         %s\n' "${BASH_SOURCE[0]}"
        printf 'Script path:    %s\n' "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
        printf 'Log file:       %s\n' "$LOG_FILE"
        printf 'Host:           %s\n' "$(hostname 2>/dev/null || printf unknown)"
        printf 'Kernel:         %s\n' "$(uname -r 2>/dev/null || printf unknown)"
        printf 'Architecture:   %s\n' "$(uname -m 2>/dev/null || printf unknown)"
        printf 'Installer PID:  %s\n' "$$"
        printf 'Target:         %s\n' "$TARGET"
        printf 'Locale runtime: LANG=%s LC_ALL=%s LANGUAGE=%s\n' \
                "${LANG:-}" "${LC_ALL:-}" "${LANGUAGE:-}"
        printf '%s\n' '============================================================'
}

close_logging() {
        local status="${1:-0}"
        local ended_epoch=""
        local elapsed=0
        local result="SUCCESS"

        [[ "$LOG_ENABLED" == yes ]] || return 0
        [[ "$LOG_CLOSED" == no ]] || return 0
        [[ -n "$LOG_TEE_PID" ]] || return 0

        ended_epoch="$(date +%s)"
        if [[ -n "$LOG_STARTED_EPOCH" ]]; then
                elapsed=$((ended_epoch - LOG_STARTED_EPOCH))
        fi

        [[ "$status" -eq 0 ]] || result="FAILED"

        printf '\n%s\n' '============================================================'
        printf 'Finished:       %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
        printf 'Result:         %s\n' "$result"
        printf 'Exit status:    %s\n' "$status"
        printf 'Elapsed:        %02d:%02d:%02d\n' \
                "$((elapsed / 3600))" \
                "$(((elapsed % 3600) / 60))" \
                "$((elapsed % 60))"
        printf '%s\n' '============================================================'

        exec 1>&3 2>&4
        wait "$LOG_TEE_PID" 2>/dev/null || true
        rm -f "$LOG_FIFO"

        LOG_FIFO=""
        LOG_TEE_PID=""
        LOG_CLOSED=yes
}

copy_log_to_installed_system() {
        local installed_dir=""
        local installed_log=""

        [[ "$LOG_ENABLED" == yes && -f "$LOG_FILE" ]] || return 0
        [[ -d "$TARGET" ]] || return 0

        installed_dir="$TARGET/var/log/bfs/installer"
        mkdir -p "$installed_dir"

        installed_log="$installed_dir/$(basename "$LOG_FILE")"
        cp -f "$LOG_FILE" "$installed_log"
        chmod 0600 "$installed_log"

        printf 'Installed-system log: /var/log/bfs/installer/%s\n' \
                "$(basename "$LOG_FILE")"
}

require_root() {
        if [[ $EUID -eq 0 ]]; then
                force_posix_locale
                return 0
        fi

        command -v sudo >/dev/null 2>&1 ||
                die "This installer requires root privileges and sudo is unavailable."

        printf '\nThis installer requires root privileges.\n'
        printf 'Authenticating with sudo before the installer starts...\n'
        printf 'The complete installer session will then run as root.\n\n'

        sudo -v || die "sudo authentication failed."

        exec sudo \
                --preserve-env=TERM,BFS_INSTALLER_THEME,BFS_LOG_ENABLED,BFS_LOG_FILE \
                env \
                LANG=C \
                LC_ALL=C \
                LANGUAGE=C \
                "$0" "$@"
}

require_commands() {
        local command
        for command in mount umount mountpoint findmnt lsblk swapoff swapon tar chroot blkid sed awk grep install readlink sha256sum find sort head cut tee mkfifo mktemp date cp dirname; do
                command -v "$command" >/dev/null 2>&1 || die "Missing host command: $command"
        done
}

prepare_target_environment() {
        log "Preparing clean installer mount state"

        # A previous failed run may have left bind mounts nested under TARGET.
        if findmnt -Rrn "$TARGET" 2>/dev/null | grep -q .; then
                warn "Existing mounts were found under $TARGET; unmounting them."
                umount -R "$TARGET" 2>/dev/null || umount -Rl "$TARGET" 2>/dev/null || \
                        die "Could not unmount everything below $TARGET."
        fi

        if findmnt -Rrn "$TARGET" 2>/dev/null | grep -q .; then
                die "A filesystem is still mounted below $TARGET."
        fi

        # Live media normally does not need swap. Turning it all off prevents a
        # selected swap partition from remaining busy during mkswap.
        if swapon --noheadings --show=NAME 2>/dev/null | grep -q .; then
                log "Disabling active swap before partition selection"
                swapoff -a || die "Could not disable all active swap devices."
        fi

        mkdir -p "$TARGET"
}

is_used_device() {
        local wanted="$1" used
        for used in "${USED_DEVICES[@]}"; do
                [[ "$used" == "$wanted" ]] && return 0
        done
        return 1
}

get_available_partitions() {
        local path type size fstype label mountpoints
        local lv_path=""
        local -A seen_paths=()

        AVAILABLE_PATHS=()
        AVAILABLE_TYPES=()
        AVAILABLE_SIZES=()
        AVAILABLE_FSTYPES=()
        AVAILABLE_LABELS=()
        AVAILABLE_MOUNTPOINTS=()
        AVAILABLE_NICS=()
        AVAILABLE_NIC_MACS=()
        AVAILABLE_NIC_STATES=()
        AVAILABLE_NIC_DRIVERS=()

        # First collect ordinary usable block devices. Do not show RAID-member
        # partitions or an MD device that has already become an LVM PV.
        #
        # LVM devices are intentionally excluded here because lsblk commonly
        # exposes the same LV through /dev/mapper/<vg>-<lv>. We add LVs once,
        # below, using the friendlier canonical paths reported by `lvs`
        # (for example /dev/bfs-vg/home).
        while read -r path type size fstype label mountpoints; do
                [[ "$type" == part || "$type" == crypt || "$type" == raid* ]] || continue

                case "$fstype" in
                        linux_raid_member|LVM2_member|crypto_LUKS)
                                # A LUKS header is a storage layer, not a filesystem target.
                                # Format/mount the active /dev/mapper device (or descendants) instead.
                                continue
                                ;;
                esac

                is_used_device "$path" && continue
                [[ -n "${seen_paths[$path]:-}" ]] && continue
                seen_paths["$path"]=1

                AVAILABLE_PATHS+=("$path")
                AVAILABLE_TYPES+=("$type")
                AVAILABLE_SIZES+=("${size:--}")
                AVAILABLE_FSTYPES+=("${fstype:--}")
                AVAILABLE_LABELS+=("${label:--}")
                AVAILABLE_MOUNTPOINTS+=("${mountpoints:--}")
        done < <(
                lsblk -plno PATH,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS |
                awk '{p=$1;t=$2;s=$3;f=$4;l=$5;$1=$2=$3=$4=$5="";sub(/^ +/,"");print p,t,s,f,l,$0}'
        )

        # A previous installer run/cleanup may have deactivated an existing VG.
        # Activate discovered volume groups before enumerating LVs so their
        # /dev/<vg>/<lv> block-device nodes exist for filesystem assignment.
        if command -v vgchange >/dev/null 2>&1; then
                vgchange -ay >/dev/null 2>&1 || true
                command -v udevadm >/dev/null 2>&1 && udevadm settle || true
        fi

        # Query LVM directly and add each logical volume exactly once using
        # LVM's friendly /dev/<vg>/<lv> path. This avoids duplicate aliases such
        # as /dev/mapper/bfs--vg-home and /dev/bfs-vg/home appearing together.
        if command -v lvs >/dev/null 2>&1; then
                while IFS= read -r lv_path; do
                        lv_path="${lv_path#"${lv_path%%[![:space:]]*}"}"
                        lv_path="${lv_path%"${lv_path##*[![:space:]]}"}"
                        [[ -n "$lv_path" && -b "$lv_path" ]] || continue
                        is_used_device "$lv_path" && continue
                        [[ -n "${seen_paths[$lv_path]:-}" ]] && continue

                        path="$lv_path"
                        type="lvm"
                        size="$(lsblk -dnro SIZE "$lv_path" 2>/dev/null | head -n1)"
                        fstype="$(lsblk -dnro FSTYPE "$lv_path" 2>/dev/null | head -n1)"
                        label="$(lsblk -dnro LABEL "$lv_path" 2>/dev/null | head -n1)"
                        mountpoints="$(lsblk -dnro MOUNTPOINTS "$lv_path" 2>/dev/null | head -n1)"

                        seen_paths["$path"]=1
                        AVAILABLE_PATHS+=("$path")
                        AVAILABLE_TYPES+=("$type")
                        AVAILABLE_SIZES+=("${size:--}")
                        AVAILABLE_FSTYPES+=("${fstype:--}")
                        AVAILABLE_LABELS+=("${label:--}")
                        AVAILABLE_MOUNTPOINTS+=("${mountpoints:--}")
                done < <(
                        lvs --noheadings -o lv_path 2>/dev/null || true
                )
        fi
}

show_available_partitions() {
        local index
        get_available_partitions

        printf '\nAvailable partitions not yet assigned:\n'
        printf '  %-4s %-24s %-9s %-10s %-12s %-16s %s\n' \
                NUM DEVICE TYPE SIZE FSTYPE LABEL MOUNTPOINTS

        for ((index=0; index<${#AVAILABLE_PATHS[@]}; index++)); do
                printf '  %-4d %-24s %-9s %-10s %-12s %-16s %s\n' \
                        "$((index + 1))" \
                        "${AVAILABLE_PATHS[$index]}" \
                        "${AVAILABLE_TYPES[$index]}" \
                        "${AVAILABLE_SIZES[$index]}" \
                        "${AVAILABLE_FSTYPES[$index]}" \
                        "${AVAILABLE_LABELS[$index]}" \
                        "${AVAILABLE_MOUNTPOINTS[$index]}"
        done
        printf '\n'
}

select_partition() {
        local variable="$1"
        local prompt="$2"
        local optional="${3:-no}"
        local optional_label="${4:-Skip this partition}"
        local answer=""
        local selected_index=""
        local selected_device=""
        local status=0
        local index=0
        local -a menu_items=()

        if [[ -n "${!variable:-}" ]]; then
                USED_DEVICES+=("${!variable}")
                return 0
        fi

        while true; do
                get_available_partitions
                ((${#AVAILABLE_PATHS[@]} > 0)) ||
                        die "No unassigned partitions are available."

                menu_items=()

                if [[ "$optional" == yes ]]; then
                        menu_items+=(0 "$optional_label")
                fi

                for ((index=0; index<${#AVAILABLE_PATHS[@]}; index++)); do
                        menu_items+=(
                                "$((index + 1))"
                                "${AVAILABLE_PATHS[$index]}  ${AVAILABLE_SIZES[$index]}  ${AVAILABLE_FSTYPES[$index]}  ${AVAILABLE_LABELS[$index]}"
                        )
                done

                set +e
                themed_menu answer \
                        "Filesystem device selection" \
                        "$prompt" \
                        22 92 14 \
                        "${menu_items[@]}"
                status=$?
                set -e

                if ((status != 0)); then
                        return 2
                fi

                if [[ -z "$answer" ]]; then
                        return 2
                fi

                if [[ "$optional" == yes && "$answer" == 0 ]]; then
                        printf -v "$variable" ''
                        return 0
                fi

                [[ "$answer" =~ ^[0-9]+$ ]] || {
                        warn "Choose a partition from the menu."
                        sleep 1
                        continue
                }

                ((answer >= 1 && answer <= ${#AVAILABLE_PATHS[@]})) || {
                        warn "That selection is outside the available range."
                        sleep 1
                        continue
                }

                selected_index=$((answer - 1))
                selected_device="${AVAILABLE_PATHS[$selected_index]}"
                printf -v "$variable" '%s' "$selected_device"
                USED_DEVICES+=("$selected_device")
                return 0
        done
}

choose_linux_format() {
        local variable="$1"
        local device="$2"
        local role="$3"
        local choice=""
        local status=0

        [[ -n "$device" ]] || return 0

        set +e
        themed_menu choice \
                "Filesystem format" \
                "Choose how to prepare $role on $device." \
                19 78 10 \
                1 "Keep the existing filesystem" \
                2 "Format as ext2" \
                3 "Format as ext4" \
                4 "Format as XFS" \
                5 "Format as Btrfs" \
                6 "Format as F2FS"
        status=$?
        set -e

        [[ -n "$choice" ]] || choice=1

        case "$choice" in
                1) printf -v "$variable" '%s' keep ;;
                2) printf -v "$variable" '%s' ext2 ;;
                3) printf -v "$variable" '%s' ext4 ;;
                4) printf -v "$variable" '%s' xfs ;;
                5) printf -v "$variable" '%s' btrfs ;;
                6) printf -v "$variable" '%s' f2fs ;;
                *) warn "Invalid filesystem selection; keeping the existing filesystem."
                   printf -v "$variable" '%s' keep ;;
        esac
}

choose_efi_format() {
        local choice=""
        local status=0

        [[ -n "$EFI_DEV" ]] || return 0

        set +e
        themed_menu choice \
                "EFI System Partition" \
                "Choose how to prepare $EFI_DEV." \
                15 72 6 \
                1 "Keep the existing filesystem" \
                2 "Format as FAT32 with mkfs.fat -F 32"
        status=$?
        set -e

        [[ -n "$choice" ]] || choice=1

        case "$choice" in
                2) EFI_FORMAT=vfat ;;
                *) EFI_FORMAT=keep ;;
        esac
}

choose_swap_format() {
        local choice=""
        local status=0

        [[ -n "$SWAP_DEV" ]] || return 0

        set +e
        themed_menu choice \
                "Swap partition" \
                "Choose how to prepare $SWAP_DEV." \
                15 72 6 \
                1 "Keep the existing swap signature" \
                2 "Reinitialize with mkswap"
        status=$?
        set -e

        [[ -n "$choice" ]] || choice=1

        case "$choice" in
                2) SWAP_FORMAT=swap ;;
                *) SWAP_FORMAT=keep ;;
        esac
}

collect_additional_partitions() {
        local answer="" device="" mountpoint="" format="" status=0
        while true; do
                if command -v dialog >/dev/null 2>&1 &&
                   [[ -r /dev/tty && -w /dev/tty ]]; then
                        set +e
                        dialog --clear \
                                --backtitle "BFS Linux Installer" \
                                --title "Additional filesystem" \
                                --yesno "Add another filesystem partition?" \
                                9 54 \
                                </dev/tty >/dev/tty 2>/dev/tty
                        status=$?
                        set -e
                        ((status == 0)) || break
                else
                        read -r -p "Add another filesystem partition? [y/N]: " answer
                        [[ "${answer,,}" == y || "${answer,,}" == yes ]] || break
                fi
                device=""
                select_partition device "Device for the additional partition" no
                while true; do
                        read -r -p "Mount point (for example /var): " mountpoint
                        [[ "$mountpoint" == /* && "$mountpoint" != / && "$mountpoint" != /boot && "$mountpoint" != /boot/efi && "$mountpoint" != /home && "$mountpoint" != *'..'* ]] && break
                        warn "Use an absolute, non-reserved mount point such as /var or /srv."
                done
                format=keep
                choose_linux_format format "$device" "$mountpoint"
                EXTRA_DEVICES+=("$device")
                EXTRA_MOUNTPOINTS+=("$mountpoint")
                EXTRA_FORMATS+=("$format")
        done
}


get_available_nics() {
        local interface="" mac="" state="" driver=""

        AVAILABLE_NICS=()
        AVAILABLE_NIC_MACS=()
        AVAILABLE_NIC_STATES=()
        AVAILABLE_NIC_DRIVERS=()

        while IFS= read -r interface; do
                [[ "$interface" == lo ]] && continue
                [[ -d "/sys/class/net/$interface" ]] || continue

                mac="$(cat "/sys/class/net/$interface/address" 2>/dev/null || true)"
                state="$(cat "/sys/class/net/$interface/operstate" 2>/dev/null || printf '%s' unknown)"
                driver="$(basename "$(readlink -f "/sys/class/net/$interface/device/driver" 2>/dev/null || true)")"
                [[ -n "$driver" ]] || driver="-"

                AVAILABLE_NICS+=("$interface")
                AVAILABLE_NIC_MACS+=("${mac:--}")
                AVAILABLE_NIC_STATES+=("${state:--}")
                AVAILABLE_NIC_DRIVERS+=("$driver")
        done < <(
                find /sys/class/net -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null |
                sort
        )
}

show_available_nics() {
        local index=""

        get_available_nics
        printf '\nAvailable network interfaces:\n'
        printf '  %-4s %-16s %-20s %-12s %s\n' NUM INTERFACE MAC STATE DRIVER

        for ((index=0; index<${#AVAILABLE_NICS[@]}; index++)); do
                printf '  %-4d %-16s %-20s %-12s %s\n' \
                        "$((index + 1))" \
                        "${AVAILABLE_NICS[$index]}" \
                        "${AVAILABLE_NIC_MACS[$index]}" \
                        "${AVAILABLE_NIC_STATES[$index]}" \
                        "${AVAILABLE_NIC_DRIVERS[$index]}"
        done
        printf '\n'
}

select_network_interface() {
        local answer=""
        local selected_index=""
        local status=0
        local index=0
        local -a menu_items=()

        if [[ -n "$NETWORK_IFACE" ]]; then
                [[ -d "/sys/class/net/$NETWORK_IFACE" ]] ||
                        die "Configured network interface does not exist: $NETWORK_IFACE"
                NETWORK_MAC="$(cat "/sys/class/net/$NETWORK_IFACE/address" 2>/dev/null || true)"
                return 0
        fi

        while true; do
                get_available_nics
                ((${#AVAILABLE_NICS[@]} > 0)) ||
                        die "No usable network interfaces were found."

                menu_items=()
                for ((index=0; index<${#AVAILABLE_NICS[@]}; index++)); do
                        menu_items+=(
                                "$((index + 1))"
                                "${AVAILABLE_NICS[$index]}  ${AVAILABLE_NIC_MACS[$index]}  ${AVAILABLE_NIC_STATES[$index]}  ${AVAILABLE_NIC_DRIVERS[$index]}"
                        )
                done

                themed_menu answer \
                        "Network interface" \
                        "Select the interface BFS should configure." \
                        20 92 12 \
                        "${menu_items[@]}"

                [[ -n "$answer" ]] || return 1
                [[ "$answer" =~ ^[0-9]+$ ]] || continue
                ((answer >= 1 && answer <= ${#AVAILABLE_NICS[@]})) || continue

                selected_index=$((answer - 1))
                NETWORK_IFACE="${AVAILABLE_NICS[$selected_index]}"
                NETWORK_MAC="${AVAILABLE_NIC_MACS[$selected_index]}"
                return 0
        done
}


get_whole_disks() {
        lsblk -dpno NAME,SIZE,MODEL,TYPE |
        awk '$NF == "disk" {
                type=$NF
                $NF=""
                sub(/[[:space:]]+$/, "")
                print
        }'
}

refresh_storage_state() {
        local disk="" failed=0

        sync

        # Ask the kernel to reread partition tables on all whole disks. Busy
        # devices are reported but do not abort the installer; the subsequent
        # inventory is always rebuilt from current kernel state.
        while IFS= read -r disk; do
                [[ -b "$disk" ]] || continue
                if command -v partprobe >/dev/null 2>&1; then
                        partprobe "$disk" >/dev/null 2>&1 || {
                                warn "Could not refresh the partition table for $disk (device may be busy)."
                                failed=1
                        }
                elif command -v blockdev >/dev/null 2>&1; then
                        blockdev --rereadpt "$disk" >/dev/null 2>&1 || {
                                warn "Could not reread the partition table for $disk (device may be busy)."
                                failed=1
                        }
                fi
        done < <(lsblk -dnpo NAME,TYPE 2>/dev/null | awk '$2=="disk" {print $1}')

        command -v udevadm >/dev/null 2>&1 && udevadm settle || true
        command -v pvscan >/dev/null 2>&1 && pvscan --cache >/dev/null 2>&1 || true
        command -v vgscan >/dev/null 2>&1 && vgscan --mknodes >/dev/null 2>&1 || true

        # Rebuild the installer's cached device arrays; never carry a pre-change
        # inventory into the next storage screen.
        get_available_partitions
        return 0
}

partition_disks() {
        local choice="" disk="" index="" line="" status=0
        local -a disk_paths=()
        local -a disk_descriptions=()
        local -a menu_items=()

        command -v cfdisk >/dev/null 2>&1 || {
                warn "cfdisk is not available in this live environment."
                pause_screen
                return 0
        }

        while true; do
                disk_paths=()
                disk_descriptions=()
                menu_items=()

                while IFS= read -r line; do
                        [[ -n "$line" ]] || continue
                        disk="${line%% *}"
                        disk_paths+=("$disk")
                        disk_descriptions+=("$line")
                done < <(get_whole_disks)

                ((${#disk_paths[@]} > 0)) || {
                        warn "No whole disks were found."
                        pause_screen
                        return 0
                }

                for ((index=0; index<${#disk_paths[@]}; index++)); do
                        menu_items+=("$((index + 1))" "${disk_descriptions[$index]}")
                done
                menu_items+=("$(( ${#disk_paths[@]} + 1 ))" "Finished partitioning")

                set +e
                themed_menu choice \
                        "Partition disks" \
                        "Choose a disk to open with cfdisk, or finish without changing partitions." \
                        20 88 12 \
                        "${menu_items[@]}"
                status=$?
                set -e
                [[ -n "$choice" ]] || return 0

                [[ "$choice" =~ ^[0-9]+$ ]] || {
                        warn "Choose a disk number from the menu."
                        sleep 1
                        continue
                }

                if ((choice == ${#disk_paths[@]} + 1)); then
                        return 0
                fi

                ((choice >= 1 && choice <= ${#disk_paths[@]})) || {
                        warn "That selection is outside the available range."
                        sleep 1
                        continue
                }

                disk="${disk_paths[$((choice - 1))]}"
                echo
                echo "Starting cfdisk for $disk..."
                echo "Changes are written only when you choose Write in cfdisk."
                echo

                if ! run_on_tty cfdisk "$disk"; then
                        warn "cfdisk exited with an error for $disk."
                        pause_screen
                fi

                refresh_storage_state
                sleep 1
        done
}


list_raid_member_candidates() {
        # RAID creation in the installer is partition-oriented. Whole disks are
        # intentionally excluded so users do not see both /dev/vdb and
        # /dev/vdb1 for the same physical device after partitioning.
        lsblk -prno PATH,TYPE,SIZE,FSTYPE,MOUNTPOINTS |
        awk '
                $2 == "part" && $5 == "" {
                        print
                }
        '
}

choose_raid_level() {
        local variable="$1"
        local choice="" status=0

        set +e
        themed_menu choice \
                "Select RAID level" \
                "Choose the software RAID layout." \
                20 76 10 \
                1 "Linear / JBOD — combines disks, no redundancy" \
                2 "RAID 0 — striping, performance, no redundancy" \
                3 "RAID 1 — mirroring and redundancy" \
                4 "RAID 4 — striping with dedicated parity" \
                5 "RAID 5 — striping with distributed parity" \
                6 "RAID 6 — striping with dual parity" \
                7 "RAID 10 — striped mirrors" \
                8 "Cancel"
        status=$?
        set -e
        [[ -n "$choice" ]] || return 1

        case "$choice" in
                1) printf -v "$variable" '%s' linear ;;
                2) printf -v "$variable" '%s' 0 ;;
                3) printf -v "$variable" '%s' 1 ;;
                4) printf -v "$variable" '%s' 4 ;;
                5) printf -v "$variable" '%s' 5 ;;
                6) printf -v "$variable" '%s' 6 ;;
                7) printf -v "$variable" '%s' 10 ;;
                8) return 1 ;;
                *) warn "Choose a RAID level from the menu."; return 1 ;;
        esac
}


show_raid_level_summary() {
        local raid_level="$1" summary=""
        case "$raid_level" in
                linear) summary=$'RAID type     : Linear / JBOD\nMinimum disks : 2\nLayout        : Concatenation\nRedundancy    : None\nPerformance   : Similar to a single disk\nUsable space  : Sum of all member capacities' ;;
                0) summary=$'RAID type     : RAID 0\nMinimum disks : 2\nLayout        : Striping\nRedundancy    : None\nPerformance   : Excellent read and write performance\nUsable space  : Sum of all member capacities' ;;
                1) summary=$'RAID type     : RAID 1\nMinimum disks : 2\nLayout        : Mirroring\nRedundancy    : One complete mirrored copy\nPerformance   : Fast reads; writes similar to one disk\nUsable space  : Capacity of the smallest member' ;;
                4) summary=$'RAID type     : RAID 4\nMinimum disks : 3\nLayout        : Striping with dedicated parity\nRedundancy    : One drive may fail\nPerformance   : Fast reads; parity disk may limit writes\nUsable space  : Capacity of N-1 members' ;;
                5) summary=$'RAID type     : RAID 5\nMinimum disks : 3\nLayout        : Striping with distributed parity\nRedundancy    : One drive may fail\nPerformance   : Fast reads; good general-purpose writes\nUsable space  : Capacity of N-1 members' ;;
                6) summary=$'RAID type     : RAID 6\nMinimum disks : 4\nLayout        : Striping with dual distributed parity\nRedundancy    : Two drives may fail\nPerformance   : Fast reads; slower writes than RAID 5\nUsable space  : Capacity of N-2 members' ;;
                10) summary=$'RAID type     : RAID 10\nMinimum disks : 4\nLayout        : Striping across mirrored pairs\nRedundancy    : Multiple failures may be tolerated if mirrors remain intact\nPerformance   : Excellent read and write performance\nUsable space  : Approximately 50% of total capacity' ;;
                *) summary="Unknown RAID level: $raid_level" ;;
        esac
        dialog_message "RAID selection summary" "$summary"
}

minimum_raid_members() {
        case "$1" in
                linear|0|1) printf '%s\n' 2 ;;
                4|5)        printf '%s\n' 3 ;;
                6)          printf '%s\n' 4 ;;
                10)         printf '%s\n' 4 ;;
                *)          return 1 ;;
        esac
}

choose_raid_members() {
        local result_variable="$1"
        local minimum="$2"
        local choice=""
        local index=""
        local selected=""
        local candidate=""
        local status=0
        local line=""
        local description=""
        local fstype=""
        local -a candidates=()
        local -a descriptions=()
        local -a selected_members=()
        local -a menu_items=()
        local -a remaining_candidates=()
        local -a remaining_descriptions=()

        while IFS= read -r line; do
                [[ -n "$line" ]] || continue
                candidate="${line%% *}"
                candidates+=("$candidate")
                descriptions+=("$line")
        done < <(list_raid_member_candidates)

        ((${#candidates[@]} >= minimum)) || {
                warn "At least $minimum unused RAID member partitions are required."
                return 1
        }

        # Preferred interface: one checklist showing only partitions. Space
        # toggles a member, Enter accepts the complete selection, and users can
        # correct a mistaken selection before continuing.
        if command -v dialog >/dev/null 2>&1 &&
           [[ -r /dev/tty && -w /dev/tty ]]; then
                while true; do
                        menu_items=()

                        for ((index=0; index<${#candidates[@]}; index++)); do
                                candidate="${candidates[$index]}"
                                description="${descriptions[$index]}"
                                # Remove the path from the descriptive text because
                                # the path is already the checklist tag.
                                description="${description#"$candidate"}"
                                description="${description#"${description%%[![:space:]]*}"}"
                                [[ -n "$description" ]] || description="RAID member partition"

                                menu_items+=(
                                        "$candidate"
                                        "$description"
                                        off
                                )
                        done

                        set +e
                        choice="$(
                                dialog --stdout --clear \
                                        --backtitle "BFS Linux Installer" \
                                        --title "Select RAID member partitions" \
                                        --cancel-label "Cancel" \
                                        --separate-output \
                                        --checklist \
                                        "Use Up/Down to move, Space to select or unselect members, then Enter on OK.\n\nThis RAID level requires at least $minimum member(s)." \
                                        23 92 15 \
                                        "${menu_items[@]}" \
                                        </dev/tty
                        )"
                        status=$?
                        set -e

                        ((status == 0)) || return 1

                        selected_members=()
                        while IFS= read -r selected; do
                                [[ -n "$selected" ]] || continue
                                selected_members+=("$selected")
                        done <<< "$choice"

                        if ((${#selected_members[@]} < minimum)); then
                                dialog --clear \
                                        --backtitle "BFS Linux Installer" \
                                        --title "Not enough RAID members" \
                                        --msgbox \
                                        "This RAID level requires at least $minimum member(s).\n\nYou selected ${#selected_members[@]}." \
                                        10 60 \
                                        </dev/tty >/dev/tty 2>/dev/tty || true
                                continue
                        fi

                        printf -v "$result_variable" '%s' "${selected_members[*]}"
                        return 0
                done
        fi

        # Text fallback: select one partition at a time, but remove each chosen
        # member from the displayed list so it cannot be selected twice.
        remaining_candidates=("${candidates[@]}")
        remaining_descriptions=("${descriptions[@]}")

        while true; do
                clear_screen
                echo "Select RAID member partitions"
                echo "============================="
                echo
                echo "Selected: ${selected_members[*]:-none}"
                echo

                for ((index=0; index<${#remaining_candidates[@]}; index++)); do
                        printf '  %d) %s\n' \
                                "$((index + 1))" \
                                "${remaining_descriptions[$index]}"
                done

                printf '  %d) Finished selecting members\n' \
                        "$(( ${#remaining_candidates[@]} + 1 ))"
                printf '  %d) Cancel\n\n' \
                        "$(( ${#remaining_candidates[@]} + 2 ))"

                read -r -p "Choose [1-$(( ${#remaining_candidates[@]} + 2 ))]: " choice

                [[ "$choice" =~ ^[0-9]+$ ]] || {
                        warn "Enter a number from the list."
                        sleep 1
                        continue
                }

                if ((choice == ${#remaining_candidates[@]} + 1)); then
                        if ((${#selected_members[@]} < minimum)); then
                                warn "This RAID level requires at least $minimum members."
                                sleep 2
                                continue
                        fi

                        printf -v "$result_variable" '%s' "${selected_members[*]}"
                        return 0
                fi

                if ((choice == ${#remaining_candidates[@]} + 2)); then
                        return 1
                fi

                ((choice >= 1 && choice <= ${#remaining_candidates[@]})) || {
                        warn "That selection is outside the available range."
                        sleep 1
                        continue
                }

                index=$((choice - 1))
                selected="${remaining_candidates[$index]}"
                selected_members+=("$selected")

                unset 'remaining_candidates[index]'
                unset 'remaining_descriptions[index]'
                remaining_candidates=("${remaining_candidates[@]}")
                remaining_descriptions=("${remaining_descriptions[@]}")
        done
}

assemble_raid_arrays() {
        local status_text="" assemble_status=0

        command -v mdadm >/dev/null 2>&1 || {
                dialog_message "Software RAID" "mdadm is not available in this live environment."
                return 0
        }

        # Run mdadm in an if-condition rather than under `set +e`.  The
        # installer has an ERR trap, and a bare non-zero mdadm exit can still
        # trigger that trap even when "no arrays exist" is a perfectly normal
        # result on a clean installation.
        if mdadm --assemble --scan; then
                assemble_status=0
        else
                assemble_status=$?
        fi

        refresh_storage_state

        status_text="$(cat /proc/mdstat 2>/dev/null || true)"

        if ((assemble_status == 0)); then
                dialog_message "Software RAID" "RAID assembly scan completed.\n\n$status_text"
        elif ! awk '$2 == ":" && $4 ~ /^raid/ {found=1} END {exit !found}' /proc/mdstat 2>/dev/null; then
                dialog_message "Software RAID" "No existing RAID arrays were found.\n\nThis is normal on a clean installation. Choose 'Create a new array' to continue."
        else
                dialog_message "Software RAID" "One or more RAID arrays could not be assembled automatically.\n\nCurrent MD status:\n\n$status_text"
        fi
}

create_raid_array() {
        local raid_level="" minimum="" member_string="" array_device="/dev/md0"
        local bitmap_choice=no status_text=""
        local -a members=() bitmap_args=()

        command -v mdadm >/dev/null 2>&1 || { dialog_message "Software RAID" "mdadm is not available in this live environment."; return 0; }
        choose_raid_level raid_level || return 0
        minimum="$(minimum_raid_members "$raid_level")"
        show_raid_level_summary "$raid_level"
        choose_raid_members member_string "$minimum" || return 0
        read -r -a members <<< "$member_string"

        ask_default array_device "Array device (for example /dev/md0)" "/dev/md0" || return 0
        [[ "$array_device" =~ ^/dev/md[0-9]+$ ]] || { dialog_message "Invalid RAID device" "Use an array device such as /dev/md0."; return 0; }
        confirm "Create $array_device as RAID $raid_level using:\n\n${members[*]}\n\nExisting data on all selected members will be destroyed." || return 0

        if [[ "$raid_level" != linear && "$raid_level" != 0 ]]; then
                ask_yes_no bitmap_choice "Enable an internal write-intent bitmap?\n\nThis can improve recovery/resync behavior after an unclean shutdown." no || return 0
                [[ "$bitmap_choice" == yes ]] && bitmap_args=(--bitmap=internal) || bitmap_args=(--bitmap=none)
        fi

        # Refuse to hand already-consumed devices to mdadm.  A live ISO may
        # auto-assemble arrays from stale member metadata (often as /dev/md127),
        # which otherwise makes mdadm --create fail through the global ERR trap.
        local member="" holder="" holder_name="" busy_detail=""
        for member in "${members[@]}"; do
                if findmnt -rn -S "$member" >/dev/null 2>&1; then
                        busy_detail+="$member is mounted or otherwise in use.\n"
                fi
                if [[ -d "/sys/class/block/${member##*/}/holders" ]]; then
                        for holder in /sys/class/block/${member##*/}/holders/*; do
                                [[ -e "$holder" ]] || continue
                                holder_name="${holder##*/}"
                                busy_detail+="$member is held by /dev/$holder_name.\n"
                        done
                fi
        done
        if [[ -n "$busy_detail" ]]; then
                dialog_message "RAID members are busy" "One or more selected RAID members are already in use:\n\n$busy_detail\nStop/close the existing storage layer or choose different members, then retry. No new array was created."
                return 0
        fi

        if [[ "$raid_level" == linear ]]; then
                if ! mdadm --create "$array_device" --run --force --level=linear --raid-devices="${#members[@]}" "${members[@]}"; then
                        dialog_message "RAID creation failed" "mdadm could not create $array_device.\n\nCheck whether any selected member still contains active RAID/LUKS/LVM state, then retry."
                        return 0
                fi
        else
                if ! mdadm --create "$array_device" --run --force --level="$raid_level" --raid-devices="${#members[@]}" "${bitmap_args[@]}" "${members[@]}"; then
                        dialog_message "RAID creation failed" "mdadm could not create $array_device.\n\nCheck whether any selected member still contains active RAID/LUKS/LVM state, then retry."
                        return 0
                fi
        fi
        refresh_storage_state

        local stale_signatures=""
        stale_signatures="$(wipefs -n "$array_device" 2>/dev/null | sed '1d' || true)"
        if [[ -n "$stale_signatures" ]]; then
                if confirm "The newly created array $array_device still exposes old filesystem/LUKS signatures:\n\n$stale_signatures\n\nWipe these stale signatures now?\n\nThis affects only signatures on the assembled array, not its MD member metadata."; then
                        wipefs -a "$array_device"
                        refresh_storage_state
                else
                        dialog_message "RAID signatures kept" "The stale signatures were left intact. They may hide $array_device from later LUKS/filesystem selectors."
                fi
        fi
        status_text="$(cat /proc/mdstat 2>/dev/null || true)"
        dialog_message "RAID array created" "$array_device was created successfully.\n\n$status_text"
}

show_raid_details() {
        local array="" tmp=""

        tmp="$(mktemp /tmp/bfs-raid-status.XXXXXX)"
        {
                printf '%s\n' "Software RAID status"
                printf '%s\n\n' "===================="
                cat /proc/mdstat 2>/dev/null || true

                if command -v mdadm >/dev/null 2>&1; then
                        while IFS= read -r array; do
                                [[ -n "$array" ]] || continue
                                printf '\n%s\n' "------------------------------------------------------------"
                                mdadm --detail "$array" 2>/dev/null || true
                        done < <(
                                lsblk -prno PATH,TYPE 2>/dev/null |
                                awk '$2 ~ /^raid/ { print $1 }'
                        )
                fi
        } >"$tmp"

        if command -v dialog >/dev/null 2>&1 &&
           [[ -r /dev/tty && -w /dev/tty ]]; then
                dialog --clear \
                        --backtitle "BFS Linux Installer" \
                        --title "Software RAID status" \
                        --textbox "$tmp" 28 110 \
                        </dev/tty >/dev/tty 2>/dev/tty || true
        else
                cat "$tmp"
                pause_screen
        fi

        rm -f "$tmp"
}

raid_menu() {
        local choice="" status=0

        while true; do
                set +e
                themed_menu choice \
                        "Software RAID" \
                        "Create, assemble, or inspect Linux software RAID arrays." \
                        17 74 7 \
                        1 "Assemble existing arrays" \
                        2 "Create a new array" \
                        3 "Show array status and details" \
                        4 "Return to Storage setup"
                status=$?
                set -e
                [[ -n "$choice" ]] || return 0

                case "$choice" in
                        1) assemble_raid_arrays ;;
                        2) create_raid_array ;;
                        3) show_raid_details ;;
                        4) return 0 ;;
                        *) warn "Choose a valid RAID option."; sleep 1 ;;
                esac
        done
}

list_luks_candidates() {
        local p="" t="" sz="" fs="" mp="" array=""
        local -A seen=()

        # Always enumerate active MD arrays explicitly.  Depending on util-linux
        # version and array state, lsblk may report an MD device as raid5,
        # raid6, raid10, or another MD-specific TYPE.  The LUKS selector should
        # never lose a valid assembled /dev/md* target because of that detail.
        if [[ -r /proc/mdstat ]]; then
                while IFS= read -r array; do
                        [[ -n "$array" && -b "$array" ]] || continue
                        sz="$(lsblk -dnro SIZE "$array" 2>/dev/null | head -n1)"
                        t="$(lsblk -dnro TYPE "$array" 2>/dev/null | head -n1)"
                        fs="$(lsblk -dnro FSTYPE "$array" 2>/dev/null | head -n1)"
                        mp="$(lsblk -dnro MOUNTPOINTS "$array" 2>/dev/null | head -n1)"
                        [[ -z "$mp" ]] || continue
                        case "$fs" in LVM2_member|crypto_LUKS) continue ;; esac
                        seen["$array"]=1
                        printf '%s|%s|%s|%s\n' "$array" "${sz:--}" "${t:-raid}" "${fs:--}"
                done < <(
                        awk '$2 == ":" && $4 ~ /^raid/ {print "/dev/" $1}' /proc/mdstat
                )
        fi

        while read -r p t sz fs mp; do
                [[ -n "$p" ]] || continue
                [[ -z "${seen[$p]:-}" ]] || continue
                [[ "$t" == part || "$t" == raid* || "$p" == /dev/md* ]] || continue
                [[ -z "$mp" ]] || continue
                case "$fs" in linux_raid_member|LVM2_member|crypto_LUKS) continue ;; esac

                # Do not offer an individual partition that is currently a
                # member of an assembled MD array; offer the MD array itself.
                if [[ "$t" == part ]] &&
                   lsblk -nrpo TYPE "$p" 2>/dev/null |
                        tail -n +2 |
                        grep -qE '^(raid|md)'; then
                        continue
                fi

                printf '%s|%s|%s|%s\n' "$p" "$sz" "$t" "${fs:--}"
        done < <(
                lsblk -prno PATH,TYPE,SIZE,FSTYPE,MOUNTPOINTS |
                        awk '{print $1,$2,$3,$4,$5}'
        )
}

select_luks_device() {
        local result_variable="$1" title="$2" line p sz t fs choice="" status=0
        local -a items=() paths=()
        while IFS='|' read -r p sz t fs; do
                [[ -n "$p" ]] || continue
                paths+=("$p"); items+=("${#paths[@]}" "$p  $sz  $t  $fs")
        done < <(list_luks_candidates)
        ((${#paths[@]})) || { dialog_message "$title" "No eligible LUKS target devices were found."; return 1; }
        themed_menu choice "$title" "Select the block device." 22 92 14 "${items[@]}"
        [[ "$choice" =~ ^[0-9]+$ ]] && ((choice>=1 && choice<=${#paths[@]})) || return 1
        printf -v "$result_variable" '%s' "${paths[$((choice-1))]}"
}

select_luks_existing_device() {
        local result_variable="$1" p="" sz="" fs="" choice=""
        local -a paths=() items=()
        local -A seen=()

        while read -r p sz fs; do
                [[ "$fs" == crypto_LUKS && -n "$p" ]] || continue
                [[ -z "${seen[$p]:-}" ]] || continue
                seen["$p"]=1
                paths+=("$p")
                items+=("${#paths[@]}" "$p  $sz  LUKS")
        done < <(lsblk -prno PATH,SIZE,FSTYPE)

        ((${#paths[@]})) || {
                dialog_message "Open LUKS" "No LUKS containers were found."
                return 1
        }

        themed_menu choice "Open LUKS container" "Select a LUKS device." 20 88 12 "${items[@]}"
        [[ "$choice" =~ ^[0-9]+$ ]] &&
                ((choice>=1 && choice<=${#paths[@]})) || return 1
        printf -v "$result_variable" '%s' "${paths[$((choice-1))]}"
}

ask_mapping_name() {
        local result_variable="$1" default="$2" selected_mapping=""
        while true; do
                ask_default selected_mapping "Mapper name (creates /dev/mapper/<name>)" "$default" || return 1
                [[ "$selected_mapping" =~ ^[A-Za-z0-9+_.-]+$ ]] || { dialog_message "Invalid mapper name" "Use letters, numbers, +, _, . or -. Spaces and / are not allowed."; continue; }
                [[ ! -e "/dev/mapper/$selected_mapping" ]] || { dialog_message "Mapper already exists" "/dev/mapper/$selected_mapping already exists. Choose another name."; continue; }

                # Bash uses dynamic scoping for local variables. Do not name this
                # helper-local value `mapping`, because the caller also asks us
                # to return into a variable named `mapping`; otherwise printf -v
                # updates the helper's local variable and the caller sees blank.
                printf -v "$result_variable" '%s' "$selected_mapping"
                return 0
        done
}

luks_menu() {
        local choice="" device="" mapping="" pass1="" pass2="" status=0 default_mapping="cryptroot"
        while true; do
                themed_menu choice "LUKS encryption" "Create, open, or close encrypted block-device mappings." 17 74 7 \
                        1 "Create a new LUKS container" 2 "Open an existing LUKS container" 3 "Close a mapped LUKS container" 4 "Return to Storage setup"
                [[ -n "$choice" ]] || return 0
                case "$choice" in
                        1)
                                command -v cryptsetup >/dev/null 2>&1 || { dialog_message "LUKS encryption" "cryptsetup is unavailable."; continue; }
                                select_luks_device device "Create LUKS container" || continue
                                [[ "$device" == /dev/md* ]] && default_mapping="cryptraid" || default_mapping="cryptroot"
                                confirm "WARNING: This will permanently overwrite data on $device.\n\nCreate a new LUKS2 container?" || continue
                                while true; do
                                        dialog_password pass1 "LUKS passphrase" "Enter the new passphrase for $device." || { pass1=""; break; }
                                        dialog_password pass2 "Confirm LUKS passphrase" "Enter the same passphrase again." || { pass1=""; pass2=""; break; }
                                        [[ -n "$pass1" ]] || { dialog_message "LUKS passphrase" "The passphrase cannot be empty."; continue; }
                                        [[ "$pass1" == "$pass2" ]] || { dialog_message "LUKS passphrase" "The passphrases did not match. Try again."; pass1=""; pass2=""; continue; }
                                        break
                                done
                                [[ -n "$pass1" ]] || continue
                                if ! printf '%s' "$pass1" | cryptsetup luksFormat --type luks2 --batch-mode --key-file - "$device"; then
                                        pass1=""; pass2=""; dialog_message "LUKS error" "cryptsetup luksFormat failed for $device."; continue
                                fi
                                ask_mapping_name mapping "$default_mapping" || { pass1=""; pass2=""; continue; }
                                if ! printf '%s' "$pass1" | cryptsetup open --key-file - "$device" "$mapping"; then
                                        pass1=""; pass2=""; dialog_message "LUKS error" "The new container was created, but /dev/mapper/$mapping could not be opened."; continue
                                fi
                                pass1=""; pass2=""
                                OPENED_LUKS_BY_SCRIPT+=("$mapping")
                                refresh_storage_state
                                if [[ -b "/dev/mapper/$mapping" ]] && cryptsetup status "$mapping" >/dev/null 2>&1; then
                                        dialog_message "LUKS ready" "$device is encrypted and open as /dev/mapper/$mapping."
                                else
                                        dialog_message "LUKS error" "The mapping /dev/mapper/$mapping did not remain active."
                                fi
                                ;;
                        2)
                                command -v cryptsetup >/dev/null 2>&1 || { dialog_message "LUKS encryption" "cryptsetup is unavailable."; continue; }
                                select_luks_existing_device device || continue
                                ask_mapping_name mapping "cryptroot" || continue
                                dialog_password pass1 "LUKS passphrase" "Enter the passphrase for $device." || continue
                                if printf '%s' "$pass1" | cryptsetup open --key-file - "$device" "$mapping"; then
                                        OPENED_LUKS_BY_SCRIPT+=("$mapping"); refresh_storage_state
                                        dialog_message "LUKS opened" "$device is open as /dev/mapper/$mapping."
                                else
                                        dialog_message "LUKS error" "Could not open $device."
                                fi
                                pass1=""
                                ;;
                        3)
                                ask_default mapping "Mapping name to close" "cryptroot" || continue
                                if cryptsetup close "$mapping"; then
                                        refresh_storage_state
                                        dialog_message "LUKS closed" "/dev/mapper/$mapping was closed."
                                else
                                        dialog_message "LUKS error" "Could not close $mapping."
                                fi
                                ;;
                        4) return 0 ;;
                esac
        done
}

select_pv_devices() {
        local result_variable="$1" p="" t="" sz="" fs="" mp="" choice="" status=0
        local -a paths=() items=()
        local -A seen=()

        while read -r p t sz fs mp; do
                [[ -n "$p" ]] || continue
                [[ -z "${seen[$p]:-}" ]] || continue
                seen["$p"]=1
                [[ "$t" == part || "$t" == crypt || "$t" == raid* || "$p" == /dev/mapper/* ]] || continue
                [[ -z "$mp" ]] || continue
                case "$fs" in linux_raid_member|LVM2_member|crypto_LUKS) continue ;; esac
                paths+=("$p")
                items+=("$p" "$sz  $t  ${fs:--}" off)
        done < <(lsblk -prno PATH,TYPE,SIZE,FSTYPE,MOUNTPOINTS | awk '{print $1,$2,$3,$4,$5}')

        ((${#paths[@]})) || {
                dialog_message "LVM physical volume" "No eligible block devices were found."
                return 1
        }

        if command -v dialog >/dev/null 2>&1 && [[ -r /dev/tty && -w /dev/tty ]]; then
                if choice="$(dialog --stdout --clear \
                        --backtitle "BFS Linux Installer" \
                        --title "LVM physical volume" \
                        --cancel-label "Back" --separate-output --checklist \
                        "Use Up/Down to move and Space to select one or more devices." \
                        22 92 14 "${items[@]}" </dev/tty)"; then
                        status=0
                else
                        status=$?
                fi
                ((status==0)) || return 1
                choice="$(printf '%s\n' "$choice" | tr '\n' ' ')"
        else
                ask_default choice "Physical volume device(s), separated by spaces" "/dev/" || return 1
        fi

        [[ -n "${choice// /}" ]] || return 1
        printf -v "$result_variable" '%s' "$choice"
}

select_existing_pvs() {
        local result_variable="$1" pv="" size="" vg="" choice="" status=0
        local -a items=()
        local -A seen=()

        while IFS='|' read -r pv size vg; do
                pv="$(printf '%s' "$pv" | xargs)"
                size="$(printf '%s' "$size" | xargs)"
                vg="$(printf '%s' "$vg" | xargs)"
                [[ -n "$pv" && -z "$vg" ]] || continue
                [[ -z "${seen[$pv]:-}" ]] || continue
                seen["$pv"]=1
                items+=("$pv" "${size:-unknown}  unassigned PV" off)
        done < <(pvs --noheadings --separator '|' -o pv_name,pv_size,vg_name 3>&- 4>&- 2>/dev/null || true)

        ((${#items[@]})) || {
                dialog_message "Create volume group" \
                        "No unassigned LVM physical volumes were found.\n\nCreate a physical volume first."
                return 1
        }

        if command -v dialog >/dev/null 2>&1 && [[ -r /dev/tty && -w /dev/tty ]]; then
                if choice="$(dialog --stdout --clear \
                        --backtitle "BFS Linux Installer" \
                        --title "Select physical volumes" \
                        --cancel-label "Back" --separate-output --checklist \
                        "Select one or more existing, unassigned physical volumes for the new volume group." \
                        22 92 14 "${items[@]}" </dev/tty)"; then
                        status=0
                else
                        status=$?
                fi
                ((status==0)) || return 1
                choice="$(printf '%s\n' "$choice" | tr '\n' ' ')"
        else
                ask_default choice "Existing physical volume(s), separated by spaces" "" || return 1
        fi

        [[ -n "${choice// /}" ]] || return 1
        printf -v "$result_variable" '%s' "$choice"
}

select_existing_vg() {
        local result_variable="$1" vg="" size="" free="" choice=""
        local -a names=() items=()
        local -A seen=()

        while IFS='|' read -r vg size free; do
                vg="$(printf '%s' "$vg" | xargs)"
                size="$(printf '%s' "$size" | xargs)"
                free="$(printf '%s' "$free" | xargs)"
                [[ -n "$vg" ]] || continue
                [[ -z "${seen[$vg]:-}" ]] || continue
                seen["$vg"]=1
                names+=("$vg")
                items+=("${#names[@]}" "$vg  size=${size:-?} free=${free:-?}")
        done < <(vgs --noheadings --separator '|' -o vg_name,vg_size,vg_free 3>&- 4>&- 2>/dev/null || true)

        ((${#names[@]})) || {
                dialog_message "Create logical volume" "No LVM volume groups were found."
                return 1
        }

        themed_menu choice "Select volume group" \
                "Choose the volume group in which to create the logical volume." \
                20 86 12 "${items[@]}"
        [[ "$choice" =~ ^[0-9]+$ ]] &&
                ((choice>=1 && choice<=${#names[@]})) || return 1
        printf -v "$result_variable" '%s' "${names[$((choice-1))]}"
}

lvm_review_text() {
        local pv="" vg="" size="" free="" lv="" path=""
        local found=no

        printf 'Physical Volumes:\n'
        while IFS='|' read -r pv vg size free; do
                pv="$(printf '%s' "$pv" | xargs)"
                vg="$(printf '%s' "$vg" | xargs)"
                size="$(printf '%s' "$size" | xargs)"
                free="$(printf '%s' "$free" | xargs)"
                [[ -n "$pv" ]] || continue
                found=yes
                printf '  %s  size=%s free=%s  VG=%s\n' \
                        "$pv" "${size:-?}" "${free:-?}" "${vg:-unassigned}"
        done < <(pvs --noheadings --separator '|' -o pv_name,vg_name,pv_size,pv_free 3>&- 4>&- 2>/dev/null || true)
        [[ "$found" == yes ]] || printf '  none\n'

        printf 'Volume Groups:\n'
        found=no
        while IFS='|' read -r vg size free; do
                vg="$(printf '%s' "$vg" | xargs)"
                size="$(printf '%s' "$size" | xargs)"
                free="$(printf '%s' "$free" | xargs)"
                [[ -n "$vg" ]] || continue
                found=yes
                printf '  %s  size=%s free=%s\n' "$vg" "${size:-?}" "${free:-?}"
        done < <(vgs --noheadings --separator '|' -o vg_name,vg_size,vg_free 3>&- 4>&- 2>/dev/null || true)
        [[ "$found" == yes ]] || printf '  none\n'

        printf 'Logical Volumes:\n'
        found=no
        while IFS='|' read -r vg lv path size; do
                vg="$(printf '%s' "$vg" | xargs)"
                lv="$(printf '%s' "$lv" | xargs)"
                path="$(printf '%s' "$path" | xargs)"
                size="$(printf '%s' "$size" | xargs)"
                [[ -n "$lv" ]] || continue
                found=yes
                printf '  %s/%s  %s  size=%s\n' "$vg" "$lv" "${path:-/dev/$vg/$lv}" "${size:-?}"
        done < <(lvs --noheadings --separator '|' -o vg_name,lv_name,lv_path,lv_size 3>&- 4>&- 2>/dev/null || true)
        [[ "$found" == yes ]] || printf '  none\n'
}

show_lvm_status_dialog() {
        local text
        text="$( { printf 'PHYSICAL VOLUMES\n'; pvs 2>&1 || true; printf '\nVOLUME GROUPS\n'; vgs 2>&1 || true; printf '\nLOGICAL VOLUMES\n'; lvs 2>&1 || true; } 3>&- 4>&-)"
        dialog_message "LVM status" "$text"
}

lvm_menu() {
        local choice=""
        local device=""
        local pv_list=""
        local vg_name=""
        local lv_name=""
        local lv_size=""
        local normalized_size=""
        local status=0 index=""
        local -a pv_array=()

        # LVM reports inherited installer logging descriptors as "leaked".
        # Closing only fd 3/4 for LVM utilities keeps normal stdout/stderr logging
        # while preventing those harmless warnings.
        lvm_run() {
                "$@" 3>&- 4>&-
        }

        while true; do
                set +e
                themed_menu choice \
                        "LVM storage" \
                        "Create or inspect Linux Logical Volume Manager objects." \
                        18 74 8 \
                        1 "Create a physical volume" \
                        2 "Create a volume group" \
                        3 "Create a logical volume" \
                        4 "Show LVM devices" \
                        5 "Return to Storage setup"
                status=$?
                set -e
                [[ -n "$choice" ]] || return 0

                case "$choice" in
                        1)
                                command -v pvcreate >/dev/null 2>&1 || {
                                        warn "LVM tools are unavailable."
                                        pause_screen
                                        continue
                                }
                                pv_list=""
                                select_pv_devices pv_list || continue
                                read -r -a pv_array <<< "$pv_list"
                                confirm "Initialize these device(s) as LVM physical volumes?\n\n${pv_array[*]}" || continue
                                if ! lvm_run pvcreate "${pv_array[@]}"; then
                                        dialog_message "LVM error" "pvcreate failed. Returning to the LVM menu."
                                        continue
                                fi
                                refresh_storage_state
                                dialog_message "LVM physical volume" "Physical volume creation completed successfully.\n\n${pv_array[*]}"
                                ;;
                        2)
                                command -v vgcreate >/dev/null 2>&1 || {
                                        warn "LVM tools are unavailable."
                                        pause_screen
                                        continue
                                }
                                vg_name=""
                                pv_list=""
                                ask_default vg_name "New volume-group name" "bfs-vg" || continue
                                select_existing_pvs pv_list || continue
                                [[ -n "$vg_name" && -n "$pv_list" ]] || {
                                        dialog_message "LVM volume group" "A volume-group name and at least one physical volume are required."
                                        continue
                                }
                                read -r -a pv_array <<< "$pv_list"
                                if ! lvm_run vgcreate "$vg_name" "${pv_array[@]}"; then
                                        warn "vgcreate failed. Returning to the LVM menu."
                                        pause_screen
                                        continue
                                fi
                                ACTIVATED_VGS_BY_SCRIPT+=("$vg_name")
                                refresh_storage_state
                                dialog_message "LVM volume group" "Volume group '$vg_name' created successfully."
                                ;;
                        3)
                                command -v lvcreate >/dev/null 2>&1 || {
                                        warn "LVM tools are unavailable."
                                        pause_screen
                                        continue
                                }
                                vg_name=""
                                lv_name=""
                                lv_size=""
                                select_existing_vg vg_name || continue
                                ask_default lv_name "Logical-volume name" "home" || continue
                                ask_default lv_size \
                                        "LV size: 10G, 50%, 50%VG, 50%FREE, or 100%FREE (bare % means %VG)" \
                                        "50%" || continue

                                [[ "$vg_name" =~ ^[A-Za-z0-9+_.-]+$ ]] || {
                                        warn "Invalid volume-group name: $vg_name"
                                        pause_screen
                                        continue
                                }
                                [[ "$lv_name" =~ ^[A-Za-z0-9+_.-]+$ ]] || {
                                        warn "Invalid logical-volume name: $lv_name"
                                        pause_screen
                                        continue
                                }

                                normalized_size="${lv_size^^}"
                                normalized_size="${normalized_size//[[:space:]]/}"

                                # Friendly shorthand: LVM itself rejects 50%, but users
                                # naturally expect it to mean 50% of the volume group.
                                if [[ "$normalized_size" =~ ^([1-9][0-9]?|100)%$ ]]; then
                                        normalized_size="${normalized_size%%%}%VG"
                                fi

                                if [[ "$normalized_size" =~ ^([1-9][0-9]?|100)%(VG|FREE)$ ]]; then
                                        if ! lvm_run lvcreate -l "$normalized_size" -n "$lv_name" "$vg_name"; then
                                                warn "lvcreate failed. Check the requested percentage and free space; the installer will continue."
                                                pause_screen
                                                continue
                                        fi
                                elif [[ "$normalized_size" =~ ^[1-9][0-9]*([.][0-9]+)?[KMGTPE]$ ]]; then
                                        if ! lvm_run lvcreate -L "$normalized_size" -n "$lv_name" "$vg_name"; then
                                                warn "lvcreate failed. Check the requested size and free space; the installer will continue."
                                                pause_screen
                                                continue
                                        fi
                                else
                                        warn "Invalid LV size '$lv_size'. Use values such as 10G, 50%, 50%VG, 50%FREE, or 100%FREE."
                                        pause_screen
                                        continue
                                fi

                                refresh_storage_state
                                dialog_message "LVM logical volume" "Logical volume '$lv_name' created successfully in '$vg_name'."
                                ;;
                        4)
                                show_lvm_status_dialog
                                ;;
                        5) return 0 ;;
                        *) warn "Choose a valid LVM option."; sleep 1 ;;
                esac
        done
}

show_current_storage_dialog() {
        local tmp
        tmp="$(mktemp /tmp/bfs-storage-devices.XXXXXX)"
        lsblk -fp -o NAME,FSTYPE,FSVER,LABEL,UUID,FSAVAIL,FSUSE%,MOUNTPOINTS >"$tmp" 2>&1 || true
        if command -v dialog >/dev/null 2>&1 && [[ -r /dev/tty && -w /dev/tty ]]; then
                dialog --clear --backtitle "BFS Linux Installer" \
                        --title "Current storage devices" --textbox "$tmp" 24 110 \
                        </dev/tty >/dev/tty 2>/dev/tty || true
        else
                cat "$tmp"
        fi
        rm -f "$tmp"
}

storage_menu() {
        local choice="" status=0

        while true; do
                set +e
                themed_menu choice \
                        "Storage setup" \
                        "Use only the storage tools you need. Existing partitions may be assigned directly." \
                        22 84 12 \
                        1 "Partition disks with cfdisk (optional)" \
                        2 "Create or assemble software RAID (optional)" \
                        3 "Configure LUKS encryption (optional)" \
                        4 "Configure LVM (optional)" \
                        5 "Assign filesystems and mount points (required)" \
                        6 "Configure ZRAM swap (optional) [$ZRAM_SWAP, $ZRAM_SIZE_SPEC]" \
                        7 "Show current storage devices" \
                        8 "Return to main menu"
                status=$?
                set -e
                [[ -n "$choice" ]] || return 0

                case "$choice" in
                        1) partition_disks ;;
                        2) raid_menu ;;
                        3) luks_menu ;;
                        4) lvm_menu ;;
                        5) configure_disks ;;
                        6) configure_zram_menu ;;
                        7) show_current_storage_dialog ;;
                        8) return 0 ;;
                        *) warn "Choose a valid storage option."; sleep 1 ;;
                esac
        done
}


choose_storage_format() {
        local result_variable="$1"
        local device="$2"
        local selection=""
        local status=0

        set +e
        themed_menu selection \
                "Filesystem action" \
                "Choose whether to keep or format $device." \
                20 82 11 \
                1 "Do not format; keep the existing filesystem" \
                2 "Format as ext2" \
                3 "Format as ext4" \
                4 "Format as XFS" \
                5 "Format as Btrfs" \
                6 "Format as F2FS" \
                7 "Format as FAT32 (EFI or other VFAT use)" \
                8 "Initialize as swap"
        status=$?
        set -e

        [[ -n "$selection" ]] || return 1

        case "$selection" in
                1) printf -v "$result_variable" '%s' keep ;;
                2) printf -v "$result_variable" '%s' ext2 ;;
                3) printf -v "$result_variable" '%s' ext4 ;;
                4) printf -v "$result_variable" '%s' xfs ;;
                5) printf -v "$result_variable" '%s' btrfs ;;
                6) printf -v "$result_variable" '%s' f2fs ;;
                7) printf -v "$result_variable" '%s' vfat ;;
                8) printf -v "$result_variable" '%s' swap ;;
                *) return 1 ;;
        esac
}

ask_mountpoint_dialog() {
        local result_variable="$1"
        local device="$2"
        local format="$3"
        local value=""
        local status=0
        local default_value="/"
        local base="${device##*/}"

        # Suggest obvious mount points, but always leave the value editable.
        case "$base" in
                root|luksroot) default_value=/ ;;
                usr) default_value=/usr ;;
                opt) default_value=/opt ;;
                home) default_value=/home ;;
                var) default_value=/var ;;
                tmp) default_value=/tmp ;;
                srv) default_value=/srv ;;
                swap) default_value=swap ;;
                *)
                        if [[ "$format" == ext2 ]] && ! storage_mountpoint_in_use /boot; then
                                default_value=/boot
                        elif [[ "$format" == vfat ]] && ! storage_mountpoint_in_use /boot/efi; then
                                default_value=/boot/efi
                        fi
                        ;;
        esac

        if [[ "$format" == swap ]]; then
                printf -v "$result_variable" '%s' swap
                return 0
        fi

        while true; do
                if command -v dialog >/dev/null 2>&1 &&
                   [[ -r /dev/tty && -w /dev/tty ]]; then
                        if value="$(
                                dialog --stdout --clear \
                                        --backtitle "BFS Linux Installer" \
                                        --title "Mount point" \
                                        --cancel-label "Back" \
                                        --inputbox \
                                        "Enter where $device should be mounted.\n\nExamples: /, /boot, /boot/efi, /home, /var" \
                                        14 76 "$default_value" \
                                        </dev/tty
                        )"; then
                                status=0
                        else
                                status=$?
                        fi
                        ((status == 0)) || return 1
                else
                        read -r -p "Mount point for $device: " value
                fi

                value="$(
                        printf '%s' "$value" |
                                tr -d '\r\n' |
                                sed -e 's/^[[:space:]]*//' \
                                    -e 's/[[:space:]]*$//'
                )"

                if [[ "$value" == /* &&
                      "$value" != *'..'* &&
                      "$value" != *' '* ]]; then
                        printf -v "$result_variable" '%s' "$value"
                        return 0
                fi

                warn "Use an absolute mount point such as /, /home, or /var."
                sleep 1
        done
}

storage_mountpoint_in_use() {
        local wanted="$1"
        local existing=""

        for existing in "${STORAGE_MOUNTPOINTS[@]}"; do
                [[ "$existing" == "$wanted" ]] && return 0
        done
        return 1
}

storage_selection_summary_text() {
        local index=0 action="" format="" dev=""
        printf '%s
' "Selected filesystems and mount points" "====================================" ""
        printf '%-4s %-38s %-22s %s
' NUM DEVICE ACTION MOUNTPOINT
        printf '%-4s %-38s %-22s %s
' --- ------ ------ ----------
        for ((index=0; index<${#STORAGE_DEVICES[@]}; index++)); do
                format="${STORAGE_FORMATS[$index]}"
                dev="${STORAGE_DEVICES[$index]}"
                if [[ "$format" == keep ]]; then
                        action="KEEP"
                else
                        action="FORMAT as $format"
                fi
                printf '%-4d %-38s %-22s %s
' \
                        "$((index + 1))" "$dev" "$action" "${STORAGE_MOUNTPOINTS[$index]}"
        done
}

confirm_storage_selection_plan() {
        local tmp="" choice="" status=0
        tmp="$(mktemp /tmp/bfs-filesystem-plan.XXXXXX)"
        storage_selection_summary_text >"$tmp"

        if command -v dialog >/dev/null 2>&1 && [[ -r /dev/tty && -w /dev/tty ]]; then
                dialog --clear --backtitle "BFS Linux Installer" \
                        --title "Filesystem plan" \
                        --exit-label "Continue" \
                        --textbox "$tmp" 28 118 \
                        </dev/tty >/dev/tty 2>/dev/tty || { rm -f "$tmp"; return 1; }

                dialog --clear --backtitle "BFS Linux Installer" \
                        --title "Confirm storage assignments" \
                        --yes-label "Continue" \
                        --no-label "Back" \
                        --yesno "Use the filesystem plan shown on the previous screen?" 9 72 \
                        </dev/tty >/dev/tty 2>/dev/tty
                status=$?
                rm -f "$tmp"
                ((status == 0))
                return
        fi

        cat "$tmp"
        rm -f "$tmp"
        read -r -p "Use these selections? [Y/n]: " choice
        [[ -z "$choice" || "${choice,,}" == y || "${choice,,}" == yes ]]
}

show_storage_selection_summary() {
        local text
        text="$(storage_selection_summary_text)"
        if command -v dialog >/dev/null 2>&1 && [[ -r /dev/tty && -w /dev/tty ]]; then
                dialog --clear --backtitle "BFS Linux Installer" \
                        --title "Filesystem plan" --msgbox "$text" 22 100 \
                        </dev/tty >/dev/tty 2>/dev/tty || true
        else
                clear_screen
                printf '%s\n' "$text"
        fi
}

apply_storage_selections() {
        local index=0
        local device=""
        local format=""
        local mountpoint=""

        ROOT_DEV=""
        BOOT_DEV=""
        EFI_DEV=""
        SWAP_DEV=""
        HOME_DEV=""

        ROOT_FORMAT=keep
        BOOT_FORMAT=keep
        EFI_FORMAT=keep
        SWAP_FORMAT=keep
        HOME_FORMAT=keep

        EXTRA_DEVICES=()
        EXTRA_MOUNTPOINTS=()
        EXTRA_FORMATS=()

        for ((index=0; index<${#STORAGE_DEVICES[@]}; index++)); do
                device="${STORAGE_DEVICES[$index]}"
                format="${STORAGE_FORMATS[$index]}"
                mountpoint="${STORAGE_MOUNTPOINTS[$index]}"

                case "$mountpoint" in
                        /)
                                ROOT_DEV="$device"
                                ROOT_FORMAT="$format"
                                ;;
                        /boot)
                                BOOT_DEV="$device"
                                BOOT_FORMAT="$format"
                                ;;
                        /boot/efi)
                                EFI_DEV="$device"
                                EFI_FORMAT="$format"
                                ;;
                        /home)
                                HOME_DEV="$device"
                                HOME_FORMAT="$format"
                                ;;
                        swap)
                                SWAP_DEV="$device"
                                SWAP_FORMAT="$format"
                                ;;
                        *)
                                EXTRA_DEVICES+=("$device")
                                EXTRA_MOUNTPOINTS+=("$mountpoint")
                                EXTRA_FORMATS+=("$format")
                                ;;
                esac
        done

        [[ -n "$ROOT_DEV" ]] || {
                warn "A root filesystem mounted at / is required."
                return 1
        }

        DISKS_CONFIGURED=yes
        return 0
}

configure_disks() {
        local device=""
        local format=""
        local mountpoint=""
        local choice=""
        local status=0
        local confirmed=no
        local index=0

        while true; do
                USED_DEVICES=()
                STORAGE_DEVICES=()
                STORAGE_FORMATS=()
                STORAGE_MOUNTPOINTS=()

                while true; do
                        get_available_partitions

                        if ((${#AVAILABLE_PATHS[@]} == 0)); then
                                [[ ${#STORAGE_DEVICES[@]} -gt 0 ]] ||
                                        die "No unassigned partitions are available."
                                break
                        fi

                        device=""
                        set +e
                        select_partition device \
                                "Select a device to add/edit its filesystem and mount point.\n\nCurrent selections: ${#STORAGE_DEVICES[@]}\nChoose Done when all filesystems are assigned." \
                                yes \
                                "Done selecting filesystems"
                        status=$?
                        set -e
                        if ((status == 2)); then
                                return 0
                        elif ((status != 0)); then
                                continue
                        fi

                        [[ -n "$device" ]] || break

                        format=""
                        if ! choose_storage_format format "$device"; then
                                continue
                        fi

                        mountpoint=""
                        if ! ask_mountpoint_dialog mountpoint "$device" "$format"; then
                                continue
                        fi

                        if storage_mountpoint_in_use "$mountpoint"; then
                                warn "The mount point $mountpoint has already been assigned."
                                sleep 1
                                continue
                        fi

                        STORAGE_DEVICES+=("$device")
                        STORAGE_FORMATS+=("$format")
                        STORAGE_MOUNTPOINTS+=("$mountpoint")

                        # Return to the same device-selection menu. The user
                        # chooses "Done selecting filesystems" when complete,
                        # instead of answering a repeated Add another? prompt.
                        continue
                done

                if ((${#STORAGE_DEVICES[@]} == 0)); then
                        dialog_message "Filesystem assignment" "No filesystem assignments were saved. Returning to Storage setup."
                        return 0
                fi

                if ! apply_storage_selections; then
                        dialog_message "Filesystem assignment" "The filesystem plan is incomplete or invalid. Review the assignments and try again."
                        continue
                fi

                if confirm_storage_selection_plan; then
                        confirmed=yes
                else
                        confirmed=no
                fi

                if [[ "$confirmed" == yes ]]; then
                        DISKS_CONFIGURED=yes
                        validate_zram_settings
                        return 0
                fi
        done
}


supported_base_archive() {
        local file="$1"
        [[ -f "$file" && -r "$file" ]] || return 1
        case "$file" in
                *.tar.xz|*.tar.zst|*.tar.gz) return 0 ;;
                *) return 1 ;;
        esac
}

archive_timestamp_key() {
        local file="$1" base="" mtime=""
        base="$(basename "$file")"
        if [[ "$base" =~ ([0-9]{8})[-_]?([0-9]{6}) ]]; then
                printf '%s%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
                return 0
        fi
        mtime="$(stat -c '%Y' "$file" 2>/dev/null || printf '0')"
        printf 'mtime-%020d\n' "$mtime"
}

newest_base_archive() {
        local directory="$1" file="" key="" best="" best_key=""
        [[ -d "$directory" ]] || return 1
        while IFS= read -r -d '' file; do
                supported_base_archive "$file" || continue
                key="$(archive_timestamp_key "$file")"
                if [[ -z "$best" || "$key" > "$best_key" ||
                      ( "$key" == "$best_key" && "$file" > "$best" ) ]]; then
                        best="$file"
                        best_key="$key"
                fi
        done < <(
                find "$directory" -maxdepth 1 -type f \
                        \( -name 'bfs-rootfs-*.tar.xz' -o \
                           -name 'bfs-rootfs-*.tar.zst' -o \
                           -name 'bfs-rootfs-*.tar.gz' \) \
                        -print0 2>/dev/null
        )
        [[ -n "$best" ]] || return 1
        printf '%s\n' "$best"
}

browse_base_archive() {
        local result_var="$1" start_path="$2" selected="" status=0
        if command -v dialog >/dev/null 2>&1 &&
           [[ -r /dev/tty && -w /dev/tty ]]; then
                [[ -d "$start_path" ]] || start_path="$(dirname "$start_path")"
                [[ -d "$start_path" ]] || start_path="/"
                set +e
                selected="$(
                        dialog --stdout --clear \
                                --backtitle "BFS Linux Installer" \
                                --title "Select BFSOS base rootfs archive" \
                                --cancel-label "Back" \
                                --fselect "${start_path%/}/" \
                                22 100 \
                                </dev/tty 2>/dev/tty
                )"
                status=$?
                set -e
                ((status == 0)) || return 1
        else
                read -r -p "Path to BFSOS base rootfs archive: " selected
                [[ -n "$selected" ]] || return 1
        fi
        printf -v "$result_var" '%s' "$selected"
}

confirm_detected_archive() {
        local archive="$1" choice="" status=0 size="" stamp=""
        size="$(du -h "$archive" 2>/dev/null | awk '{print $1}')"
        stamp="$(date -r "$archive" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
        if command -v dialog >/dev/null 2>&1 &&
           [[ -r /dev/tty && -w /dev/tty ]]; then
                set +e
                choice="$(
                        dialog --stdout --clear \
                                --backtitle "BFS Linux Installer" \
                                --title "Base rootfs archive" \
                                --cancel-label "Back" \
                                --menu \
                                "Newest available BFSOS base archive:\n\n$archive\nSize: ${size:-unknown}\nTimestamp: ${stamp:-unknown}\n\nChoose an action." \
                                18 100 5 \
                                use "Use this archive" \
                                browse "Browse for a different archive" \
                                </dev/tty 2>/dev/tty
                )"
                status=$?
                set -e
                ((status == 0)) || return 2
                case "$choice" in
                        use) return 0 ;;
                        browse) return 1 ;;
                        *) return 2 ;;
                esac
        fi
        printf '\nNewest available BFSOS base archive:\n  %s\n  Size: %s\n  Timestamp: %s\n' \
                "$archive" "${size:-unknown}" "${stamp:-unknown}"
        read -r -p "Use this archive? [Y/n/b=browse]: " choice
        case "${choice,,}" in
                ""|y|yes) return 0 ;;
                b|browse|n|no) return 1 ;;
                *) return 2 ;;
        esac
}



validate_zram_settings() {
        [[ "$ZRAM_SWAP" == yes || "$ZRAM_SWAP" == no ]] || ZRAM_SWAP=no
        [[ "$ZRAM_SWAP" == no ]] && return 0
        [[ "$ZRAM_SIZE_SPEC" =~ ^([1-9][0-9]{0,2})%$ ||
           "$ZRAM_SIZE_SPEC" =~ ^[1-9][0-9]*([.][0-9]+)?[GM]$ ]] || {
                warn "Invalid ZRAM size '$ZRAM_SIZE_SPEC'; using 200%."
                ZRAM_SIZE_SPEC=200%
        }
}

configure_zram_menu() {
        local choice="" custom="" status=0
        while true; do
                themed_menu choice \
                        "ZRAM swap" \
                        "ZRAM is optional compressed swap in RAM. Current: $ZRAM_SWAP  Size: $ZRAM_SIZE_SPEC" \
                        19 76 10 \
                        1 "Enable ZRAM" \
                        2 "Disable ZRAM" \
                        3 "Size: 50% of RAM" \
                        4 "Size: 100% of RAM" \
                        5 "Size: 150% of RAM" \
                        6 "Size: 200% of RAM" \
                        7 "Custom size (for example 8G or 4096M)" \
                        8 "Return to Storage setup"
                [[ -n "$choice" ]] || return 0
                case "$choice" in
                        1) ZRAM_SWAP=yes ;;
                        2) ZRAM_SWAP=no ;;
                        3) ZRAM_SWAP=yes; ZRAM_SIZE_SPEC=50% ;;
                        4) ZRAM_SWAP=yes; ZRAM_SIZE_SPEC=100% ;;
                        5) ZRAM_SWAP=yes; ZRAM_SIZE_SPEC=150% ;;
                        6) ZRAM_SWAP=yes; ZRAM_SIZE_SPEC=200% ;;
                        7)
                                custom=""
                                set +e
                                themed_inputbox custom "ZRAM custom size" \
                                        "Enter a fixed ZRAM size such as 8G or 4096M." \
                                        "$ZRAM_SIZE_SPEC"
                                status=$?
                                set -e
                                ((status == 0)) || continue
                                custom="${custom^^}"
                                custom="${custom//[[:space:]]/}"
                                if [[ "$custom" =~ ^[1-9][0-9]*([.][0-9]+)?[GM]$ ]]; then
                                        ZRAM_SWAP=yes
                                        ZRAM_SIZE_SPEC="$custom"
                                else
                                        dialog_message "ZRAM size" "Invalid size '$custom'. Use values such as 8G or 4096M."
                                fi
                                ;;
                        8) return 0 ;;
                esac
        done
}

configure_archive() {
        local installer_dir="" project_dir="" archive_dir=""
        local default_archive="" selected="" action_status=0

        installer_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [[ "$(basename "$installer_dir")" == scripts ]]; then
                project_dir="$(cd "$installer_dir/.." && pwd)"
        elif [[ -d "$installer_dir/archives/base" ]]; then
                project_dir="$installer_dir"
        elif [[ -n "${HOME:-}" && -d "$HOME/BFSOS/archives/base" ]]; then
                project_dir="$HOME/BFSOS"
        else
                project_dir="$PROJECT_DIR"
        fi
        archive_dir="$project_dir/archives/base"

        if [[ -n "$ARCHIVE" ]] && supported_base_archive "$ARCHIVE"; then
                default_archive="$ARCHIVE"
        else
                default_archive="$(newest_base_archive "$archive_dir" 2>/dev/null || true)"
        fi

        while true; do
                selected=""
                if [[ -n "$default_archive" ]]; then
                        set +e
                        confirm_detected_archive "$default_archive"
                        action_status=$?
                        set -e
                        case "$action_status" in
                                0) selected="$default_archive" ;;
                                1) browse_base_archive selected "$archive_dir" || return 0 ;;
                                2) return 0 ;;
                        esac
                else
                        dialog_message "Base rootfs archive" \
                                "No usable BFSOS base archive was found in:\n$archive_dir\n\nBrowse to the archive you want to install."
                        browse_base_archive selected "$archive_dir" || return 0
                fi

                if ! supported_base_archive "$selected"; then
                        dialog_message "Invalid base archive" \
                                "The selected file is missing, unreadable, or unsupported:\n\n$selected\n\nSupported formats: .tar.xz, .tar.zst, .tar.gz"
                        default_archive=""
                        continue
                fi
                ARCHIVE="$selected"
                break
        done

        ask_yes_no SAVE_BASE_ARCHIVE \
                "Save a copy of the BFS base archive on the installed system?" \
                "$SAVE_BASE_ARCHIVE"
        ARCHIVE_CONFIGURED=yes
}

detect_console_video_argument() {
        local status_file="" connector=""
        CONSOLE_VIDEO_ARG=""
        [[ -n "$CONSOLE_VIDEO_MODE" ]] || return 0
        for status_file in /sys/class/drm/card*-*/status; do
                [[ -r "$status_file" ]] || continue
                [[ "$(cat "$status_file" 2>/dev/null)" == connected ]] || continue
                connector="$(basename "${status_file%/status}")"
                connector="${connector#card*-}"
                [[ -n "$connector" ]] || continue

                # Do not force a mode the display does not advertise.  The
                # tested high-DPI default is 1920x1080@60, but lower-resolution
                # panels should simply keep their native/default console mode.
                if [[ -r "${status_file%/status}/modes" ]] &&
                   ! grep -qx "${CONSOLE_VIDEO_MODE%@*}" "${status_file%/status}/modes" 2>/dev/null; then
                        log "Connected DRM output $connector does not advertise ${CONSOLE_VIDEO_MODE%@*}; leaving console video mode unchanged"
                        continue
                fi

                CONSOLE_VIDEO_ARG="video=${connector}:${CONSOLE_VIDEO_MODE}"
                log "Detected connected DRM console output: $connector; default text-console mode: $CONSOLE_VIDEO_MODE"
                return 0
        done
        log "No suitable connected DRM connector was detected for $CONSOLE_VIDEO_MODE; leaving console video mode unchanged"
}

configure_system() {
        ask_default HOSTNAME "Hostname" "$HOSTNAME" || return 0
        ask_default TIMEZONE "Timezone" "$TIMEZONE" || return 0
        ask_default LOCALE "Locale, for example en_US.UTF-8" "$LOCALE" || return 0

        SYSTEM_CONFIGURED=yes
}

valid_username() {
        [[ "$1" =~ ^[a-z_][a-z0-9_-]*$ ]]
}

username_selected() {
        local wanted="$1"
        local existing=""

        [[ "$USERNAME" == "$wanted" ]] && return 0

        for existing in "${ADDITIONAL_USERS[@]}"; do
                [[ "$existing" == "$wanted" ]] && return 0
        done

        return 1
}

configure_users() {
        local add_more=no
        local extra_user=""

        while true; do
                if ! ask_default USERNAME \
                        "Primary regular username" \
                        "${USERNAME:-user}"; then
                        return 0
                fi
                valid_username "$USERNAME" && break
                warn "Invalid username."
                sleep 1
        done

        ADDITIONAL_USERS=()

        while true; do
                add_more=no
                if ! ask_yes_no add_more "Add another regular user?" no; then
                        return 0
                fi
                [[ "$add_more" == yes ]] || break

                while true; do
                        extra_user=""
                        if ! ask_default extra_user "Additional username" user2; then
                                return 0
                        fi

                        if ! valid_username "$extra_user"; then
                                warn "Invalid username."
                                sleep 1
                                continue
                        fi

                        if username_selected "$extra_user"; then
                                warn "That username is already selected."
                                sleep 1
                                continue
                        fi

                        ADDITIONAL_USERS+=("$extra_user")
                        break
                done
        done

        USERS_CONFIGURED=yes
}

configure_kernel() {
        local choice=""

        themed_menu choice \
                "Kernel selection" \
                "Choose the kernel package for the installed system." \
                16 72 7 \
                1 "linux (current BFSOS kernel)" \
                2 "linux-lts (6.12 LTS, Debian patches, broad x86_64 support included)" \
                3 "Do not install a kernel"

        [[ -n "$choice" ]] || return 0

        case "$choice" in
                1) KERNEL_PACKAGE=linux ;;
                2) KERNEL_PACKAGE=linux-lts ;;
                3) KERNEL_PACKAGE=none ;;
                *) return 0 ;;
        esac

        KERNEL_CONFIGURED=yes
}

configure_networking() {
        select_network_interface || return 0
        ask_yes_no INSTALL_NETWORKMANAGER \
                "Use NetworkManager instead of systemd-networkd?" \
                "$INSTALL_NETWORKMANAGER" || return 0
        ask_yes_no ENABLE_OPENSSH \
                "Do you want to enable OpenSSH on boot?" \
                "$ENABLE_OPENSSH" || return 0

        NETWORK_CONFIGURED=yes
}

toggle_setting() {
        local variable="$1"

        if [[ "${!variable}" == yes ]]; then
                printf -v "$variable" '%s' no
        else
                printf -v "$variable" '%s' yes
        fi
}

selection_mark() {
        [[ "$1" == yes ]] && printf '[x]' || printf '[ ]'
}

configure_packages() {
        local choice=""
        local status=0

        while true; do
                if command -v dialog >/dev/null 2>&1 &&
                   [[ -r /dev/tty && -w /dev/tty ]]; then
                        if choice="$(
                                dialog --stdout --clear \
                                        --backtitle "BFS Linux Installer" \
                                        --title "Optional software" \
                                        --cancel-label "Back" \
                                        --checklist \
                                        "Select optional software packages.\n\nStorage utilities such as cryptsetup, lvm2, and mdadm are installed automatically when the selected storage layout requires them." \
                                        20 88 8 \
                                        git "Git version-control system" "$([[ "$INSTALL_GIT" == yes ]] && echo on || echo off)" \
                                        wget "Wget download utility" "$([[ "$INSTALL_WGET" == yes ]] && echo on || echo off)" \
                                        wpa_supplicant "WPA/WPA2 wireless supplicant" "$([[ "$INSTALL_WPA_SUPPLICANT" == yes ]] && echo on || echo off)" \
                                        wireless_tools "Legacy iwconfig/iwlist wireless utilities" "$([[ "$INSTALL_WIRELESS_TOOLS" == yes ]] && echo on || echo off)" \
                                        gpm "Console mouse support" "$([[ "$INSTALL_GPM" == yes ]] && echo on || echo off)" \
                                        </dev/tty
                        )"; then
                                status=0
                        else
                                status=$?
                        fi
                        ((status == 0)) || return 0

                        INSTALL_GIT=no
                        INSTALL_WGET=no
                        INSTALL_WPA_SUPPLICANT=no
                        INSTALL_WIRELESS_TOOLS=no
                        INSTALL_GPM=no

                        [[ " $choice " == *' "git" '* || " $choice " == *' git '* ]] &&
                                INSTALL_GIT=yes
                        [[ " $choice " == *' "wget" '* || " $choice " == *' wget '* ]] &&
                                INSTALL_WGET=yes
                        [[ " $choice " == *' "wpa_supplicant" '* || " $choice " == *' wpa_supplicant '* ]] &&
                                INSTALL_WPA_SUPPLICANT=yes
                        [[ " $choice " == *' "wireless_tools" '* || " $choice " == *' wireless_tools '* ]] &&
                                INSTALL_WIRELESS_TOOLS=yes
                        [[ " $choice " == *' "gpm" '* || " $choice " == *' gpm '* ]] &&
                                INSTALL_GPM=yes

                        PACKAGES_CONFIGURED=yes
                        return 0
                fi

                clear_screen
                cat <<EOF_PACKAGES
Optional software
=================

Storage utilities (cryptsetup, lvm2, mdadm) are installed automatically
when the selected storage layout requires them.

  1) $(selection_mark "$INSTALL_GIT") git
  2) $(selection_mark "$INSTALL_WGET") wget
  3) $(selection_mark "$INSTALL_WPA_SUPPLICANT") wpa_supplicant
  4) $(selection_mark "$INSTALL_WIRELESS_TOOLS") wireless_tools
  5) $(selection_mark "$INSTALL_GPM") gpm
  6) Done

EOF_PACKAGES
                read -r -p "Choose [1-6]: " choice

                case "$choice" in
                        1) toggle_setting INSTALL_GIT ;;
                        2) toggle_setting INSTALL_WGET ;;
                        3) toggle_setting INSTALL_WPA_SUPPLICANT ;;
                        4) toggle_setting INSTALL_WIRELESS_TOOLS ;;
                        5) toggle_setting INSTALL_GPM ;;
                        6) PACKAGES_CONFIGURED=yes; return 0 ;;
                        *) warn "Choose a number from 1 through 6."; sleep 1 ;;
                esac
        done
}

configure_sudo() {
        local choice=""

        themed_menu choice \
                "Sudo configuration" \
                "Choose how sudo should be configured for wheel-group users." \
                17 78 8 \
                1 "Do not install sudo" \
                2 "Install sudo; require the user's password" \
                3 "Install sudo; allow wheel users without a password"

        [[ -n "$choice" ]] || return 0

        case "$choice" in
                1)
                        INSTALL_SUDO=no
                        SUDO_MODE=disabled
                        ;;
                2)
                        INSTALL_SUDO=yes
                        SUDO_MODE=password
                        ;;
                3)
                        INSTALL_SUDO=yes
                        SUDO_MODE=nopasswd
                        ;;
                *) return 0 ;;
        esac

        SUDO_CONFIGURED=yes
}

configure_bootloader() {
        if [[ -n "$EFI_DEV" || -d /sys/firmware/efi ]]; then
                BOOT_MODE=uefi
        else
                BOOT_MODE=bios
        fi

        ask_yes_no INSTALL_GRUB \
                "Detected boot mode: $BOOT_MODE\n\nWrite and configure the GRUB bootloader?" \
                "$INSTALL_GRUB" || return 0

        if [[ "$INSTALL_GRUB" == yes && "$BOOT_MODE" == bios ]]; then
                ask_default BOOT_DISK \
                        "Whole disk for BIOS GRUB, for example /dev/sda" \
                        "$BOOT_DISK" || return 0
        fi

        if [[ "$INSTALL_GRUB" == yes && "$BOOT_MODE" == uefi ]]; then
                ask_yes_no GRUB_FALLBACK \
                        "Also install the EFI fallback loader?\n\nThis is recommended for some MSI and other firmware implementations." \
                        "$GRUB_FALLBACK" || return 0
        fi

        BOOTLOADER_CONFIGURED=yes
}

additional_users_text() {
        local user_name=""
        local separator=""

        for user_name in "${ADDITIONAL_USERS[@]}"; do
                printf '%s%s' "$separator" "$user_name"
                separator=" "
        done
}

show_additional_users_review() {
        local user_name=""

        if ((${#ADDITIONAL_USERS[@]} == 0)); then
                printf 'Additional users:     none\n'
                return 0
        fi

        printf 'Additional users:\n'
        for user_name in "${ADDITIONAL_USERS[@]}"; do
                printf '  - %s\n' "$user_name"
        done
}

show_btrfs_review() {
        local index=0
        local found=no
        local device="" mountpoint="" format=""
        local name="" data_subvol="" snapshot_subvol="" snapshot_mountpoint=""

        printf 'Btrfs snapshots:\n'

        for ((index=0; index<5+${#EXTRA_DEVICES[@]}; index++)); do
                case "$index" in
                        0) device="$ROOT_DEV"; mountpoint=/; format="$ROOT_FORMAT" ;;
                        1) device="$BOOT_DEV"; mountpoint=/boot; format="$BOOT_FORMAT" ;;
                        2) device="$EFI_DEV"; mountpoint=/boot/efi; format="$EFI_FORMAT" ;;
                        3) device="$HOME_DEV"; mountpoint=/home; format="$HOME_FORMAT" ;;
                        4) continue ;;
                        *)
                                device="${EXTRA_DEVICES[$((index - 5))]}"
                                mountpoint="${EXTRA_MOUNTPOINTS[$((index - 5))]}"
                                format="${EXTRA_FORMATS[$((index - 5))]}"
                                ;;
                esac

                [[ -n "$device" ]] || continue
                [[ "$format" == btrfs ]] || continue
                found=yes

                name="$(sanitize_btrfs_name "$mountpoint")"
                case "$mountpoint" in
                        /)
                                data_subvol=@
                                snapshot_subvol=@snapshots
                                snapshot_mountpoint=/.snapshots
                                ;;
                        /home)
                                data_subvol=@home
                                snapshot_subvol=@home-snapshots
                                snapshot_mountpoint=/home/.snapshots
                                ;;
                        *)
                                data_subvol="@$name"
                                snapshot_subvol="@$name-snapshots"
                                snapshot_mountpoint="$mountpoint/.snapshots"
                                ;;
                esac

                printf '  %-16s %-24s data=%-18s snapshots=%s mounted at %s\n' \
                        "$mountpoint" "$device" "$data_subvol" \
                        "$snapshot_subvol" "$snapshot_mountpoint"
        done

        [[ "$found" == yes ]] || printf '  none (no filesystem is set to format as Btrfs)\n'
}

menu_status() {
        case "$1" in
                yes) printf configured ;;
                optional) printf optional ;;
                default) printf default ;;
                *) printf pending ;;
        esac
}

show_main_menu() {
        clear_screen

        cat <<EOF_MENU
============================================================
                  BFS Linux Installer
============================================================

Configure each section, then select Install BFS.
The installer authenticates once and all installation actions run as root.

  1) Storage assignment         [$(menu_status "$DISKS_CONFIGURED")]
  2) Base archive               [$(menu_status "$ARCHIVE_CONFIGURED")]
  3) System settings            [$(menu_status "$SYSTEM_CONFIGURED")]
  4) User accounts              [$(menu_status "$USERS_CONFIGURED")]
  5) Kernel selection           [$(menu_status "$KERNEL_CONFIGURED")]
  6) Networking                 [$(menu_status "$NETWORK_CONFIGURED")]
  7) Optional software          [$(menu_status "$PACKAGES_CONFIGURED")]
  8) Sudo configuration         [$(menu_status "$SUDO_CONFIGURED")]
  9) Bootloader                 [$(menu_status "$BOOTLOADER_CONFIGURED")]
 10) Review selections          [AVAILABLE]
 11) Install BFS                 [$(available_status installer_ready)]
 12) Chroot into target          [$(available_status target_chroot_available)]
 13) Quit                        [EXIT]

EOF_MENU
}

target_mount_tree_complete() {
        local index="" mp="" expected=""
        mountpoint -q "$TARGET" || return 1

        # Every configured Btrfs role must be mounted at its real subvolume,
        # never merely at top-level ID 5.
        for ((index=0; index<${#BTRFS_MOUNTPOINTS[@]}; index++)); do
                mp="${BTRFS_MOUNTPOINTS[$index]}"
                [[ "$mp" == / ]] && expected="$TARGET" || expected="$TARGET$mp"
                mountpoint -q "$expected" || return 1
                findmnt -rn -o OPTIONS --target "$expected" 2>/dev/null |
                        tr ',' '\n' | grep -qx "subvol=/${BTRFS_SUBVOLUMES[$index]}" ||
                findmnt -rn -o OPTIONS --target "$expected" 2>/dev/null |
                        tr ',' '\n' | grep -qx "subvol=${BTRFS_SUBVOLUMES[$index]}" || return 1
        done

        [[ -z "$BOOT_DEV" ]] || mountpoint -q "$TARGET/boot" || return 1
        if [[ "$BOOT_MODE" == uefi && -n "$EFI_DEV" ]]; then
                mountpoint -q "$TARGET/boot/efi" || return 1
        fi
        return 0
}

chroot_into_target() {
        force_posix_locale
        clear_screen
        echo "Chroot into BFS target"
        echo "======================"
        echo

        [[ -n "$ROOT_DEV" ]] ||
                die "Configure the root filesystem first."

        # A mounted Btrfs top-level is not enough: separate /usr, /opt,
        # /home, /var and snapshot subvolumes must be mounted exactly as the
        # installer recorded them.  If the shell is hidden by an incomplete or
        # top-level mount, reconstruct the complete canonical target tree.
        if ! target_mount_tree_complete ||
           [[ ! -x "$TARGET/bin/bash" && ! -x "$TARGET/usr/bin/bash" ]]; then
                if findmnt -Rrn "$TARGET" 2>/dev/null | grep -q .; then
                        umount -R "$TARGET" 2>/dev/null || umount -Rl "$TARGET" 2>/dev/null || true
                        MOUNTED_BY_SCRIPT=()
                fi
                mount_target_filesystems
        fi

        [[ -x "$TARGET/bin/bash" || -x "$TARGET/usr/bin/bash" ]] || {
                dialog_message "Chroot unavailable"                         "The target is mounted, but no usable Bash exists at /bin/bash or /usr/bin/bash.

For Btrfs layouts this usually means a required subvolume was not mounted. The installer attempted to reconstruct the complete target mount tree and still could not verify the shell."
                return 1
        }

        mount_virtual_filesystems

        if [[ -e /etc/resolv.conf ]]; then
                rm -f "$TARGET/etc/resolv.conf"
                cp -L /etc/resolv.conf "$TARGET/etc/resolv.conf"
        fi

        KEEP_MOUNTS=yes

        echo "Entering $TARGET. Type exit to return to the installer."
        echo

        run_on_tty \
                chroot "$TARGET" /usr/bin/env -i \
                HOME=/root \
                TERM="${TERM:-linux}" \
                PATH=/usr/bin:/usr/sbin:/bin:/sbin \
                LANG=C \
                LC_ALL=C \
                /bin/bash --login

        KEEP_MOUNTS=no
        unmount_virtual_filesystems
        # Return directly to the installer menu; no redundant terminal pause.
        return 0
}

installer_menu() {
        local choice="" status=0 error_file=""

        while true; do
                SELECTED_MENU_CHOICE=""

                if command -v dialog >/dev/null 2>&1 &&
                   [[ -r /dev/tty && -w /dev/tty ]]; then
                        error_file="$(mktemp /tmp/bfs-installer-dialog-error.XXXXXX)"

                        if SELECTED_MENU_CHOICE="$(
                                dialog --stdout --clear \
                                        --backtitle "BFS Linux Installer" \
                                        --title "BFS Linux Installer" \
                                        --ok-label "Select" \
                                        --cancel-label "Quit" \
                                        --extra-button \
                                        --extra-label "Settings" \
                                        --menu \
                                        "Use Up/Down arrows and Enter, or type an option number.\n\nThe installer authenticates once with sudo and all installation actions run as root.\n\nUse Tab or Shift+Tab to move between Select, Quit, and Settings." \
                                        26 92 15 \
                                        1 "$(
                                                dialog_menu_description \
                                                        'Storage assignment' \
                                                        "$(dialog_status "$DISKS_CONFIGURED")"
                                        )" \
                                        2 "$(
                                                dialog_menu_description \
                                                        'Base archive' \
                                                        "$(dialog_status "$ARCHIVE_CONFIGURED")"
                                        )" \
                                        3 "$(
                                                dialog_menu_description \
                                                        'System settings' \
                                                        "$(dialog_status "$SYSTEM_CONFIGURED")"
                                        )" \
                                        4 "$(
                                                dialog_menu_description \
                                                        'User accounts' \
                                                        "$(dialog_status "$USERS_CONFIGURED")"
                                        )" \
                                        5 "$(
                                                dialog_menu_description \
                                                        'Kernel selection' \
                                                        "$(dialog_status "$KERNEL_CONFIGURED")"
                                        )" \
                                        6 "$(
                                                dialog_menu_description \
                                                        'Networking' \
                                                        "$(dialog_status "$NETWORK_CONFIGURED")"
                                        )" \
                                        7 "$(
                                                dialog_menu_description \
                                                        'Optional software' \
                                                        "$(dialog_status "$PACKAGES_CONFIGURED")"
                                        )" \
                                        8 "$(
                                                dialog_menu_description \
                                                        'Sudo configuration' \
                                                        "$(dialog_status "$SUDO_CONFIGURED")"
                                        )" \
                                        9 "$(
                                                dialog_menu_description \
                                                        'Bootloader' \
                                                        "$(dialog_status "$BOOTLOADER_CONFIGURED")"
                                        )" \
                                        10 "$(
                                                dialog_menu_description \
                                                        'Review selections' \
                                                        'AVAILABLE'
                                        )" \
                                        11 "$(
                                                dialog_menu_description \
                                                        'Install BFS (root)' \
                                                        "$(available_status installer_ready)"
                                        )" \
                                        12 "$(
                                                dialog_menu_description \
                                                        'Chroot into target (root)' \
                                                        "$(available_status target_chroot_available)"
                                        )" \
                                        13 "$(
                                                dialog_menu_description \
                                                        'Quit' \
                                                        'EXIT'
                                        )" \
                                        </dev/tty 2>"$error_file"
                        )"; then
                                status=0
                        else
                                status=$?
                        fi

                        case "$status" in
                                0)
                                        choice="$SELECTED_MENU_CHOICE"
                                        ;;
                                1|255)
                                        choice=13
                                        ;;
                                3)
                                        choice=settings
                                        ;;
                                *)
                                        warn "Dialog failed; switching to the text menu."
                                        [[ ! -s "$error_file" ]] || cat "$error_file" >&2
                                        choice=""
                                        ;;
                        esac

                        rm -f "$error_file"
                fi

                if [[ -z "$choice" ]]; then
                        show_main_menu
                        read -r -p "Choose [1-14; 14=Settings]: " choice
                        [[ "$choice" == 14 ]] && choice=settings
                fi

                choice="$(
                        printf '%s' "$choice" |
                                tr -d '\r\n' |
                                sed -e 's/^[[:space:]]*//' \
                                    -e 's/[[:space:]]*$//' \
                                    -e 's/^"//' \
                                    -e 's/"$//'
                )"

                case "$choice" in
                        1)  storage_menu ;;
                        2)  configure_archive ;;
                        3)  configure_system ;;
                        4)  configure_users ;;
                        5)  configure_kernel ;;
                        6)  configure_networking ;;
                        7)  configure_packages ;;
                        8)  configure_sudo ;;
                        9)  configure_bootloader ;;
                        10)
                                show_summary
                                if installer_ready; then
                                        while true; do
                                                if confirm_continue "Begin the BFS installation?"; then
                                                        INSTALL_CONFIRMED=yes
                                                        return 0
                                                fi
                                                # Back from Ready to install returns directly to Review.
                                                show_summary
                                        done
                                fi
                                ;;
                        11)
                                if installer_ready; then
                                        INSTALL_CONFIRMED=no
                                        return 0
                                fi

                                warn "Complete every configuration section before installing BFS."
                                pause_screen
                                ;;
                        12) chroot_into_target ;;
                        13)
                                echo "Installer exited."
                                exit 0
                                ;;
                        settings)
                                installer_settings_menu
                                ;;
                        *)
                                warn "Choose a valid installer option."
                                sleep 1
                                ;;
                esac

                choice=""
        done
}

validate_format_command() {
        local format="$1" command=""
        case "$format" in
                keep) return 0 ;;
                ext2) command=mkfs.ext2 ;;
                ext4) command=mkfs.ext4 ;;
                xfs) command=mkfs.xfs ;;
                btrfs) command=mkfs.btrfs ;;
                f2fs) command=mkfs.f2fs ;;
                vfat) command=mkfs.fat ;;
                swap) command=mkswap ;;
                *) die "Unknown format selection: $format" ;;
        esac
        command -v "$command" >/dev/null 2>&1 || die "Required formatting command is missing: $command"
}


selected_target_devices() {
        local device=""
        local index=""

        for device in \
                "$ROOT_DEV" \
                "$BOOT_DEV" \
                "$EFI_DEV" \
                "$SWAP_DEV" \
                "$HOME_DEV"
        do
                [[ -n "$device" ]] && printf '%s\n' "$device"
        done

        for ((index=0; index<${#EXTRA_DEVICES[@]}; index++)); do
                [[ -n "${EXTRA_DEVICES[$index]}" ]] &&
                        printf '%s\n' "${EXTRA_DEVICES[$index]}"
        done
}

device_ancestry_has_type() {
        local device="$1"
        local wanted="$2"
        local type=""

        [[ -b "$device" ]] || return 1

        while IFS= read -r type; do
                case "$wanted" in
                        raid)
                                [[ "$type" == raid* ]] && return 0
                                ;;
                        *)
                                [[ "$type" == "$wanted" ]] && return 0
                                ;;
                esac
        done < <(
                lsblk -s -nro TYPE "$device" 2>/dev/null || true
        )

        return 1
}

detect_storage_requirements() {
        local device=""

        AUTO_CRYPTSETUP=no
        AUTO_LVM2=no
        AUTO_MDADM=no

        # These are derived from the final devices selected for /, /home, swap,
        # and other mountpoints. Merely visiting the LUKS/LVM/RAID menus does
        # not force packages into the installed system.
        while IFS= read -r device; do
                [[ -n "$device" ]] || continue

                if device_ancestry_has_type "$device" crypt; then
                        AUTO_CRYPTSETUP=yes
                fi

                if device_ancestry_has_type "$device" lvm; then
                        AUTO_LVM2=yes
                fi

                if device_ancestry_has_type "$device" raid; then
                        AUTO_MDADM=yes
                fi
        done < <(selected_target_devices)

        # cryptsetup is never a manual optional-package choice. Keep the legacy
        # variable synchronized for the chroot template/review code.
        INSTALL_CRYPTSETUP="$AUTO_CRYPTSETUP"
}

crypt_mapping_records() {
        local selected_device="" path="" type="" mapping_name="" parent_device="" luks_uuid="" record=""
        local status_output="" line=""
        local -a seen=()

        while IFS= read -r selected_device; do
                [[ -n "$selected_device" ]] || continue
                while read -r path type; do
                        [[ "$type" == crypt ]] || continue
                        mapping_name="$(basename "$path")"
                        status_output="$(cryptsetup status "$mapping_name" 2>/dev/null || true)"
                        parent_device="$(printf '%s\n' "$status_output" | sed -n 's/^[[:space:]]*device:[[:space:]]*//p' | head -n1)"
                        [[ -b "$parent_device" ]] || continue
                        luks_uuid="$(cryptsetup luksUUID "$parent_device" 2>/dev/null || blkid -s UUID -o value "$parent_device" 2>/dev/null || true)"
                        [[ -n "$luks_uuid" ]] || continue
                        record="$mapping_name|$parent_device|$luks_uuid"
                        if ((${#seen[@]})) && printf '%s\n' "${seen[@]}" | grep -qxF "$record"; then continue; fi
                        seen+=("$record")
                        printf '%s\n' "$record"
                done < <(lsblk -s -prno PATH,TYPE "$selected_device" 2>/dev/null || true)
        done < <(selected_target_devices)
}

generate_crypttab() {
        local crypttab="$TARGET/etc/crypttab"
        local record=""
        local mapping_name=""
        local parent_device=""
        local luks_uuid=""
        local generated=0

        detect_storage_requirements

        if [[ "$AUTO_CRYPTSETUP" != yes ]]; then
                rm -f "$crypttab"
                return 0
        fi

        log "Generating /etc/crypttab"

        mkdir -p "$TARGET/etc"
        : > "$crypttab"

        while IFS='|' read -r mapping_name parent_device luks_uuid; do
                [[ -n "$mapping_name" && -n "$luks_uuid" ]] || continue

                printf '# %s\n' "$parent_device" >> "$crypttab"
                printf '%-24s UUID=%-36s none luks\n\n' \
                        "$mapping_name" "$luks_uuid" >> "$crypttab"
                generated=$((generated + 1))
        done < <(crypt_mapping_records)

        ((generated > 0)) ||
                die "Encrypted storage was detected, but no crypttab entries could be generated."

        chmod 0600 "$crypttab"
}

validate_settings() {
        detect_storage_requirements
        validate_zram_settings
        [[ "$DISKS_CONFIGURED" == yes ]] || die "Disk and filesystem setup is incomplete."
        [[ "$ARCHIVE_CONFIGURED" == yes ]] || die "Base archive selection is incomplete."
        [[ "$SYSTEM_CONFIGURED" == yes ]] || die "System settings are incomplete."
        [[ "$USERS_CONFIGURED" == yes ]] || die "User account setup is incomplete."
        [[ "$KERNEL_CONFIGURED" == yes ]] || die "Kernel selection is incomplete."
        [[ "$NETWORK_CONFIGURED" == yes ]] || die "Networking setup is incomplete."
        [[ "$BOOTLOADER_CONFIGURED" == yes ]] || die "Bootloader setup is incomplete."
        [[ -b "$ROOT_DEV" ]] || die "Root device does not exist: $ROOT_DEV"
        [[ -f "$ARCHIVE" ]] || die "Rootfs archive does not exist: $ARCHIVE"
        [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid username: $USERNAME"
        [[ -d "/sys/class/net/$NETWORK_IFACE" ]] ||
                die "Network interface does not exist: $NETWORK_IFACE"
        [[ "$NETWORK_MAC" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] ||
                die "Invalid MAC address for $NETWORK_IFACE: $NETWORK_MAC"
        [[ "$NETWORK_TARGET_NAME" =~ ^[a-zA-Z0-9_.-]+$ ]] ||
                die "Invalid target network-interface name: $NETWORK_TARGET_NAME"
        local device index mountpoint
        for device in "$BOOT_DEV" "$EFI_DEV" "$SWAP_DEV" "$HOME_DEV"; do
                [[ -z "$device" || -b "$device" ]] || die "Device does not exist: $device"
        done
        for ((index=0; index<${#EXTRA_DEVICES[@]}; index++)); do
                device="${EXTRA_DEVICES[$index]}"; mountpoint="${EXTRA_MOUNTPOINTS[$index]}"
                [[ -b "$device" ]] || die "Additional partition does not exist: $device"
                [[ "$mountpoint" == /* && "$mountpoint" != *'..'* ]] || die "Invalid additional mount point: $mountpoint"
                validate_format_command "${EXTRA_FORMATS[$index]}"
        done
        validate_format_command "$ROOT_FORMAT"
        validate_format_command "$BOOT_FORMAT"
        validate_format_command "$EFI_FORMAT"
        validate_format_command "$SWAP_FORMAT"
        validate_format_command "$HOME_FORMAT"
        [[ "$BOOT_MODE" == uefi || "$BOOT_MODE" == bios ]] || die "Boot mode must be uefi or bios."
        if [[ "$INSTALL_GRUB" == yes ]]; then
                [[ "$BOOT_MODE" != uefi || -n "$EFI_DEV" ]] || die "UEFI GRUB requires an EFI partition."
                [[ "$BOOT_MODE" != bios || -b "$BOOT_DISK" ]] || die "BIOS GRUB requires a whole-disk target."
        fi
}

mdraid_review_text() {
        local array="" device="" detail="" level="" size="" state="" members="" member=""
        local found=no

        if [[ ! -r /proc/mdstat ]]; then
                printf 'none\n'
                return 0
        fi

        while read -r array; do
                [[ -n "$array" ]] || continue
                found=yes
                device="/dev/$array"
                detail="$(mdadm --detail "$device" 2>/dev/null || true)"
                level="$(printf '%s\n' "$detail" | awk -F: '/Raid Level/ {gsub(/^[[:space:]]+/,"",$2); print $2; exit}')"
                size="$(printf '%s\n' "$detail" | awk -F: '/Array Size/ {gsub(/^[[:space:]]+/,"",$2); print $2; exit}')"
                state="$(printf '%s\n' "$detail" | awk -F: '/^[[:space:]]*State/ {gsub(/^[[:space:]]+/,"",$2); print $2; exit}')"
                members=""
                while IFS= read -r member; do
                        [[ -n "$member" ]] || continue
                        members+="${members:+ }$member"
                done < <(printf '%s\n' "$detail" | awk '$NF ~ /^\/dev\// {print $NF}')

                printf 'Array:    %s\n' "$device"
                printf 'Level:    %s\n' "${level:-unknown}"
                printf 'Size:     %s\n' "${size:-unknown}"
                printf 'State:    %s\n' "${state:-unknown}"
                printf 'Members:  %s\n\n' "${members:-unknown}"
        done < <(awk '$2 == ":" && $4 ~ /^raid/ {print $1}' /proc/mdstat)

        [[ "$found" == yes ]] || printf 'none\n'
}

show_additional_partitions() {
        local index
        if ((${#EXTRA_DEVICES[@]} == 0)); then
                printf 'Additional mounts:   none\n'
                return
        fi
        printf 'Additional mounts:\n'
        for ((index=0; index<${#EXTRA_DEVICES[@]}; index++)); do
                printf '  %-18s %-24s format: %s\n' "${EXTRA_MOUNTPOINTS[$index]}" "${EXTRA_DEVICES[$index]}" "${EXTRA_FORMATS[$index]}"
        done
}

show_summary() {
        local summary_file=""
        local formatting_requested=no
        local format=""
        local index=0
        local selected_count=0
        local format_count=0
        local preserve_count=0
        local additional_user_count=0
        local warning_count=0

        detect_storage_requirements
        CRYPT_TARGETS="$(crypt_mapping_records | awk -F'|' '{printf "%s%s -> %s", (NR>1 ? ", " : ""), $2, $1}')"

        selected_count=1
        [[ -n "$BOOT_DEV" ]] && selected_count=$((selected_count + 1))
        [[ -n "$EFI_DEV" ]] && selected_count=$((selected_count + 1))
        [[ -n "$SWAP_DEV" ]] && selected_count=$((selected_count + 1))
        [[ -n "$HOME_DEV" ]] && selected_count=$((selected_count + 1))
        selected_count=$((selected_count + ${#EXTRA_DEVICES[@]}))

        for format in \
                "$ROOT_FORMAT" \
                "$BOOT_FORMAT" \
                "$EFI_FORMAT" \
                "$SWAP_FORMAT" \
                "$HOME_FORMAT" \
                "${EXTRA_FORMATS[@]}"; do
                [[ -n "$format" ]] || continue
                if [[ "$format" == keep ]]; then
                        preserve_count=$((preserve_count + 1))
                else
                        formatting_requested=yes
                        format_count=$((format_count + 1))
                fi
        done

        additional_user_count=${#ADDITIONAL_USERS[@]}

        summary_file="$(mktemp /tmp/bfs-install-summary.XXXXXX)"

        {
                cat <<'SUMMARY_HEADER'
BFS Installation Review
=======================

Filesystem Layout
-----------------
Mount Point      Device                          Action
-----------      ------------------------------  ------------
SUMMARY_HEADER

                printf '%-16s %-30s %s\n' \
                        "/" "$ROOT_DEV" "$ROOT_FORMAT"

                [[ -z "$BOOT_DEV" ]] || \
                        printf '%-16s %-30s %s\n' \
                                "/boot" "$BOOT_DEV" "$BOOT_FORMAT"

                [[ -z "$EFI_DEV" ]] || \
                        printf '%-16s %-30s %s\n' \
                                "/boot/efi" "$EFI_DEV" "$EFI_FORMAT"

                [[ -z "$HOME_DEV" ]] || \
                        printf '%-16s %-30s %s\n' \
                                "/home" "$HOME_DEV" "$HOME_FORMAT"

                for ((index=0; index<${#EXTRA_DEVICES[@]}; index++)); do
                        printf '%-16s %-30s %s\n' \
                                "${EXTRA_MOUNTPOINTS[$index]}" \
                                "${EXTRA_DEVICES[$index]}" \
                                "${EXTRA_FORMATS[$index]}"
                done

                [[ -z "$SWAP_DEV" ]] || \
                        printf '%-16s %-30s %s\n' \
                                "swap" "$SWAP_DEV" "$SWAP_FORMAT"

                cat <<SUMMARY

System
------
Hostname:             $HOSTNAME
Timezone:             $TIMEZONE
Locale:               $LOCALE
Target directory:     $TARGET
Base archive:         $ARCHIVE

Users
-----
Primary user:         $USERNAME
SUMMARY

                show_additional_users_review

                cat <<SUMMARY

Networking
----------
Interface:            $NETWORK_IFACE
MAC address:          $NETWORK_MAC
Installed NIC name:   $NETWORK_TARGET_NAME
NetworkManager:       $INSTALL_NETWORKMANAGER
OpenSSH server:       $ENABLE_OPENSSH

Boot Loader
-----------
Boot mode:            $BOOT_MODE
Install GRUB:         $INSTALL_GRUB
GRUB disk:            ${BOOT_DISK:-not applicable}
EFI fallback loader:  $GRUB_FALLBACK

Packages
--------
Kernel package:       $KERNEL_PACKAGE
Git:                  $INSTALL_GIT
Wget:                 $INSTALL_WGET
Sudo:                 $INSTALL_SUDO
Sudo mode:            $SUDO_MODE
Cryptsetup:           $(if [[ "$AUTO_CRYPTSETUP" == yes ]]; then printf '%s' "AUTO (required by LUKS)"; else printf '%s' "not required"; fi)
Save base archive:    $SAVE_BASE_ARCHIVE
Archive save dir:     $BASE_ARCHIVE_DIR

Detected Storage Features
-------------------------
Encrypted targets:    $AUTO_CRYPTSETUP
LVM detected:         $AUTO_LVM2
mdraid detected:      $AUTO_MDADM
ZRAM swap:            $ZRAM_SWAP
ZRAM size:            $(if [[ "$ZRAM_SWAP" == yes ]]; then printf '%s' "$ZRAM_SIZE_SPEC"; else printf '%s' "disabled"; fi)
SUMMARY

                show_btrfs_review

                cat <<SUMMARY

RAID
----
Enabled:             ${AUTO_MDADM:-no}
$(mdraid_review_text)
LUKS Encryption
---------------
Enabled:             ${AUTO_CRYPTSETUP:-no}
Encrypted devices:   ${CRYPT_TARGETS:-none}

LVM
---
Enabled:             ${AUTO_LVM2:-no}
$(lvm_review_text)

Installation Totals
-------------------
Partitions selected:  $selected_count
Will format/init:     $format_count
Will preserve:        $preserve_count
Additional users:     $additional_user_count
Boot type:            $BOOT_MODE
Kernel:               $KERNEL_PACKAGE
RAID:                 ${AUTO_MDADM:-no}
LUKS:                 ${AUTO_CRYPTSETUP:-no}
LVM:                  ${AUTO_LVM2:-no}
ZRAM:                 $ZRAM_SWAP $(if [[ "$ZRAM_SWAP" == yes ]]; then printf '(%s)' "$ZRAM_SIZE_SPEC"; fi)

Warnings
--------
SUMMARY

                if [[ "$formatting_requested" == yes ]]; then
                        echo "- Every partition marked for formatting or initialization will be erased."
                        warning_count=$((warning_count + 1))
                fi

                if [[ "$INSTALL_GRUB" == yes &&
                      "$KERNEL_PACKAGE" == none ]]; then
                        echo "- GRUB will be configured, but BFS will not install a kernel."
                        warning_count=$((warning_count + 1))
                fi

                if [[ "$INSTALL_GRUB" == yes &&
                      "$BOOT_MODE" == uefi &&
                      -z "$EFI_DEV" ]]; then
                        echo "- UEFI boot was selected, but no EFI System Partition is assigned."
                        warning_count=$((warning_count + 1))
                fi

                if ((warning_count == 0)); then
                        echo "None."
                fi
        } > "$summary_file"

        if command -v dialog >/dev/null 2>&1 &&
           [[ -r /dev/tty && -w /dev/tty ]]; then
                dialog --clear \
                        --backtitle "BFS Linux Installer" \
                        --title "Review selections" \
                        --exit-label "Continue" \
                        --textbox "$summary_file" \
                        32 100 \
                        </dev/tty >/dev/tty 2>/dev/tty || true
        else
                clear_screen
                cat "$summary_file"
                pause_screen
        fi

        rm -f "$summary_file"
        return 0
}

unmount_device_everywhere() {
        local device="$1" destination

        while IFS= read -r destination; do
                [[ -n "$destination" ]] || continue
                umount "$destination" || die "Could not unmount $device from $destination"
        done < <(findmnt -rn -S "$device" -o TARGET 2>/dev/null | sort -r || true)

        # An empty while loop otherwise returns a nonzero status under
        # set -E, which caused misleading ERR-trap reports at this function.
        return 0
}

format_device() {
        local device="$1" format="$2" role="$3"
        [[ -n "$device" && "$format" != keep ]] || return 0
        unmount_device_everywhere "$device"
        swapoff "$device" 2>/dev/null || true
        log "Formatting $device as $format for $role"
        case "$format" in
                ext2) mkfs.ext2 -F "$device" ;;
                ext4) mkfs.ext4 -F "$device" ;;
                xfs) mkfs.xfs -f "$device" ;;
                btrfs) mkfs.btrfs -f "$device" ;;
                f2fs) mkfs.f2fs -f "$device" ;;
                vfat) mkfs.fat -F 32 "$device" ;;
                swap) mkswap -f "$device" ;;
        esac
        refresh_storage_state
}


sanitize_btrfs_name() {
        local mountpoint="$1"
        local name="${mountpoint#/}"

        [[ -n "$name" ]] || {
                printf '%s\n' root
                return 0
        }

        name="${name//\//-}"
        name="${name//[^a-zA-Z0-9_.-]/-}"
        printf '%s\n' "$name"
}

register_btrfs_layout() {
        local device="$1" mountpoint="$2"
        local name="" data_subvol="" snapshot_subvol=""

        name="$(sanitize_btrfs_name "$mountpoint")"

        case "$mountpoint" in
                /)
                        data_subvol="@"
                        snapshot_subvol="@snapshots"
                        name=root
                        ;;
                /home)
                        data_subvol="@home"
                        snapshot_subvol="@home-snapshots"
                        name=home
                        ;;
                *)
                        data_subvol="@$name"
                        snapshot_subvol="@$name-snapshots"
                        ;;
        esac

        BTRFS_DEVICES+=("$device")
        BTRFS_MOUNTPOINTS+=("$mountpoint")
        BTRFS_SUBVOLUMES+=("$data_subvol")
        BTRFS_SNAPSHOT_SUBVOLUMES+=("$snapshot_subvol")
        BTRFS_CONFIG_NAMES+=("$name")
}

prepare_btrfs_subvolumes() {
        local index="" device="" data_subvol="" snapshot_subvol="" temp_mount=""

        BTRFS_DEVICES=()
        BTRFS_MOUNTPOINTS=()
        BTRFS_SUBVOLUMES=()
        BTRFS_SNAPSHOT_SUBVOLUMES=()
        BTRFS_CONFIG_NAMES=()

        [[ "$ROOT_FORMAT" == btrfs ]] && register_btrfs_layout "$ROOT_DEV" /
        [[ "$HOME_FORMAT" == btrfs ]] && register_btrfs_layout "$HOME_DEV" /home

        for ((index=0; index<${#EXTRA_DEVICES[@]}; index++)); do
                [[ "${EXTRA_FORMATS[$index]}" == btrfs ]] || continue
                register_btrfs_layout \
                        "${EXTRA_DEVICES[$index]}" \
                        "${EXTRA_MOUNTPOINTS[$index]}"
        done

        ((${#BTRFS_DEVICES[@]} > 0)) || return 0
        command -v btrfs >/dev/null 2>&1 ||
                die "The btrfs command is required for automatic snapshots."

        log "Creating Btrfs data and snapshot subvolumes"

        for ((index=0; index<${#BTRFS_DEVICES[@]}; index++)); do
                device="${BTRFS_DEVICES[$index]}"
                data_subvol="${BTRFS_SUBVOLUMES[$index]}"
                snapshot_subvol="${BTRFS_SNAPSHOT_SUBVOLUMES[$index]}"
                temp_mount="$(mktemp -d /tmp/bfs-btrfs.XXXXXX)"

                mount "$device" "$temp_mount"
                [[ -e "$temp_mount/$data_subvol" ]] ||
                        btrfs subvolume create "$temp_mount/$data_subvol"
                [[ -e "$temp_mount/$snapshot_subvol" ]] ||
                        btrfs subvolume create "$temp_mount/$snapshot_subvol"
                umount "$temp_mount"
                rmdir "$temp_mount"
        done
}

btrfs_layout_index_for_mountpoint() {
        local wanted="$1" index=""

        for ((index=0; index<${#BTRFS_MOUNTPOINTS[@]}; index++)); do
                if [[ "${BTRFS_MOUNTPOINTS[$index]}" == "$wanted" ]]; then
                        printf '%s\n' "$index"
                        return 0
                fi
        done

        return 1
}

mount_btrfs_layout() {
        local device="$1" destination="$2" mountpoint_name="$3"
        local index="" snapshot_destination=""

        index="$(btrfs_layout_index_for_mountpoint "$mountpoint_name")" ||
                return 1

        mkdir -p "$destination"
        mount -o "subvol=${BTRFS_SUBVOLUMES[$index]}" "$device" "$destination"
        record_mount "$destination"

        snapshot_destination="$destination/.snapshots"
        mkdir -p "$snapshot_destination"
        mount -o "subvol=${BTRFS_SNAPSHOT_SUBVOLUMES[$index]}" \
                "$device" "$snapshot_destination"
        record_mount "$snapshot_destination"

        return 0
}

format_selected_partitions() {
        local index
        format_device "$ROOT_DEV" "$ROOT_FORMAT" / 
        format_device "$BOOT_DEV" "$BOOT_FORMAT" /boot
        format_device "$EFI_DEV" "$EFI_FORMAT" /boot/efi
        format_device "$SWAP_DEV" "$SWAP_FORMAT" swap
        format_device "$HOME_DEV" "$HOME_FORMAT" /home
        for ((index=0; index<${#EXTRA_DEVICES[@]}; index++)); do
                format_device "${EXTRA_DEVICES[$index]}" "${EXTRA_FORMATS[$index]}" "${EXTRA_MOUNTPOINTS[$index]}"
        done

        prepare_btrfs_subvolumes
}

record_mount() { MOUNTED_BY_SCRIPT+=("$1"); }

mount_device() {
        local device="$1" destination="$2"
        [[ -n "$device" ]] || return 0
        mkdir -p "$destination"
        mountpoint -q "$destination" && die "$destination unexpectedly remained mounted."
        mount "$device" "$destination"
        record_mount "$destination"
}

mount_target_filesystems() {
        local index="" device="" mountpoint_name="" record=""
        local -a records=()

        log "Mounting target filesystems"

        for device in "$ROOT_DEV" "$BOOT_DEV" "$EFI_DEV" "$HOME_DEV" "${EXTRA_DEVICES[@]}"; do
                [[ -n "$device" ]] && unmount_device_everywhere "$device"
        done

        mkdir -p "$TARGET"

        if ! mount_btrfs_layout "$ROOT_DEV" "$TARGET" /; then
                mount_device "$ROOT_DEV" "$TARGET"
        fi

        [[ -z "$BOOT_DEV" ]] || records+=("$BOOT_DEV|/boot")
        if [[ "$BOOT_MODE" == uefi && -n "$EFI_DEV" ]]; then
                records+=("$EFI_DEV|/boot/efi")
        fi
        [[ -z "$HOME_DEV" ]] || records+=("$HOME_DEV|/home")

        for ((index=0; index<${#EXTRA_DEVICES[@]}; index++)); do
                records+=("${EXTRA_DEVICES[$index]}|${EXTRA_MOUNTPOINTS[$index]}")
        done

        # Mount parents before children regardless of the order in which the
        # user selected them. This is required for layouts such as /usr plus
        # /usr/local, /boot plus /boot/efi, and arbitrary separate /opt trees.
        while IFS= read -r record; do
                [[ -n "$record" ]] || continue
                device="${record%%|*}"
                mountpoint_name="${record#*|}"

                if ! mount_btrfs_layout \
                        "$device" "$TARGET$mountpoint_name" "$mountpoint_name"
                then
                        mount_device "$device" "$TARGET$mountpoint_name"
                fi
        done < <(
                printf '%s\n' "${records[@]}" |
                awk -F'|' '
                        NF >= 2 {
                                mp=$2
                                depth=gsub(/\//, "/", mp)
                                printf "%04d|%s\n", depth, $0
                        }
                ' |
                sort -t'|' -k1,1n -k3,3 |
                cut -d'|' -f2-
        )

        [[ -z "$SWAP_DEV" ]] || swapon "$SWAP_DEV"
}

mount_virtual_filesystems() {
        log "Mounting virtual filesystems for chroot"
        mkdir -p "$TARGET"/{dev,dev/pts,proc,sys,run}

        if ! mountpoint -q "$TARGET/dev"; then
                mount --rbind /dev "$TARGET/dev"
                mount --make-rslave "$TARGET/dev"
                record_mount "$TARGET/dev"
        fi
        if ! mountpoint -q "$TARGET/proc"; then
                mount -t proc proc "$TARGET/proc"
                record_mount "$TARGET/proc"
        fi
        if ! mountpoint -q "$TARGET/sys"; then
                mount --rbind /sys "$TARGET/sys"
                mount --make-rslave "$TARGET/sys"
                record_mount "$TARGET/sys"
        fi
        if ! mountpoint -q "$TARGET/run"; then
                mount --rbind /run "$TARGET/run"
                mount --make-rslave "$TARGET/run"
                record_mount "$TARGET/run"
        fi
}

unmount_virtual_filesystems() {
        local destination=""

        # Recursive unmount is required because --rbind includes nested mounts
        # such as /dev/pts, /dev/shm, and EFI variables below /sys.
        for destination in "$TARGET/run" "$TARGET/sys" "$TARGET/proc" "$TARGET/dev"; do
                if findmnt -Rrn "$destination" 2>/dev/null | grep -q .; then
                        umount -R "$destination" 2>/dev/null ||
                                umount -Rl "$destination" 2>/dev/null ||
                                warn "Could not completely unmount $destination"
                fi
        done
}

cleanup() {
        local status=$?
        local index destination

        # Preserve a complete failure log before target filesystems are
        # unmounted. Successful runs close and copy the log in main().
        if [[ "$LOG_ENABLED" == yes && "$LOG_CLOSED" == no ]]; then
                close_logging "$status" || true
                copy_log_to_installed_system || true
        fi

        rm -f "$TARGET$CHROOT_INSTALLER" 2>/dev/null || true

        [[ -z "$DIALOGRC_FILE" ]] || rm -f "$DIALOGRC_FILE"

        if [[ -n "$ORIGINAL_DIALOGRC" ]]; then
                export DIALOGRC="$ORIGINAL_DIALOGRC"
        else
                unset DIALOGRC
        fi

        reset_terminal_ui
        [[ "$KEEP_MOUNTS" == yes ]] && return "$status"

        # First remove every target mount, including Btrfs snapshot mounts and
        # nested chroot bind mounts. Storage layers cannot be closed while any
        # filesystem above them remains mounted.
        if findmnt -Rrn "$TARGET" 2>/dev/null | grep -q .; then
                umount -R "$TARGET" 2>/dev/null ||
                        umount -Rl "$TARGET" 2>/dev/null || true
        fi

        [[ -z "$SWAP_DEV" ]] || swapoff "$SWAP_DEV" 2>/dev/null || true

        # Deactivate only volume groups created by this installer session.
        if command -v vgchange >/dev/null 2>&1; then
                for ((index=${#ACTIVATED_VGS_BY_SCRIPT[@]}-1; index>=0; index--)); do
                        vgchange -an "${ACTIVATED_VGS_BY_SCRIPT[$index]}" 2>/dev/null || true
                done
        fi

        # Close only LUKS mappings opened by this installer session, after LVM.
        if command -v cryptsetup >/dev/null 2>&1; then
                for ((index=${#OPENED_LUKS_BY_SCRIPT[@]}-1; index>=0; index--)); do
                        cryptsetup close "${OPENED_LUKS_BY_SCRIPT[$index]}" 2>/dev/null || true
                done
        fi

        # Leave a clean, empty mountpoint for the next installer run. Never
        # remove TARGET unless recursive mount verification proves that neither
        # TARGET nor anything below it is mounted. The path guards protect
        # against an empty TARGET or an accidental request to remove /.
        if [[ -n "$TARGET" && "$TARGET" == /* && "$TARGET" != / ]]; then
                if findmnt -Rrn "$TARGET" 2>/dev/null | grep -q .; then
                        warn "Not removing leftover directories because a mount still exists below $TARGET."
                else
                        rm -rf --one-file-system -- "$TARGET" 2>/dev/null ||
                                warn "Could not remove leftover mountpoint directories below $TARGET."
                        mkdir -p -- "$TARGET" 2>/dev/null ||
                                warn "Could not recreate clean target mountpoint $TARGET."
                fi
        else
                warn "Refusing to clean unsafe target path: ${TARGET:-<empty>}"
        fi

        return "$status"
}

installer_err_trap() {
        local status=$?
        local line="${BASH_LINENO[0]:-${LINENO}}"
        local command="${BASH_COMMAND:-unknown}"
        local stack=""
        stack="$(caller 0 2>/dev/null || true)"
        printf '\nERROR: command failed\n' >&2
        printf '  Exit status : %s\n' "$status" >&2
        printf '  Source      : %s\n' "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}" >&2
        printf '  Line        : %s\n' "$line" >&2
        printf '  Function    : %s\n' "${FUNCNAME[1]:-main}" >&2
        printf '  Command     : %s\n' "$command" >&2
        [[ -z "$stack" ]] || printf '  Caller      : %s\n' "$stack" >&2
        exit "$status"
}

trap cleanup EXIT
trap installer_err_trap ERR

path_is_or_contains_mount() {
        local path="$1" mounted_target=""

        while IFS= read -r mounted_target; do
                [[ "$mounted_target" == "$path" || "$mounted_target" == "$path/"* ]] && return 0
        done < <(findmnt -Rrn -o TARGET "$TARGET" 2>/dev/null || true)

        return 1
}

extract_rootfs() {
        local entry has_existing_content=no
        log "Extracting BFS root filesystem"

        while IFS= read -r -d '' entry; do
                [[ "$(basename "$entry")" == lost+found ]] && continue

                # Ignore directories created solely to host selected filesystems.
                # This includes direct mounts such as /home and /var, and parent
                # directories such as /boot when only /boot/efi is mounted.
                path_is_or_contains_mount "$entry" && continue

                has_existing_content=yes
                break
        done < <(find "$TARGET" -mindepth 1 -maxdepth 1 -print0)

        if [[ "$has_existing_content" == yes ]]; then
                warn "$TARGET contains existing files."
                confirm "Extract into it anyway?" || die "Installation cancelled."
        fi

        tar --xattrs --acls --numeric-owner -xpf "$ARCHIVE" -C "$TARGET"
}


fix_installed_bfsos_branding() {
        local file=""
        for file in "$TARGET/etc/os-release" "$TARGET/usr/lib/os-release"; do
                [[ -f "$file" ]] || continue
                sed -i \
                        -e 's|https://codeberg.org/bmadonnaster/BFS-Linux/issues|https://codeberg.org/bmadonnaster/BFSOS/issues|g' \
                        -e 's|https://codeberg.org/bmadonnaster/BFS-Linux|https://codeberg.org/bmadonnaster/BFSOS|g' \
                        "$file"
        done
}

save_base_archive() {
        local archive_name destination
        [[ "$SAVE_BASE_ARCHIVE" == yes ]] || return 0

        archive_name="$(basename "$ARCHIVE")"
        destination="$TARGET$BASE_ARCHIVE_DIR"

        log "Saving BFS base archive"
        mkdir -p "$destination"
        if [[ "$(readlink -f "$ARCHIVE")" != "$(readlink -m "$destination/$archive_name")" ]]; then
                cp -f "$ARCHIVE" "$destination/$archive_name"
        fi

        (
                cd "$destination"
                sha256sum "$archive_name" > "$archive_name.sha256"
        )

        log "Saved base archive to $BASE_ARCHIVE_DIR/$archive_name"
}

device_is_nonrotational() {
        local device="$1"
        local rota=""

        rota="$(lsblk -dnro ROTA "$device" 2>/dev/null | head -n1 || true)"
        [[ "$rota" == 0 ]]
}

fstab_mount_options() {
        local device="$1"
        local fstype="$2"

        case "$fstype" in
                vfat|fat|msdos)
                        printf '%s\n' defaults
                        ;;
                ext2|ext3|ext4|xfs|btrfs|f2fs)
                        if device_is_nonrotational "$device"; then
                                printf '%s\n' defaults,discard
                        else
                                printf '%s\n' defaults
                        fi
                        ;;
                *)
                        printf '%s\n' defaults
                        ;;
        esac
}

write_fstab_entry() {
        local fstab="$1" device="$2" mountpoint="$3" pass="$4"
        local subvol="${5:-}" uuid="" fstype="" options=""

        [[ -n "$device" ]] || return 0

        uuid="$(blkid -s UUID -o value "$device" 2>/dev/null || true)"
        fstype="$(blkid -s TYPE -o value "$device" 2>/dev/null || true)"

        [[ -n "$uuid" ]] || die "Could not determine UUID for $device."
        [[ -n "$fstype" ]] || die "Could not determine filesystem type for $device."

        options="$(fstab_mount_options "$device" "$fstype")"
        [[ -z "$subvol" ]] || options="$options,subvol=$subvol"

        printf '# %s\n' "$device" >> "$fstab"
        printf 'UUID=%-36s %-20s %-8s %-36s 0 %s\n\n' \
                "$uuid" "$mountpoint" "$fstype" "$options" "$pass" >> "$fstab"
}

write_btrfs_fstab_layout() {
        local fstab="$1" mountpoint_name="$2"
        local index="" device="" snapshot_mountpoint=""

        index="$(btrfs_layout_index_for_mountpoint "$mountpoint_name")" ||
                return 1

        device="${BTRFS_DEVICES[$index]}"
        snapshot_mountpoint="$mountpoint_name/.snapshots"
        [[ "$mountpoint_name" == / ]] && snapshot_mountpoint="/.snapshots"

        write_fstab_entry \
                "$fstab" "$device" "$mountpoint_name" 0 \
                "${BTRFS_SUBVOLUMES[$index]}"
        write_fstab_entry \
                "$fstab" "$device" "$snapshot_mountpoint" 0 \
                "${BTRFS_SNAPSHOT_SUBVOLUMES[$index]}"

        return 0
}


validate_fstab_syntax() {
        local fstab="$1"

        awk '
                /^[[:space:]]*($|#)/ {
                        next
                }

                NF != 6 {
                        printf "Invalid fstab field count on line %d: %s\n", NR, $0 > "/dev/stderr"
                        failed=1
                        next
                }

                $1 !~ /^(UUID=|LABEL=|PARTUUID=|PARTLABEL=|\/dev\/)/ {
                        printf "Invalid fstab source on line %d: %s\n", NR, $1 > "/dev/stderr"
                        failed=1
                }

                $2 != "none" && $2 !~ /^\// {
                        printf "Invalid fstab target on line %d: %s\n", NR, $2 > "/dev/stderr"
                        failed=1
                }

                $3 == "" || $4 == "" {
                        printf "Missing filesystem type or options on line %d\n", NR > "/dev/stderr"
                        failed=1
                }

                $5 !~ /^[0-9]+$/ || $6 !~ /^[0-9]+$/ {
                        printf "Invalid dump/pass fields on line %d: %s %s\n", NR, $5, $6 > "/dev/stderr"
                        failed=1
                }

                END {
                        exit failed
                }
        ' "$fstab"
}

generate_fstab() {
        local fstab="$TARGET/etc/fstab"
        local index="" uuid=""

        log "Generating clean /etc/fstab"
        mkdir -p "$TARGET/etc"
        : > "$fstab"

        if ! write_btrfs_fstab_layout "$fstab" /; then
                write_fstab_entry "$fstab" "$ROOT_DEV" / 1
        fi

        write_fstab_entry "$fstab" "$BOOT_DEV" /boot 2

        if [[ "$BOOT_MODE" == uefi ]]; then
                write_fstab_entry "$fstab" "$EFI_DEV" /boot/efi 2
        fi

        if [[ -n "$HOME_DEV" ]]; then
                if ! write_btrfs_fstab_layout "$fstab" /home; then
                        write_fstab_entry "$fstab" "$HOME_DEV" /home 2
                fi
        fi

        for ((index=0; index<${#EXTRA_DEVICES[@]}; index++)); do
                if ! write_btrfs_fstab_layout "$fstab" "${EXTRA_MOUNTPOINTS[$index]}"; then
                        write_fstab_entry \
                                "$fstab" \
                                "${EXTRA_DEVICES[$index]}" \
                                "${EXTRA_MOUNTPOINTS[$index]}" \
                                2
                fi
        done

        if [[ -n "$SWAP_DEV" ]]; then
                uuid="$(blkid -s UUID -o value "$SWAP_DEV" 2>/dev/null || true)"
                [[ -n "$uuid" ]] || die "Could not determine swap UUID for $SWAP_DEV."
                printf '# %s\n' "$SWAP_DEV" >> "$fstab"
                printf 'UUID=%-36s %-16s %-8s %-20s 0 0\n' \
                        "$uuid" none swap sw >> "$fstab"
        fi

        validate_fstab_syntax "$fstab" ||
                die "Generated fstab failed syntax validation."

        log "Generated /etc/fstab passed syntax validation"
}


build_package_list() {
        local packages=()

        [[ "$KERNEL_PACKAGE" != none ]] && packages+=("$KERNEL_PACKAGE")
        [[ "$INSTALL_NETWORKMANAGER" == yes ]] && packages+=(networkmanager)
        [[ "$AUTO_CRYPTSETUP" == yes ]] && packages+=(cryptsetup)
        [[ "$AUTO_LVM2" == yes ]] && packages+=(lvm2)
        [[ "$AUTO_MDADM" == yes ]] && packages+=(mdadm)
        [[ "$INSTALL_GIT" == yes ]] && packages+=(git)
        [[ "$INSTALL_SUDO" == yes ]] && packages+=(sudo)
        [[ "$INSTALL_WGET" == yes ]] && packages+=(wget)
        [[ "$INSTALL_WPA_SUPPLICANT" == yes ]] && packages+=(wpa_supplicant)
        [[ "$INSTALL_WIRELESS_TOOLS" == yes ]] && packages+=(wireless_tools)
        [[ "$INSTALL_GPM" == yes ]] && packages+=(gpm)
        if ((${#BTRFS_DEVICES[@]} > 0)); then
                packages+=(snapper)
        fi

        if ((${#packages[@]} > 0)); then
                printf '%s
' "${packages[@]}" |
                        awk '!seen[$0]++' |
                        tr '
' ' '
        fi
}

write_chroot_installer() {
        local package_list
        detect_storage_requirements
        package_list="$(build_package_list)"
        log "Preparing chroot configuration"
        install -d -m 0755 "$TARGET/root"

        cat > "$TARGET$CHROOT_INSTALLER" <<'CHROOT'
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH=/usr/bin:/usr/sbin:/bin:/sbin
export LANG=C LC_ALL=C LANGUAGE=C
export BFS_INSTALLER_RUNNING=yes
STATE_DIR=/var/lib/bfs-installer
mkdir -p "$STATE_DIR"

HOSTNAME_VALUE="__HOSTNAME__"
TIMEZONE_VALUE="__TIMEZONE__"
LOCALE_VALUE="__LOCALE__"
USERNAME_VALUE="__USERNAME__"
ADDITIONAL_USERS_VALUE="__ADDITIONAL_USERS__"
BOOT_MODE_VALUE="__BOOT_MODE__"
BOOT_DISK_VALUE="__BOOT_DISK__"
NETWORK_IFACE_VALUE="__NETWORK_IFACE__"
NETWORK_MAC_VALUE="__NETWORK_MAC__"
NETWORK_TARGET_NAME_VALUE="__NETWORK_TARGET_NAME__"
PACKAGE_LIST_VALUE="__PACKAGE_LIST__"
ENABLE_OPENSSH_VALUE="__ENABLE_OPENSSH__"
INSTALL_GRUB_VALUE="__INSTALL_GRUB__"
GRUB_FALLBACK_VALUE="__GRUB_FALLBACK__"
KERNEL_PACKAGE_VALUE="__KERNEL_PACKAGE__"
INSTALL_SUDO_VALUE="__INSTALL_SUDO__"
SUDO_MODE_VALUE="__SUDO_MODE__"
INSTALL_NETWORKMANAGER_VALUE="__INSTALL_NETWORKMANAGER__"
INSTALL_GPM_VALUE="__INSTALL_GPM__"
CONSOLE_VIDEO_ARG_VALUE="__CONSOLE_VIDEO_ARG__"
# INSTALL_CRYPTSETUP_VALUE is retained for compatibility with older template
# logic; both values are derived automatically from selected LUKS storage.
INSTALL_CRYPTSETUP_VALUE="__INSTALL_CRYPTSETUP__"
AUTO_CRYPTSETUP_VALUE="__AUTO_CRYPTSETUP__"
AUTO_LVM2_VALUE="__AUTO_LVM2__"
AUTO_MDADM_VALUE="__AUTO_MDADM__"
BTRFS_CONFIG_NAMES_VALUE="__BTRFS_CONFIG_NAMES__"
BTRFS_MOUNTPOINTS_VALUE="__BTRFS_MOUNTPOINTS__"
CONSOLE_FONT_SIZE_VALUE="__CONSOLE_FONT_SIZE__"
INSTALL_CONSOLE_FONT_VALUE="__INSTALL_CONSOLE_FONT__"
ZRAM_SWAP_VALUE="__ZRAM_SWAP__"
ZRAM_SIZE_SPEC_VALUE="__ZRAM_SIZE_SPEC__"
BUILD_JOBS_VALUE="__BUILD_JOBS__"
BUILD_OPT_VALUE="__BUILD_OPT__"
BUILD_CCACHE_VALUE="__BUILD_CCACHE__"
BUILD_CCACHE_SIZE_VALUE="__BUILD_CCACHE_SIZE__"

log() { printf '\n==> %s\n' "$*"; }

log "Setting hostname and timezone"
printf '%s\n' "$HOSTNAME_VALUE" > /etc/hostname
[[ -e "/usr/share/zoneinfo/$TIMEZONE_VALUE" ]] || { echo "Missing timezone: $TIMEZONE_VALUE" >&2; exit 1; }
ln -sfn "/usr/share/zoneinfo/$TIMEZONE_VALUE" /etc/localtime

log "Configuring locales"
mkdir -p /etc

normalize_locale_entry() {
        local locale_name="$1"
        local locale_base="$locale_name"

        case "$locale_name" in
                C.UTF-8|C.utf8)
                        printf '%s\n' 'C.UTF-8 UTF-8'
                        return 0
                        ;;
        esac

        locale_base="${locale_base%.UTF-8}"
        locale_base="${locale_base%.utf8}"
        printf '%s UTF-8\n' "$locale_base"
}

add_locale_entry() {
        local entry="$1"

        touch /etc/locales
        grep -qxF "$entry" /etc/locales ||
                printf '%s\n' "$entry" >> /etc/locales
}

SELECTED_LOCALE_ENTRY="$(normalize_locale_entry "$LOCALE_VALUE")"
C_UTF8_ENTRY="$(normalize_locale_entry C.UTF-8)"

add_locale_entry "$C_UTF8_ENTRY"
add_locale_entry "$SELECTED_LOCALE_ENTRY"

if command -v genlocales >/dev/null 2>&1; then
        genlocales || {
                echo "Locale generation failed with genlocales." >&2
                echo "Contents of /etc/locales:" >&2
                cat /etc/locales >&2
                exit 1
        }
elif command -v locale-gen >/dev/null 2>&1; then
        locale-gen || {
                echo "Locale generation failed with locale-gen." >&2
                echo "Contents of /etc/locales:" >&2
                cat /etc/locales >&2
                exit 1
        }
else
        echo "No locale generation command was found." >&2
        exit 1
fi

printf 'LANG=%s\n' "$LOCALE_VALUE" > /etc/locale.conf

log "Writing hosts and console configuration"
cat > /etc/hosts <<EOF_HOSTS
127.0.0.1 localhost
127.0.1.1 $HOSTNAME_VALUE
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF_HOSTS
configure_installed_console_font() {
        local size="$CONSOLE_FONT_SIZE_VALUE" font="" base=""
        local -a dirs=(/usr/share/consolefonts /usr/share/kbd/consolefonts /lib/kbd/consolefonts)
        local dir="" pattern=""
        local -a patterns=()

        # Keep the BFSOS normal console default unless the user explicitly
        # selected a persistent large font.
        if [[ "$INSTALL_CONSOLE_FONT_VALUE" != yes || "$size" == default ]]; then
                printf 'FONT=Lat2-Terminus16\n' > /etc/vconsole.conf
                log "Installed console font: default (Lat2-Terminus16)"
                return 0
        fi

        case "$size" in
                16) patterns=('Lat2-Terminus16*' 'LatGrkCyr-8x16*' 'Uni2-Terminus16*' 'ter-v16n*' '*Terminus*16*' '*16*.psf*') ;;
                20) patterns=('LatGrkCyr-12x22*' 'Lat2-Terminus20*' 'Uni2-Terminus20*' 'ter-v20n*' 'LatArCyrHeb-19*' 'lat4-19*' '*Terminus*20*' '*22*.psf*' '*20*.psf*' '*19*.psf*') ;;
                32) patterns=('latarcyrheb-sun32*' '*sun32*' '*32*.psf*') ;;
                *)  patterns=() ;;
        esac

        for dir in "${dirs[@]}"; do
                [[ -d "$dir" ]] || continue
                for pattern in "${patterns[@]}"; do
                        font="$(find "$dir" -maxdepth 1 -type f -name "$pattern" -print -quit 2>/dev/null)"
                        [[ -z "$font" ]] || break 2
                done
        done

        if [[ -z "$font" ]]; then
                echo "WARNING: Requested ${size}-pixel installed console font was unavailable; using Lat2-Terminus16." >&2
                printf 'FONT=Lat2-Terminus16\n' > /etc/vconsole.conf
                log "Installed console font fallback: requested size=$size; wrote Lat2-Terminus16"
                return 0
        fi

        base="$(basename "$font")"
        base="${base%.gz}"
        base="${base%.psfu}"
        base="${base%.psf}"
        printf 'FONT=%s\n' "$base" > /etc/vconsole.conf
        log "Installed console font: requested size=$size; wrote FONT=$base from $font"

        # Validate exactly what we persisted before declaring configuration done.
        if ! grep -qx "FONT=$base" /etc/vconsole.conf; then
                echo "ERROR: /etc/vconsole.conf did not preserve the selected console font ($base)." >&2
                return 1
        fi
}

configure_installed_console_font

cat > /etc/inputrc <<'EOF_INPUTRC'
set horizontal-scroll-mode Off
set meta-flag On
set input-meta On
set convert-meta Off
set output-meta On
set bell-style none
"\eOd": backward-word
"\eOc": forward-word
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[5~": beginning-of-history
"\e[6~": end-of-history
"\e[3~": delete-char
"\e[2~": quoted-insert
"\eOH": beginning-of-line
"\eOF": end-of-line
"\e[H": beginning-of-line
"\e[F": end-of-line
EOF_INPUTRC

log "Configuring systemd"
systemd-machine-id-setup
mkdir -p /etc/systemd/system/getty@tty1.service.d
rm -f /etc/systemd/system/getty@tty1.service.d/noclear.conf
cat > /etc/systemd/system/getty@tty1.service.d/clear.conf <<'EOF_GETTY'
[Service]
TTYVTDisallocate=yes
EOF_GETTY
mkdir -p /etc/systemd/coredump.conf.d
cat > /etc/systemd/coredump.conf.d/maxuse.conf <<'EOF_CORE'
[Coredump]
MaxUse=5G
EOF_CORE

mkdir -p /etc/systemd/network
rm -f \
        /etc/systemd/network/10-bfs-dhcp.network \
        /etc/systemd/network/10-bfs-ethernet.link \
        /etc/systemd/network/20-bfs-dhcp.network

# The .link file is handled by udev, so it provides the same eth0 naming
# whether systemd-networkd or NetworkManager is selected.
cat > /etc/systemd/network/10-bfs-ethernet.link <<EOF_LINK
[Match]
MACAddress=$NETWORK_MAC_VALUE

[Link]
Name=$NETWORK_TARGET_NAME_VALUE
EOF_LINK

chmod 0644 /etc/systemd/network/10-bfs-ethernet.link

if [[ "$INSTALL_NETWORKMANAGER_VALUE" != yes ]]; then
        cat > /etc/systemd/network/20-bfs-dhcp.network <<EOF_NETWORK
[Match]
Name=$NETWORK_TARGET_NAME_VALUE

[Network]
DHCP=ipv4

[DHCPv4]
UseDomains=true
EOF_NETWORK

        chmod 0644 /etc/systemd/network/20-bfs-dhcp.network
fi

log "Checking account database"
[[ -f /etc/passwd ]] || { echo "Missing required account file: /etc/passwd" >&2; exit 1; }
[[ -f /etc/group ]] || { echo "Missing required account file: /etc/group" >&2; exit 1; }

grep -q '^root:' /etc/passwd || { echo "The BFS archive has no root entry in /etc/passwd." >&2; exit 1; }
grep -q '^root:' /etc/group || { echo "The BFS archive has no root entry in /etc/group." >&2; exit 1; }

if [[ ! -f /etc/shadow ]]; then
        log "Creating /etc/shadow from /etc/passwd"
        awk -F: '{ print $1 ":!:1::::::" }' /etc/passwd > /etc/shadow
fi

if [[ ! -f /etc/gshadow ]]; then
        log "Creating /etc/gshadow from /etc/group"
        awk -F: '{ print $1 ":!::" $4 }' /etc/group > /etc/gshadow
fi

grep -q '^root:' /etc/shadow || printf '%s\n' 'root:!:1::::::' >> /etc/shadow
grep -q '^root:' /etc/gshadow || printf '%s\n' 'root:!::' >> /etc/gshadow

chown root:root /etc/passwd /etc/group /etc/shadow /etc/gshadow
chmod 0644 /etc/passwd /etc/group
chmod 0600 /etc/shadow /etc/gshadow

log "Creating users"

DEFAULT_USER_GROUPS="users,wheel,audio,video,optical,cdrom,plugdev,storage,input,render"

ensure_default_user_groups() {
        local group_name=""

        command -v groupadd >/dev/null 2>&1 || {
                echo "groupadd is missing" >&2
                exit 1
        }

        for group_name in ${DEFAULT_USER_GROUPS//,/ }; do
                getent group "$group_name" >/dev/null 2>&1 ||
                        groupadd -r "$group_name"
        done
}

verify_regular_user_groups() {
        local user_name="$1"
        local group_name=""
        local user_groups=""

        user_groups="$(id -nG "$user_name")"

        for group_name in ${DEFAULT_USER_GROUPS//,/ }; do
                if ! grep -qw "$group_name" <<< "$user_groups"; then
                        echo "User $user_name was not added to group $group_name." >&2
                        exit 1
                fi
        done

        printf 'Groups for %s: %s\n' "$user_name" "$user_groups"
}

create_regular_user() {
        local user_name="$1"

        if ! id "$user_name" >/dev/null 2>&1; then
                if [[ -d "/home/$user_name" ]]; then
                        useradd -M \
                                -d "/home/$user_name" \
                                -s /bin/bash \
                                "$user_name"
                else
                        useradd -m \
                                -s /bin/bash \
                                "$user_name"
                fi
        fi

        # Apply the standard BFS groups to both newly-created accounts and
        # accounts that were already present in the base archive.
        usermod -aG "$DEFAULT_USER_GROUPS" "$user_name"

        mkdir -p "/home/$user_name"
        chown -R "$user_name:$user_name" "/home/$user_name"

        verify_regular_user_groups "$user_name"
}

ensure_default_user_groups

set_account_password() {
        local account="$1"
        local label="$2"
        local password_one=""
        local password_two=""

        command -v chpasswd >/dev/null 2>&1 || {
                echo "chpasswd is missing" >&2
                exit 1
        }

        while true; do
                printf '\nSet password for %s.\n' "$label"
                read -r -s -p "New password: " password_one
                printf '\n'
                read -r -s -p "Retype new password: " password_two
                printf '\n'

                if [[ -z "$password_one" ]]; then
                        echo "Password cannot be blank."
                elif [[ "$password_one" != "$password_two" ]]; then
                        echo "Passwords do not match."
                else
                        break
                fi
        done

        printf '%s:%s\n' "$account" "$password_one" | chpasswd
        unset password_one password_two
}

if [[ ! -f "$STATE_DIR/accounts_configured" ]]; then
create_regular_user "$USERNAME_VALUE"
set_account_password "$USERNAME_VALUE" "user $USERNAME_VALUE"

read -r -a ADDITIONAL_USERS_ARRAY <<< "$ADDITIONAL_USERS_VALUE"

for user_name in "${ADDITIONAL_USERS_ARRAY[@]}"; do
        [[ -n "$user_name" ]] || continue
        create_regular_user "$user_name"
        set_account_password "$user_name" "user $user_name"
done

set_account_password root root
touch "$STATE_DIR/accounts_configured"
else
        log "Account/password checkpoint already complete; preserving configured accounts"
fi

if [[ ! -f "$STATE_DIR/packages_complete" ]]; then
command -v prt-get >/dev/null 2>&1 || {
        echo "prt-get is missing; mandatory system upgrade cannot run." >&2
        exit 1
}
command -v ports >/dev/null 2>&1 || {
        echo "ports is missing; mandatory ports synchronization cannot run." >&2
        exit 1
}

record_package_failure() {
        local operation="$1" status="$2"
        mkdir -p /run
        {
                printf 'operation=%s\n' "$operation"
                printf 'status=%s\n' "$status"
        } > /run/bfs-install-failure
}

run_package_operation() {
        local operation="$1"; shift
        local status=0
        set +e
        "$@"
        status=$?
        set -e
        if ((status != 0)); then
                record_package_failure "$operation" "$status"
                echo "ERROR: $operation failed with exit status $status" >&2
                exit "$status"
        fi
}

rm -f /run/bfs-install-failure
log "Synchronizing BFSOS ports tree"
run_package_operation "ports synchronization (ports -u)" ports -u

log "Running mandatory installed-system upgrade"
run_package_operation "mandatory package upgrade (prt-get sysup)" prt-get sysup

log "Ensuring BFSOS package-build safety/cache tooling is installed"
run_package_operation "mandatory build tooling (fakeroot/ccache)" prt-get depinst fakeroot fmt xxhash ccache

if [[ -n "$PACKAGE_LIST_VALUE" ]]; then
        read -r -a PACKAGE_LIST_ARRAY <<< "$PACKAGE_LIST_VALUE"
        ((${#PACKAGE_LIST_ARRAY[@]} > 0)) || {
                echo "Internal error: package selection was empty." >&2
                exit 1
        }
        MISSING_PACKAGES=()
        log "Checking selected package installation status"
        for package in "${PACKAGE_LIST_ARRAY[@]}"; do
                if prt-get isinst "$package" >/dev/null 2>&1; then
                        printf 'Already installed: %s\n' "$package"
                else
                        printf 'Will install:      %s\n' "$package"
                        MISSING_PACKAGES+=("$package")
                fi
        done
        if ((${#MISSING_PACKAGES[@]} > 0)); then
                log "Installing missing packages: ${MISSING_PACKAGES[*]}"
                run_package_operation "optional package installation (${MISSING_PACKAGES[*]})" prt-get depinst "${MISSING_PACKAGES[@]}"
        else
                log "All selected packages are already installed"
        fi
else
        log "No optional packages were selected"
fi

touch "$STATE_DIR/packages_complete"
else
        log "Package transaction checkpoint already complete; skipping ports/sysup/depinst"
fi

if [[ "$INSTALL_GPM_VALUE" == yes ]]; then
        if [[ -f /usr/lib/systemd/system/gpm.service || -f /etc/systemd/system/gpm.service ]]; then
                offline_systemctl enable gpm.service 2>/dev/null ||
                        echo "WARNING: gpm was installed but gpm.service could not be enabled automatically." >&2
        else
                echo "WARNING: gpm was selected/installed but no gpm.service unit was found." >&2
        fi
fi

if [[ "$INSTALL_SUDO_VALUE" == yes ]]; then
        mkdir -p /etc/sudoers.d

        case "$SUDO_MODE_VALUE" in
                password)
                        cat > /etc/sudoers.d/10-wheel <<'EOF_SUDO_PASSWORD'
## Allow members of group wheel to execute any command
%wheel ALL=(ALL:ALL) ALL
EOF_SUDO_PASSWORD
                        ;;
                nopasswd)
                        cat > /etc/sudoers.d/10-wheel <<'EOF_SUDO_NOPASSWD'
## Allow members of group wheel to execute any command without a password
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
EOF_SUDO_NOPASSWD
                        ;;
                *)
                        echo "Invalid sudo mode: $SUDO_MODE_VALUE" >&2
                        exit 1
                        ;;
        esac

        chmod 0440 /etc/sudoers.d/10-wheel

        if command -v visudo >/dev/null 2>&1; then
                visudo -cf /etc/sudoers.d/10-wheel
        fi
else
        rm -f /etc/sudoers.d/10-wheel
fi

offline_systemctl() {
        # /run is bind-mounted from the live environment while installing.
        # Force systemctl to operate only on the target filesystem so it never
        # attempts to contact the live system's D-Bus or systemd manager.
        env -u DBUS_SESSION_BUS_ADDRESS \
            -u DBUS_SYSTEM_BUS_ADDRESS \
            -u SYSTEMD_EXEC_PID \
            SYSTEMD_OFFLINE=1 \
            SYSTEMD_IGNORE_CHROOT=1 \
            systemctl --root=/ --no-reload --no-ask-password "$@"
}

command -v ssh-keygen >/dev/null 2>&1 && ssh-keygen -A
ldconfig
offline_systemctl preset-all || true

if [[ "$INSTALL_NETWORKMANAGER_VALUE" == yes ]] && offline_systemctl list-unit-files NetworkManager.service >/dev/null 2>&1; then
        log "Enabling NetworkManager and disabling systemd-networkd"
        offline_systemctl enable NetworkManager.service
        offline_systemctl disable systemd-networkd.service 2>/dev/null || true
        offline_systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true
elif offline_systemctl list-unit-files systemd-networkd.service >/dev/null 2>&1; then
        log "Enabling systemd-networkd"
        offline_systemctl enable systemd-networkd.service
        offline_systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true
fi

if offline_systemctl list-unit-files systemd-resolved.service >/dev/null 2>&1; then
        offline_systemctl enable systemd-resolved.service
        ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
fi

if [[ "$ENABLE_OPENSSH_VALUE" == yes ]]; then
        if offline_systemctl list-unit-files sshd.service >/dev/null 2>&1; then
                offline_systemctl enable sshd.service
        elif offline_systemctl list-unit-files ssh.service >/dev/null 2>&1; then
                offline_systemctl enable ssh.service
        else
                echo "WARNING: No OpenSSH service unit was found." >&2
        fi
fi

if [[ "$AUTO_LVM2_VALUE" == yes ]] &&
   command -v lvmconfig >/dev/null 2>&1; then
        if [[ ! -f /etc/lvm/lvm.conf ]]; then
                mkdir -p /etc/lvm
                lvmconfig --type full --withcomments > /etc/lvm/lvm.conf
        fi
        offline_systemctl enable lvm2-monitor.service 2>/dev/null || true
fi

if [[ "$AUTO_MDADM_VALUE" == yes ]] &&
   command -v mdadm >/dev/null 2>&1; then
        mdadm --detail --scan > /etc/mdadm.conf || true
fi

if [[ "$AUTO_CRYPTSETUP_VALUE" == yes ]]; then
        mkdir -p /etc/cryptsetup-keys.d
        chmod 0700 /etc/cryptsetup-keys.d
fi

configure_btrfs_snapshots() {
        local -a config_names=()
        local -a mountpoints=()
        local index="" config_name="" mountpoint_name="" config_file=""
        local have_root_config=no
        local snapper_configs=""

        read -r -a config_names <<< "$BTRFS_CONFIG_NAMES_VALUE"
        read -r -a mountpoints <<< "$BTRFS_MOUNTPOINTS_VALUE"

        ((${#config_names[@]} > 0)) || {
                # preset-all may have enabled the root-only boot timer even when
                # the installation has no root Snapper configuration.
                offline_systemctl disable snapper-boot.timer 2>/dev/null || true
                return 0
        }

        command -v snapper >/dev/null 2>&1 || {
                echo "Btrfs was selected but snapper is not installed." >&2
                exit 1
        }

        # BFS creates and mounts the dedicated *.snapshots Btrfs subvolumes
        # itself. Do not run `snapper create-config`, because it tries to create
        # .snapshots again and fails when that subvolume already exists.
        #
        # This Snapper build reads the global list from /etc/sysconfig/snapper.
        # Keep /etc/default/snapper in sync as a compatibility copy.
        mkdir -p /etc/snapper/configs /etc/sysconfig /etc/default

        for ((index=0; index<${#config_names[@]}; index++)); do
                config_name="${config_names[$index]}"
                mountpoint_name="${mountpoints[$index]}"
                config_file="/etc/snapper/configs/$config_name"

                [[ "$config_name" == root ]] && have_root_config=yes

                cat > "$config_file" <<EOF_SNAPPER
SUBVOLUME="$mountpoint_name"
FSTYPE="btrfs"
QGROUP=""
SPACE_LIMIT="0.5"
FREE_LIMIT="0.2"
ALLOW_USERS=""
ALLOW_GROUPS="wheel"
SYNC_ACL="yes"
BACKGROUND_COMPARISON="yes"
NUMBER_CLEANUP="yes"
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="50"
NUMBER_LIMIT_IMPORTANT="10"
TIMELINE_CREATE="yes"
TIMELINE_CLEANUP="yes"
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="10"
TIMELINE_LIMIT_DAILY="10"
TIMELINE_LIMIT_WEEKLY="0"
TIMELINE_LIMIT_MONTHLY="10"
TIMELINE_LIMIT_YEARLY="10"
EMPTY_PRE_POST_CLEANUP="yes"
EMPTY_PRE_POST_MIN_AGE="1800"
EOF_SNAPPER
        done

        snapper_configs="${config_names[*]}"
        printf 'SNAPPER_CONFIGS="%s"\n' "$snapper_configs" > /etc/sysconfig/snapper
        printf 'SNAPPER_CONFIGS="%s"\n' "$snapper_configs" > /etc/default/snapper

        # Verify the global registration and every per-filesystem config before
        # enabling timers. This prevents a fresh install from booting with a
        # guaranteed failed Snapper unit.
        grep -q '^SNAPPER_CONFIGS=.*[^"]' /etc/sysconfig/snapper || {
                echo "Snapper configuration error: no configurations were registered." >&2
                exit 1
        }

        for config_name in "${config_names[@]}"; do
                [[ -s "/etc/snapper/configs/$config_name" ]] || {
                        echo "Snapper configuration error: missing config '$config_name'." >&2
                        exit 1
                }
        done

        # The installer configures Snapper from inside the target chroot.
        # D-Bus is not normally running there, so plain `snapper list-configs`
        # can fail with org.freedesktop.DBus.Error.ServiceUnknown even when the
        # generated configuration is valid. Use Snapper's direct mode instead.
        if snapper --help 2>&1 | grep -q -- '--no-dbus'; then
                if ! snapper --no-dbus list-configs >/dev/null 2>&1; then
                        echo "Snapper configuration error: generated configs are not readable." >&2
                        exit 1
                fi
        else
                echo "NOTE: Snapper --no-dbus is unavailable; file-level configuration checks passed." >&2
        fi

        offline_systemctl enable snapper-timeline.timer 2>/dev/null || true
        offline_systemctl enable snapper-cleanup.timer 2>/dev/null || true

        # snapper-boot.service is hard-coded to use --config root, so only
        # enable its timer when / is actually one of the configured Btrfs
        # filesystems. Explicitly disable it otherwise because preset-all may
        # have enabled it earlier.
        if [[ "$have_root_config" == yes ]]; then
                offline_systemctl enable snapper-boot.timer 2>/dev/null || true
        else
                offline_systemctl disable snapper-boot.timer 2>/dev/null || true
        fi

        for config_name in "${config_names[@]}"; do
                if snapper --help 2>&1 | grep -q -- '--no-dbus'; then
                        snapper --no-dbus -c "$config_name" create \
                                --cleanup-algorithm number \
                                --description "Initial BFSOS installation" || {
                                echo "WARNING: Could not create initial Snapper snapshot for '$config_name'." >&2
                        }
                else
                        # The configs and snapshot subvolumes are already in
                        # place. Defer the initial snapshot until normal boot
                        # rather than failing the whole installation.
                        echo "NOTE: Initial Snapper snapshot for '$config_name' deferred until boot." >&2
                fi
        done
}

configure_btrfs_snapshots

# Keep normal cosmetic options in GRUB_CMDLINE_LINUX_DEFAULT, while storage
# discovery arguments live in GRUB_CMDLINE_LINUX so normal, recovery, and
# future kernel entries all inherit the same required early-boot topology.
mkdir -p /etc/default
touch /etc/default/grub

grub_get_cmdline_value() {
        local key="$1"
        sed -n "s/^${key}=\"\([^\"]*\)\"/\1/p" /etc/default/grub | head -n1
}

grub_set_cmdline_value() {
        local key="$1" value="$2"
        if grep -q "^${key}=" /etc/default/grub; then
                sed -i "s|^${key}=.*|${key}=\"${value}\"|" /etc/default/grub
        else
                printf '%s="%s"\n' "$key" "$value" >> /etc/default/grub
        fi
}

cmdline_append_unique() {
        local variable="$1" token="$2" value="${!1:-}"
        case " $value " in
                *" $token "*) ;;
                *) value="${value:+$value }$token" ;;
        esac
        printf -v "$variable" '%s' "$value"
}

strip_bfs_storage_cmdline() {
        local value="$1" token="" result=""
        for token in $value; do
                case "$token" in
                        rd.auto|rd.md=*|rd.luks.uuid=*|rd.lvm.lv=*|video=*)
                                ;;
                        *)
                                result+="${result:+ }$token"
                                ;;
                esac
        done
        printf '%s' "$result"
}

discover_required_lvm_cmdline() {
        local source="" mountpoint="" fstype="" options="" dump="" passno=""
        local device="" device_real="" source_uuid=""
        local lv_record="" vg="" lv="" lv_path="" lv_real="" lv_uuid=""

        command -v lvs >/dev/null 2>&1 || return 0
        [[ -r /etc/fstab ]] || return 0

        while read -r source mountpoint fstype options dump passno; do
                [[ -n "$source" && "$source" != \#* ]] || continue

                device=""
                source_uuid=""
                case "$source" in
                        UUID=*)
                                source_uuid="${source#UUID=}"
                                command -v blkid >/dev/null 2>&1 &&
                                        device="$(blkid -U "$source_uuid" 2>/dev/null || true)"
                                ;;
                        /dev/*)
                                device="$source"
                                command -v blkid >/dev/null 2>&1 &&
                                        source_uuid="$(blkid -s UUID -o value "$device" 2>/dev/null || true)"
                                ;;
                        *)
                                continue
                                ;;
                esac

                device_real=""
                [[ -n "$device" ]] && device_real="$(readlink -f "$device" 2>/dev/null || true)"

                # Do not ask `lvs` to resolve the fstab device as a positional
                # LV selector.  Device-mapper may expose the same LV through
                # /dev/mapper/<escaped>, /dev/<vg>/<lv>, or /dev/dm-N, and the
                # selector lookup proved unreliable for non-root LVs on real
                # hardware.  Instead inventory every LV and match the fstab
                # filesystem by canonical block-device path and, independently,
                # by the filesystem UUID stored in fstab.
                while IFS='|' read -r vg lv lv_path; do
                        vg="$(printf '%s' "$vg" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                        lv="$(printf '%s' "$lv" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                        lv_path="$(printf '%s' "$lv_path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                        [[ -n "$vg" && -n "$lv" && -n "$lv_path" ]] || continue

                        lv_real="$(readlink -f "$lv_path" 2>/dev/null || true)"
                        lv_uuid=""
                        command -v blkid >/dev/null 2>&1 &&
                                lv_uuid="$(blkid -s UUID -o value "$lv_path" 2>/dev/null || true)"

                        if [[ -n "$device_real" && -n "$lv_real" && "$device_real" == "$lv_real" ]] ||
                           [[ -n "$source_uuid" && -n "$lv_uuid" && "$source_uuid" == "$lv_uuid" ]]; then
                                printf '%s/%s\n' "$vg" "$lv"
                                break
                        fi
                done < <(lvs --noheadings --separator '|' -o vg_name,lv_name,lv_path 2>/dev/null || true)
        done < /etc/fstab
}


discover_required_luks_cmdline() {
        local name="" source="" keyfile="" options="" uuid=""
        [[ -r /etc/crypttab ]] || return 0
        while read -r name source keyfile options; do
                [[ -n "$name" && "$name" != \#* ]] || continue
                case "$source" in
                        UUID=*) uuid="${source#UUID=}" ;;
                        /dev/*)
                                uuid="$(cryptsetup luksUUID "$source" 2>/dev/null ||
                                        blkid -s UUID -o value "$source" 2>/dev/null || true)"
                                ;;
                        *) uuid="" ;;
                esac
                [[ -n "$uuid" ]] && printf '%s\n' "$uuid"
        done < /etc/crypttab
}

discover_required_md_cmdline() {
        local source="" mountpoint="" fstype="" options="" dump="" passno=""
        local device=""
        [[ -r /etc/fstab ]] || return 0
        while read -r source mountpoint fstype options dump passno; do
                [[ -n "$source" && "$source" != \#* ]] || continue
                case "$source" in
                        UUID=*) device="$(blkid -U "${source#UUID=}" 2>/dev/null || true)" ;;
                        /dev/*) device="$source" ;;
                        *) continue ;;
                esac
                [[ -n "$device" ]] || continue
                lsblk -s -prno PATH,TYPE "$device" 2>/dev/null |
                        awk '$2 ~ /^raid/ {print $1}'
        done < /etc/fstab
}


discover_required_md_uuids() {
        local array="" uuid=""
        command -v mdadm >/dev/null 2>&1 || return 0
        while IFS= read -r array; do
                [[ -b "$array" ]] || continue
                uuid="$(
                        mdadm --detail "$array" 2>/dev/null |
                                sed -n 's/^[[:space:]]*UUID[[:space:]]*:[[:space:]]*//p' |
                                head -n1
                )"
                uuid="${uuid%%[[:space:]]*}"
                [[ -n "$uuid" ]] && printf '%s\n' "$uuid"
        done < <(discover_required_md_cmdline | sort -u)
}

configure_grub_storage_cmdline() {
        local default_cmdline="" storage_cmdline="" token="" uuid="" lv=""
        local -A seen_luks=() seen_lvs=()

        default_cmdline="$(grub_get_cmdline_value GRUB_CMDLINE_LINUX_DEFAULT)"
        storage_cmdline="$(grub_get_cmdline_value GRUB_CMDLINE_LINUX)"

        # Remove storage arguments from both variables before rebuilding them.
        # This makes repeated installer runs idempotent and avoids stale UUID/LV
        # references after changing a storage layout.
        default_cmdline="$(strip_bfs_storage_cmdline "$default_cmdline")"
        storage_cmdline="$(strip_bfs_storage_cmdline "$storage_cmdline")"

        case " $default_cmdline " in
                *" consoleblank="*) ;;
                *) default_cmdline="${default_cmdline:+$default_cmdline }consoleblank=1800" ;;
        esac
        if [[ -n "$CONSOLE_VIDEO_ARG_VALUE" ]]; then
                cmdline_append_unique default_cmdline "$CONSOLE_VIDEO_ARG_VALUE"
        fi

        if [[ "$AUTO_CRYPTSETUP_VALUE" == yes ]]; then
                while IFS= read -r uuid; do
                        uuid="${uuid#luks-}"
                        [[ -n "$uuid" ]] || continue
                        [[ -z "${seen_luks[$uuid]:-}" ]] || continue
                        seen_luks["$uuid"]=1
                        cmdline_append_unique storage_cmdline "rd.luks.uuid=$uuid"
                done < <(discover_required_luks_cmdline)
        fi

        while IFS= read -r uuid; do
                [[ -n "$uuid" ]] || continue
                cmdline_append_unique storage_cmdline "rd.md.uuid=$uuid"
        done < <(discover_required_md_uuids)

        if [[ "$AUTO_LVM2_VALUE" == yes ]]; then
                while IFS= read -r lv; do
                        [[ -n "$lv" ]] || continue
                        [[ -z "${seen_lvs[$lv]:-}" ]] || continue
                        seen_lvs["$lv"]=1
                        cmdline_append_unique storage_cmdline "rd.lvm.lv=$lv"
                done < <(discover_required_lvm_cmdline)
        fi

        grub_set_cmdline_value GRUB_CMDLINE_LINUX_DEFAULT "$default_cmdline"
        grub_set_cmdline_value GRUB_CMDLINE_LINUX "$storage_cmdline"

        log "GRUB default kernel arguments: ${default_cmdline:-none}"
        log "GRUB storage kernel arguments: ${storage_cmdline:-none}"
}


verify_grub_storage_cmdline() {
        local cfg="/boot/grub/grub.cfg" uuid="" lv="" expected=""
        local linux_lines="" recovery_lines=""
        local -A seen_luks=() seen_lvs=() seen_md=()

        [[ -s "$cfg" ]] || return 1
        linux_lines="$(grep -E '^[[:space:]]*linux[[:space:]]' "$cfg" || true)"
        [[ -n "$linux_lines" ]] || {
                echo "GRUB verification failed: no Linux entries found." >&2
                return 1
        }

        while IFS= read -r uuid; do
                [[ -n "$uuid" ]] || continue
                [[ -z "${seen_md[$uuid]:-}" ]] || continue
                seen_md["$uuid"]=1
                expected="rd.md.uuid=$uuid"
                grep -qF "$expected" <<<"$linux_lines" || {
                        echo "GRUB verification failed: missing complete MD RAID UUID." >&2
                        echo "Expected: $expected" >&2
                        printf 'Generated Linux lines:\n%s\n' "$linux_lines" >&2
                        return 1
                }
        done < <(discover_required_md_uuids)

        if [[ "$AUTO_CRYPTSETUP_VALUE" == yes ]]; then
                while IFS= read -r uuid; do
                        uuid="${uuid#luks-}"
                        [[ -n "$uuid" ]] || continue
                        [[ -z "${seen_luks[$uuid]:-}" ]] || continue
                        seen_luks["$uuid"]=1
                        expected="rd.luks.uuid=$uuid"
                        grep -qF "$expected" <<<"$linux_lines" || {
                                echo "GRUB verification failed: missing required LUKS UUID." >&2
                                echo "Expected: $expected" >&2
                                printf 'Generated Linux lines:\n%s\n' "$linux_lines" >&2
                                return 1
                        }
                done < <(discover_required_luks_cmdline)
        fi

        if [[ "$AUTO_LVM2_VALUE" == yes ]]; then
                while IFS= read -r lv; do
                        [[ -n "$lv" ]] || continue
                        [[ -z "${seen_lvs[$lv]:-}" ]] || continue
                        seen_lvs["$lv"]=1
                        expected="rd.lvm.lv=$lv"
                        grep -qF "$expected" <<<"$linux_lines" || {
                                echo "GRUB verification failed: missing required LVM argument." >&2
                                echo "Expected: $expected" >&2
                                printf 'Generated Linux lines:\n%s\n' "$linux_lines" >&2
                                return 1
                        }
                done < <(discover_required_lvm_cmdline)
        fi

        recovery_lines="$(grep -E '^[[:space:]]*linux[[:space:]].*[[:space:]]single([[:space:]]|$)' "$cfg" || true)"
        if [[ -n "$recovery_lines" ]]; then
                for uuid in "${!seen_md[@]}"; do
                        grep -qF "rd.md.uuid=$uuid" <<<"$recovery_lines" || {
                                echo "GRUB verification failed: recovery entry is missing MD UUID $uuid." >&2
                                return 1
                        }
                done
                for uuid in "${!seen_luks[@]}"; do
                        grep -qF "rd.luks.uuid=$uuid" <<<"$recovery_lines" || {
                                echo "GRUB verification failed: recovery entry is missing LUKS UUID $uuid." >&2
                                return 1
                        }
                done
                for lv in "${!seen_lvs[@]}"; do
                        grep -qF "rd.lvm.lv=$lv" <<<"$recovery_lines" || {
                                echo "GRUB verification failed: recovery entry is missing LVM argument $lv." >&2
                                return 1
                        }
                done
        fi
        return 0
}

configure_grub_storage_cmdline

configure_zram_swap() {
        local config="" module_found=no service="/usr/lib/systemd/system/bfs-zram.service"
        [[ "$ZRAM_SWAP_VALUE" == yes ]] || {
                rm -f "$service" /usr/libexec/bfs-zram-setup /usr/libexec/bfs-zram-stop
                rm -f /etc/systemd/system/swap.target.wants/bfs-zram.service
                return 0
        }

        config="$(find /boot -maxdepth 1 -type f -name 'config-*' -print 2>/dev/null | sort -V | tail -n1)"
        if [[ -n "$config" ]] && grep -qE '^CONFIG_ZRAM=(y|m)$' "$config"; then
                module_found=yes
        elif find /lib/modules -type f -name 'zram.ko*' -print -quit 2>/dev/null | grep -q .; then
                module_found=yes
        fi

        [[ "$module_found" == yes ]] || {
                echo "ZRAM swap was selected, but the installed kernel does not appear to provide ZRAM support." >&2
                exit 1
        }

        mkdir -p /usr/libexec /usr/lib/systemd/system
        cat > /usr/libexec/bfs-zram-setup <<'EOF_ZRAM_SETUP'
#!/usr/bin/env bash
set -e
modprobe zram 2>/dev/null || true
[[ -b /dev/zram0 ]] || { echo "zram0 device is unavailable" >&2; exit 1; }
mem_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
size_spec="__ZRAM_SIZE_SPEC__"
case "$size_spec" in
        *%)
                percent=${size_spec%%%}
                size_bytes=$((mem_kb * 1024 * percent / 100))
                ;;
        *G)
                value=${size_spec%G}
                size_bytes=$(awk -v v="$value" 'BEGIN { printf "%.0f", v * 1024 * 1024 * 1024 }')
                ;;
        *M)
                value=${size_spec%M}
                size_bytes=$(awk -v v="$value" 'BEGIN { printf "%.0f", v * 1024 * 1024 }')
                ;;
        *)
                echo "Invalid BFSOS ZRAM size: $size_spec" >&2
                exit 1
                ;;
esac
(( size_bytes > 0 )) || { echo "Calculated ZRAM size is zero" >&2; exit 1; }
if [[ -e /sys/block/zram0/reset ]]; then
        swapoff /dev/zram0 2>/dev/null || true
        echo 1 > /sys/block/zram0/reset 2>/dev/null || true
fi
echo "$size_bytes" > /sys/block/zram0/disksize
mkswap -f /dev/zram0
swapon -p 100 /dev/zram0
EOF_ZRAM_SETUP
        chmod 0755 /usr/libexec/bfs-zram-setup

        cat > /usr/libexec/bfs-zram-stop <<'EOF_ZRAM_STOP'
#!/usr/bin/env bash
swapoff /dev/zram0 2>/dev/null || true
[[ -e /sys/block/zram0/reset ]] && echo 1 > /sys/block/zram0/reset 2>/dev/null || true
EOF_ZRAM_STOP
        chmod 0755 /usr/libexec/bfs-zram-stop

        cat > "$service" <<'EOF_ZRAM_SERVICE'
[Unit]
Description=BFSOS compressed ZRAM swap
DefaultDependencies=no
After=systemd-modules-load.service
Before=swap.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/libexec/bfs-zram-setup
ExecStop=/usr/libexec/bfs-zram-stop

[Install]
WantedBy=swap.target
EOF_ZRAM_SERVICE

        offline_systemctl enable bfs-zram.service
        [[ -L /etc/systemd/system/swap.target.wants/bfs-zram.service ]] || {
                echo "ZRAM service was created but was not enabled successfully." >&2
                exit 1
        }
        log "Configured ZRAM swap for boot"
}

configure_pkgmk_build_settings() {
        local conf=/etc/pkgmk.conf jobs flags size kb gib
        [[ -f "$conf" ]] || return 0
        [[ "$BUILD_JOBS_VALUE" == inherited ]] || {
                jobs="$BUILD_JOBS_VALUE"; [[ "$jobs" == auto ]] && jobs="$(nproc)"
                sed -i "s|^export JOBS=.*|export JOBS=$jobs|; s|^export MAKEFLAGS=.*|export MAKEFLAGS=\"-j \$JOBS\"|" "$conf"
        }
        case "$BUILD_OPT_VALUE" in
                portable) flags='-O2 -march=x86-64 -pipe' ;;
                native) flags='-O2 -march=native -mtune=native -pipe' ;;
                *) flags='' ;;
        esac
        [[ -z "$flags" ]] || sed -i "s|^export CFLAGS=.*|export CFLAGS=\"$flags\"|; s|^export CXXFLAGS=.*|export CXXFLAGS=\"\${CFLAGS}\"|" "$conf"
        if [[ "$BUILD_CCACHE_VALUE" == yes ]]; then
                grep -q '^export PATH="/usr/lib/ccache:' "$conf" || printf '\nexport PATH="/usr/lib/ccache:$PATH"\n' >> "$conf"
        elif [[ "$BUILD_CCACHE_VALUE" == no ]]; then
                sed -i '\|^export PATH="/usr/lib/ccache:|d' "$conf"
        fi
        if [[ "$BUILD_CCACHE_SIZE_VALUE" != inherited && "$BUILD_CCACHE_VALUE" != no ]] && command -v ccache >/dev/null 2>&1; then
                size="$BUILD_CCACHE_SIZE_VALUE"
                if [[ "$size" == auto ]]; then
                        if command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt -q; then size=20G; else
                                kb=$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo); gib=$(( (kb + 1048575) / 1048576 )); size="${gib}G"
                        fi
                fi
                install -d -m 0775 -o pkgmk -g pkgmk /var/cache/ccache
                CCACHE_DIR=/var/cache/ccache ccache --set-config="max_size=$size"
                chown -R pkgmk:pkgmk /var/cache/ccache
        fi
}

configure_pkgmk_build_settings
configure_zram_swap

configure_dracut_storage_modules() {
        local config_file="/etc/dracut.conf.d/20-bfs-storage.conf"
        local -a modules=()
        local separate_usr=no

        mkdir -p /etc/dracut.conf.d

        if awk '!/^[[:space:]]*#/ && $2 == "/usr" {found=1} END {exit !found}' /etc/fstab 2>/dev/null; then
                separate_usr=yes
                modules+=(usrmount)
        fi

        if [[ "$AUTO_CRYPTSETUP_VALUE" == yes ]]; then
                command -v cryptsetup >/dev/null 2>&1 || {
                        echo "Encrypted storage was detected, but cryptsetup is missing." >&2
                        return 1
                }
                modules+=(crypt)
        fi

        if [[ "$AUTO_LVM2_VALUE" == yes ]]; then
                command -v lvm >/dev/null 2>&1 ||
                command -v vgchange >/dev/null 2>&1 || {
                        echo "LVM storage was detected, but LVM tools are missing." >&2
                        return 1
                }
                modules+=(lvm)
        fi

        if [[ "$AUTO_MDADM_VALUE" == yes ]]; then
                command -v mdadm >/dev/null 2>&1 || {
                        echo "Software RAID storage was detected, but mdadm is missing." >&2
                        return 1
                }
                modules+=(mdraid)
        fi

        if ((${#modules[@]} > 0)); then
                printf '# Generated by the BFS installer from the final storage topology.\n' > "$config_file"
                printf '# Separate /usr: %s\n' "$separate_usr" >> "$config_file"
                # BFS uses host-only initramfs images. Force these topology-
                # critical modules into every future rebuild of this machine.
                printf 'force_add_dracutmodules+=" %s "\n' "${modules[*]}" >> "$config_file"
                if [[ "$AUTO_MDADM_VALUE" == yes ]]; then
                        printf 'force_drivers+=" linear raid0 raid1 raid10 raid456 "\n' >> "$config_file"
                fi
        else
                rm -f "$config_file"
        fi
}

verify_required_dracut_modules() {
        local image="$1" module="" required_line=""
        local -a required=()

        command -v lsinitrd >/dev/null 2>&1 || {
                echo "WARNING: lsinitrd is unavailable; cannot verify initramfs module list." >&2
                return 0
        }

        [[ "$AUTO_CRYPTSETUP_VALUE" == yes ]] && required+=(crypt)
        [[ "$AUTO_LVM2_VALUE" == yes ]] && required+=(lvm)
        [[ "$AUTO_MDADM_VALUE" == yes ]] && required+=(mdraid)
        if awk '!/^[[:space:]]*#/ && $2 == "/usr" {found=1} END {exit !found}' /etc/fstab 2>/dev/null; then
                required+=(usrmount)
        fi

        required_line="$(lsinitrd "$image" 2>/dev/null || true)"
        for module in "${required[@]}"; do
                if ! grep -qE "(^|[[:space:]/-])${module}([[:space:]/.-]|$)" <<<"$required_line"; then
                        echo "Initramfs verification failed: required Dracut module '$module' was not found in $image." >&2
                        return 1
                fi
        done
        if [[ "$AUTO_MDADM_VALUE" == yes ]]; then
                for module in linear raid0 raid1 raid10 raid456; do
                        if ! grep -qE "/${module}\.ko([.]|$)" <<<"$required_line"; then
                                echo "Initramfs verification failed: required md driver '$module' was not found in $image." >&2
                                return 1
                        fi
                done
        fi
        return 0
}

rebuild_final_initramfs() {
        local kernel_image=""
        local kernel_release=""
        local initramfs_image=""

        [[ "$KERNEL_PACKAGE_VALUE" != none ]] || return 0

        command -v dracut >/dev/null 2>&1 || {
                echo "A kernel was installed, but dracut is unavailable." >&2
                exit 1
        }

        kernel_image="$(
                find /boot -maxdepth 1 -type f -name 'vmlinuz-*' \
                        -printf '%T@ %p\n' |
                sort -nr |
                head -n1 |
                cut -d' ' -f2-
        )"

        [[ -n "$kernel_image" ]] || {
                echo "Could not find a kernel for initramfs generation." >&2
                exit 1
        }

        kernel_release="${kernel_image#/boot/vmlinuz-}"
        initramfs_image="/boot/initramfs-$kernel_release.img"

        configure_dracut_storage_modules || exit 1

        log "Generating final initramfs for $kernel_release"
        log "Storage stack: RAID=$AUTO_MDADM_VALUE LUKS=$AUTO_CRYPTSETUP_VALUE LVM=$AUTO_LVM2_VALUE"
        if [[ "$AUTO_MDADM_VALUE" == yes ]]; then
                dracut --force --force-drivers "linear raid0 raid1 raid10 raid456" \
                        "$initramfs_image" "$kernel_release"
        else
                dracut --force "$initramfs_image" "$kernel_release"
        fi
        verify_required_dracut_modules "$initramfs_image" || exit 1
}

touch "$STATE_DIR/system_config_complete"
rebuild_final_initramfs

verify_kernel_installation() {
        local kernel_image=""
        local kernel_release=""
        local initramfs_image=""

        [[ "$KERNEL_PACKAGE_VALUE" != none ]] || return 0

        kernel_image="$(
                find /boot -maxdepth 1 -type f -name 'vmlinuz-*' \
                        -printf '%T@ %p\n' |
                sort -nr |
                head -n1 |
                cut -d' ' -f2-
        )"

        [[ -n "$kernel_image" && -s "$kernel_image" ]] || {
                echo "No installed kernel image was found." >&2
                exit 1
        }

        kernel_release="${kernel_image#/boot/vmlinuz-}"
        initramfs_image="/boot/initramfs-$kernel_release.img"

        if [[ ! -s "$initramfs_image" ]]; then
                initramfs_image="$(
                        find /boot -maxdepth 1 -type f \
                                \( -name "initramfs*$kernel_release*.img" -o -name "initrd*$kernel_release*" \) \
                                -printf '%T@ %p\n' |
                        sort -nr |
                        head -n1 |
                        cut -d' ' -f2-
                )"
        fi

        [[ -n "$initramfs_image" && -s "$initramfs_image" ]] || {
                echo "No matching initramfs was found for $kernel_release." >&2
                exit 1
        }

        printf 'Verified kernel: %s\n' "$kernel_image"
        printf 'Verified initramfs: %s\n' "$initramfs_image"
}

verify_kernel_installation

if [[ "$INSTALL_GRUB_VALUE" == yes ]]; then
        log "Writing and configuring GRUB"

        command -v grub-install >/dev/null 2>&1 || {
                echo "grub-install is missing" >&2
                exit 1
        }

        command -v grub-mkconfig >/dev/null 2>&1 || {
                echo "grub-mkconfig is missing" >&2
                exit 1
        }

        mkdir -p /boot/grub

        if [[ "$BOOT_MODE_VALUE" == uefi ]]; then
                grub-install \
                        --target=x86_64-efi \
                        --efi-directory=/boot/efi \
                        --bootloader-id=BFS \
                        --recheck

                if [[ "$GRUB_FALLBACK_VALUE" == yes ]]; then
                        grub-install \
                                --target=x86_64-efi \
                                --efi-directory=/boot/efi \
                                --bootloader-id=BFS \
                                --removable \
                                --recheck
                fi
        else
                grub-install "$BOOT_DISK_VALUE"
        fi

        grub-mkconfig -o /boot/grub/grub.cfg

        [[ -s /boot/grub/grub.cfg ]] || {
                echo "GRUB configuration was not generated." >&2
                exit 1
        }

        if [[ "$KERNEL_PACKAGE_VALUE" != none ]]; then
                grep -q '^[[:space:]]*linux[[:space:]]' /boot/grub/grub.cfg || {
                        echo "grub.cfg contains no Linux kernel line." >&2
                        exit 1
                }

                grep -q '^[[:space:]]*initrd[[:space:]]' /boot/grub/grub.cfg || {
                        echo "grub.cfg contains no initrd line." >&2
                        exit 1
                }
        fi

        verify_grub_storage_cmdline || {
                echo "GRUB storage command-line verification failed." >&2
                exit 1
        }

        if [[ -n "$CONSOLE_VIDEO_ARG_VALUE" ]]; then
                grep -E '^[[:space:]]*linux[[:space:]]' /boot/grub/grub.cfg | grep -qF "$CONSOLE_VIDEO_ARG_VALUE" || {
                        echo "GRUB verification failed: configured console video argument is missing." >&2
                        echo "Expected: $CONSOLE_VIDEO_ARG_VALUE" >&2
                        exit 1
                }
        fi

        if [[ "$BOOT_MODE_VALUE" == uefi ]]; then
                [[ -s /boot/efi/EFI/BFS/grubx64.efi ]] || {
                        echo "BFS EFI loader was not installed." >&2
                        exit 1
                }

                if [[ "$GRUB_FALLBACK_VALUE" == yes ]]; then
                        [[ -s /boot/efi/EFI/BOOT/BOOTX64.EFI ]] || {
                                echo "EFI fallback loader was not installed." >&2
                                exit 1
                        }
                fi
        fi
        touch "$STATE_DIR/bootloader_complete"
else
        log "Skipping GRUB bootloader configuration"
fi

log "Running final checks"

if [[ "$AUTO_CRYPTSETUP_VALUE" == yes ]]; then
        [[ -s /etc/crypttab ]] || {
                echo "Encrypted storage was detected, but /etc/crypttab is missing." >&2
                exit 1
        }

        command -v cryptsetup >/dev/null 2>&1 || {
                echo "Encrypted storage was detected, but cryptsetup is missing." >&2
                exit 1
        }
fi

[[ -s /etc/systemd/network/10-bfs-ethernet.link ]] ||
        { echo "Missing BFS network link file." >&2; exit 1; }

grep -qx "MACAddress=$NETWORK_MAC_VALUE" /etc/systemd/network/10-bfs-ethernet.link ||
        { echo "BFS network link file has the wrong MAC address." >&2; exit 1; }
grep -qx "Name=$NETWORK_TARGET_NAME_VALUE" /etc/systemd/network/10-bfs-ethernet.link ||
        { echo "BFS network link file has the wrong target interface name." >&2; exit 1; }

if [[ "$INSTALL_NETWORKMANAGER_VALUE" == yes ]]; then
        [[ ! -e /etc/systemd/network/20-bfs-dhcp.network ]] ||
                { echo "A systemd-networkd DHCP file exists while NetworkManager is selected." >&2; exit 1; }
else
        [[ -s /etc/systemd/network/20-bfs-dhcp.network ]] ||
                { echo "Missing BFS DHCP network file." >&2; exit 1; }
        grep -qx "Name=$NETWORK_TARGET_NAME_VALUE" /etc/systemd/network/20-bfs-dhcp.network ||
                { echo "BFS DHCP file has the wrong interface name." >&2; exit 1; }
fi

awk '
        /^[[:space:]]*($|#)/ {
                next
        }

        NF != 6 {
                printf "Invalid fstab field count on line %d: %s\n", NR, $0 > "/dev/stderr"
                failed=1
                next
        }

        $1 !~ /^(UUID=|LABEL=|PARTUUID=|PARTLABEL=|\/dev\/)/ {
                printf "Invalid fstab source on line %d: %s\n", NR, $1 > "/dev/stderr"
                failed=1
        }

        $2 != "none" && $2 !~ /^\// {
                printf "Invalid fstab target on line %d: %s\n", NR, $2 > "/dev/stderr"
                failed=1
        }

        $5 !~ /^[0-9]+$/ || $6 !~ /^[0-9]+$/ {
                printf "Invalid dump/pass fields on line %d\n", NR > "/dev/stderr"
                failed=1
        }

        END {
                exit failed
        }
' /etc/fstab ||
        { echo "Generated /etc/fstab failed syntax validation." >&2; exit 1; }

if command -v findmnt >/dev/null 2>&1; then
        findmnt --verify --verbose >/root/bfs-fstab-verify.log 2>&1 || {
                cat /root/bfs-fstab-verify.log >&2
                echo "findmnt verification of the generated fstab failed." >&2
                exit 1
        }
fi

for command in bash sh env sed grep awk find tar gzip xz make gcc g++ ld ar nm strip readelf mount umount ls cp mv rm chmod chown pkgmk pkgadd pkginfo; do
        command -v "$command" >/dev/null 2>&1 || printf 'MISSING COMMAND: %s\n' "$command" >&2
done

cat > /tmp/bfs-test.c <<'EOF_TEST'
#include <stdio.h>
int main(void) { puts("BFS compiler test passed"); return 0; }
EOF_TEST
gcc /tmp/bfs-test.c -o /tmp/bfs-test
/tmp/bfs-test
if gcc -dumpspecs | grep -q '/tmp/lfs-tools'; then
        echo "ERROR: GCC still references /tmp/lfs-tools." >&2
        exit 1
fi
rm -f /tmp/bfs-test /tmp/bfs-test.c

pkginfo -i | sort > /root/base-system.manifest
find /usr/lib/systemd/system /etc/systemd/system -type f -o -type l 2>/dev/null | sort > /root/systemd-units.manifest
ldconfig -p > /root/ldconfig.manifest

log "BFS installation finished successfully"
CHROOT

        sed -i \
                -e "s|__HOSTNAME__|$(printf '%s' "$HOSTNAME" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__TIMEZONE__|$(printf '%s' "$TIMEZONE" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__LOCALE__|$(printf '%s' "$LOCALE" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__USERNAME__|$(printf '%s' "$USERNAME" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__ADDITIONAL_USERS__|$(printf '%s' "$(additional_users_text)" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__BOOT_MODE__|$BOOT_MODE|g" \
                -e "s|__BOOT_DISK__|$(printf '%s' "$BOOT_DISK" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__NETWORK_IFACE__|$(printf '%s' "$NETWORK_IFACE" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__NETWORK_MAC__|$(printf '%s' "$NETWORK_MAC" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__NETWORK_TARGET_NAME__|$(printf '%s' "$NETWORK_TARGET_NAME" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__PACKAGE_LIST__|$(printf '%s' "$package_list" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__ENABLE_OPENSSH__|$ENABLE_OPENSSH|g" \
                -e "s|__INSTALL_GRUB__|$INSTALL_GRUB|g" \
                -e "s|__GRUB_FALLBACK__|$GRUB_FALLBACK|g" \
                -e "s|__KERNEL_PACKAGE__|$KERNEL_PACKAGE|g" \
                -e "s|__INSTALL_SUDO__|$INSTALL_SUDO|g" \
                -e "s|__SUDO_MODE__|$SUDO_MODE|g" \
                -e "s|__INSTALL_NETWORKMANAGER__|$INSTALL_NETWORKMANAGER|g" \
                -e "s|__INSTALL_GPM__|$INSTALL_GPM|g" \
                -e "s|__CONSOLE_VIDEO_ARG__|$(printf '%s' "$CONSOLE_VIDEO_ARG" | sed 's/[&|]/\&/g')|g" \
                -e "s|__INSTALL_CRYPTSETUP__|$INSTALL_CRYPTSETUP|g" \
                -e "s|__AUTO_CRYPTSETUP__|$AUTO_CRYPTSETUP|g" \
                -e "s|__AUTO_LVM2__|$AUTO_LVM2|g" \
                -e "s|__AUTO_MDADM__|$AUTO_MDADM|g" \
                -e "s|__BTRFS_CONFIG_NAMES__|$(printf '%s' "${BTRFS_CONFIG_NAMES[*]}" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__BTRFS_MOUNTPOINTS__|$(printf '%s' "${BTRFS_MOUNTPOINTS[*]}" | sed 's/[&|]/\\&/g')|g" \
                -e "s|__CONSOLE_FONT_SIZE__|$CONSOLE_FONT_SIZE|g" \
                -e "s|__INSTALL_CONSOLE_FONT__|$INSTALL_CONSOLE_FONT|g" \
                -e "s|__ZRAM_SWAP__|$ZRAM_SWAP|g" \
                -e "s|__ZRAM_SIZE_SPEC__|$ZRAM_SIZE_SPEC|g" \
                -e "s|__BUILD_JOBS__|$BUILD_JOBS|g" \
                -e "s|__BUILD_OPT__|$BUILD_OPT|g" \
                -e "s|__BUILD_CCACHE__|$BUILD_CCACHE|g" \
                -e "s|__BUILD_CCACHE_SIZE__|$BUILD_CCACHE_SIZE|g" \
                "$TARGET$CHROOT_INSTALLER"
        chmod 0700 "$TARGET$CHROOT_INSTALLER"
}

INSTALL_CHECKPOINT_DIR="/run/bfs-installer-checkpoints"

checkpoint_reset() {
        rm -rf "$INSTALL_CHECKPOINT_DIR"
        mkdir -p "$INSTALL_CHECKPOINT_DIR"
}

checkpoint_mark() {
        mkdir -p "$INSTALL_CHECKPOINT_DIR"
        : > "$INSTALL_CHECKPOINT_DIR/$1"
}

checkpoint_done() {
        [[ -f "$INSTALL_CHECKPOINT_DIR/$1" ]]
}

show_install_failure_dialog() {
        local status="$1" marker="$TARGET/run/bfs-install-failure" operation="installation/chroot configuration"
        local detail="" failed_url=""
        if [[ -r "$marker" ]]; then
                operation="$(sed -n 's/^operation=//p' "$marker" | head -n1)"
        fi
        if [[ -n "$LOG_FILE" && -r "$LOG_FILE" ]]; then
                detail="$(tail -n 20 "$LOG_FILE" 2>/dev/null || true)"
                failed_url="$(grep -Eo 'https?://[^[:space:]'\"'<>]+' "$LOG_FILE" 2>/dev/null | tail -n1 || true)"
        fi
        local message="Installation operation failed:\n$operation\n\nExit status: $status"
        [[ -z "$failed_url" ]] || message+="\n\nLast URL seen:\n$failed_url"
        [[ -z "$LOG_FILE" ]] || message+="\n\nInstaller log:\n$LOG_FILE"
        [[ -z "$detail" ]] || message+="\n\nLast output:\n$detail"
        dialog_message "Installation operation failed" "$message"
}

run_chroot_installer() {
        local status=0
        log "Entering BFS chroot"
        set +e
        chroot "$TARGET" /usr/bin/env -i \
                HOME=/root \
                TERM="${TERM:-linux}" \
                PATH=/usr/bin:/usr/sbin:/bin:/sbin \
                LANG=C \
                LC_ALL=C \
                /bin/bash "$CHROOT_INSTALLER"
        status=$?
        set -e
        if ((status != 0)); then
                show_install_failure_dialog "$status"
                return "$status"
        fi
        return 0
}


offer_package_cache_cleanup() {
        local answer=no cache_dir="$TARGET/var/cache/pkg/packages"
        ask_yes_no answer \
                "Package installation and system upgrade completed successfully. Clear /var/cache/pkg/packages/* before finishing? Keeping packages is useful for reinstalling or deploying to additional systems." \
                no || answer=no
        [[ "$answer" == yes ]] || return 0
        mkdir -p "$cache_dir"
        find "$cache_dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
        CLEAR_PACKAGE_CACHE=yes
        log "Cleared installed-system binary package cache: /var/cache/pkg/packages/*"
}

show_installation_success_dialog() {
        local root_fs="${ROOT_FORMAT:-unknown}"
        local snapshot_status="Disabled"
        local bootloader_status="Not installed"
        local additional_count="${#ADDITIONAL_USERS[@]}"
        local installed_log="disabled"
        local message=""

        if [[ "$root_fs" == keep && -n "$ROOT_DEV" ]]; then
                root_fs="$(blkid -s TYPE -o value "$ROOT_DEV" 2>/dev/null || printf '%s' existing)"
        fi

        ((${#BTRFS_CONFIG_NAMES[@]} > 0)) && snapshot_status="Enabled"
        [[ "$INSTALL_GRUB" == yes ]] && bootloader_status="GRUB"

        if [[ "$LOG_ENABLED" == yes && -n "$LOG_FILE" ]]; then
                installed_log="/var/log/bfs/installer/$(basename "$LOG_FILE")"
        fi

        message="Congratulations!\n\nYour BFS Linux system installation is complete!\n\nInstallation summary\n--------------------\nHostname:          $HOSTNAME\nKernel package:    $KERNEL_PACKAGE\nBoot mode:         ${BOOT_MODE:-unknown}\nBootloader:        $bootloader_status\nRoot filesystem:   $root_fs\nBtrfs snapshots:   $snapshot_status\nPrimary user:      ${USERNAME:-none}\nAdditional users:  $additional_count\nInstaller log:     $installed_log\n\nWelcome to BFS Linux!"

        if command -v dialog >/dev/null 2>&1 &&
           [[ -r /dev/tty && -w /dev/tty ]]; then
                dialog --clear \
                        --backtitle "BFS Linux Installer" \
                        --title "BFS Linux Installation Complete" \
                        --ok-label "Continue" \
                        --msgbox "$message" \
                        24 76 \
                        </dev/tty >/dev/tty 2>/dev/tty
        else
                clear_screen
                printf '%s\n' '============================================================'
                printf '%s\n' '            BFS Linux Installation Complete'
                printf '%s\n' '============================================================'
                printf '\n%b\n\n' "$message"
                pause_screen
        fi
}

post_install_menu() {
        local choice="" status=0

        while true; do
                set +e
                themed_menu choice \
                        "BFS installation complete" \
                        "The installation completed successfully. You may enter the installed system again or finish and return to the live environment." \
                        16 82 6 \
                        1 "Chroot into the installed BFS system" \
                        2 "Finish and unmount the installed system"
                status=$?
                set -e

                [[ -n "$choice" ]] || choice=2

                case "$choice" in
                        1) chroot_into_target ;;
                        2) return 0 ;;
                        *) warn "Choose a valid post-install option."; sleep 1 ;;
                esac
        done
}

offer_final_chroot() {
        show_installation_success_dialog
        post_install_menu
        # Finish returns directly to the calling shell/bootstrap. Cleanup is
        # handled by the normal EXIT trap without another completion message.
        reset_terminal_ui
}

main() {
        parse_arguments "$@"
        require_root "$@"
        force_posix_locale
        sync_system_clock
        load_installer_settings
        detect_console_video_argument
        if [[ -n "$CONSOLE_FONT_OVERRIDE" ]]; then
                CONSOLE_FONT_SIZE="$CONSOLE_FONT_OVERRIDE"
        else
                CONSOLE_FONT_SIZE="$CONSOLE_FONT_PREFERENCE"
        fi
        setup_installer_theme
        apply_console_font "$CONSOLE_FONT_SIZE"
        report_installer_interface_mode
        setup_logging
        require_commands
        prepare_target_environment
        checkpoint_reset

        while true; do
                while true; do
                        INSTALL_CONFIRMED=no
                        installer_menu
                        validate_settings

                        # Review (option 10) already flows through Ready to install.
                        [[ "$INSTALL_CONFIRMED" == yes ]] && break

                        # Direct option 11 opens Ready to install; Back returns to menu.
                        if confirm_continue "Begin the BFS installation?"; then
                                break
                        fi
                done

                format_selected_partitions
                mount_target_filesystems
                if ! checkpoint_done base_extracted; then
                        extract_rootfs
                        fix_installed_bfsos_branding
                        save_base_archive
                        checkpoint_mark base_extracted
                else
                        log "Resume checkpoint: base archive already extracted; preserving installed target"
                fi
                generate_fstab
                generate_crypttab
                mount_virtual_filesystems
                write_chroot_installer

                if ! run_chroot_installer; then
                        for state in packages_complete system_config_complete bootloader_complete; do
                                [[ -f "$TARGET/var/lib/bfs-installer/$state" ]] && checkpoint_mark "$state"
                        done
                        # Keep the process and UI alive.  Avoid reformatting the
                        # already-created filesystems if the user chooses to retry
                        # after inspecting/fixing a package/download failure.
                        ROOT_FORMAT=keep
                        BOOT_FORMAT=keep
                        EFI_FORMAT=keep
                        SWAP_FORMAT=keep
                        HOME_FORMAT=keep
                        local i
                        for ((i=0; i<${#EXTRA_FORMATS[@]}; i++)); do
                                EXTRA_FORMATS[$i]=keep
                        done
                        INSTALL_CONFIRMED=no
                        dialog_message "Installation paused" \
                                "Installed-system configuration did not complete.\n\nThe target remains mounted and the full log is preserved. You are being returned to the installer menu. Chroot can be used to inspect the target; a retry will preserve existing filesystem formats rather than formatting them again."
                        continue
                fi

                for state in packages_complete system_config_complete bootloader_complete; do
                        [[ -f "$TARGET/var/lib/bfs-installer/$state" ]] && checkpoint_mark "$state"
                done
                offer_package_cache_cleanup
                log "Installation complete"
                offer_final_chroot
                break
        done

        if [[ "$LOG_ENABLED" == yes ]]; then
                printf '\nLive-environment log: %s\n' "$LOG_FILE"
                close_logging 0
                copy_log_to_installed_system
        fi
}

set +e
main "$@"
_main_status=$?
set -e
exit "$_main_status"
