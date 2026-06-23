#!/bin/bash
# lib/archinstall.sh - Generate archinstall JSON config and run archinstall
# Uses pre_mounted_config mode since we handle partitioning ourselves

# --- JSON GENERATION ---

plasma_packages_json() {
    local package_file="$SCRIPT_DIR/packages/plasma.txt"

    [[ -f "$package_file" ]] || die "Missing Plasma package baseline: $package_file"

    while IFS= read -r package; do
        [[ -n "$package" && "$package" != \#* ]] || continue
        printf '        "%s",\n' "$package"
    done < "$package_file"
}

generate_user_config() {
    local config_file="$1"

    log_info "Generating archinstall configuration..."

    # Get LUKS partition UUID for encryption reference
    local luks_uuid
    luks_uuid=$(blkid -s UUID -o value "$LUKS_PARTITION")

    # Note: For pre_mounted_config, we use minimal disk_config
    # archinstall will detect what's mounted at mountpoint
    cat > "$config_file" <<EOF
{
    "archinstall-language": "English",
    "audio_config": {
        "audio": "pipewire"
    },
    "bootloader": null,
    "disk_config": {
        "config_type": "pre_mounted_config",
        "mountpoint": "$MOUNT_POINT"
    },
    "hostname": "$HOSTNAME",
    "kernels": ["linux"],
    "locale_config": {
        "kb_layout": "$KEYBOARD",
        "sys_enc": "UTF-8",
        "sys_lang": "en_US.UTF-8"
    },
    "mirror_config": {
        "custom_servers": [],
        "mirror_regions": {}
    },
    "network_config": {
        "type": "nm"
    },
    "no_pkg_lookups": false,
    "ntp": true,
    "packages": [
        "base-devel",
        "git",
        "curl",
        "gum",
        "less",
        "vim",
        "networkmanager",
        "snapper",
        "limine",
$(plasma_packages_json)
        "firefox",
        "zsh",
        "bluez",
        "bluez-utils",
        "fastfetch",
        "btop",
        "docker",
        "docker-buildx",
        "docker-compose",
        "mise",
        "noto-fonts",
        "noto-fonts-cjk",
        "noto-fonts-emoji",
        "noto-fonts-extra"
    ],
    "parallel_downloads": 8,
    "profile_config": {
        "gfx_driver": null,
        "greeter": null,
        "profile": null
    },
    "swap": false,
    "timezone": "$TIMEZONE",
    "version": "3.0.9"
}
EOF

    log_success "Configuration file created: $config_file"
}

generate_user_credentials() {
    local creds_file="$1"

    log_info "Generating credentials file..."

    # Escape values for JSON
    local password_escaped
    local password_hash_escaped
    local username_escaped

    password_escaped=$(echo -n "$PASSWORD" | jq -Rsa)
    password_hash_escaped=$(echo -n "$PASSWORD_HASH" | jq -Rsa)
    username_escaped=$(echo -n "$USERNAME" | jq -Rsa)

    cat > "$creds_file" <<EOF
{
    "encryption_password": $password_escaped,
    "root_enc_password": $password_hash_escaped,
    "users": [
        {
            "enc_password": $password_hash_escaped,
            "groups": ["wheel"],
            "sudo": true,
            "username": $username_escaped
        }
    ]
}
EOF

    # Secure the credentials file
    chmod 600 "$creds_file"

    log_success "Credentials file created: $creds_file"
}

# --- ARCHINSTALL EXECUTION ---

verify_archinstall() {
    # archinstall is pre-installed on the Arch ISO - just verify it works
    # IMPORTANT: Don't upgrade Python or archinstall, as this can cause version mismatches
    log_info "Verifying archinstall..."

    if ! python -c "import archinstall" >> "$LOG_FILE" 2>&1; then
        log_error "archinstall module not working"
        python --version >> "$LOG_FILE" 2>&1
        die "archinstall not available - is this a standard Arch ISO?"
    fi

    log_success "archinstall is ready"
}

run_archinstall() {
    log_step "Running Archinstall"

    # Create temp directory for config files
    local config_dir="/tmp/wintarch-install"
    mkdir -p "$config_dir"

    # Generate config files
    generate_user_config "$config_dir/config.json"
    generate_user_credentials "$config_dir/creds.json"

    # Verify archinstall is available (pre-installed on ISO)
    verify_archinstall

    # Show what we're doing
    log_info "Installing base system with archinstall..."
    log_info "This will take 10-30 minutes depending on your internet speed."
    log_info "(Note: One initramfs build during kernel installation is unavoidable)"
    echo >&2

    # Run archinstall with our pre-mounted config
    # Note: archinstall will use what's already mounted at $MOUNT_POINT
    # The first initramfs build will happen when the kernel is installed - this is unavoidable
    if ! archinstall \
        --config "$config_dir/config.json" \
        --creds "$config_dir/creds.json" \
        --mountpoint "$MOUNT_POINT" \
        --silent \
        --skip-ntp \
        2>&1 | tee -a "$LOG_FILE"; then

        log_error "Archinstall failed. Check log for details."
        cat "$config_dir/config.json" >> "$LOG_FILE"
        die "Archinstall failed"
    fi

    # Cleanup config files (contain sensitive data)
    rm -rf "$config_dir"

    log_success "Base system installed successfully"
}
