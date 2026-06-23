#!/bin/bash
# test.sh - Simple QEMU test for the Wintarch installer
#
# Prerequisites:
#   - qemu-system-x86_64
#   - OVMF (UEFI firmware)
#   - Arch Linux ISO (auto-downloaded if missing)
#
# Usage:
#   ./test.sh              # Create disk and boot ISO
#   ./test.sh --boot-disk  # Boot from installed disk
#   ./test.sh --clean      # Remove test files

set -euo pipefail

# Script directory (test.sh is in the test/ directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR"

# Configuration
DISK_FILE="$TEST_DIR/test-disk.qcow2"
DISK_SIZE="60G"
ISO_PATH="${ARCH_ISO:-$TEST_DIR/archlinux-x86_64.iso}"
ISO_URL="https://mirror.rackspace.com/archlinux/iso/latest/archlinux-x86_64.iso"
OVMF_CODE="/usr/share/OVMF/OVMF_CODE.fd"
OVMF_VARS="/usr/share/OVMF/OVMF_VARS.fd"
OVMF_VARS_COPY="$TEST_DIR/test-ovmf-vars.fd"
SSH_PORT=2222
RAM="8G"
CPUS="4"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Ensure test directory exists
ensure_test_dir() {
    mkdir -p "$TEST_DIR"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."

    command -v qemu-system-x86_64 &>/dev/null || error "qemu-system-x86_64 not found"
    command -v qemu-img &>/dev/null || error "qemu-img not found"

    if [[ ! -f "$OVMF_CODE" ]]; then
        # Try alternative paths
        for path in \
            /usr/share/edk2/x64/OVMF_CODE.4m.fd \
            /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
            /usr/share/edk2/ovmf/OVMF_CODE.fd \
            /usr/share/OVMF/x64/OVMF_CODE.fd; do
            if [[ -f "$path" ]]; then
                OVMF_CODE="$path"
                OVMF_VARS="${path/CODE/VARS}"
                break
            fi
        done
        [[ -f "$OVMF_CODE" ]] || error "OVMF firmware not found. Install 'ovmf' or 'edk2-ovmf'"
    fi

    info "Prerequisites OK"
}

# Download Arch ISO if not present
download_iso() {
    if [[ -f "$ISO_PATH" ]]; then
        return 0
    fi

    info "Arch ISO not found at: $ISO_PATH"
    info "Downloading from: $ISO_URL"
    echo

    if command -v curl &>/dev/null; then
        curl -L -o "$ISO_PATH" "$ISO_URL"
    elif command -v wget &>/dev/null; then
        wget -O "$ISO_PATH" "$ISO_URL"
    else
        error "Neither curl nor wget found. Please install one or download manually:
  $ISO_URL"
    fi

    info "ISO downloaded successfully"
}

# Create virtual disk
create_disk() {
    if [[ -f "$DISK_FILE" ]]; then
        warn "Disk file already exists: $DISK_FILE"
        read -p "Delete and recreate? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -f "$DISK_FILE"
        else
            return 0
        fi
    fi

    info "Creating virtual disk: $DISK_FILE ($DISK_SIZE)"
    qemu-img create -f qcow2 "$DISK_FILE" "$DISK_SIZE"
}

# Create OVMF vars copy (for persistent UEFI settings)
create_ovmf_vars() {
    if [[ ! -f "$OVMF_VARS_COPY" ]]; then
        info "Creating OVMF vars copy..."
        cp "$OVMF_VARS" "$OVMF_VARS_COPY"
    fi
}

# Boot from ISO (installation mode)
boot_iso() {
    info "Booting from ISO: $ISO_PATH"
    info "SSH will be available on port $SSH_PORT after boot"
    echo
    info "To connect via SSH (after enabling in live environment):"
    echo "  ssh -p $SSH_PORT root@localhost"
    echo
    info "To run the installer after SSH:"
    echo "  git clone https://github.com/kacpersledz/arch.git"
    echo "  cd arch && ./install.sh"
    echo

    qemu-system-x86_64 \
        -enable-kvm \
        -cpu host \
        -m "$RAM" \
        -smp "$CPUS" \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$OVMF_VARS_COPY" \
        -drive file="$DISK_FILE",format=qcow2,if=virtio \
        -cdrom "$ISO_PATH" \
        -boot d \
        -device virtio-net-pci,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
        -device virtio-vga-gl \
        -display gtk,gl=on \
        -monitor stdio \
        -name "Wintarch Installer Test"
}

# Boot from installed disk
boot_disk() {
    if [[ ! -f "$DISK_FILE" ]]; then
        error "Disk file not found: $DISK_FILE"
    fi

    info "Booting from installed disk: $DISK_FILE"
    info "SSH available on port $SSH_PORT"
    echo

    qemu-system-x86_64 \
        -enable-kvm \
        -cpu host \
        -m "$RAM" \
        -smp "$CPUS" \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$OVMF_VARS_COPY" \
        -drive file="$DISK_FILE",format=qcow2,if=virtio \
        -boot c \
        -device virtio-net-pci,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
        -device virtio-vga-gl \
        -display gtk,gl=on \
        -monitor stdio \
        -name "Wintarch Test"
}

# Clean up test files
clean() {
    info "Cleaning up test files..."
    rm -f "$DISK_FILE" "$OVMF_VARS_COPY"
    # Note: ISO is kept to avoid re-downloading
    info "Done (ISO kept at $ISO_PATH)"
}

# Show help
show_help() {
    cat <<EOF
Wintarch Installer - QEMU Test Script

Usage:
  ./test.sh              Create disk and boot from ISO (installation mode)
  ./test.sh --boot-disk  Boot from installed disk
  ./test.sh --clean      Remove test files (keeps ISO)
  ./test.sh --help       Show this help

Files:
  test/archlinux-x86_64.iso   Arch ISO (auto-downloaded if missing)
  test/test-disk.qcow2        Virtual disk image
  test/test-ovmf-vars.fd      UEFI variables

Environment variables:
  ARCH_ISO    Override ISO path (default: test/archlinux-x86_64.iso)

Prerequisites:
  - qemu-system-x86_64
  - OVMF/edk2-ovmf (UEFI firmware)

After booting the ISO:
  1. Set root password: passwd
  2. Start SSH: systemctl start sshd
  3. Connect: ssh -p 2222 root@localhost
  4. Clone and run installer:
     git clone https://github.com/kacpersledz/arch.git
     cd arch && ./install.sh
EOF
}

# Main
main() {
    case "${1:-}" in
        --boot-disk)
            ensure_test_dir
            check_prerequisites
            create_ovmf_vars
            boot_disk
            ;;
        --clean)
            clean
            ;;
        --help|-h)
            show_help
            ;;
        *)
            ensure_test_dir
            check_prerequisites
            download_iso
            create_disk
            create_ovmf_vars
            boot_iso
            ;;
    esac
}

main "$@"
