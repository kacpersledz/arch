#!/bin/bash
# Shared Wintarch hibernation configuration helpers.

WINTARCH_HIBERNATION_LEGACY_MKINITCPIO_CONF="${WINTARCH_HIBERNATION_LEGACY_MKINITCPIO_CONF:-/etc/mkinitcpio.conf.d/arch-cosmic.conf}"
WINTARCH_HIBERNATION_PREFERRED_MKINITCPIO_CONF="${WINTARCH_HIBERNATION_PREFERRED_MKINITCPIO_CONF:-/etc/mkinitcpio.conf.d/wintarch.conf}"
WINTARCH_HIBERNATION_LIMINE_DEFAULTS="${WINTARCH_HIBERNATION_LIMINE_DEFAULTS:-/etc/default/limine}"
WINTARCH_HIBERNATION_CRYPTROOT_DEVICE="${WINTARCH_HIBERNATION_CRYPTROOT_DEVICE:-/dev/mapper/cryptroot}"
WINTARCH_HIBERNATION_SWAP_MOUNTPOINT="${WINTARCH_HIBERNATION_SWAP_MOUNTPOINT:-/swap}"
WINTARCH_HIBERNATION_SWAPFILE="${WINTARCH_HIBERNATION_SWAPFILE:-/swap/swapfile}"
WINTARCH_HIBERNATION_SLEEP_CONF_DIR="${WINTARCH_HIBERNATION_SLEEP_CONF_DIR:-/etc/systemd/sleep.conf.d}"
WINTARCH_HIBERNATION_SLEEP_CONF_FILE="${WINTARCH_HIBERNATION_SLEEP_CONF_FILE:-/etc/systemd/sleep.conf.d/wintarch-hibernation.conf}"
WINTARCH_HIBERNATION_ALLOW_CREATE_MKINITCPIO="${WINTARCH_HIBERNATION_ALLOW_CREATE_MKINITCPIO:-false}"
WINTARCH_HIBERNATION_REQUIRE_OVERLAY_HOOK="${WINTARCH_HIBERNATION_REQUIRE_OVERLAY_HOOK:-false}"

wintarch_hibernation_reset_state() {
    WINTARCH_HIBERNATION_MKINITCPIO_CONF=""
    WINTARCH_HIBERNATION_ROOT_SOURCE=""
    WINTARCH_HIBERNATION_SWAP_SOURCE=""
    WINTARCH_HIBERNATION_RESUME_OFFSET=""
    WINTARCH_HIBERNATION_HOOKS_LINE_NUMBER=""
    WINTARCH_HIBERNATION_HOOKS_LINE=""
    WINTARCH_HIBERNATION_HOOKS_CONTENT=""
    WINTARCH_HIBERNATION_HOOKS_UPDATED_LINE=""
    WINTARCH_HIBERNATION_LIMINE_LINE_NUMBER=""
    WINTARCH_HIBERNATION_CMDLINE_LINE=""
    WINTARCH_HIBERNATION_CMDLINE_CONTENT=""
    WINTARCH_HIBERNATION_LIMINE_UPDATED_LINE=""

    WINTARCH_HIBERNATION_CONFIG_RENAMED=false
    WINTARCH_HIBERNATION_CONFIG_CREATED=false
    WINTARCH_HIBERNATION_LEGACY_DUPLICATE_REMOVED=false
    WINTARCH_HIBERNATION_HOOKS_UPDATED=false
    WINTARCH_HIBERNATION_LIMINE_UPDATED=false
    WINTARCH_HIBERNATION_SLEEP_CONF_UPDATED=false
    WINTARCH_HIBERNATION_LIMINE_REFRESHED=false
    WINTARCH_HIBERNATION_MKINITCPIO_ACTION="use-preferred"
}

wintarch_hibernation_fail() {
    echo "ERROR: $*" >&2
    return 1
}

