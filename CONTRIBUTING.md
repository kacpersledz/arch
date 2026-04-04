# Contributing to Wintarch

This guide is for developers working on Wintarch itself. If you're looking for how to *use* Wintarch, see [README.md](README.md).

## Documentation Structure

**For end users (installed system)**:
- [README.md](README.md) - Installation, usage, commands

**For developers (this repo)**:
- This file (CONTRIBUTING.md) - Development workflow, testing, releases, migrations
- [CLAUDE.md](CLAUDE.md) - Architecture, file structure, implementation details

## Quick Start

```bash
# Clone the repo
git clone https://github.com/kacpersledz/arch.git
cd arch

# Test in a VM
./test/test.sh              # Create disk and boot ISO
./test/test.sh --boot-disk  # Test installed system
```

## Architecture Overview

Wintarch is a wrapper around archinstall that adds:
- TUI configurator for user input (keyboard, disk, etc.)
- BTRFS + LUKS partitioning with dual-boot support
- Post-install configuration (Limine, Snapper, COSMIC, wintarch tools)
- Migration system for managing updates to installed systems

See [CLAUDE.md](CLAUDE.md) for detailed architecture and file structure.

### Installation Flow

```
1. TUI Configurator     → Gather user input
2. Partitioning        → LUKS + BTRFS setup
3. Archinstall         → Base system install
4. Post-install        → Wintarch setup
```

### Installed System

After installation, Wintarch lives at:
- `/opt/wintarch/` - Full repo (bin/, migrations/, install/)
- `/usr/local/bin/wintarch-*` - Symlinks to bin/ scripts
- `/var/lib/wintarch/` - State (version, migration markers)

## Making Changes

### Adding Features

1. **Create feature branch**
   ```bash
   git checkout -b feature/my-feature
   ```

2. **Make changes**
   - Scripts in `install/` for installer changes
   - Scripts in `bin/` for system management commands
   - Scripts in `user/` for user-level configuration

3. **Add migration if needed**
   - If feature requires changes on existing installations, create a migration
   - See "Creating Migrations" section below for complete guide
   ```bash
   timestamp=$(date +%s)
   touch "migrations/$timestamp.sh"
   chmod +x "migrations/$timestamp.sh"
   ```

4. **Test in VM**
   ```bash
   ./test/test.sh
   ```

5. **Commit with clear message**
   ```bash
   git commit -m "feat: Add feature description

   - Detail what changed
   - Note if migration is included"
   ```

### Creating Migrations

#### When to Use Migrations

Create a migration when you need to:
- Enable/configure new systemd services
- Modify system configuration files on existing installations
- Update user dotfiles or shell configurations
- Install additional packages or dependencies
- Fix issues that require changes on already-installed systems

**Don't use migrations for**:
- Changes that only affect new installations (add to `install/post-install.sh` instead)
- Package updates (handled by `pacman`/`yay` automatically)

#### Quick Start

**System Migration**:
```bash
# 1. Create migration file
timestamp=$(date +%s)
sudo touch "/opt/wintarch/migrations/$timestamp.sh"
sudo chmod +x "/opt/wintarch/migrations/$timestamp.sh"

# 2. Edit the file
sudo vim "/opt/wintarch/migrations/$timestamp.sh"
```

Template:
```bash
#!/bin/bash
# Migration: Brief description of what this does
# Date: YYYY-MM-DD
# Why: Reason for this change

set -e  # Exit on error

# Your changes here

echo "Migration completed"
```

**User Migration**: Same process, but in `/opt/wintarch/user/migrations/` and runs as user (no sudo in the script).

#### File Naming

**Use Unix timestamp**: `date +%s` gives you a sortable, unique filename like `1704067200.sh`

Why timestamps?
- Automatically sorted chronologically
- Always unique
- No version numbering conflicts

#### Writing Good Migrations

**1. Make It Idempotent**

Bad:
```bash
echo "source /opt/wintarch/user/dotfiles/zshrc" >> ~/.zshrc
systemctl enable myservice.service
```

Good:
```bash
# Check before adding
if ! grep -q "source /opt/wintarch/user/dotfiles/zshrc" ~/.zshrc; then
    echo "source /opt/wintarch/user/dotfiles/zshrc" >> ~/.zshrc
fi

# Check if service exists and isn't already enabled
if systemctl list-unit-files | grep -q "myservice.service"; then
    if ! systemctl is-enabled myservice.service &>/dev/null; then
        systemctl enable myservice.service
    fi
fi
```

**2. Handle Missing Dependencies**

```bash
# Don't assume a file/command exists
if [[ ! -f /path/to/config ]]; then
    echo "Config not found, skipping"
    exit 0
fi

if ! command -v some-tool &>/dev/null; then
    echo "Tool not installed, skipping"
    exit 0
fi
```

**3. Use set -e**

Always add `set -e` at the top so the script fails fast on any error.

