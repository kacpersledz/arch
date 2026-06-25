#!/bin/bash
# Migration: Enable hibernation on existing standard Wintarch installs.
# Date: 2026-06-24

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../install/hibernation.sh"

main() {
    echo "=== Wintarch Existing-Install Hibernation Migration ==="
    wintarch_enable_hibernation "Existing install"
    echo "Reboot, then test manually with: systemctl hibernate"
}

main "$@"
