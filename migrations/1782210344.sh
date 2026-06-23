#!/bin/bash
# Migration: Move existing Wintarch installations to the Plasma login stack.
# Date: 2026-06-23
# COSMIC and SDDM packages are intentionally retained for rollback.

set -euo pipefail

WINTARCH_PATH="${WINTARCH_PATH:-/opt/wintarch}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_FILE="$SCRIPT_DIR/../install/packages/plasma.txt"
FIRST_BOOT_SOURCE="$SCRIPT_DIR/../systemd/wintarch-first-boot.service"
FIRST_BOOT_TARGET="/etc/systemd/system/wintarch-first-boot.service"
DM_UNITS=(
    cosmic-greeter.service
    sddm.service
    plasmalogin.service
    gdm.service
    lightdm.service
    lxdm.service
)
KEY_PACKAGES=(
    plasma-login-manager
    plasma-desktop
    plasma-workspace
    xdg-desktop-portal-kde
    powerdevil
    plasma-nm
    bluedevil
)

SNAPSHOT_CREATED=false
SDDM_INSTALLED=false
COSMIC_PACKAGES_PRESERVED=false
PLASMALOGIN_ENABLED=false
ALIAS_VERIFIED=false
CURRENT_DM="none"
CURRENT_ALIAS="none"
declare -a ENABLED_DMS=()
declare -a DISABLED_DMS=()
declare -a BASELINE_SPECS=()
declare -a BASELINE_PACKAGES=()
declare -a ALREADY_INSTALLED=()
declare -a PACKAGES_TO_INSTALL=()
declare -a COSMIC_PACKAGES=()

