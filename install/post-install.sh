#!/bin/bash
# install/post-install.sh - Post-installation setup
# Based on omarchy's install/login/limine-snapper.sh
#
# This runs AFTER archinstall, in chroot, to configure:
# - mkinitcpio with proper hooks for LUKS + BTRFS
# - Limine bootloader with snapshot support
# - Snapper for BTRFS snapshots
# - COSMIC desktop greeter
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
    chroot_run "cat > /etc/mkinitcpio.conf.d/arch-cosmic.conf << 'EOF'
# Arch COSMIC Installer - mkinitcpio configuration
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
TARGET_OS_NAME=\"Arch Linux COSMIC\"

ESP_PATH=\"/boot\"

KERNEL_CMDLINE[default]=\"$cmdline\"

ENABLE_UKI=yes
CUSTOM_UKI_NAME=\"archcosmic\"

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
### Arch Linux COSMIC - Limine Configuration
timeout: 5
default_entry: 2
interface_branding: Arch Linux COSMIC
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

install_limine_snapper_packages() {
    log_info "Installing Limine-Snapper integration packages from AUR..."
    echo >&2

    # Check if packages exist in official repos first
    if chroot_run "pacman -Ss limine-snapper-sync" &>/dev/null; then
        chroot_run "pacman -S --noconfirm --needed limine-snapper-sync limine-mkinitcpio-hook" 2>&1 | tee -a "$LOG_FILE" >&2 || {
            log_warn "Failed to install Limine-Snapper packages from pacman repos"
            return 1
        }
    else
        # Fall back to AUR
        if ! install_aur_helper; then
            log_warn "Failed to install yay for Limine-Snapper packages"
            return 1
        fi

        chroot_run "
            echo '$USERNAME ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/temp-build
            sudo -u '$USERNAME' yay -S --noconfirm --needed limine-snapper-sync limine-mkinitcpio-hook
            rm -f /etc/sudoers.d/temp-build
        " 2>&1 | tee -a "$LOG_FILE" >&2 || {
            log_warn "Failed to install Limine-Snapper packages"
            return 1
        }
    fi

    # Update mkinitcpio hooks to include btrfs-overlayfs
    echo "Updating mkinitcpio hooks for btrfs-overlayfs..." >&2
    chroot_run "
        if [ -f /usr/lib/initcpio/install/btrfs-overlayfs ]; then
            sed -i 's/^HOOKS=.*/HOOKS=(base udev keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)/' /etc/mkinitcpio.conf.d/arch-cosmic.conf
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
    log_info "Installing AUR packages (brave, vscode, clipboard-manager)..."
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
        sudo -u '$USERNAME' yay -S --noconfirm --needed brave-bin visual-studio-code-bin win11-clipboard-history-bin
        rm -f /etc/sudoers.d/temp-build
    " 2>&1 | tee -a "$LOG_FILE" >&2 || {
        log_warn "Failed to install some AUR packages"
        return 1
    }

    log_success "AUR packages installed"
    return 0
}

# --- CLIPBOARD MANAGER SETUP ---

configure_clipboard_manager() {
    log_info "Configuring clipboard manager (uinput module)..."
    echo >&2

    # Configure uinput module to load at boot
    # Note: User is already in 'input' group from archinstall user creation
    echo "Configuring uinput module to load at boot..." >&2
    chroot_run "cat > /etc/modules-load.d/uinput.conf << 'EOF'
# Load uinput module for clipboard manager
uinput
EOF" 2>&1 | tee -a "$LOG_FILE" >&2

    log_success "Clipboard manager configured"
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
        systemctl enable cosmic-greeter.service
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

    # Install user AUR packages (brave, vscode, clipboard-manager)
    install_aur_packages || true

    # Configure clipboard manager requirements (uinput, input group)
    configure_clipboard_manager

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