**4. Test Before Deploying**

```bash
# Test system migration manually
sudo bash /opt/wintarch/migrations/1704067200.sh

# Check status
wintarch-migrations --status
```

#### Common Patterns

Check if already done:
```bash
if [[ -f ~/.config/myapp/migrated ]]; then
    echo "Already migrated"
    exit 0
fi
```

Backup before modifying:
```bash
CONFIG="$HOME/.config/app/config.json"
if [[ -f "$CONFIG" ]]; then
    cp "$CONFIG" "$CONFIG.backup-$(date +%s)"
fi
```

Add to config file safely:
```bash
CONFIG="$HOME/.zshrc"
LINE="export MY_VAR=value"

if ! grep -qF "$LINE" "$CONFIG"; then
    echo "$LINE" >> "$CONFIG"
fi
```

Enable systemd service:
```bash
SERVICE="myapp.service"

if systemctl list-unit-files | grep -q "$SERVICE"; then
    if ! systemctl is-enabled "$SERVICE" &>/dev/null; then
        systemctl enable "$SERVICE"
    fi
fi
```

#### How Migrations Run

**System Migrations**:
- **Command**: `wintarch-migrations --run` (or via `wintarch-update`)
- **Location**: `/opt/wintarch/migrations/*.sh`
- **State**: `/var/lib/wintarch/migrations/` (completed) and `skipped/` (skipped)
- **Runs as**: root

**User Migrations**:
- **Command**: `wintarch-user-update` (calls `user/scripts/migrations.sh`)
- **Location**: `/opt/wintarch/user/migrations/*.sh`
- **State**: `~/.local/state/wintarch/migrations/` (completed) and `skipped/` (skipped)
- **Runs as**: regular user

**On Fresh Install**: All existing migrations are automatically marked as completed during `install/post-install.sh`. Only migrations created *after* installation will run.

#### Troubleshooting Migrations

**Migration Failed**:
```bash
# Run manually to see error details
sudo bash /opt/wintarch/migrations/1704067200.sh

# Fix the script and run migrations again
wintarch-migrations --run
```

**Retry a Skipped Migration**:
```bash
# Remove skip marker
sudo rm /var/lib/wintarch/migrations/skipped/1704067200.sh

# Run again
wintarch-migrations --run
```

**Check Migration Status**:
```bash
# System migrations
wintarch-migrations --status

# Shows:
# - Pending (will run next)
# - Completed (already done)
# - Skipped (failed and user chose to skip)
```

#### Migration Examples

**Example 1: Enable New Service**

```bash
#!/bin/bash
# Migration: Enable wintarch-update-check timer
# Date: 2024-01-15
# Why: New auto-update feature needs background timer

set -e

TIMER="wintarch-update-check.timer"

if ! systemctl list-unit-files | grep -q "$TIMER"; then
    echo "Timer not found, skipping"
    exit 0
fi

if ! systemctl is-enabled "$TIMER" &>/dev/null; then
    systemctl enable "$TIMER"
    echo "Enabled $TIMER"
else
    echo "$TIMER already enabled"
fi

echo "Migration completed"
```

**Example 2: Update User Config (User Migration)**

```bash
#!/bin/bash
# User Migration: Add zsh-syntax-highlighting plugin
# Date: 2024-01-20
# Why: Better shell experience for all users

set -e

PLUGIN_DIR="$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"

if [[ -d "$PLUGIN_DIR" ]]; then
    echo "Plugin already installed"
    exit 0
fi

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    echo "Oh My Zsh not installed, skipping"
    exit 0
fi

git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$PLUGIN_DIR"

echo "User migration completed"
```

**Example 3: Fix Config File**

```bash
#!/bin/bash
# Migration: Fix mkinitcpio hooks order
# Date: 2024-02-01
# Why: btrfs-overlayfs must come after filesystems

set -e

CONFIG="/etc/mkinitcpio.conf"
BACKUP="$CONFIG.backup-$(date +%s)"

if [[ ! -f "$CONFIG" ]]; then
    echo "Config not found"
    exit 0
fi

# Check if fix is already applied
if grep -q "HOOKS=.*filesystems.*btrfs-overlayfs" "$CONFIG"; then
    echo "Already fixed"
    exit 0
fi

# Backup
cp "$CONFIG" "$BACKUP"

# Fix the order (example - adjust regex as needed)
sed -i 's/HOOKS=\(.*btrfs-overlayfs.*filesystems.*\)/HOOKS=\1/' "$CONFIG"

# Rebuild initramfs
mkinitcpio -P

echo "Migration completed"
```

### Modifying Installation

Files in `install/` control the installation process:

| File | Purpose |
|------|---------|
| `install.sh` | Main entry point |
| `configurator.sh` | TUI for user input |
| `disk.sh` | Disk detection |
| `partitioning.sh` | LUKS + BTRFS setup |
| `archinstall.sh` | Generate JSON, run archinstall |
| `post-install.sh` | Post-install configuration |
| `helpers.sh` | Logging, errors, presentation |

