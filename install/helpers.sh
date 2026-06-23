#!/bin/bash
# lib/helpers.sh - Logging, errors, and presentation helpers
# Adapted from omarchy's install/helpers/

# --- TERMINAL SETUP ---

init_helpers() {
    # Get terminal size
    if [[ -e /dev/tty ]]; then
        TERM_SIZE=$(stty size 2>/dev/null </dev/tty || echo "24 80")
        TERM_HEIGHT=$(echo "$TERM_SIZE" | cut -d' ' -f1)
        TERM_WIDTH=$(echo "$TERM_SIZE" | cut -d' ' -f2)
    else
        TERM_WIDTH=80
        TERM_HEIGHT=24
    fi
    export TERM_WIDTH TERM_HEIGHT

    # Logo dimensions
    LOGO_WIDTH=60
    PADDING_LEFT=$(( (TERM_WIDTH - LOGO_WIDTH) / 2 ))
    PADDING_LEFT_SPACES=$(printf "%*s" $PADDING_LEFT "")
    export LOGO_WIDTH PADDING_LEFT PADDING_LEFT_SPACES

    # Gum styling
    export GUM_CONFIRM_PROMPT_FOREGROUND="6"
    export GUM_CONFIRM_SELECTED_FOREGROUND="0"
    export GUM_CONFIRM_SELECTED_BACKGROUND="2"
    export GUM_CONFIRM_UNSELECTED_FOREGROUND="7"
    export GUM_CONFIRM_UNSELECTED_BACKGROUND="0"

    # Set Tokyo Night colors if on real TTY
    if [[ $(tty 2>/dev/null) == "/dev/tty"* ]]; then
        set_tokyo_night_colors
    fi
}

set_tokyo_night_colors() {
    echo -en "\e]P01a1b26"  # black (background)
    echo -en "\e]P1f7768e"  # red
    echo -en "\e]P29ece6a"  # green
    echo -en "\e]P3e0af68"  # yellow
    echo -en "\e]P47aa2f7"  # blue
    echo -en "\e]P5bb9af7"  # magenta
    echo -en "\e]P67dcfff"  # cyan
    echo -en "\e]P7a9b1d6"  # white
    echo -en "\e]P8414868"  # bright black
    echo -en "\e]P9f7768e"  # bright red
    echo -en "\e]PA9ece6a"  # bright green
    echo -en "\e]PBe0af68"  # bright yellow
    echo -en "\e]PC7aa2f7"  # bright blue
    echo -en "\e]PDbb9af7"  # bright magenta
    echo -en "\e]PE7dcfff"  # bright cyan
    echo -en "\e]PFc0caf5"  # bright white (foreground)
    echo -en "\033[0m"
    clear
}

# --- LOGO ---

LOGO='
   ▄████████    ▄████████  ▄████████    ▄█    █▄
  ███    ███   ███    ███ ███    ███   ███    ███
  ███    ███   ███    ███ ███    █▀    ███    ███
  ███    ███  ▄███▄▄▄▄██▀ ███         ▄███▄▄▄▄███▄▄
▀███████████ ▀▀███▀▀▀▀▀   ███        ▀▀███▀▀▀▀███▀
  ███    ███ ▀███████████ ███    █▄    ███    ███
  ███    ███   ███    ███ ███    ███   ███    ███
  ███    █▀    ███    ███ ████████▀    ███    █▀
               ███    ███
                       Wintarch
'

show_logo() {
    gum style --foreground 5 --padding "1 0 0 $PADDING_LEFT" "$LOGO"
}

clear_screen() {
    printf "\033[H\033[2J"
}

# --- LOGGING ---

start_log() {
    touch "$LOG_FILE"
    chmod 666 "$LOG_FILE"
    echo "=== Wintarch Installation Started: $(date) ===" >> "$LOG_FILE"
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

log_info() {
    log "INFO: $*"
    gum style --foreground 4 "ℹ $*" >&2
}

log_success() {
    log "SUCCESS: $*"
    gum style --foreground 2 "✓ $*" >&2
}

log_warn() {
    log "WARN: $*"
    gum style --foreground 3 "⚠ $*" >&2
}

log_error() {
    log "ERROR: $*"
    gum style --foreground 1 "✗ $*" >&2
}

log_step() {
    log "STEP: $*"
    echo >&2
    gum style --foreground 6 --bold "→ $*" >&2
}

# --- ERROR HANDLING ---

ERROR_HANDLING=false

die() {
    log_error "$1"
    echo
    gum style --foreground 1 "Installation failed: $1"
    gum style "Check log file: $LOG_FILE"
    exit 1
}

show_cursor() {
    printf "\033[?25h"
}

cleanup_mounts() {
    # Best-effort cleanup of mounts and LUKS
    umount -R "${MOUNT_POINT:-/mnt/archinstall}" 2>/dev/null || true
    umount -R /mnt 2>/dev/null || true
    cryptsetup close cryptroot 2>/dev/null || true
}

catch_errors() {
    local exit_code=$?  # Capture immediately, before any commands run

    if [[ $ERROR_HANDLING == true ]]; then
        return
    fi
    ERROR_HANDLING=true
    show_cursor

    # Cleanup mounts
    cleanup_mounts

    clear_screen

    # Check if gum is available, fall back to echo if not
    if command -v gum &>/dev/null; then
        show_logo

        gum style --foreground 1 --padding "1 0" "Installation stopped!"
        echo
        gum style "Exit code: $exit_code"
        gum style "Log file: $LOG_FILE"
        echo

        # Show last few log lines
        if [[ -f "$LOG_FILE" ]]; then
            gum style --foreground 8 "Last log entries:"
            tail -10 "$LOG_FILE" | while read -r line; do
                gum style --foreground 8 "  $line"
            done
        fi

        echo
        gum style "Please report issues at:"
        gum style --foreground 4 "https://github.com/kacpersledz/arch/issues"
    else
        echo "=== Installation stopped! ==="
        echo "Exit code: $exit_code"
        echo "Log file: $LOG_FILE"
        echo
        if [[ -f "$LOG_FILE" ]]; then
            echo "Last log entries:"
            tail -10 "$LOG_FILE"
        fi
        echo
        echo "Please report issues at:"
        echo "https://github.com/kacpersledz/arch/issues"
    fi
}

trap catch_errors ERR INT TERM

# --- UTILITY FUNCTIONS ---

confirm() {
    local prompt="$1"
    gum confirm "$prompt"
}

input() {
    local prompt="$1"
    local placeholder="${2:-}"
    local default="${3:-}"

    if [[ -n "$default" ]]; then
        gum input --prompt "$prompt " --placeholder "$placeholder" --value "$default"
    else
        gum input --prompt "$prompt " --placeholder "$placeholder"
    fi
}

input_password() {
    local prompt="$1"
    local placeholder="${2:-Enter password}"
    gum input --prompt "$prompt " --placeholder "$placeholder" --password
}

choose() {
    local header="$1"
    shift
    gum choose --header "$header" "$@"
}

spin() {
    local title="$1"
    shift
    gum spin --spinner pulse --title "$title" -- "$@"
}