wintarch_hibernation_rewrite_line() {
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

wintarch_hibernation_require_root() {
    [[ $EUID -eq 0 ]] || wintarch_hibernation_fail "This command must run as root."
}

wintarch_hibernation_require_command() {
    command -v "$1" &>/dev/null || wintarch_hibernation_fail "Required command not found: $1"
}

wintarch_hibernation_write_default_mkinitcpio_config() {
    mkdir -p "$(dirname "$WINTARCH_HIBERNATION_PREFERRED_MKINITCPIO_CONF")"
    cat >"$WINTARCH_HIBERNATION_PREFERRED_MKINITCPIO_CONF" <<'EOF'
# Wintarch mkinitcpio configuration
# Hooks for LUKS encrypted BTRFS root
HOOKS=(base udev keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck)
EOF
}

wintarch_hibernation_ensure_mkinitcpio_permissions() {
    chown root:root "$WINTARCH_HIBERNATION_MKINITCPIO_CONF"
    chmod 0644 "$WINTARCH_HIBERNATION_MKINITCPIO_CONF"
}

wintarch_hibernation_inspect_mkinitcpio_config() {
    local legacy_exists=false
    local preferred_exists=false

    [[ -f "$WINTARCH_HIBERNATION_LEGACY_MKINITCPIO_CONF" ]] && legacy_exists=true
    [[ -f "$WINTARCH_HIBERNATION_PREFERRED_MKINITCPIO_CONF" ]] && preferred_exists=true

    if [[ "$legacy_exists" == "true" && "$preferred_exists" == "false" ]]; then
        WINTARCH_HIBERNATION_MKINITCPIO_ACTION="rename-legacy"
        WINTARCH_HIBERNATION_MKINITCPIO_CONF="$WINTARCH_HIBERNATION_LEGACY_MKINITCPIO_CONF"
        return 0
    fi

    if [[ "$legacy_exists" == "false" && "$preferred_exists" == "true" ]]; then
        WINTARCH_HIBERNATION_MKINITCPIO_ACTION="use-preferred"
        WINTARCH_HIBERNATION_MKINITCPIO_CONF="$WINTARCH_HIBERNATION_PREFERRED_MKINITCPIO_CONF"
        return 0
    fi

    if [[ "$legacy_exists" == "true" && "$preferred_exists" == "true" ]]; then
        if cmp -s "$WINTARCH_HIBERNATION_LEGACY_MKINITCPIO_CONF" "$WINTARCH_HIBERNATION_PREFERRED_MKINITCPIO_CONF"; then
            WINTARCH_HIBERNATION_MKINITCPIO_ACTION="remove-legacy-duplicate"
            WINTARCH_HIBERNATION_MKINITCPIO_CONF="$WINTARCH_HIBERNATION_PREFERRED_MKINITCPIO_CONF"
            return 0
        fi

        wintarch_hibernation_fail \
            "Both mkinitcpio configs exist and differ: $WINTARCH_HIBERNATION_LEGACY_MKINITCPIO_CONF and $WINTARCH_HIBERNATION_PREFERRED_MKINITCPIO_CONF"
        return 1
    fi

    if [[ "$WINTARCH_HIBERNATION_ALLOW_CREATE_MKINITCPIO" == "true" ]]; then
        WINTARCH_HIBERNATION_MKINITCPIO_ACTION="create-preferred"
        WINTARCH_HIBERNATION_MKINITCPIO_CONF="$WINTARCH_HIBERNATION_PREFERRED_MKINITCPIO_CONF"
        return 0
    fi

    wintarch_hibernation_fail \
        "Expected mkinitcpio config not found at $WINTARCH_HIBERNATION_LEGACY_MKINITCPIO_CONF or $WINTARCH_HIBERNATION_PREFERRED_MKINITCPIO_CONF"
}

wintarch_hibernation_apply_mkinitcpio_normalization() {
    case "$WINTARCH_HIBERNATION_MKINITCPIO_ACTION" in
        rename-legacy)
            mv "$WINTARCH_HIBERNATION_LEGACY_MKINITCPIO_CONF" "$WINTARCH_HIBERNATION_PREFERRED_MKINITCPIO_CONF"
            WINTARCH_HIBERNATION_CONFIG_RENAMED=true
            WINTARCH_HIBERNATION_MKINITCPIO_CONF="$WINTARCH_HIBERNATION_PREFERRED_MKINITCPIO_CONF"
            ;;
        remove-legacy-duplicate)
            rm -f "$WINTARCH_HIBERNATION_LEGACY_MKINITCPIO_CONF"
            WINTARCH_HIBERNATION_LEGACY_DUPLICATE_REMOVED=true
            WINTARCH_HIBERNATION_MKINITCPIO_CONF="$WINTARCH_HIBERNATION_PREFERRED_MKINITCPIO_CONF"
            ;;
        create-preferred)
            wintarch_hibernation_write_default_mkinitcpio_config
            WINTARCH_HIBERNATION_CONFIG_CREATED=true
            WINTARCH_HIBERNATION_MKINITCPIO_CONF="$WINTARCH_HIBERNATION_PREFERRED_MKINITCPIO_CONF"
            ;;
        use-preferred)
            ;;
        *)
            wintarch_hibernation_fail "Unsupported mkinitcpio normalization action: $WINTARCH_HIBERNATION_MKINITCPIO_ACTION"
            return 1
            ;;
    esac

    wintarch_hibernation_ensure_mkinitcpio_permissions
}