### Adding Packages

**For new installations**: Add to `install/archinstall.sh` (base packages) or `install/post-install.sh` (AUR packages)

**For existing installations**: Create migration that checks/installs package

### Updating mkinitcpio Hooks

We disable mkinitcpio hooks during post-install to avoid multiple rebuilds:
- `install/post-install.sh:disable_mkinitcpio_hooks()`
- `install/post-install.sh:enable_mkinitcpio_hooks()`

Only re-enable at the end, then run `mkinitcpio -P` once.

## Testing

### VM Testing with QEMU

```bash
# Full test - creates disk, boots ISO, runs installer
./test/test.sh

# Test installed system
./test/test.sh --boot-disk

# Clean up test files
rm -rf test/*.img test/*.iso
```

The test script:
- Creates 100GB disk image
- Downloads Arch ISO
- Boots with QEMU + OVMF (UEFI)
- You manually run the installer in the VM

### Testing Migrations

```bash
# In a VM with Wintarch installed
sudo bash /opt/wintarch/migrations/1704067200.sh

# Check status
wintarch-migrations --status
```

## Release Process

This project uses a semi-automated release process managed by a GitHub Action. The version is derived from the branch name, then a maintainer triggers the release by commenting on an approved pull request.

### How to Release

Only users with write access can trigger releases.

**1. Create a version branch**

Branch names must follow the `vX.Y.Z` pattern:
```bash
# For bugfixes: v0.1.0 → v0.1.1
git checkout -b v0.1.1

# For new features: v0.1.1 → v0.2.0
git checkout -b v0.2.0

# For breaking changes: v0.2.0 → v1.0.0
git checkout -b v1.0.0
```

The version file will be updated automatically from the branch name during release.

**2. Make changes and open PR**

Commit your changes and open a pull request.

**3. Get PR approved**

Ensure the PR is reviewed and approved.

**4. Comment on the PR**

Post a `/release` comment on the approved PR. Optionally specify merge strategy:
- `/release` - Default (rebase and fast-forward)
- `/release --squash` - Squash merge
- `/release --merge-commit` - Create merge commit

**5. Automation runs**

The GitHub Action will:
1. Validate branch name matches `vX.Y.Z` pattern
2. Extract version from branch name
3. Merge the PR using your chosen strategy (rebase by default)
4. Update `version` file with the extracted version
5. Create commit: `chore(release): v0.2.0`
6. Tag the commit with the version
7. Publish GitHub Release with auto-generated notes
8. Close PR with link to release

### Versioning

- Version derived from release branch name (e.g., `v0.5.0`)
- Follows semantic versioning (vMAJOR.MINOR.PATCH)
- Version file updated automatically during release
- Displayed to users via `wintarch-version` command

## Code Style

### Shell Scripts

- Use `#!/bin/bash` shebang
- Use `set -e` to fail fast
- Quote variables: `"$var"` not `$var`
- Check before modifying (idempotent)
- Use helper functions from `install/helpers.sh`

### Error Handling

```bash
# Good
if ! command -v something &>/dev/null; then
    log_error "something not found"
    exit 1
fi

# Also good - let set -e handle it
command_that_might_fail
```

### Logging

Use helpers from `install/helpers.sh`:
```bash
log_info "Information message"
log_success "Success message"
log_warning "Warning message"
log_error "Error message"
```

## Common Tasks

### Update Archinstall Version

When archinstall updates break compatibility:

1. Check new JSON schema:
   ```bash
   archinstall --dry-run
   ```

2. Update `install/archinstall.sh` with new format

3. Update pinned version (currently 3.0.9-1)

### Add New wintarch-* Command

1. Create script in `bin/wintarch-mycommand`
2. Make executable: `chmod +x bin/wintarch-mycommand`
3. Symlink is created by `install/post-install.sh:setup_wintarch()`
4. For existing systems, create migration to add symlink

### Modify User Configuration

Changes to user config (zsh, dotfiles):
- Modify scripts in `user/scripts/`
- Update dotfiles in `user/dotfiles/`
- Create user migration if needed (in `user/migrations/`)

## Project Structure

```
arch/
├── README.md              # User documentation
├── CONTRIBUTING.md        # This file (developer docs)
├── CLAUDE.md              # AI/developer reference (architecture)
├── bin/                   # Wintarch commands
├── user/                  # User-level configuration
├── install/               # Installer scripts
├── migrations/            # System migrations
├── test/                  # Test scripts
└── vendor/                # Reference implementations
```

## Getting Help

- **Issues**: File bugs/features on GitHub
- **Architecture**: See [CLAUDE.md](CLAUDE.md)
- **Migrations**: See "Creating Migrations" section above
- **Original inspiration**: [Omarchy](https://github.com/basecamp/omarchy)

## License

MIT
