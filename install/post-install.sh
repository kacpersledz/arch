#!/bin/bash
# install/post-install.sh - Post-installation setup
# Based on omarchy's install/login/limine-snapper.sh
#
# This runs AFTER archinstall, in chroot, to configure:
# - mkinitcpio with proper hooks for LUKS + BTRFS
# - Limine bootloader with snapshot support
# - Snapper for BTRFS snapshots
# - Plasma Login Manager
# - Wintarch system management

# --- CHROOT HELPER ---

chroot_run() {
    arch-chroot "$MOUNT_POINT" /bin/bash -c "$1"
}

# --- MKINITCPIO OPTIMIZATION ---
# Disable hooks during post-install configuration to prevent multiple rebuilds

disable_mkinitcpio_hooks() {
    log_info "Disabling mkinitcpio hooks during configuration..."
    echo >&2

    chroot_run "
        if [ -f /usr/share/libalpm/hooks/90-mkinitcpio-install.hook ]; then
            mv /usr/share/libalpm/hooks/90-mkinitcpio-install.hook \
               /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled
        fi
        if [ -f /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook ]; then
            mv /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook \
               /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled
        fi
    " 2>&1 | tee -a "$LOG_FILE" >&2

    log_success "mkinitcpio hooks disabled"
}

enable_mkinitcpio_hooks() {
    log_info "Re-enabling mkinitcpio hooks..."
    echo >&2

    chroot_run "
        if [ -f /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled ]; then
            mv /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled \
               /usr/share/libalpm/hooks/90-mkinitcpio-install.hook
        fi
        if [ -f /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled ]; then
            mv /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled \
               /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook
        fi
    " 2>&1 | tee -a "$LOG_FILE" >&2

    log_success "mkinitcpio hooks re-enabled"
}

# --- MKINITCPIO CONFIGURATION ---

configure_mkinitcpio() {
    log_info "Configuring mkinitcpio hooks..."
    echo >&2

    # Create hook configuration for LUKS + BTRFS
    # Note: btrfs-overlayfs is added later if limine-mkinitcpio-hook is installed
    chroot_run "cat > /etc/mkinitcpio.conf.d/wintarch.conf << 'EOF'
# Wintarch mkinitcpio configuration
# Hooks for LUKS encrypted BTRFS root
HOOKS=(base udev keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck)
EOF" 2>&1 | tee -a "$LOG_FILE" >&2

    log_success "mkinitcpio configured"
}

# --- LIMINE BOOTLOADER CONFIGURATION ---

configure_limine() {
    log_info "Configuring Limine bootloader..."
    echo >&2

    # Get LUKS partition UUID
    local luks_uuid
    luks_uuid=$(blkid -s UUID -o value "$LUKS_PARTITION")

    local cmdline="cryptdevice=UUID=${luks_uuid}:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet"

    # Create /etc/default/limine configuration
    echo "Creating /etc/default/limine..." >&2
    chroot_run "cat > /etc/default/limine << EOF
TARGET_OS_NAME=\"Wintarch\"

ESP_PATH=\"/boot\"

KERNEL_CMDLINE[default]=\"$cmdline\"

ENABLE_UKI=yes
CUSTOM_UKI_NAME=\"wintarch\"

ENABLE_LIMINE_FALLBACK=yes

# Find and add other bootloaders (Windows, etc.)
FIND_BOOTLOADERS=yes

BOOT_ORDER=\"*, *fallback, Snapshots\"

MAX_SNAPSHOT_ENTRIES=5

SNAPSHOT_FORMAT_CHOICE=5
EOF" 2>&1 | tee -a "$LOG_FILE" >&2

    # Create base limine.conf
    echo "Creating /boot/limine.conf..." >&2
    chroot_run "cat > /boot/limine.conf << 'EOF'
### Wintarch - Limine Configuration
timeout: 5
default_entry: 2
interface_branding: Wintarch
interface_branding_color: 2
hash_mismatch_panic: no

# Tokyo Night color palette
term_background: 1a1b26
backdrop: 1a1b26
term_palette: 15161e;f7768e;9ece6a;e0af68;7aa2f7;bb9af7;7dcfff;a9b1d6
term_palette_bright: 414868;f7768e;9ece6a;e0af68;7aa2f7;bb9af7;7dcfff;c0caf5
term_foreground: c0caf5
term_foreground_bright: c0caf5
term_background_bright: 24283b
EOF" 2>&1 | tee -a "$LOG_FILE" >&2

    log_success "Limine configured"
}

