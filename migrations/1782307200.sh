#!/bin/bash
# Migration: Sync wintarch-first-boot.service to the Plasma-aware unit.
# Date: 2026-06-24
# Why: Existing installs can keep the old COSMIC ordering in /etc/systemd/system.

set -euo pipefail

WINTARCH_PATH="${WINTARCH_PATH:-/opt/wintarch}"
SOURCE_UNIT="$WINTARCH_PATH/systemd/wintarch-first-boot.service"
TARGET_UNIT="/etc/systemd/system/wintarch-first-boot.service"
EXPECTED_BEFORE="Before=plasmalogin.service display-manager.service"
LEGACY_BEFORE="Before=cosmic-greeter.service display-manager.service"

echo "=== Wintarch First-Boot Unit Sync ==="

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This migration must run as root." >&2
    exit 1
fi

if [[ ! -f "$SOURCE_UNIT" ]]; then
    echo "ERROR: Source unit not found: $SOURCE_UNIT" >&2
    exit 1
fi

if [[ ! -f "$TARGET_UNIT" ]]; then
    echo "No existing first-boot unit at $TARGET_UNIT; nothing to sync."
    exit 0
fi

if grep -qF "$EXPECTED_BEFORE" "$TARGET_UNIT"; then
    echo "First-boot unit already matches Plasma ordering."
    exit 0
fi

if ! grep -qF "$LEGACY_BEFORE" "$TARGET_UNIT"; then
    echo "First-boot unit does not match the known legacy COSMIC ordering; leaving it unchanged."
    exit 0
fi

install -Dm644 "$SOURCE_UNIT" "$TARGET_UNIT"
systemctl daemon-reload

echo "Updated $TARGET_UNIT to use Plasma ordering."
