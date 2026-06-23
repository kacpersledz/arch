#!/bin/bash
# Migration: Remove explicitly approved legacy desktop runtime packages.
# Date: 2026-06-23
# User configuration and the SDDM package are intentionally preserved.

set -euo pipefail

WINTARCH_PATH="${WINTARCH_PATH:-/opt/wintarch}"
CLEANUP_CANDIDATES=(
    cosmic
    cosmic-greeter
    xdg-desktop-portal-cosmic
    win11-clipboard-history-bin
)
KEY_PLASMA_PACKAGES=(
    plasma-desktop
    plasma-workspace
    plasma-login-manager
    xdg-desktop-portal-kde
    powerdevil
    plasma-nm
    bluedevil
)
PROTECTED_PACKAGES=(
    plasma-desktop
    plasma-workspace
    plasma-login-manager
    xdg-desktop-portal
    xdg-desktop-portal-kde
    powerdevil
    plasma-nm
    bluedevil
    NetworkManager
    networkmanager
    pipewire
    wireplumber
    bluez
    bluez-utils
    limine
    snapper
    btrfs-progs
    cryptsetup
    linux
    linux-firmware
    base
    sudo
    git
    pacman
    systemd
    glibc
    filesystem
    bash
    coreutils
)

SNAPSHOT_CREATED=false
PLASMA_PREFLIGHT_PASSED=false
COSMIC_GREETER_DISABLED=false
PLASMALOGIN_ENABLED=false
ALIAS_VERIFIED=false
CLIPBOARD_WAS_INSTALLED=false
SDDM_INSTALLED=false
declare -a INSTALLED_CLEANUP=()
declare -a INSTALLED_COSMIC=()
declare -a ADDITIONAL_COSMIC=()
declare -a ADDITIONAL_COSMIC_PRESERVED=()
declare -a REMOVAL_PLAN=()
declare -a REMOVED_PACKAGES=()
declare -a MISSING_PLASMA=()