wintarch_hibernation_verify_layout() {
    local root_fstype
    local swap_fstype
    local swap_options

    [[ -e "$WINTARCH_HIBERNATION_CRYPTROOT_DEVICE" ]] || {
        wintarch_hibernation_fail "$WINTARCH_HIBERNATION_CRYPTROOT_DEVICE does not exist."
        return 1
    }

    root_fstype="$(findmnt -no FSTYPE /)"
    [[ "$root_fstype" == "btrfs" ]] || {
        wintarch_hibernation_fail "Root filesystem is not BTRFS."
        return 1
    }

    WINTARCH_HIBERNATION_ROOT_SOURCE="$(findmnt -no SOURCE /)"
    [[ "$WINTARCH_HIBERNATION_ROOT_SOURCE" == *"$WINTARCH_HIBERNATION_CRYPTROOT_DEVICE"* ]] || {
        wintarch_hibernation_fail "Root is not mounted from $WINTARCH_HIBERNATION_CRYPTROOT_DEVICE."
        return 1
    }

    findmnt -rn -M "$WINTARCH_HIBERNATION_SWAP_MOUNTPOINT" &>/dev/null || {
        wintarch_hibernation_fail "$WINTARCH_HIBERNATION_SWAP_MOUNTPOINT is not mounted."
        return 1
    }

    swap_fstype="$(findmnt -no FSTYPE -M "$WINTARCH_HIBERNATION_SWAP_MOUNTPOINT")"
    [[ "$swap_fstype" == "btrfs" ]] || {
        wintarch_hibernation_fail "$WINTARCH_HIBERNATION_SWAP_MOUNTPOINT is not a BTRFS mount."
        return 1
    }

    WINTARCH_HIBERNATION_SWAP_SOURCE="$(findmnt -no SOURCE -M "$WINTARCH_HIBERNATION_SWAP_MOUNTPOINT")"
    [[ "$WINTARCH_HIBERNATION_SWAP_SOURCE" == *"$WINTARCH_HIBERNATION_CRYPTROOT_DEVICE"* ]] || {
        wintarch_hibernation_fail "$WINTARCH_HIBERNATION_SWAP_MOUNTPOINT is not mounted from $WINTARCH_HIBERNATION_CRYPTROOT_DEVICE."
        return 1
    }

    swap_options="$(findmnt -no OPTIONS -M "$WINTARCH_HIBERNATION_SWAP_MOUNTPOINT")"
    [[ "$swap_options" =~ (^|,)subvol=/?@swap($|,) ]] || {
        wintarch_hibernation_fail "$WINTARCH_HIBERNATION_SWAP_MOUNTPOINT is not mounted from the expected @swap subvolume."
        return 1
    }

    [[ -f "$WINTARCH_HIBERNATION_SWAPFILE" ]] || {
        wintarch_hibernation_fail "Swapfile not found: $WINTARCH_HIBERNATION_SWAPFILE"
        return 1
    }

    [[ -f "$WINTARCH_HIBERNATION_LIMINE_DEFAULTS" ]] || {
        wintarch_hibernation_fail "Limine defaults file not found: $WINTARCH_HIBERNATION_LIMINE_DEFAULTS"
        return 1
    }
}

