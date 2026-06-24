#!/bin/bash
# Migration: Enable hibernation on existing standard Wintarch installs.
# Date: 2026-06-24

set -euo pipefail

LEGACY_MKINITCPIO_CONF="/etc/mkinitcpio.conf.d/arch-cosmic.conf"
PREFERRED_MKINITCPIO_CONF="/etc/mkinitcpio.conf.d/wintarch.conf"
LIMINE_DEFAULTS="/etc/default/limine"
CRYPTROOT_DEVICE="/dev/mapper/cryptroot"
SWAP_MOUNTPOINT="/swap"
SWAPFILE="/swap/swapfile"

MKINITCPIO_CONF=""
ROOT_SOURCE=""
SWAP_SOURCE=""
RESUME_OFFSET=""
HOOKS_LINE_NUMBER=""
HOOKS_LINE=""
HOOKS_CONTENT=""
HOOKS_UPDATED_LINE=""
LIMINE_LINE_NUMBER=""
LIMINE_CMDLINE_LINE=""
LIMINE_CMDLINE_CONTENT=""
LIMINE_UPDATED_LINE=""

CONFIG_RENAMED=false
LEGACY_DUPLICATE_REMOVED=false
HOOKS_UPDATED=false
LIMINE_UPDATED=false
LIMINE_REFRESHED=false
MKINITCPIO_ACTION="use-preferred"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

rewrite_line() {
    local file="$1"
    local line_number="$2"
    local replacement="$3"
    local tmp_file

    tmp_file="$(mktemp)"
    awk -v target="$line_number" -v replacement="$replacement" '
        NR == target { print replacement; next }
        { print }
    ' "$file" >"$tmp_file"
    mv "$tmp_file" "$file"
}

require_root() {
    [[ $EUID -eq 0 ]] || fail "This migration must run as root."
}

require_command() {
    command -v "$1" &>/dev/null || fail "Required command not found: $1"
}

inspect_mkinitcpio_config() {
    local legacy_exists=false
    local preferred_exists=false

    [[ -f "$LEGACY_MKINITCPIO_CONF" ]] && legacy_exists=true
    [[ -f "$PREFERRED_MKINITCPIO_CONF" ]] && preferred_exists=true

    if [[ "$legacy_exists" == "true" && "$preferred_exists" == "false" ]]; then
        MKINITCPIO_ACTION="rename-legacy"
        MKINITCPIO_CONF="$LEGACY_MKINITCPIO_CONF"
        return
    fi

    if [[ "$legacy_exists" == "false" && "$preferred_exists" == "true" ]]; then
        MKINITCPIO_ACTION="use-preferred"
        MKINITCPIO_CONF="$PREFERRED_MKINITCPIO_CONF"
        return
    fi

    if [[ "$legacy_exists" == "true" && "$preferred_exists" == "true" ]]; then
        if cmp -s "$LEGACY_MKINITCPIO_CONF" "$PREFERRED_MKINITCPIO_CONF"; then
            MKINITCPIO_ACTION="remove-legacy-duplicate"
            MKINITCPIO_CONF="$PREFERRED_MKINITCPIO_CONF"
            return
        fi

        fail "Both mkinitcpio configs exist and differ: $LEGACY_MKINITCPIO_CONF and $PREFERRED_MKINITCPIO_CONF"
    fi

    fail "Expected mkinitcpio config not found at $LEGACY_MKINITCPIO_CONF or $PREFERRED_MKINITCPIO_CONF"
}

apply_mkinitcpio_normalization() {
    case "$MKINITCPIO_ACTION" in
        rename-legacy)
            mv "$LEGACY_MKINITCPIO_CONF" "$PREFERRED_MKINITCPIO_CONF"
            CONFIG_RENAMED=true
            MKINITCPIO_CONF="$PREFERRED_MKINITCPIO_CONF"
            ;;
        remove-legacy-duplicate)
            rm -f "$LEGACY_MKINITCPIO_CONF"
            LEGACY_DUPLICATE_REMOVED=true
            MKINITCPIO_CONF="$PREFERRED_MKINITCPIO_CONF"
            ;;
        use-preferred)
            ;;
        *)
            fail "Unsupported mkinitcpio normalization action: $MKINITCPIO_ACTION"
            ;;
    esac
}

