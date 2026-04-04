# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-01-28

### Added

-   **Color Support for Package Managers:** Enabled colored output for pacman and yay system-wide.
    -   Automatically uncomments `Color` option in `/etc/pacman.conf` during installation
    -   Works for both pacman (official repos) and yay (AUR packages)
    -   Fresh installations include color support by default
    -   Migration (1769463342) enables colors on existing systems

### Changed

-   **Release Workflow:** Improved release process with version-named branches.
    -   Release branches must now follow `vX.Y.Z` naming pattern (e.g., `v0.5.0`)
    -   Version is automatically derived from branch name (no manual `version` file updates)
    -   Default merge strategy changed from squash to rebase
    -   `/release --squash` and `/release --merge-commit` options still available
    -   Fixed rebase failures caused by shallow clone (now fetches full git history)

## [0.4.0] - 2026-01-18

### Added

-   **Swap Support:** Two-tier swap configuration for optimal performance.
    -   **Zram:** 50% of RAM size, compressed with zstd, priority 100 (used first for fast swapping)
    -   **Swapfile:** RAM size, priority 1 (used as fallback when zram fills)
    -   Dedicated `@swap` BTRFS subvolume with NOCOW attribute
    -   Automatic RAM detection and appropriate swap sizing
    -   Free space check (RAM + 2GB buffer) before migration to prevent disk space issues
    -   Fresh installations include swap configuration automatically
    -   Migration (1737201600) adds swap to existing systems

### Changed

-   **BTRFS Subvolumes:** Added `@swap` subvolume to standard installation layout
-   **Package Updates:** Added `zram-generator` to post-install packages

## [0.3.2] - 2026-01-17

### Fixed

-   **Test Release:** This is a test patch release to verify the version detection fix from v0.3.1 is working correctly.

## [0.3.1] - 2026-01-17

### Fixed

-   **Version Detection:** Fixed `wintarch-update` not detecting new versions when they are available.
    -   Added `--tags` flag to `git fetch` to ensure version tags are fetched
    -   Added `sudo` for git fetch (repository is root-owned)
    -   Replaced silent failure with warning message when fetch fails
    -   Fixes issue where new releases weren't detected until `git pull` ran

## [0.3.0] - 2026-01-17

### Added

-   **Git and SSH Setup:** Added optional git configuration and SSH key generation to user setup.
    -   Interactive prompts for git user.name and user.email during first-time setup
    -   Automatic generation of ed25519 SSH keys with blank password (protected by LUKS encryption)
    -   Existing SSH keys are automatically backed up before regeneration
    -   User migration for existing users to opt-in to git/SSH setup
    -   Accessible via `wintarch-user-update` on fresh installations

## [0.2.0] - 2026-01-17

### Added

-   **Font Support:** Noto fonts are now included in base installation for comprehensive international character and emoji support.
    -   `noto-fonts`: Base Google Noto fonts
    -   `noto-fonts-cjk`: CJK (Chinese, Japanese, Korean) support
    -   `noto-fonts-emoji`: Color emoji support
    -   `noto-fonts-extra`: Additional font variants

-   **Clipboard Manager:** Windows 11-style clipboard history manager with paste simulation support.
    -   `win11-clipboard-history-bin`: Modern clipboard manager with visual history
    -   User added to `input` group for input device access
    -   `uinput` kernel module configured to load at boot for paste functionality

### Changed

-   **Dual-Boot Improvements:** Enhanced Limine bootloader configuration for better dual-boot experience.
    -   Changed default boot entry from 1 to 2, ensuring Arch Linux boots automatically when dual-booting with Windows.
    -   Implemented automatic Windows bootloader detection using `limine-scan` with a two-pass approach (scan → parse → add).
    -   Windows entries are now automatically added to boot menu during installation without user interaction.

### ⚠️ BREAKING CHANGES