wintarch_hibernation_load_hooks_line() {
    local hook_matches
    local hooks_regex='^[[:space:]]*HOOKS=\(([^)]*)\)[[:space:]]*$'

    mapfile -t hook_matches < <(awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*HOOKS=\(/ { print NR ":" $0 }
    ' "$WINTARCH_HIBERNATION_MKINITCPIO_CONF")

    [[ ${#hook_matches[@]} -eq 1 ]] || {
        wintarch_hibernation_fail \
            "Expected exactly one classic HOOKS=(...) line in $WINTARCH_HIBERNATION_MKINITCPIO_CONF."
        return 1
    }

    WINTARCH_HIBERNATION_HOOKS_LINE_NUMBER="${hook_matches[0]%%:*}"
    WINTARCH_HIBERNATION_HOOKS_LINE="${hook_matches[0]#*:}"
    WINTARCH_HIBERNATION_HOOKS_CONTENT="${WINTARCH_HIBERNATION_HOOKS_LINE%%#*}"

    [[ "$WINTARCH_HIBERNATION_HOOKS_CONTENT" =~ $hooks_regex ]] || {
        wintarch_hibernation_fail "Unsupported HOOKS format in $WINTARCH_HIBERNATION_MKINITCPIO_CONF."
        return 1
    }

    WINTARCH_HIBERNATION_HOOKS_CONTENT="${BASH_REMATCH[1]}"
}

wintarch_hibernation_update_hooks() {
    local hooks=()
    local hook
    local found_encrypt=false
    local inserted_resume=false
    local had_overlay=false
    local new_hooks=()

    wintarch_hibernation_load_hooks_line || return 1
    read -r -a hooks <<<"$WINTARCH_HIBERNATION_HOOKS_CONTENT"

    for hook in "${hooks[@]}"; do
        case "$hook" in
            resume)
                continue
                ;;
            btrfs-overlayfs)
                had_overlay=true
                continue
                ;;
            systemd|sd-encrypt)
                wintarch_hibernation_fail \
                    "Unsupported systemd-style initramfs hooks detected in $WINTARCH_HIBERNATION_MKINITCPIO_CONF."
                return 1
                ;;
        esac

        new_hooks+=("$hook")
        if [[ "$hook" == "encrypt" ]]; then
            found_encrypt=true
            if [[ "$inserted_resume" == "false" ]]; then
                new_hooks+=("resume")
                inserted_resume=true
            fi
        fi
    done

    [[ "$found_encrypt" == "true" ]] || {
        wintarch_hibernation_fail "Expected classic encrypt hook in $WINTARCH_HIBERNATION_MKINITCPIO_CONF."
        return 1
    }

    if [[ "$WINTARCH_HIBERNATION_REQUIRE_OVERLAY_HOOK" == "true" || "$had_overlay" == "true" ]]; then
        new_hooks+=("btrfs-overlayfs")
    fi

    WINTARCH_HIBERNATION_HOOKS_UPDATED_LINE="HOOKS=(${new_hooks[*]})"
    if [[ "$WINTARCH_HIBERNATION_HOOKS_CONTENT" != "${new_hooks[*]}" ]]; then
        wintarch_hibernation_rewrite_line \
            "$WINTARCH_HIBERNATION_MKINITCPIO_CONF" \
            "$WINTARCH_HIBERNATION_HOOKS_LINE_NUMBER" \
            "$WINTARCH_HIBERNATION_HOOKS_UPDATED_LINE"
        WINTARCH_HIBERNATION_HOOKS_UPDATED=true
    fi

    wintarch_hibernation_ensure_mkinitcpio_permissions
}

wintarch_hibernation_calculate_resume_offset() {
    WINTARCH_HIBERNATION_RESUME_OFFSET="$(
        btrfs inspect-internal map-swapfile -r "$WINTARCH_HIBERNATION_SWAPFILE" 2>/dev/null | tr -d '[:space:]'
    )"
    [[ "$WINTARCH_HIBERNATION_RESUME_OFFSET" =~ ^[0-9]+$ ]] || {
        wintarch_hibernation_fail \
            "Failed to determine a numeric resume_offset from $WINTARCH_HIBERNATION_SWAPFILE."
        return 1
    }
}

