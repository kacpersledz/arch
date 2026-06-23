#!/bin/bash
# Wintarch Installer
# Dual-boot capable with LUKS encryption and BTRFS snapshots
#
# Usage: Run from Arch Linux live environment
#        curl -fsSL https://raw.githubusercontent.com/kacpersledz/arch/master/boot.sh | bash

set -eEuo pipefail

# Installation paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOUNT_POINT="/mnt/archinstall"
LOG_FILE="/var/log/wintarch-install.log"

# Source libraries
source "$SCRIPT_DIR/helpers.sh"
source "$SCRIPT_DIR/disk.sh"
source "$SCRIPT_DIR/configurator.sh"
source "$SCRIPT_DIR/partitioning.sh"
source "$SCRIPT_DIR/archinstall.sh"
source "$SCRIPT_DIR/post-install.sh"

# --- MAIN INSTALLATION FLOW ---

main() {
    # Initialize
    init_helpers
    start_log

    # Preflight checks
    preflight_checks

    # Step 1: Collect user configuration via TUI
    run_configurator

    # Step 2: Partition disk (custom, for dual-boot support)
    run_partitioning

    # Step 3: Run archinstall with pre-mounted config
    run_archinstall

    # Step 4: Post-installation setup (limine-snapper, COSMIC)
    run_post_install

    # Done!
    show_completion
}

preflight_checks() {
    # Install required tools FIRST (before using gum for logging)
    echo ":: Installing required tools..."
    pacman -Sy --noconfirm --needed gum jq >/dev/null 2>&1 || {
        echo "ERROR: Failed to install required tools (gum, jq)"
        exit 1
    }

    log_step "Running preflight checks..."

    # Must be root
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root"
    fi

    # Must be UEFI
    if [[ ! -d /sys/firmware/efi ]]; then
        die "UEFI not detected. This installer requires UEFI."
    fi

    # Must be x86_64
    if [[ "$(uname -m)" != "x86_64" ]]; then
        die "Only x86_64 architecture is supported"
    fi

    # Must have network
    if ! ping -c 1 -W 3 archlinux.org &>/dev/null; then
        die "No network connection. Please connect to the internet first."
    fi

    log_success "Preflight checks passed"
}

show_completion() {
    clear_screen
    show_logo

    gum style --foreground 2 --bold --padding "1 0" \
        "Installation Complete!"

    echo
    gum style "Your system is ready. Please reboot to start using COSMIC."
    echo
    gum style "Credentials:"
    gum style "  Username: $USERNAME"
    gum style "  Hostname: $HOSTNAME"
    echo
    gum style --foreground 3 \
        "Remember your LUKS password - it's required at every boot!"
    echo

    if gum confirm "Reboot now?"; then
        reboot
    fi
}

# Run main
main "$@"