> **These changes only affect new installations.** Existing systems will diverge from fresh install state unless manually updated.
>
> **For existing users who want to match fresh install state:**
>
> 1. **Install Noto fonts:**
>    ```bash
>    sudo pacman -S noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra
>    ```
>
> 2. **Install clipboard manager and configure access:**
>    ```bash
>    # Install the AUR package
>    yay -S win11-clipboard-history-bin
>
>    # Add your user to input group
>    sudo usermod -aG input $USER
>
>    # Configure uinput module to load at boot
>    echo 'uinput' | sudo tee /etc/modules-load.d/uinput.conf
>
>    # Load the module now
>    sudo modprobe uinput
>
>    # Log out and back in for group changes to take effect
>    ```
>
> 3. **Update Limine configuration (dual-boot only):**
>    - Edit `/boot/limine.conf` and change `default_entry: 1` to `default_entry: 2`
>    - Run `sudo limine-scan` and select Windows to add it to the boot menu
>
> **Alternatively:** Perform a fresh installation to get all improvements automatically.
>
> _Note: Pre-v1.0, we prioritize rapid development over migration scripts. Breaking changes like these are expected._

## [0.1.0] - 2026-01-16

### Added

-   **New Installer:** Complete rewrite of the system installer, inspired by `omarchy`.
    -   Features a TUI-driven configuration process.
    -   Supports dual-booting with Windows (options to wipe disk, use free space, or use an existing partition).
    -   Enforces mandatory LUKS2 full-disk encryption.
    -   Uses BTRFS with subvolumes (`@`, `@home`, `@log`, `@pkg`) for an efficient filesystem layout.
-   **Bootable Snapshots:** Integrated `limine` bootloader with `snapper`.
    -   Automatically creates system snapshots before updates.
    -   Allows booting into read-only snapshots from the boot menu for easy rollback.
    -   A new `wintarch-snapshot restore` command makes a booted snapshot permanent.
-   **Wintarch System Management:** The installed system is now self-managing via a suite of commands.
    -   `wintarch-update`: Safely updates the system (snapshot -> git pull -> packages -> migrations).
    -   `wintarch-snapshot`: Manages BTRFS snapshots (list, create, delete, restore).
    -   `wintarch-pkg-add`/`drop`: Wrappers for safe package management.
    -   `wintarch-migrations`: A migration system to handle changes on installed systems over time.
-   **User Configuration System:** Added `wintarch-user-update` for managing user-level settings.
    -   Installs and manages Oh My Zsh with custom aliases and configurations.
    -   Installs the Claude Code CLI and adds it to the user's PATH.
    -   Configures the COSMIC desktop dock and sets the default browser on first run.
-   **Included Software & DEs:**
    -   **COSMIC Desktop:** Features System76's modern, Rust-based desktop environment.
    -   **Applications:** Firefox, Brave (default browser), VS Code.
    -   **Development Tools:** `fastfetch`, `btop`, `docker` (with service enabled), and `mise` for version management.
    -   **System Utilities:** Bluetooth support, `curl`, `less`, `gum` for TUI prompts.
-   **Automated Release Workflow:** Implemented a secure, semi-automated release process.
    -   Triggered by a `/release` command in a PR comment by a maintainer.
    -   Automatically merges, bumps the version, tags, and creates a GitHub Release.
-   **Automated Installation:** Added `boot.sh` script to enable one-liner installation from the Arch ISO.
-   **Testing:** Included a QEMU script (`test/test.sh`) for testing installer builds.

### Changed

-   **Project Structure:** Reorganized the repository into a clearer structure (`install/`, `bin/`, `user/`, `systemd/`, etc.).
-   **Root Handling:** Refactored system management scripts to use `sudo` for specific commands instead of requiring the entire script to be run as root, improving compatibility with tools like `yay`.
-   **Installer Output:** Post-installation steps now show real-time output instead of appearing to hang.
-   **Documentation:** Split documentation into a user-focused `README.md` and a developer-focused `CLAUDE.md`.

### Fixed

-   **Snapper Configuration:** Moved Snapper setup to a `systemd` service that runs on first boot, fixing failures caused by the lack of a D-Bus session in the installer's `chroot` environment.
-   **Archinstall Stability:** Resolved multiple issues where `archinstall` would fail due to Python version mismatches or missing dependencies on the live ISO.
-   **Git Pager:** Prevented `wintarch-update` from failing on minimal systems by setting `GIT_PAGER=cat`.
-   **Git Ownership:** Fixed "dubious ownership" errors from `git` by adding `/opt/wintarch` to the system's `safe.directory` list during installation.

[unreleased]: https://github.com/kacpersledz/arch/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/kacpersledz/arch/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/kacpersledz/arch/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/kacpersledz/arch/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/kacpersledz/arch/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/kacpersledz/arch/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/kacpersledz/arch/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/kacpersledz/arch/releases/tag/v0.1.0
