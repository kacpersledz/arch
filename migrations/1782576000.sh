#!/bin/bash
# Migration: Enable automatic Snapper number snapshot cleanup.
# Date: 2026-07-14

set -euo pipefail

CONFIG_DIR="/etc/snapper/configs"
CLEANUP_TIMER="snapper-cleanup.timer"

echo "=== Wintarch Snapper Cleanup Timer Migration ==="

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This migration must run as root." >&2
    exit 1
fi

if ! command -v snapper &>/dev/null; then
    echo "Snapper is not installed; nothing to do."
    exit 0
fi

if ! command -v systemctl &>/dev/null; then
    echo "ERROR: systemctl is required to enable $CLEANUP_TIMER." >&2
    exit 1
fi

if [[ ! -d "$CONFIG_DIR" ]]; then
    echo "No Snapper configuration directory at $CONFIG_DIR; nothing to do."
    exit 0
fi

shopt -s nullglob
config_files=("$CONFIG_DIR"/*)
shopt -u nullglob

regular_configs=()
for config_file in "${config_files[@]}"; do
    if [[ -f "$config_file" ]]; then
        regular_configs+=("$config_file")
    fi
done

if [[ ${#regular_configs[@]} -eq 0 ]]; then
    echo "No Snapper configuration files found in $CONFIG_DIR; nothing to do."
    exit 0
fi

echo "Cleaning up excess Snapper number snapshots..."
for config_file in "${regular_configs[@]}"; do
    config="$(basename -- "$config_file")"
    echo "Running number cleanup for Snapper config: $config"
    if ! snapper -c "$config" cleanup number; then
        echo "WARNING: Failed to clean up number snapshots for Snapper config: $config" >&2
    fi
done

echo "Enabling automatic Snapper cleanup timer..."
if ! systemctl enable --now "$CLEANUP_TIMER"; then
    echo "ERROR: Failed to enable and start $CLEANUP_TIMER; automatic Snapper cleanup is not active." >&2
    exit 1
fi

echo "Snapper cleanup timer is enabled."