verify_layout() {
    local root_fstype
    local swap_fstype
    local swap_options

    [[ -e "$CRYPTROOT_DEVICE" ]] || fail "$CRYPTROOT_DEVICE does not exist."

    root_fstype="$(findmnt -no FSTYPE /)"
    [[ "$root_fstype" == "btrfs" ]] || fail "Root filesystem is not BTRFS."

    ROOT_SOURCE="$(findmnt -no SOURCE /)"
    [[ "$ROOT_SOURCE" == *"$CRYPTROOT_DEVICE"* ]] || fail "Root is not mounted from $CRYPTROOT_DEVICE."

    findmnt -rn -M "$SWAP_MOUNTPOINT" &>/dev/null || fail "$SWAP_MOUNTPOINT is not mounted."

    swap_fstype="$(findmnt -no FSTYPE -M "$SWAP_MOUNTPOINT")"
    [[ "$swap_fstype" == "btrfs" ]] || fail "$SWAP_MOUNTPOINT is not a BTRFS mount."

    SWAP_SOURCE="$(findmnt -no SOURCE -M "$SWAP_MOUNTPOINT")"
    [[ "$SWAP_SOURCE" == *"$CRYPTROOT_DEVICE"* ]] || fail "$SWAP_MOUNTPOINT is not mounted from $CRYPTROOT_DEVICE."

    swap_options="$(findmnt -no OPTIONS -M "$SWAP_MOUNTPOINT")"
    [[ "$swap_options" =~ (^|,)subvol=/?@swap($|,) ]] || fail "$SWAP_MOUNTPOINT is not mounted from the expected @swap subvolume."

    [[ -f "$SWAPFILE" ]] || fail "Swapfile not found: $SWAPFILE"
    [[ -f "$LIMINE_DEFAULTS" ]] || fail "Limine defaults file not found: $LIMINE_DEFAULTS"
    [[ -d /boot ]] || fail "/boot does not exist."

    if ! findmnt -rn -M /boot &>/dev/null && [[ ! -f /boot/limine.conf && ! -d /boot/EFI ]]; then
        fail "/boot is not mounted separately and does not look like a usable Limine boot path."
    fi
}

