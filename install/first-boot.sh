#!/bin/bash
# First-boot configuration for wintarch
# Runs once on first boot to configure components that need D-Bus
#
# This handles:
# - Snapper configuration (requires D-Bus/snapperd)
# - Initial snapshots
# - BTRFS quota

set -e

MARKER_FILE="/var/lib/wintarch/first-boot-done"
LOG_FILE="/var/log/wintarch/first-boot.log"

# Exit if already completed
if [[ -f "$MARKER_FILE" ]]; then
    echo "First-boot already completed, skipping."
    exit 0
fi

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "=== Wintarch first-boot configuration started ==="

# --- SNAPPER CONFIGURATION ---
configure_snapper() {
    log "Configuring Snapper..."

    # Create snapper config for root if missing
    if ! snapper list-configs 2>/dev/null | grep -q "root"; then
        log "Creating snapper config for root..."
        snapper -c root create-config / 2>&1 | tee -a "$LOG_FILE" || true
    else
        log "Snapper root config already exists"
    fi

    # Create snapper config for home if missing
    if ! snapper list-configs 2>/dev/null | grep -q "home"; then
        log "Creating snapper config for home..."
        snapper -c home create-config /home 2>&1 | tee -a "$LOG_FILE" || true
    else
        log "Snapper home config already exists"
    fi

    # Configure snapper settings
    log "Applying snapper settings..."
    for config in root home; do
        if [[ -f /etc/snapper/configs/$config ]]; then
            # Disable timeline snapshots (manual/pacman only)
            sed -i 's/^TIMELINE_CREATE="yes"/TIMELINE_CREATE="no"/' /etc/snapper/configs/$config

            # Limit number of snapshots
            sed -i 's/^NUMBER_LIMIT="50"/NUMBER_LIMIT="5"/' /etc/snapper/configs/$config
            sed -i 's/^NUMBER_LIMIT_IMPORTANT="10"/NUMBER_LIMIT_IMPORTANT="5"/' /etc/snapper/configs/$config

            # Space limits
            sed -i 's/^SPACE_LIMIT="0.5"/SPACE_LIMIT="0.3"/' /etc/snapper/configs/$config
            sed -i 's/^FREE_LIMIT="0.2"/FREE_LIMIT="0.3"/' /etc/snapper/configs/$config
        fi
    done

    # Enable btrfs quota for space-aware cleanup
    log "Enabling btrfs quota..."
    btrfs quota enable / 2>&1 | tee -a "$LOG_FILE" || true

    # Enable automatic cleanup for number snapshots.
    # Timeline snapshots remain disabled via TIMELINE_CREATE above.
    log "Enabling snapper cleanup timer..."
    systemctl enable --now snapper-cleanup.timer 2>&1 | tee -a "$LOG_FILE" || true

    log "Snapper configuration complete"
}

# --- INITIAL SNAPSHOTS ---
create_initial_snapshots() {
    log "Creating initial snapshots..."

    # Create snapshot for root
    if snapper list-configs 2>/dev/null | grep -q "root"; then
        snapper -c root create -c number -d "Fresh Install" 2>&1 | tee -a "$LOG_FILE" || true
        log "Root snapshot created"
    fi

    # Create snapshot for home
    if snapper list-configs 2>/dev/null | grep -q "home"; then
        snapper -c home create -c number -d "Fresh Install" 2>&1 | tee -a "$LOG_FILE" || true
        log "Home snapshot created"
    fi

    log "Initial snapshots complete"
}

# --- MAIN ---
main() {
    configure_snapper
    create_initial_snapshots

    # Mark as complete
    mkdir -p "$(dirname "$MARKER_FILE")"
    touch "$MARKER_FILE"

    log "=== Wintarch first-boot configuration completed ==="
}

main "$@"
