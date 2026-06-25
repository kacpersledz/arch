#!/bin/bash
# Migration: Configure HibernateMode=shutdown for reliable hibernation poweroff.
# Date: 2026-06-25

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../install/hibernation.sh"

main() {
    echo "=== Wintarch Hibernation Shutdown-Mode Migration ==="
    wintarch_configure_hibernate_shutdown_mode "Existing install"
}

main "$@"
