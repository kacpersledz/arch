# Wintarch

Wintarch is an opinionated Arch Linux system with its own defaults, BTRFS snapshots, and simple system management.

Fresh Wintarch installations use KDE Plasma with `plasma-login-manager`. Existing installations are migrated to the same login stack through the standard `wintarch-update` / `wintarch-migrations` flow. The migration can switch from COSMIC Greeter or SDDM to `plasmalogin.service`; COSMIC and SDDM packages remain installed for rollback until a separate legacy-cleanup step. The project is inspired by [Omarchy](https://github.com/basecamp/omarchy), which is retained only as a development reference and is not a runtime dependency.

## Features

- **KDE Plasma Desktop** - Plasma with Plasma Login Manager and the KDE desktop portal
- **BTRFS with Snapshots** - Automatic snapshots before updates, bootable rollback via Limine
- **LUKS Encryption** - Full disk encryption (mandatory)
- **Dual-Boot Friendly** - Preserve Windows, use free space, or existing partitions
- **Smart Swap** - Two-tier swap (zram + swapfile) for optimal performance
- **Simple Updates** - One command (`wintarch-update`) handles everything safely
- **Pre-configured** - Ready to use out of the box

## What's Included

### Desktop & System
- KDE Plasma desktop + Plasma Login Manager
- Plasma's native clipboard manager
- PipeWire audio
- NetworkManager
- Bluetooth (bluez + bluez-utils, service enabled)
- Power profiles daemon

### Applications
- Firefox - Web browser
- Brave - Privacy-focused browser (AUR)
- VS Code - Code editor (AUR)
- Vim - Terminal editor

### Shell & Tools
- Zsh + Oh My Zsh - Modern shell with plugins (optional, via `wintarch-user-update`)
- Git - Version control
- yay - AUR helper

## Requirements

- UEFI system (Legacy BIOS not supported)
- Minimum 40GB free space
- Internet connection

## Installation

Boot from Arch Linux live USB, then:

```bash
# Connect to internet (if on WiFi)
iwctl
# station wlan0 scan
# station wlan0 connect <network>

# One-liner install (recommended)
curl -fsSL https://raw.githubusercontent.com/kacpersledz/arch/master/boot.sh | bash

# Or clone manually
git clone https://github.com/kacpersledz/arch.git
cd arch
./install/install.sh
```

The TUI installer will guide you through:
- Keyboard layout
- Username & password
- Hostname & timezone
- Disk selection (wipe, use free space, or existing partition)

## Partition Layout

| Partition | Size | Type | Encryption |
|-----------|------|------|------------|
| EFI | 2GB | FAT32 | No |
| Root | Remaining | BTRFS | LUKS2 |

### BTRFS Subvolumes

| Subvolume | Mountpoint | Purpose |
|-----------|------------|---------|
| @ | / | Root filesystem |
| @home | /home | User data |
| @log | /var/log | System logs |
| @pkg | /var/cache/pacman/pkg | Package cache |
| @swap | /swap | Swap storage |

## System Management

### Update System
```bash
wintarch-update        # Update system (creates snapshot first)
wintarch-update -y     # Skip confirmation
```

The update process:
1. Creates BTRFS snapshot (for easy rollback)
2. Pulls latest wintarch from git
3. Updates system packages (pacman + yay)
4. Runs any new migrations
5. Prompts for reboot if kernel updated

The Plasma migration requires and creates its own safety snapshot before installing the fresh-install Plasma baseline and switching the display-manager alias to `plasmalogin.service`. It stops before making changes if snapshot support is unavailable. It does not restart the active display manager or remove COSMIC/SDDM packages.

A subsequent legacy-runtime cleanup migration removes only the explicitly approved `cosmic`, `cosmic-greeter`, `xdg-desktop-portal-cosmic`, and `win11-clipboard-history-bin` packages after verifying the Plasma login stack. Plasma provides its own clipboard manager, so `win11-clipboard-history-bin` is no longer installed. The cleanup preserves `~/.config/cosmic`, legacy clipboard-manager user configuration, and the SDDM package. It requires a working Snapper snapshot and stops before changes if one cannot be created. Rollback uses the pre-cleanup snapshot or manual package reinstallation.

### Manage Snapshots
```bash
wintarch-snapshot list              # List all snapshots
wintarch-snapshot create "message"  # Create manual snapshot
wintarch-snapshot delete 5          # Delete snapshot #5
wintarch-snapshot restore           # Restore from booted snapshot
```

### Package Management
```bash
wintarch-pkg-add package-name   # Install with verification
wintarch-pkg-drop package-name  # Remove (no error if missing)
```

### User Configuration
```bash
wintarch-user-update  # Setup/update user config (Oh My Zsh, dotfiles)
```

First run installs Oh My Zsh with plugins and sets zsh as default shell. Subsequent runs update OMZ and plugins.

### Other Commands
```bash
wintarch-version      # Show installed version
wintarch-migrations   # Check migration status
```

## Bootable Snapshots

If something breaks:
1. Reboot -> Limine menu -> "Snapshots" -> select one
2. System boots into snapshot (read-only overlay)
3. Run `wintarch-snapshot restore` to make it permanent
4. Reboot

Up to 5 snapshots appear in the boot menu via limine-snapper-sync.

## Swap

Wintarch automatically configures smart swap for optimal performance:

- **Zram** (50% of RAM) - Fast compressed swap in RAM
- **Swapfile** (same size as RAM) - Disk-based swap for overflow

The system uses zram first for speed, then falls back to the swapfile when needed.

## Differences from Omarchy

| Aspect | Omarchy | Wintarch |
|--------|---------|----------|
| Desktop | Hyprland | KDE Plasma |
| Disk mode | Wipe only | Dual-boot support |
| Auto-login | Yes | No (multi-user) |
| Target | Single user | General purpose |

## License

MIT

## Acknowledgments

Inspired by [Omarchy](https://omarchy.org) by DHH.

## Contributing

Want to contribute? See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, architecture overview, and how to submit changes.
