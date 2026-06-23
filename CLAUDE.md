# Wintarch - Development Guide

Technical documentation for developing and maintaining Wintarch.

Wintarch is the product identity. Fresh installations use KDE Plasma, but desktop branding must remain separate from product branding. Existing COSMIC-based installs will be migrated in a separate migration PR. The `vendor/` trees are reference-only and are not part of runtime.

## Project Status

- **Phase 1: Installer** - Complete
- **Phase 2: System Management (wintarch-*)** - Complete
- **Phase 3: User Configuration** - In Progress

## Documentation Structure

**IMPORTANT**: This repo has two audiences with different documentation:

**For end users (people who installed Wintarch)**:
- [README.md](README.md) - Installation instructions, usage, available commands

**For developers (people working on this repo)**:
- [CONTRIBUTING.md](CONTRIBUTING.md) - Development workflow, testing, releases, migrations
- [CLAUDE.md](CLAUDE.md) - This file - Architecture, file structure, implementation details

When adding features or documentation, remember this distinction:
- User-facing changes (new commands, usage) → Update README.md
- Developer-facing changes (architecture, implementation) → Update CLAUDE.md or CONTRIBUTING.md

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  1. CONFIGURATOR (TUI)                                          │
│     - Keyboard layout, user account, hostname, timezone         │
│     - Disk selection with dual-boot options                     │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  2. PARTITIONING                                                │
│     - Detect/reuse existing EFI partition                       │
│     - Create LUKS container, BTRFS with subvolumes              │
│     - Subvolumes: @, @home, @log, @pkg, @swap                   │
│     - Mount to /mnt/archinstall                                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  3. ARCHINSTALL (pinned version: 3.0.9-1)                       │
│     - pre_mounted_config mode (uses our mounts)                 │
│     - JSON config generated dynamically                         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  4. POST-INSTALL (chroot)                                       │
│     - mkinitcpio with encrypt + btrfs-overlayfs hooks           │
│     - Limine bootloader configuration                           │
│     - Snapper, AUR packages (brave, vscode, clipboard-manager)  │
│     - Clipboard manager setup (uinput, input group)             │
│     - Swap setup (zram + RAM-sized swapfile)                    │
│     - Wintarch setup (/opt/wintarch/, symlinks, state)          │
└─────────────────────────────────────────────────────────────────┘
```

## File Structure

```
arch/
├── bin/                   # Wintarch commands (symlinked to /usr/local/bin/)
│   ├── wintarch-update    # System update command
│   ├── wintarch-user-update # User configuration (OMZ, dotfiles)
│   ├── wintarch-snapshot  # BTRFS snapshot management
│   ├── wintarch-migrations # Migration runner
│   ├── wintarch-pkg-add   # Safe package install
│   ├── wintarch-pkg-drop  # Safe package removal
│   └── wintarch-version   # Show version
├── user/                  # User-level configuration
│   ├── scripts/           # Setup/update scripts (omz.sh)
│   ├── dotfiles/          # Managed dotfiles (zshrc, aliases)
│   └── migrations/        # User-level migrations (timestamp-named .sh files)
├── install/               # Installer scripts
│   ├── install.sh         # Main entry point
│   ├── helpers.sh         # Logging, errors, presentation
│   ├── configurator.sh    # TUI for user input
│   ├── disk.sh            # Disk detection and selection
│   ├── partitioning.sh    # LUKS, BTRFS, mounting
│   ├── archinstall.sh     # JSON generation, archinstall invocation
│   └── post-install.sh    # Limine-snapper setup, wintarch setup
├── migrations/            # Wintarch migrations (timestamp-named .sh files)
├── version                # Wintarch version (e.g., v0.1.0)
├── test/                  # Test scripts
└── vendor/                # Reference implementations (not runtime dependencies)
```

## Key Implementation Details

### User Configuration (install/archinstall.sh)

User created during archinstall with groups:
- `wheel` - sudo access
- `input` - access to input devices (required for clipboard manager)

### Packages (install/archinstall.sh)

Base packages via archinstall JSON:
- base-devel, git, curl, less, vim, networkmanager
- snapper, limine, KDE Plasma, SDDM
- xdg-desktop-portal, xdg-desktop-portal-kde, power-profiles-daemon
- firefox, zsh, bluez, bluez-utils

Post-install packages (install/post-install.sh):
- zram-generator (official repos)

AUR packages via yay (install/post-install.sh):
- limine-snapper-sync, limine-mkinitcpio-hook
- brave-bin, visual-studio-code-bin, win11-clipboard-history-bin

### Services Enabled

- NetworkManager.service
- sddm.service
- power-profiles-daemon.service
- bluetooth.service
- limine-snapper-sync.service

### mkinitcpio Hooks

```
HOOKS=(base udev keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)
```

### mkinitcpio Optimization

We disable mkinitcpio hooks during post-install to avoid multiple rebuilds:
- `install/post-install.sh:disable_mkinitcpio_hooks()` - disables before package installs
- `install/post-install.sh:enable_mkinitcpio_hooks()` - re-enables at the end
- Single `mkinitcpio -P` at the end

### Clipboard Manager Setup

The Windows 11-style clipboard manager (win11-clipboard-history-bin) requires access to `/dev/uinput` for paste simulation:

**Requirements:**
- User in `input` group (configured in archinstall user creation)
- `uinput` kernel module loaded at boot via `/etc/modules-load.d/uinput.conf` (configured in post-install)

This allows the clipboard manager to simulate keyboard input for paste operations without requiring root access.

### Swap Configuration

Wintarch configures a two-tier swap system for optimal performance:

**Architecture:**
- **Zram** (50% of RAM, priority 100) - Compressed swap in RAM, used first
- **Swapfile** (100% of RAM, priority 1) - Disk-based swap, used as fallback

**Why Two-Tier:**
- Zram provides fast, compressed swap for everyday use (browser tabs, inactive apps)
- Swapfile catches overflow when zram fills
- Priority system ensures zram is always used first

**BTRFS Subvolume:**
- Swap stored in dedicated `@swap` subvolume (not snapshotted)
- NOCOW attribute set on swapfile (required for BTRFS swapfiles)

**Implementation:**
- Fresh installs: `install/partitioning.sh` creates @swap, `install/post-install.sh` configures swap
- Existing systems: `migrations/1737201600.sh` adds swap with free space check (RAM + 2GB buffer)
- Migration aborts if insufficient disk space to avoid system issues

**Note:** Swapfile is sized equal to RAM which could support hibernation in the future, but hibernation configuration is currently out of scope.

### Wintarch Locations

| Path | Purpose |
|------|---------|
| `/opt/wintarch/` | Full repo (bin/, migrations/, install/) |
| `/var/lib/wintarch/` | State directory |
| `/var/lib/wintarch/version` | Installed version |
| `/var/lib/wintarch/migrations/` | Completed migration markers |
| `/usr/local/bin/wintarch-*` | Symlinks to /opt/wintarch/bin/ |

### Migrations

- Filename format: Unix timestamp (e.g., `1704067200.sh`)
- Fresh installs mark all existing migrations as completed
- `wintarch-update` runs pending migrations after package updates
- See [CONTRIBUTING.md](CONTRIBUTING.md#creating-migrations) for comprehensive migration guide

## Breaking Changes Philosophy

**Core Principle:** Fresh install state must equal updated system state.

Any change that creates divergence between a fresh installation and an updated existing system is considered a **breaking change**, even if existing systems continue to function correctly.

### Examples of Breaking Changes

- **New packages in base install**: Fresh installs have them, existing systems don't
- **Configuration file changes**: Fresh installs get new config, existing keep old config
- **Bootloader modifications**: Fresh installs have updated settings, existing don't

### Pre-v1.0 Strategy

Before reaching v1.0, we prioritize rapid development over migration complexity:

- ✅ Breaking changes are **expected and acceptable**
- ✅ Mark them clearly in CHANGELOG.md with ⚠️ BREAKING CHANGES section
- ✅ Provide manual migration steps for users who want to match fresh install state
- ✅ Offer alternative: perform a fresh installation
- ❌ Do NOT create complex migrations for every breaking change

### Post-v1.0 Commitment

After v1.0, we will maintain strict equivalence:

- All installer changes MUST have corresponding migrations
- `wintarch-update` MUST bring systems to fresh install state
- Breaking changes require major version bump (per semver)

### When to Create Migrations Now (Pre-v1.0)

Only create migrations for:

1. **Critical security fixes** that all users must have
2. **System-breaking changes** that would cause actual failures
3. **Data loss prevention** where missing the change loses user data

Otherwise, document in CHANGELOG and let users choose manual migration or fresh install.

## Development

### Testing
```bash
./test/test.sh              # Create disk and boot ISO
./test/test.sh --boot-disk  # Test installed system
```

Uses QEMU with OVMF for EFI testing.

### Updating Archinstall

When archinstall updates break compatibility:
1. Check new JSON schema: `archinstall --dry-run`
2. Update `install/archinstall.sh`
3. Update pinned version (currently 3.0.9-1)

### TUI Library

Uses [gum](https://github.com/charmbracelet/gum):
- `gum input` / `gum input --password`
- `gum choose` / `gum confirm`
- `gum spin` / `gum style`

## Reference Sources

### Code Origins

| Our File | Based On |
|----------|----------|
| `install/helpers.sh` | `omarchy/install/helpers/*.sh` |
| `install/configurator.sh` | `omarchy-iso/.../configurator` |
| `install/archinstall.sh` | `omarchy-iso/.../.automated_script.sh` |
| `install/post-install.sh` | `omarchy/install/login/limine-snapper.sh` |
| `bin/wintarch-*` | `omarchy/bin/omarchy-*` |

### Omarchy Reference Files
```
vendor/omarchy-iso/configs/airootfs/root/
├── configurator              # TUI for user input
└── .automated_script.sh      # archinstall flow

vendor/omarchy/install/
├── helpers/                  # Presentation, errors, logging
├── preflight/disable-mkinitcpio.sh  # Speed optimization
└── login/limine-snapper.sh   # Snapper + Limine config
```

## User Configuration

Per-user configuration separate from system updates. Designed for on-demand use.

### Commands

| Command | Purpose |
|---------|---------|
| `wintarch-update` | System updates (packages, migrations). Optionally runs user update. |
| `wintarch-user-update` | User config (OMZ, dotfiles). Self-bootstrapping on first run. |

### User State

| Path | Purpose |
|------|---------|
| `~/.local/state/wintarch/` | Per-user state directory |
| `~/.local/state/wintarch/user-setup-done` | Marker for first-run completion |
| `~/.local/state/wintarch/migrations/` | Completed user migration markers |
| `~/.oh-my-zsh/` | Oh My Zsh installation |

### What `wintarch-user-update` Does

**First run**: Installs OMZ, plugins, configures zshrc, sets zsh as default shell
**Subsequent runs**: Updates OMZ and plugins

### Dotfiles Strategy

Uses source pattern - user's `~/.zshrc` sources managed config:
```bash
# ~/.zshrc
source /opt/wintarch/user/dotfiles/zshrc  # Managed by wintarch
# User customizations below...
```

This allows updates without overwriting user customizations.