wintarch_hibernation_load_limine_cmdline() {
    local cmdline_matches
    local cmdline_regex='^[[:space:]]*KERNEL_CMDLINE\[default\][[:space:]]*="(.*)"[[:space:]]*$'

    mapfile -t cmdline_matches < <(awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*KERNEL_CMDLINE\[default\][[:space:]]*=/ { print NR ":" $0 }
    ' "$WINTARCH_HIBERNATION_LIMINE_DEFAULTS")

    [[ ${#cmdline_matches[@]} -eq 1 ]] || {
        wintarch_hibernation_fail \
            "Expected exactly one KERNEL_CMDLINE[default] entry in $WINTARCH_HIBERNATION_LIMINE_DEFAULTS."
        return 1
    }

    WINTARCH_HIBERNATION_LIMINE_LINE_NUMBER="${cmdline_matches[0]%%:*}"
    WINTARCH_HIBERNATION_CMDLINE_LINE="${cmdline_matches[0]#*:}"

    [[ "$WINTARCH_HIBERNATION_CMDLINE_LINE" =~ $cmdline_regex ]] || {
        wintarch_hibernation_fail \
            "Unsupported KERNEL_CMDLINE[default] format in $WINTARCH_HIBERNATION_LIMINE_DEFAULTS."
        return 1
    }

    WINTARCH_HIBERNATION_CMDLINE_CONTENT="${BASH_REMATCH[1]}"
}

wintarch_hibernation_update_limine_cmdline() {
    local tokens=()
    local token
    local filtered_tokens=()

    wintarch_hibernation_load_limine_cmdline || return 1
    read -r -a tokens <<<"$WINTARCH_HIBERNATION_CMDLINE_CONTENT"

    for token in "${tokens[@]}"; do
        case "$token" in
            resume=*|resume_offset=*)
                ;;
            *)
                filtered_tokens+=("$token")
                ;;
        esac
    done

    filtered_tokens+=(
        "resume=$WINTARCH_HIBERNATION_CRYPTROOT_DEVICE"
        "resume_offset=$WINTARCH_HIBERNATION_RESUME_OFFSET"
    )
    WINTARCH_HIBERNATION_LIMINE_UPDATED_LINE="KERNEL_CMDLINE[default]=\"${filtered_tokens[*]}\""

    if [[ "$WINTARCH_HIBERNATION_CMDLINE_CONTENT" != "${filtered_tokens[*]}" ]]; then
        wintarch_hibernation_rewrite_line \
            "$WINTARCH_HIBERNATION_LIMINE_DEFAULTS" \
            "$WINTARCH_HIBERNATION_LIMINE_LINE_NUMBER" \
            "$WINTARCH_HIBERNATION_LIMINE_UPDATED_LINE"
        WINTARCH_HIBERNATION_LIMINE_UPDATED=true
    fi
}

wintarch_hibernation_refresh_boot_artifacts() {
    echo "Rebuilding initramfs..."
    printf 'y\n' | mkinitcpio -P

    if command -v limine-update &>/dev/null; then
        echo "Refreshing Limine configuration..."
        limine-update
        WINTARCH_HIBERNATION_LIMINE_REFRESHED=true
    fi
}

wintarch_hibernation_ensure_sleep_config() {
    local expected_content='[Sleep]
HibernateMode=shutdown
'
    local current_content=""

    mkdir -p "$WINTARCH_HIBERNATION_SLEEP_CONF_DIR"

    if [[ -f "$WINTARCH_HIBERNATION_SLEEP_CONF_FILE" ]]; then
        current_content="$(cat "$WINTARCH_HIBERNATION_SLEEP_CONF_FILE")"
        current_content+=$'\n'
    fi

    if [[ "$current_content" != "$expected_content" ]]; then
        printf '%s' "$expected_content" >"$WINTARCH_HIBERNATION_SLEEP_CONF_FILE"
        WINTARCH_HIBERNATION_SLEEP_CONF_UPDATED=true
    fi

    chown root:root "$WINTARCH_HIBERNATION_SLEEP_CONF_FILE"
    chmod 0644 "$WINTARCH_HIBERNATION_SLEEP_CONF_FILE"
}

wintarch_hibernation_print_recovery_hint() {
    echo "If resume fails, add \`noresume\` at the Limine boot entry or remove \`resume=\` and \`resume_offset=\` from /etc/default/limine, then run \`mkinitcpio -P\` and \`limine-update\`."
}

wintarch_hibernation_print_rollback_hint() {
    echo "To return to systemd default hibernate mode, remove /etc/systemd/sleep.conf.d/wintarch-hibernation.conf."
}

wintarch_configure_hibernate_shutdown_mode() {
    local context="${1:-Wintarch}"

    wintarch_hibernation_reset_state
    wintarch_hibernation_require_root
    wintarch_hibernation_ensure_sleep_config

    if [[ "$WINTARCH_HIBERNATION_SLEEP_CONF_UPDATED" == "true" ]]; then
        echo "$context: hibernation shutdown mode configured."
    else
        echo "$context: hibernation shutdown mode already configured."
    fi

    echo "Wintarch configured HibernateMode=shutdown for reliable poweroff after writing the hibernation image."
    wintarch_hibernation_print_rollback_hint
}

wintarch_enable_hibernation() {
    local context="${1:-Wintarch}"

    wintarch_hibernation_reset_state
    wintarch_hibernation_require_root
    wintarch_hibernation_require_command btrfs
    wintarch_hibernation_require_command findmnt
    wintarch_hibernation_require_command mkinitcpio

    wintarch_hibernation_inspect_mkinitcpio_config
    wintarch_hibernation_verify_layout
    wintarch_hibernation_apply_mkinitcpio_normalization
    wintarch_hibernation_update_hooks
    wintarch_hibernation_calculate_resume_offset
    wintarch_hibernation_update_limine_cmdline
    wintarch_hibernation_ensure_sleep_config

    if [[ "$WINTARCH_HIBERNATION_CONFIG_RENAMED" == "false" \
        && "$WINTARCH_HIBERNATION_CONFIG_CREATED" == "false" \
        && "$WINTARCH_HIBERNATION_LEGACY_DUPLICATE_REMOVED" == "false" \
        && "$WINTARCH_HIBERNATION_HOOKS_UPDATED" == "false" \
        && "$WINTARCH_HIBERNATION_LIMINE_UPDATED" == "false" \
        && "$WINTARCH_HIBERNATION_SLEEP_CONF_UPDATED" == "false" ]]; then
        echo "$context: hibernation is enabled."
        echo "resume offset: $WINTARCH_HIBERNATION_RESUME_OFFSET"
        echo "Wintarch configured HibernateMode=shutdown for reliable poweroff after writing the hibernation image."
        wintarch_hibernation_print_recovery_hint
        wintarch_hibernation_print_rollback_hint
        return 0
    fi

    if [[ "$WINTARCH_HIBERNATION_CONFIG_RENAMED" == "true" \
        || "$WINTARCH_HIBERNATION_CONFIG_CREATED" == "true" \
        || "$WINTARCH_HIBERNATION_LEGACY_DUPLICATE_REMOVED" == "true" \
        || "$WINTARCH_HIBERNATION_HOOKS_UPDATED" == "true" \
        || "$WINTARCH_HIBERNATION_LIMINE_UPDATED" == "true" ]]; then
        wintarch_hibernation_refresh_boot_artifacts
    fi

    echo "$context: hibernation is enabled."
    echo "mkinitcpio config: $WINTARCH_HIBERNATION_MKINITCPIO_CONF"
    echo "resume offset: $WINTARCH_HIBERNATION_RESUME_OFFSET"
    echo "Wintarch configured HibernateMode=shutdown for reliable poweroff after writing the hibernation image."
    echo "config renamed: $WINTARCH_HIBERNATION_CONFIG_RENAMED"
    echo "config created: $WINTARCH_HIBERNATION_CONFIG_CREATED"
    echo "legacy duplicate removed: $WINTARCH_HIBERNATION_LEGACY_DUPLICATE_REMOVED"
    echo "hooks updated: $WINTARCH_HIBERNATION_HOOKS_UPDATED"
    echo "limine cmdline updated: $WINTARCH_HIBERNATION_LIMINE_UPDATED"
    echo "sleep config updated: $WINTARCH_HIBERNATION_SLEEP_CONF_UPDATED"
    echo "limine-update run: $WINTARCH_HIBERNATION_LIMINE_REFRESHED"
    wintarch_hibernation_print_recovery_hint
    wintarch_hibernation_print_rollback_hint
}