load_hooks_line() {
    local hook_matches
    local hooks_regex='^[[:space:]]*HOOKS=\(([^)]*)\)[[:space:]]*$'

    mapfile -t hook_matches < <(awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*HOOKS=\(/ { print NR ":" $0 }
    ' "$MKINITCPIO_CONF")

    [[ ${#hook_matches[@]} -eq 1 ]] || fail "Expected exactly one classic HOOKS=(...) line in $MKINITCPIO_CONF."

    HOOKS_LINE_NUMBER="${hook_matches[0]%%:*}"
    HOOKS_LINE="${hook_matches[0]#*:}"
    HOOKS_CONTENT="${HOOKS_LINE%%#*}"

    [[ "$HOOKS_CONTENT" =~ $hooks_regex ]] || fail "Unsupported HOOKS format in $MKINITCPIO_CONF."
    HOOKS_CONTENT="${BASH_REMATCH[1]}"
}

validate_hooks_support() {
    local hooks=()
    local hook

    load_hooks_line
    read -r -a hooks <<<"$HOOKS_CONTENT"

    [[ " ${hooks[*]} " == *" encrypt "* ]] || fail "Expected classic encrypt hook in $MKINITCPIO_CONF."

    for hook in "${hooks[@]}"; do
        if [[ "$hook" == "systemd" || "$hook" == "sd-encrypt" ]]; then
            fail "Unsupported systemd-style initramfs hooks detected in $MKINITCPIO_CONF."
        fi
    done
}

update_hooks() {
    local hooks=()
    local hook
    local found_encrypt=false
    local inserted_resume=false
    local new_hooks=()

    validate_hooks_support
    read -r -a hooks <<<"$HOOKS_CONTENT"

    for hook in "${hooks[@]}"; do
        [[ "$hook" == "resume" ]] && continue
        new_hooks+=("$hook")
        if [[ "$hook" == "encrypt" ]]; then
            found_encrypt=true
            if [[ "$inserted_resume" == "false" ]]; then
                new_hooks+=("resume")
                inserted_resume=true
            fi
        fi
    done

    [[ "$found_encrypt" == "true" ]] || fail "Expected classic encrypt hook in $MKINITCPIO_CONF."

    HOOKS_UPDATED_LINE="HOOKS=(${new_hooks[*]})"
    if [[ "$HOOKS_CONTENT" != "${new_hooks[*]}" ]]; then
        rewrite_line "$MKINITCPIO_CONF" "$HOOKS_LINE_NUMBER" "$HOOKS_UPDATED_LINE"
        HOOKS_UPDATED=true
    fi
}

calculate_resume_offset() {
    RESUME_OFFSET="$(btrfs inspect-internal map-swapfile -r "$SWAPFILE" 2>/dev/null | tr -d '[:space:]')"
    [[ "$RESUME_OFFSET" =~ ^[0-9]+$ ]] || fail "Failed to determine a numeric resume_offset from $SWAPFILE."
}

load_limine_cmdline() {
    local cmdline_matches
    local cmdline_regex='^[[:space:]]*KERNEL_CMDLINE\[default\][[:space:]]*="(.*)"[[:space:]]*$'

    mapfile -t cmdline_matches < <(awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*KERNEL_CMDLINE\[default\][[:space:]]*=/ { print NR ":" $0 }
    ' "$LIMINE_DEFAULTS")

    [[ ${#cmdline_matches[@]} -eq 1 ]] || fail "Expected exactly one KERNEL_CMDLINE[default] entry in $LIMINE_DEFAULTS."

    LIMINE_LINE_NUMBER="${cmdline_matches[0]%%:*}"
    LIMINE_CMDLINE_LINE="${cmdline_matches[0]#*:}"

    [[ "$LIMINE_CMDLINE_LINE" =~ $cmdline_regex ]] || fail "Unsupported KERNEL_CMDLINE[default] format in $LIMINE_DEFAULTS."
    LIMINE_CMDLINE_CONTENT="${BASH_REMATCH[1]}"
}

update_limine_cmdline() {
    local tokens=()
    local token
    local filtered_tokens=()

    load_limine_cmdline
    read -r -a tokens <<<"$LIMINE_CMDLINE_CONTENT"

    for token in "${tokens[@]}"; do
        case "$token" in
            resume=*|resume_offset=*)
                ;;
            *)
                filtered_tokens+=("$token")
                ;;
        esac
    done

    filtered_tokens+=("resume=$CRYPTROOT_DEVICE" "resume_offset=$RESUME_OFFSET")
    LIMINE_UPDATED_LINE="KERNEL_CMDLINE[default]=\"${filtered_tokens[*]}\""

    if [[ "$LIMINE_CMDLINE_CONTENT" != "${filtered_tokens[*]}" ]]; then
        rewrite_line "$LIMINE_DEFAULTS" "$LIMINE_LINE_NUMBER" "$LIMINE_UPDATED_LINE"
        LIMINE_UPDATED=true
    fi
}

refresh_boot_artifacts() {
    echo "Rebuilding initramfs..."
    printf 'y\n' | mkinitcpio -P

    if command -v limine-update &>/dev/null; then
        echo "Refreshing Limine configuration..."
        limine-update
        LIMINE_REFRESHED=true
    fi
}

print_summary() {
    echo "=== Wintarch Hibernation Migration Summary ==="
    echo "mkinitcpio config: $MKINITCPIO_CONF"
    echo "resume offset: $RESUME_OFFSET"
    echo "config renamed: $CONFIG_RENAMED"
    echo "legacy duplicate removed: $LEGACY_DUPLICATE_REMOVED"
    echo "hooks updated: $HOOKS_UPDATED"
    echo "limine cmdline updated: $LIMINE_UPDATED"
    echo "limine-update run: $LIMINE_REFRESHED"
    echo "Reboot, then test manually with: systemctl hibernate"
}

main() {
    echo "=== Wintarch Existing-Install Hibernation Migration ==="

    require_root
    require_command btrfs
    require_command findmnt
    require_command mkinitcpio

    inspect_mkinitcpio_config
    verify_layout
    validate_hooks_support
    apply_mkinitcpio_normalization
    update_hooks
    calculate_resume_offset
    update_limine_cmdline

    if [[ "$CONFIG_RENAMED" == "false" && "$LEGACY_DUPLICATE_REMOVED" == "false" && "$HOOKS_UPDATED" == "false" && "$LIMINE_UPDATED" == "false" ]]; then
        echo "Hibernation is already configured for the expected Wintarch layout."
        echo "Reboot, then test manually with: systemctl hibernate"
        exit 0
    fi

    refresh_boot_artifacts
    print_summary
}

main "$@"