join_by_space() {
    if [[ $# -eq 0 ]]; then
        printf '%s' "none"
    else
        printf '%s ' "$@"
    fi
}

unit_status() {
    local unit="$1"
    local status

    status="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    if [[ -z "$status" ]]; then
        status="not-found"
    fi
    printf '%s\n' "$status"
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

alias_targets_plasmalogin() {
    local alias_target
    alias_target="$(read_display_manager_alias)"
    [[ "$alias_target" != "none" && "$(basename "$alias_target")" == "plasmalogin.service" ]]
}

detect_cleanup_packages() {
    local package installed_package
    local -a cosmic_group_packages=()
    declare -A cosmic_seen=()

    mapfile -t cosmic_group_packages < <(pacman -Qg cosmic 2>/dev/null | awk '{ print $2 }')
    if [[ ${#cosmic_group_packages[@]} -gt 0 ]]; then
        INSTALLED_CLEANUP+=(cosmic)
        for package in "${cosmic_group_packages[@]}"; do
            cosmic_seen["$package"]=1
            INSTALLED_COSMIC+=("$package")
        done
    fi

    for package in "${CLEANUP_CANDIDATES[@]}"; do
        [[ "$package" != "cosmic" ]] || continue
        if pacman -Q "$package" &>/dev/null; then
            INSTALLED_CLEANUP+=("$package")
            if [[ "$package" == "win11-clipboard-history-bin" ]]; then
                CLIPBOARD_WAS_INSTALLED=true
            elif [[ -z "${cosmic_seen[$package]:-}" ]]; then
                cosmic_seen["$package"]=1
                INSTALLED_COSMIC+=("$package")
            fi
        fi
    done

    while IFS= read -r installed_package; do
        case "$installed_package" in
            cosmic|cosmic-greeter|xdg-desktop-portal-cosmic)
                ;;
            cosmic-*)
                ADDITIONAL_COSMIC+=("$installed_package")
                ;;
        esac
    done < <(pacman -Qq 2>/dev/null)
}

preflight() {
    local package plasmalogin_status alias_target cosmic_status sddm_status

    echo "=== Wintarch Legacy Desktop Runtime Cleanup ==="

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

    detect_cleanup_packages
    pacman -Q sddm &>/dev/null && SDDM_INSTALLED=true

    plasmalogin_status="$(unit_status plasmalogin.service)"
    cosmic_status="$(unit_status cosmic-greeter.service)"
    sddm_status="$(unit_status sddm.service)"
    alias_target="$(read_display_manager_alias)"

    for package in "${KEY_PLASMA_PACKAGES[@]}"; do
        if ! pacman -Q "$package" &>/dev/null; then
            MISSING_PLASMA+=("$package")
        fi
    done

    echo "Current display manager state:"
    echo "  plasmalogin.service: $plasmalogin_status"
    echo "  display-manager.service: $alias_target"
    echo "  cosmic-greeter.service: $cosmic_status"
    echo "  sddm.service: $sddm_status"
    echo "Detected cleanup packages: $(join_by_space "${INSTALLED_CLEANUP[@]}")"
    echo "Detected COSMIC cleanup packages: $(join_by_space "${INSTALLED_COSMIC[@]}")"
    echo "win11-clipboard-history-bin installed: $CLIPBOARD_WAS_INSTALLED"
    echo "Detected additional COSMIC packages (report only): $(join_by_space "${ADDITIONAL_COSMIC[@]}")"
    echo "Installed key Plasma packages:"
    for package in "${KEY_PLASMA_PACKAGES[@]}"; do
        if pacman -Q "$package" &>/dev/null; then
            echo "  $package: installed"
        else
            echo "  $package: MISSING"
        fi
    done

    if [[ ${#MISSING_PLASMA[@]} -gt 0 ]]; then
        echo "ERROR: Required Plasma packages are missing: $(join_by_space "${MISSING_PLASMA[@]}")" >&2
        echo "Run PR3 / the Plasma login migration before legacy cleanup. No packages were removed." >&2
        exit 1
    fi
    if ! unit_is_enabled plasmalogin.service; then
        echo "ERROR: plasmalogin.service is not enabled." >&2
        echo "Run PR3 / the Plasma login migration before legacy cleanup. No packages were removed." >&2
        exit 1
    fi
    if ! alias_targets_plasmalogin; then
        echo "ERROR: display-manager.service does not point to plasmalogin.service: $alias_target" >&2
        echo "Run PR3 / the Plasma login migration before legacy cleanup. No packages were removed." >&2
        exit 1
    fi

    if unit_is_enabled sddm.service; then
        echo "WARNING: sddm.service is still enabled. Its package will be preserved."
    fi

    PLASMA_PREFLIGHT_PASSED=true
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
    if ! "$snapshot_command" create "pre legacy desktop runtime cleanup"; then
        echo "ERROR: Snapshot creation failed. No cleanup changes were made." >&2
        exit 1
    fi
    SNAPSHOT_CREATED=true
}

build_and_validate_removal_plan() {
    local plan_output package protected

    if [[ ${#INSTALLED_CLEANUP[@]} -eq 0 ]]; then
        return
    fi

    echo "Calculating pacman removal transaction..."
    # pacman rejects --nosave (-n) together with --print. Omitting -n changes
    # only .pacsave handling, not the package set calculated for removal.
    if ! plan_output="$(pacman -Rs --print --print-format '%n' "${INSTALLED_CLEANUP[@]}")"; then
        echo "ERROR: pacman could not calculate a safe removal transaction. No packages were removed." >&2
        exit 1
    fi
    while IFS= read -r package; do
        [[ -n "$package" ]] && REMOVAL_PLAN+=("$package")
    done <<< "$plan_output"

    if [[ ${#REMOVAL_PLAN[@]} -eq 0 ]]; then
        echo "ERROR: pacman returned an empty removal plan for installed cleanup packages." >&2
        exit 1
    fi

    echo "Full pacman removal plan: $(join_by_space "${REMOVAL_PLAN[@]}")"
    for package in "${REMOVAL_PLAN[@]}"; do
        for protected in "${PROTECTED_PACKAGES[@]}"; do
            if [[ "$package" == "$protected" ]]; then
                echo "ERROR: Removal plan contains protected package: $package" >&2
                echo "Full blocked plan: $(join_by_space "${REMOVAL_PLAN[@]}")" >&2
                echo "No packages were removed." >&2
                exit 1
            fi
        done
    done
}

disable_cosmic_greeter() {
    if unit_is_enabled cosmic-greeter.service; then
        systemctl disable cosmic-greeter.service
        COSMIC_GREETER_DISABLED=true
    fi
}

remove_legacy_packages() {
    if [[ ${#INSTALLED_CLEANUP[@]} -eq 0 ]]; then
        echo "No explicitly approved legacy packages are installed."
        return
    fi

    pacman -Rns --noconfirm "${INSTALLED_CLEANUP[@]}"
    REMOVED_PACKAGES=("${REMOVAL_PLAN[@]}")
}

verify_display_manager_after_cleanup() {
    systemctl daemon-reload

    if ! unit_is_enabled plasmalogin.service || ! alias_targets_plasmalogin; then
        echo "WARNING: Plasma Login Manager state changed during cleanup; attempting to restore its enablement."
        systemctl enable plasmalogin.service || true
        systemctl daemon-reload
    fi

    if ! unit_is_enabled plasmalogin.service; then
        echo "ERROR: plasmalogin.service is not enabled after cleanup." >&2
        echo "Rollback using the pre-cleanup Snapper snapshot before rebooting." >&2
        exit 1
    fi
    PLASMALOGIN_ENABLED=true

    if ! alias_targets_plasmalogin; then
        echo "ERROR: display-manager.service does not point to plasmalogin.service after cleanup: $(read_display_manager_alias)" >&2
        echo "Rollback using the pre-cleanup Snapper snapshot before rebooting." >&2
        exit 1
    fi
    ALIAS_VERIFIED=true
}

print_summary() {
    local package

    ADDITIONAL_COSMIC_PRESERVED=()
    for package in "${ADDITIONAL_COSMIC[@]}"; do
        if pacman -Q "$package" &>/dev/null; then
            ADDITIONAL_COSMIC_PRESERVED+=("$package")
        fi
    done

    echo
    echo "=== Legacy Desktop Runtime Cleanup Summary ==="
    echo "  Snapshot created: $SNAPSHOT_CREATED"
    echo "  Plasma login preflight passed: $PLASMA_PREFLIGHT_PASSED"
    echo "  Installed COSMIC cleanup packages: $(join_by_space "${INSTALLED_COSMIC[@]}")"
    echo "  win11-clipboard-history-bin was installed: $CLIPBOARD_WAS_INSTALLED"
    echo "  Packages removed by pacman: $(join_by_space "${REMOVED_PACKAGES[@]}")"
    echo "  Additional COSMIC packages detected (not explicit targets): $(join_by_space "${ADDITIONAL_COSMIC[@]}")"
    echo "  Additional COSMIC packages still installed: $(join_by_space "${ADDITIONAL_COSMIC_PRESERVED[@]}")"
    echo "  cosmic-greeter.service disabled: $COSMIC_GREETER_DISABLED"
    echo "  plasmalogin.service enabled: $PLASMALOGIN_ENABLED"
    echo "  display-manager.service alias verified: $ALIAS_VERIFIED ($(read_display_manager_alias))"
    echo "  SDDM package preserved: $SDDM_INSTALLED"
    echo
    echo "User COSMIC configuration under ~/.config/cosmic was preserved."
    echo "User configuration for the legacy clipboard manager was preserved."
    echo "The SDDM package was not removed."
    echo "No display manager was restarted and no reboot was performed."
    echo "Reboot or log out and back in if any removed legacy components are still running."
}

main() {
    preflight
    build_and_validate_removal_plan

    if [[ ${#INSTALLED_CLEANUP[@]} -eq 0 ]] && ! unit_is_enabled cosmic-greeter.service; then
        PLASMALOGIN_ENABLED=true
        ALIAS_VERIFIED=true
        echo "Nothing to clean up; the system is already in the target state."
        print_summary
        exit 0
    fi

    create_safety_snapshot
    disable_cosmic_greeter
    remove_legacy_packages
    verify_display_manager_after_cleanup
    print_summary
}

main "$@"
