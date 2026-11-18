#!/usr/bin/env bash
# scripts/sync-contracts.sh
# Syncs schemas and golden fixtures from LearnCI_Contracts into LearnCI test bundle.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="$PROJECT_ROOT/LearnCITests/Fixtures/Contracts"
LOCAL_CONTRACTS="$PROJECT_ROOT/../LearnCI_Contracts"

echo "Syncing contracts to $TARGET_DIR..."
mkdir -p "$TARGET_DIR/schemas" "$TARGET_DIR/fixtures"

if [ -d "$LOCAL_CONTRACTS" ]; then
    echo "Syncing from local sibling repository ($LOCAL_CONTRACTS)..."
    rsync -av --delete "$LOCAL_CONTRACTS/schemas/" "$TARGET_DIR/schemas/"
    rsync -av --delete "$LOCAL_CONTRACTS/fixtures/" "$TARGET_DIR/fixtures/"
else
    echo "Warning: Local LearnCI_Contracts not found. Pull from remote repository if in CI."
fi

echo "✅ Contracts synchronized successfully."