# --- FIRST-BOOT SERVICE ---
# Snapper configuration requires D-Bus which isn't available in chroot.
# We install a systemd oneshot service that runs on first boot to configure snapper.

install_first_boot_service() {
    log_info "Installing first-boot service..."
    echo >&2

    # Get the repo root
    local repo_root
    repo_root="$(cd "$SCRIPT_DIR/.." && pwd)"

    # Copy systemd service file
    echo "Installing wintarch-first-boot.service..." >&2
    cp "$repo_root/systemd/wintarch-first-boot.service" \
       "$MOUNT_POINT/etc/systemd/system/" 2>&1 | tee -a "$LOG_FILE" >&2

    # Enable the service
    chroot_run "systemctl enable wintarch-first-boot.service" 2>&1 | tee -a "$LOG_FILE" >&2

    log_success "First-boot service installed (snapper will be configured on first boot)"
}

# --- AUR PACKAGES ---
# limine-snapper-sync and limine-mkinitcpio-hook are AUR packages

install_aur_helper() {
    log_info "Installing yay AUR helper..."
    echo >&2

    chroot_run "
        # Temporary sudo access for build
        echo '$USERNAME ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/temp-build
        chmod 440 /etc/sudoers.d/temp-build

        # Build yay as user
        cd /tmp
        sudo -u '$USERNAME' git clone https://aur.archlinux.org/yay.git
        cd yay
        sudo -u '$USERNAME' makepkg -si --noconfirm

        # Cleanup
        rm -rf /tmp/yay
        rm -f /etc/sudoers.d/temp-build
    " 2>&1 | tee -a "$LOG_FILE" >&2 || {
        log_warn "Failed to install yay - skipping AUR packages"
        return 1
    }

    log_success "yay installed"
    return 0
}

enable_pacman_colors() {
    log_info "Enabling colors for pacman and yay..."
    echo >&2

    chroot_run "
        # Uncomment Color in pacman.conf to enable colors for pacman and yay
        sed -i 's/^#Color/Color/' /etc/pacman.conf
    " 2>&1 | tee -a "$LOG_FILE" >&2

    log_success "Colors enabled for package managers"
}

