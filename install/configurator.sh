#!/bin/bash
# lib/configurator.sh - TUI for collecting user configuration
# Adapted from omarchy's configurator

# --- KEYBOARD SELECTION ---

select_keyboard() {
    log_step "Keyboard Layout"

    # Common keyboard layouts (subset of omarchy's list)
    local keyboards='English (US)|us
English (UK)|uk
German|de
French|fr
Spanish|es
Italian|it
Portuguese|pt-latin1
Portuguese (Brazil)|br-abnt2
Polish|pl
Russian|ru
Swedish|sv-latin1
Norwegian|no-latin1
Danish|dk-latin1
Finnish|fi
Dutch|nl
Czech|cz
Hungarian|hu
Turkish|trq
Japanese|jp106'

    local choice
    choice=$(printf '%s\n' "$keyboards" | cut -d'|' -f1 | gum choose --height 12 --selected "English (US)" --header "Select keyboard layout")

    KEYBOARD=$(printf '%s\n' "$keyboards" | awk -F'|' -v c="$choice" '$1==c{print $2; exit}')

    # Apply keyboard layout
    if [[ $(tty 2>/dev/null) == "/dev/tty"* ]]; then
        loadkeys "$KEYBOARD" 2>/dev/null || true
    fi

    log_info "Keyboard: $KEYBOARD"
    export KEYBOARD
}

# --- USER ACCOUNT ---

configure_user() {
    log_step "User Account"

    # Username
    while true; do
        USERNAME=$(input "Username>" "lowercase, no spaces (e.g., john)")

        if [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] && [[ ${#USERNAME} -ge 2 ]]; then
            break
        else
            log_warn "Username must be lowercase letters, numbers, dash or underscore"
        fi
    done

    # Password (same for user, root, and LUKS)
    while true; do
        PASSWORD=$(input_password "Password>" "Used for user, root, and disk encryption")

        if [[ -z "$PASSWORD" ]]; then
            log_warn "Password cannot be empty"
            continue
        fi

        if [[ ${#PASSWORD} -lt 4 ]]; then
            log_warn "Password must be at least 4 characters"
            continue
        fi

        local password_confirm
        password_confirm=$(input_password "Confirm>" "Re-enter password")

        if [[ "$PASSWORD" == "$password_confirm" ]]; then
            break
        else
            log_warn "Passwords don't match"
        fi
    done

    # Hash password for archinstall
    PASSWORD_HASH=$(printf '%s' "$PASSWORD" | openssl passwd -6 -stdin)

    log_success "User account configured"
    export USERNAME PASSWORD PASSWORD_HASH
}

# --- SYSTEM SETTINGS ---

configure_system() {
    log_step "System Settings"

    # Hostname
    while true; do
        HOSTNAME=$(input "Hostname>" "Your computer's name" "archlinux")

        if [[ "$HOSTNAME" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
            break
        else
            log_warn "Hostname must be alphanumeric (dashes and underscores allowed)"
        fi
    done

    # Timezone
    local geo_tz=""
    if command -v tzupdate &>/dev/null; then
        geo_tz=$(tzupdate -p 2>/dev/null || true)
    fi

    if [[ -n "$geo_tz" ]]; then
        TIMEZONE=$(timedatectl list-timezones | gum choose --height 12 --selected "$geo_tz" --header "Select timezone")
    else
        TIMEZONE=$(timedatectl list-timezones | gum filter --height 12 --header "Search timezone")
    fi

    log_info "Hostname: $HOSTNAME"
    log_info "Timezone: $TIMEZONE"
    export HOSTNAME TIMEZONE
}

# --- REVIEW CONFIGURATION ---

review_configuration() {
    log_step "Review Configuration"

    echo
    gum style --border rounded --padding "1 2" --border-foreground 6 \
"Configuration Summary

Username:   $USERNAME
Password:   $(printf '%*s' ${#PASSWORD} '' | tr ' ' '*')
Hostname:   $HOSTNAME
Timezone:   $TIMEZONE
Keyboard:   $KEYBOARD
Disk:       $SELECTED_DISK
Mode:       $INSTALL_MODE"

    echo
    if ! confirm "Proceed with installation?"; then
        die "Installation cancelled by user"
    fi
}

# --- MAIN CONFIGURATOR FLOW ---

run_configurator() {
    clear_screen
    show_logo

    gum style --foreground 5 --padding "0 0 1 $PADDING_LEFT" \
        "Welcome to the Wintarch Installer"

    echo

    # Collect configuration
    select_keyboard
    configure_user
    configure_system

    # Disk selection (from disk.sh)
    select_disk
    select_installation_target

    # Review before proceeding
    review_configuration

    log_success "Configuration complete"
}