join_by_space() {
    if [[ $# -eq 0 ]]; then
        printf '%s' "none"
    else
        printf '%s ' "$@"
    fi
}

unit_exists() {
    systemctl list-unit-files "$1" --no-legend 2>/dev/null | grep -q "^$1"
}

unit_is_enabled() {
    systemctl is-enabled --quiet "$1" 2>/dev/null
}

read_display_manager_alias() {
    if [[ -L /etc/systemd/system/display-manager.service ]]; then
        readlink -f /etc/systemd/system/display-manager.service
    else
        printf '%s\n' "none"
    fi
}

load_package_specs() {
    [[ -f "$PACKAGE_FILE" ]] || {
        echo "ERROR: Shared Plasma package baseline not found: $PACKAGE_FILE" >&2
        exit 1
    }

    while IFS= read -r package; do
        [[ -n "$package" && "$package" != \#* ]] || continue
        BASELINE_SPECS+=("$package")
    done < "$PACKAGE_FILE"
}

expand_package_specs() {
    local spec package
    declare -A seen=()

    for spec in "${BASELINE_SPECS[@]}"; do
        if pacman -Sg "$spec" &>/dev/null; then
            while IFS= read -r package; do
                [[ -n "$package" && -z "${seen[$package]:-}" ]] || continue
                seen["$package"]=1
                BASELINE_PACKAGES+=("$package")
            done < <(pacman -Sgq "$spec")
        elif [[ -z "${seen[$spec]:-}" ]]; then
            seen["$spec"]=1
            BASELINE_PACKAGES+=("$spec")
        fi
    done
}

preflight() {
    echo "=== Wintarch Plasma Login Migration ==="

    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: This migration must run as root." >&2
        exit 1
    fi
    command -v pacman &>/dev/null || {
        echo "ERROR: pacman is required." >&2
        exit 1
    }
    command -v systemctl &>/dev/null || {
        echo "ERROR: systemctl is required." >&2
        exit 1
    }
    if [[ ! -d /run/systemd/system ]] || ! systemctl show --property=Version --value &>/dev/null; then
        echo "ERROR: A running systemd system instance is required." >&2
        exit 1
    fi

    mapfile -t COSMIC_PACKAGES < <(pacman -Qq 2>/dev/null | grep -E '^(cosmic($|-)|xdg-desktop-portal-cosmic$)' || true)
    mapfile -t plasma_packages < <(pacman -Qq 2>/dev/null | grep '^plasma' || true)

    pacman -Q sddm &>/dev/null && SDDM_INSTALLED=true
    [[ ${#COSMIC_PACKAGES[@]} -gt 0 ]] && COSMIC_PACKAGES_PRESERVED=true

    CURRENT_ALIAS="$(read_display_manager_alias)"
    if [[ "$CURRENT_ALIAS" != "none" ]]; then
        CURRENT_DM="$(basename "$CURRENT_ALIAS")"
    fi

    echo "Current state:"
    echo "  COSMIC packages: $(join_by_space "${COSMIC_PACKAGES[@]}")"
    echo "  Plasma packages: $(join_by_space "${plasma_packages[@]}")"
    echo "  sddm package: $SDDM_INSTALLED"
    echo "  plasma-login-manager package: $(pacman -Q plasma-login-manager &>/dev/null && echo true || echo false)"
    echo "  display-manager.service: $CURRENT_ALIAS"
    echo "  display manager units:"

    local unit status
    for unit in "${DM_UNITS[@]}"; do
        if unit_exists "$unit"; then
            status="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
            [[ -n "$status" ]] || status="disabled"
            echo "    $unit: present, $status"
            if unit_is_enabled "$unit"; then
                ENABLED_DMS+=("$unit")
                [[ "$CURRENT_DM" == "none" ]] && CURRENT_DM="$unit"
            fi
        else
            echo "    $unit: not present"
        fi
    done

    if [[ "$CURRENT_DM" != "none" && "$CURRENT_DM" != "plasmalogin.service" ]]; then
        local known=false
        for unit in "${DM_UNITS[@]}"; do
            [[ "$unit" == "$CURRENT_DM" ]] && known=true
        done
        if [[ "$known" == "false" && "$CURRENT_DM" =~ ^[A-Za-z0-9_.@-]+\.service$ ]]; then
            echo "    $CURRENT_DM: detected through display-manager.service alias"
            DM_UNITS+=("$CURRENT_DM")
        fi
    fi
}

create_safety_snapshot() {
    local snapshot_command=""
    local config_count=0

    if command -v snapper &>/dev/null; then
        config_count="$(snapper --csvout list-configs 2>/dev/null | awk -F, 'NR > 1 && $1 != "" { count++ } END { print count + 0 }')"
    fi

    if command -v wintarch-snapshot &>/dev/null; then
        snapshot_command="$(command -v wintarch-snapshot)"
    elif [[ -x "$WINTARCH_PATH/bin/wintarch-snapshot" ]]; then
        snapshot_command="$WINTARCH_PATH/bin/wintarch-snapshot"
    fi

    if [[ -z "$snapshot_command" || ! -x "$snapshot_command" ]] || ! command -v snapper &>/dev/null || [[ "$config_count" -eq 0 ]]; then
        echo "ERROR: A working wintarch-snapshot command and at least one Snapper configuration are required." >&2
        echo "Fix snapshot support before retrying this migration." >&2
        exit 1
    fi

    echo "Creating safety snapshot..."
    if ! "$snapshot_command" create "pre Plasma login migration"; then
        echo "ERROR: Snapshot creation failed. No system changes were made." >&2
        exit 1
    fi
    SNAPSHOT_CREATED=true
}

install_plasma_baseline() {
    local package

    load_package_specs
    expand_package_specs

    for package in "${BASELINE_PACKAGES[@]}"; do
        if pacman -Q "$package" &>/dev/null; then
            ALREADY_INSTALLED+=("$package")
        else
            PACKAGES_TO_INSTALL+=("$package")
        fi
    done

    echo "Plasma baseline specs from $PACKAGE_FILE: $(join_by_space "${BASELINE_SPECS[@]}")"
    echo "Already installed: $(join_by_space "${ALREADY_INSTALLED[@]}")"
    echo "Packages to install: $(join_by_space "${PACKAGES_TO_INSTALL[@]}")"

    if [[ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]]; then
        pacman -S --needed --noconfirm "${BASELINE_SPECS[@]}"
    else
        echo "Full Plasma baseline is already installed."
    fi

    for package in "${BASELINE_PACKAGES[@]}"; do
        if ! pacman -Q "$package" &>/dev/null; then
            echo "ERROR: Plasma baseline package is missing after installation: $package" >&2
            echo "Display manager services were not changed." >&2
            exit 1
        fi
    done

    for package in "${KEY_PACKAGES[@]}"; do
        if ! pacman -Q "$package" &>/dev/null; then
            echo "ERROR: Required package is missing after installation: $package" >&2
            echo "Display manager services were not changed." >&2
            exit 1
        fi
    done
}

restore_previous_display_manager() {
    if [[ "$CURRENT_DM" == "plasmalogin.service" ]]; then
        systemctl enable plasmalogin.service &>/dev/null || true
        return
    fi

    systemctl disable plasmalogin.service &>/dev/null || true
    if [[ "$CURRENT_DM" != "none" ]] && unit_exists "$CURRENT_DM"; then
        if systemctl enable "$CURRENT_DM"; then
            echo "Restored previous display manager after switch failure: $CURRENT_DM" >&2
        else
            echo "WARNING: Could not restore previous display manager: $CURRENT_DM" >&2
        fi
    fi
}

check_first_boot_service() {
    if [[ -f "$FIRST_BOOT_TARGET" ]] && grep -q '^Before=plasmalogin.service display-manager.service$' "$FIRST_BOOT_TARGET"; then
        echo "First-boot service already orders itself before Plasma Login Manager."
        return
    fi

    echo "WARNING: Existing-system updates do not synchronize systemd unit files from the repository."
    echo "WARNING: Review source $FIRST_BOOT_SOURCE and target $FIRST_BOOT_TARGET."
    echo "WARNING: The target should contain: Before=plasmalogin.service display-manager.service"
}

switch_display_manager() {
    local unit

    for unit in "${DM_UNITS[@]}"; do
        [[ "$unit" != "plasmalogin.service" ]] || continue
        if unit_is_enabled "$unit"; then
            systemctl disable "$unit"
            DISABLED_DMS+=("$unit")
        fi
    done

    if ! systemctl enable plasmalogin.service; then
        restore_previous_display_manager
        echo "ERROR: Failed to enable plasmalogin.service." >&2
        exit 1
    fi
    systemctl daemon-reload

    if ! unit_is_enabled plasmalogin.service; then
        restore_previous_display_manager
        echo "ERROR: plasmalogin.service is not enabled after migration." >&2
        exit 1
    fi
    PLASMALOGIN_ENABLED=true

    local final_alias
    final_alias="$(read_display_manager_alias)"
    if [[ "$final_alias" == "none" || "$(basename "$final_alias")" != "plasmalogin.service" ]]; then
        restore_previous_display_manager
        echo "ERROR: display-manager.service does not point to plasmalogin.service: $final_alias" >&2
        exit 1
    fi
    ALIAS_VERIFIED=true

    if [[ "$CURRENT_DM" == "sddm.service" ]]; then
        echo "Detected SDDM as current display manager; switched to plasmalogin.service. SDDM package was left installed for rollback."
    fi
    if [[ "$CURRENT_DM" == "cosmic-greeter.service" ]]; then
        echo "Detected COSMIC Greeter as current display manager; switched to plasmalogin.service. COSMIC packages were left installed for rollback."
    fi
}

print_summary() {
    local final_alias
    final_alias="$(read_display_manager_alias)"

    echo
    echo "=== Plasma Login Migration Summary ==="
    echo "  Snapshot created: $SNAPSHOT_CREATED"
    echo "  Plasma packages already present: $(join_by_space "${ALREADY_INSTALLED[@]}")"
    echo "  Plasma packages installed: $(join_by_space "${PACKAGES_TO_INSTALL[@]}")"
    echo "  Display manager before migration: $CURRENT_DM ($CURRENT_ALIAS)"
    echo "  Display manager services disabled: $(join_by_space "${DISABLED_DMS[@]}")"
    echo "  plasmalogin.service enabled: $PLASMALOGIN_ENABLED"
    echo "  display-manager.service alias verified: $ALIAS_VERIFIED ($final_alias)"
    echo "  COSMIC packages preserved: $COSMIC_PACKAGES_PRESERVED"
    echo "  SDDM package preserved: $SDDM_INSTALLED"
    echo
    echo "COSMIC and SDDM packages were intentionally not removed; legacy cleanup is a separate change."
    echo "No display manager was restarted and no reboot was performed."
    echo "Reboot, or manually log out and back in, to enter the Plasma login stack."
}

main() {
    preflight
    create_safety_snapshot
    install_plasma_baseline
    check_first_boot_service
    switch_display_manager
    print_summary
}

main "$@"