get_aur_package_version() {
    local package_name="$1"

    chroot_run "
        set -euo pipefail

        temp_dir=\$(mktemp -d /tmp/${package_name}.XXXXXX)
        trap 'rm -rf \"\$temp_dir\"' EXIT

        git clone --depth 1 https://aur.archlinux.org/${package_name}.git \"\$temp_dir/${package_name}\" >/dev/null 2>&1

        srcinfo_file=\"\$temp_dir/${package_name}/.SRCINFO\"
        if [ ! -f \"\$srcinfo_file\" ]; then
            echo 'Missing .SRCINFO for ${package_name}' >&2
            exit 1
        fi

        pkgver=\$(awk -F ' = ' '/^[[:space:]]*pkgver = / { print \$2; exit }' \"\$srcinfo_file\")
        pkgrel=\$(awk -F ' = ' '/^[[:space:]]*pkgrel = / { print \$2; exit }' \"\$srcinfo_file\")

        if [ -z \"\$pkgver\" ] || [ -z \"\$pkgrel\" ]; then
            echo 'Failed to parse pkgver/pkgrel for ${package_name}' >&2
            exit 1
        fi

        printf '%s-%s\n' \"\$pkgver\" \"\$pkgrel\"
    "
}

install_limine_snapper_packages_from_cachyos_binary_fallback() {
    log_warn "Using CachyOS binary fallback for Limine-Snapper packages after normal install path failed"
    echo >&2

    if [[ "${DISABLE_CACHYOS_LIMINE_BINARY_FALLBACK:-0}" == "1" ]]; then
        log_warn "CachyOS binary fallback disabled via DISABLE_CACHYOS_LIMINE_BINARY_FALLBACK=1"
        return 1
    fi

    local mkinitcpio_version
    local snapper_version

    log_info "Detecting exact AUR versions for binary fallback..."
    mkinitcpio_version=$(get_aur_package_version "limine-mkinitcpio-hook") || {
        log_warn "Failed to determine AUR version for limine-mkinitcpio-hook"
        return 1
    }
    snapper_version=$(get_aur_package_version "limine-snapper-sync") || {
        log_warn "Failed to determine AUR version for limine-snapper-sync"
        return 1
    }

    log_info "Detected AUR versions: limine-mkinitcpio-hook=${mkinitcpio_version}, limine-snapper-sync=${snapper_version}"

    chroot_run "
        set -euo pipefail

        if [ \"\$(uname -m)\" != 'x86_64' ]; then
            echo 'CachyOS binary fallback is supported only on x86_64' >&2
            exit 1
        fi

        pacman -S --noconfirm --needed \
            efibootmgr btrfs-progs libnotify mkinitcpio bash grep tar curl base-devel git

        temp_dir=\$(mktemp -d /tmp/limine-cachyos-fallback.XXXXXX)
        trap 'rm -rf \"\$temp_dir\"' EXIT
        cd \"\$temp_dir\"

        base_url='https://mirror.cachyos.org/repo/x86_64/cachyos'
        mkinitcpio_file='limine-mkinitcpio-hook-${mkinitcpio_version}-x86_64.pkg.tar.zst'
        snapper_file='limine-snapper-sync-${snapper_version}-x86_64.pkg.tar.zst'
        mkinitcpio_url=\"\$base_url/\$mkinitcpio_file\"
        snapper_url=\"\$base_url/\$snapper_file\"

        echo \"Checking exact CachyOS URL: \$mkinitcpio_url\" >&2
        curl -fI \"\$mkinitcpio_url\" >/dev/null

        echo \"Checking exact CachyOS URL: \$snapper_url\" >&2
        curl -fI \"\$snapper_url\" >/dev/null

        echo \"Downloading \$mkinitcpio_file\" >&2
        curl -fL --retry 3 --retry-delay 2 -o \"\$mkinitcpio_file\" \"\$mkinitcpio_url\"

        echo \"Downloading \$snapper_file\" >&2
        curl -fL --retry 3 --retry-delay 2 -o \"\$snapper_file\" \"\$snapper_url\"

        # This fallback intentionally avoids adding the CachyOS repo or trust root.
        # It relies on HTTPS transport, exact AUR-version matching, and pacman dependency checks.
        pacman -U --noconfirm --needed \"\$mkinitcpio_file\" \"\$snapper_file\"
    " 2>&1 | tee -a "$LOG_FILE" >&2 || {
        log_warn "CachyOS binary fallback failed. Ensure exact-version binaries exist and downloads are reachable."
        return 1
    }

    log_success "CachyOS binary fallback installed Limine-Snapper packages"
    return 0
}

run_chroot_logged_allow_fail() {
    local command="$1"
    local status
    local err_trap

    err_trap=$(trap -p ERR || true)
    trap - ERR

    set +e
    chroot_run "$command" 2>&1 | tee -a "$LOG_FILE" >&2
    status=${PIPESTATUS[0]}
    set -e

    if [[ -n "$err_trap" ]]; then
        eval "$err_trap"
    fi

    return "$status"
}

install_limine_snapper_packages() {
    log_info "Installing Limine-Snapper integration packages from AUR..."
    echo >&2

    local install_succeeded=false
    local try_yay=false

    # Check if packages exist in official repos first
    if chroot_run "pacman -Ss limine-snapper-sync" &>/dev/null; then
        if ! run_chroot_logged_allow_fail "pacman -S --noconfirm --needed limine-snapper-sync limine-mkinitcpio-hook"; then
            log_warn "Failed to install Limine-Snapper packages from pacman repos"
            try_yay=true
        else
            install_succeeded=true
        fi
    else
        try_yay=true
    fi

    if [[ "$install_succeeded" != true ]] && [[ "$try_yay" == true ]]; then
        # Fall back to AUR
        if ! install_aur_helper; then
            log_warn "Failed to install yay for Limine-Snapper packages"
        else
            if ! run_chroot_logged_allow_fail "
                set -euo pipefail

                echo '$USERNAME ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/temp-build
                trap 'rm -f /etc/sudoers.d/temp-build' EXIT
                chmod 440 /etc/sudoers.d/temp-build
                sudo -u '$USERNAME' yay -S --noconfirm --needed limine-snapper-sync limine-mkinitcpio-hook
                rm -f /etc/sudoers.d/temp-build
                trap - EXIT
            "; then
                log_warn "Failed to install Limine-Snapper packages from yay/AUR"
            else
                install_succeeded=true
            fi
        fi
    fi

    if [[ "$install_succeeded" != true ]]; then
        log_warn "Normal Limine-Snapper install path failed; attempting exact-version CachyOS binary fallback"
        if ! install_limine_snapper_packages_from_cachyos_binary_fallback; then
            log_warn "Failed to install Limine-Snapper packages via all available methods"
            return 1
        fi
    fi

    # Update mkinitcpio hooks to include btrfs-overlayfs
    echo "Updating mkinitcpio hooks for btrfs-overlayfs..." >&2
    chroot_run "
        if [ -f /usr/lib/initcpio/install/btrfs-overlayfs ]; then
            sed -i 's/^HOOKS=.*/HOOKS=(base udev keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)/' /etc/mkinitcpio.conf.d/wintarch.conf
        fi
    " 2>&1 | tee -a "$LOG_FILE" >&2

    # Enable the sync service
    echo "Enabling limine-snapper-sync service..." >&2
    chroot_run "systemctl enable limine-snapper-sync.service" 2>&1 | tee -a "$LOG_FILE" >&2 || {
        log_warn "Failed to enable limine-snapper-sync.service"
        return 1
    }

    log_success "Limine-Snapper integration installed"
    return 0
}

install_aur_packages() {
    log_info "Installing AUR packages (brave, vscode)..."
    echo >&2

    # Ensure yay is available
    if ! chroot_run "command -v yay" &>/dev/null; then
        if ! install_aur_helper; then
            log_warn "yay not available - skipping AUR packages"
            return 1
        fi
    fi

    chroot_run "
        echo '$USERNAME ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/temp-build
        chmod 440 /etc/sudoers.d/temp-build
        sudo -u '$USERNAME' yay -S --noconfirm --needed brave-bin visual-studio-code-bin
        rm -f /etc/sudoers.d/temp-build
    " 2>&1 | tee -a "$LOG_FILE" >&2 || {
        log_warn "Failed to install some AUR packages"
        return 1
    }

    log_success "AUR packages installed"
    return 0
}

# --- SWAP CONFIGURATION ---

setup_swap() {
    log_info "Setting up swap (zram + swapfile)..."
    echo >&2

    # Detect RAM size
    local ram_mb
    ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    local ram_gb=$((ram_mb / 1024))

    echo "Detected ${ram_gb}GB RAM" >&2

    # Install zram-generator
    echo "Installing zram-generator..." >&2
    chroot_run "pacman -S --noconfirm --needed zram-generator" 2>&1 | tee -a "$LOG_FILE" >&2

    # Configure zram (50% of RAM, priority 100)
    echo "Configuring zram (50% of RAM)..." >&2
    chroot_run "cat > /etc/systemd/zram-generator.conf << 'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
EOF" 2>&1 | tee -a "$LOG_FILE" >&2

    # Create swapfile (RAM size, priority 1)
    echo "Creating ${ram_gb}GB swapfile..." >&2
    chroot_run "
        # Create swapfile and set NOCOW attribute
        touch /swap/swapfile
        chattr +C /swap/swapfile
        dd if=/dev/zero of=/swap/swapfile bs=1M count=${ram_mb} status=progress
        chmod 600 /swap/swapfile
        mkswap /swap/swapfile
    " 2>&1 | tee -a "$LOG_FILE" >&2

    # Add @swap subvolume to fstab (ensures it mounts on boot)
    echo "Adding @swap subvolume to fstab..." >&2
    echo "/dev/mapper/cryptroot /swap btrfs subvol=@swap,compress=zstd,noatime 0 0" >> "$MOUNT_POINT/etc/fstab"

    # Add swapfile to fstab (priority 1 - lower than zram)
    echo "Adding swapfile to fstab..." >&2
    echo "/swap/swapfile none swap defaults,pri=1 0 0" >> "$MOUNT_POINT/etc/fstab"

    log_success "Swap configured: ${ram_gb}GB swapfile + zram"
    echo "  Zram: $(( ram_gb / 2 ))GB compressed (priority 100 - fast swap)" >&2
    echo "  Swapfile: ${ram_gb}GB (priority 1 - fallback)" >&2
}

# --- REBUILD AND UPDATE ---

rebuild_initramfs() {
    log_info "Rebuilding initramfs..."
    echo >&2  # Add blank line for visibility
    # Answer 'y' to the limine-mkinitcpio prompt automatically
    echo "y" | chroot_run "mkinitcpio -P" 2>&1 | tee -a "$LOG_FILE" >&2
    log_success "Initramfs rebuilt"
}

update_limine() {
    log_info "Installing Limine bootloader..."
    echo >&2

    # Try limine-update first (from limine-mkinitcpio-hook)
    if chroot_run "command -v limine-update" &>/dev/null; then
        log_info "Running limine-update..."
        chroot_run "limine-update" 2>&1 | tee -a "$LOG_FILE" >&2 || true
    fi

    # Auto-detect and add Windows bootloader if limine-scan is available
    if chroot_run "command -v limine-scan" &>/dev/null; then
        log_info "Scanning for other bootloaders (Windows, etc.)..."

        # Run limine-scan with 'c' to cancel and capture the boot entry table
        local scan_output
        scan_output=$(chroot_run "echo 'c' | limine-scan 2>&1" || true)

        # Look for Windows/Microsoft entries in the output
        local windows_entry
        windows_entry=$(echo "$scan_output" | grep -i -E "windows|microsoft" | head -1 | awk '{print $1}' || true)

        if [ -n "$windows_entry" ] && [[ "$windows_entry" =~ ^[0-9]+$ ]]; then
            echo "Found Windows bootloader at entry $windows_entry, adding to Limine..." >&2
            chroot_run "echo '$windows_entry' | limine-scan" 2>&1 | tee -a "$LOG_FILE" >&2 || true
        else
            echo "No Windows bootloader detected, skipping..." >&2
        fi
    fi

    # Ensure Limine EFI is installed to fallback location
    log_info "Installing Limine EFI bootloader..."
    chroot_run "
        mkdir -p /boot/EFI/BOOT
        cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/
    " 2>&1 | tee -a "$LOG_FILE" >&2

    log_success "Limine installed"
}

# --- SERVICES AND FINAL SETUP ---

configure_services() {
    log_info "Enabling system services..."
    echo >&2

    chroot_run "
        systemctl enable NetworkManager.service
        systemctl enable plasmalogin.service
        systemctl enable power-profiles-daemon.service 2>/dev/null || true
        systemctl enable bluetooth.service
    " 2>&1 | tee -a "$LOG_FILE" >&2

    log_success "Services enabled"
}

configure_locale() {
    log_info "Configuring locale and timezone..."
    echo >&2

    chroot_run "
        # Timezone
        ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
        hwclock --systohc

        # Locale
        sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
        locale-gen
        echo 'LANG=en_US.UTF-8' > /etc/locale.conf

        # Keyboard
        echo 'KEYMAP=$KEYBOARD' > /etc/vconsole.conf
    " 2>&1 | tee -a "$LOG_FILE" >&2

    log_success "Locale configured"
}

# --- WINTARCH SETUP ---

setup_wintarch() {
    log_info "Setting up wintarch system management..."
    echo >&2

    # Clone wintarch repo
    echo "Cloning wintarch repository..." >&2
    chroot_run "git clone https://github.com/kacpersledz/arch.git /opt/wintarch" 2>&1 | tee -a "$LOG_FILE" >&2

    # Mark /opt/wintarch as safe for all users (owned by root but accessed by users)
    chroot_run "git config --system --add safe.directory /opt/wintarch" 2>&1 | tee -a "$LOG_FILE" >&2

    # Create state directory
    echo "Creating wintarch state directory..." >&2
    chroot_run "mkdir -p /var/lib/wintarch/migrations" 2>&1 | tee -a "$LOG_FILE" >&2

    # Mark all existing migrations as completed (fresh install = current state)
    echo "Initializing migration state..." >&2
    chroot_run "
        for migration in /opt/wintarch/migrations/*.sh; do
            [ -f \"\$migration\" ] || continue
            touch \"/var/lib/wintarch/migrations/\$(basename \"\$migration\")\"
        done
    " 2>&1 | tee -a "$LOG_FILE" >&2

    # Copy version to state
    chroot_run "cp /opt/wintarch/version /var/lib/wintarch/version" 2>&1 | tee -a "$LOG_FILE" >&2

    # Create symlinks in /usr/local/bin/
    echo "Creating command symlinks..." >&2
    chroot_run "
        for cmd in /opt/wintarch/bin/wintarch-*; do
            [ -x \"\$cmd\" ] || continue
            ln -sf \"\$cmd\" \"/usr/local/bin/\$(basename \"\$cmd\")\"
        done
    " 2>&1 | tee -a "$LOG_FILE" >&2

    log_success "Wintarch setup complete"
}

# --- DOCKER SETUP ---

setup_docker() {
    log_info "Configuring Docker..."
    echo >&2

    # Create daemon.json for log rotation
    echo "Creating Docker daemon configuration..." >&2
    chroot_run "
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << 'EOF'
{
    \"log-driver\": \"json-file\",
    \"log-opts\": {
        \"max-size\": \"10m\",
        \"max-file\": \"5\"
    }
}
EOF
    " 2>&1 | tee -a "$LOG_FILE" >&2

    # Enable Docker service
    echo "Enabling Docker service..." >&2
    chroot_run "systemctl enable docker.service" 2>&1 | tee -a "$LOG_FILE" >&2

    # Boot optimization - prevent Docker from blocking boot
    echo "Configuring boot optimization..." >&2
    chroot_run "
        mkdir -p /etc/systemd/system/docker.service.d
        cat > /etc/systemd/system/docker.service.d/no-block-boot.conf << 'EOF'
[Unit]
# Don't block boot if docker fails to start
DefaultDependencies=no
After=network-online.target
Wants=network-online.target
EOF
    " 2>&1 | tee -a "$LOG_FILE" >&2

    log_success "Docker configured"
}

# --- MAIN POST-INSTALL FLOW ---

run_post_install() {
    log_step "Post-Installation Setup"

    # Configure components
    configure_mkinitcpio
    configure_limine
    enable_pacman_colors

    # Install first-boot service (configures snapper on first boot when D-Bus is available)
    install_first_boot_service

    # Install snapshot boot integration
    install_limine_snapper_packages

    # Install user AUR packages (brave, vscode)
    install_aur_packages || true

    # Setup swap (zram + swapfile)
    setup_swap

    # Update Limine (this will trigger mkinitcpio automatically via hooks)
    update_limine

    # Final configuration
    configure_services
    configure_locale

    # Setup wintarch system management
    setup_wintarch

    # Setup Docker
    setup_docker

    # Note: Initial snapshots are created by wintarch-first-boot.service on first boot

    log_success "Post-installation complete"
}
