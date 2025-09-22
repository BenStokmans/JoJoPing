#!/usr/bin/env bash
set -euo pipefail

# This script runs in semantic-release prepare step.
# It ensures dependencies are installed for the Raycast extension and prepares paths.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RAYCAST_DIR="$ROOT_DIR/jojoping-raycast"

echo "[prepare] Root: $ROOT_DIR"

echo "[prepare] Installing Raycast extension dependencies"
if command -v pnpm >/dev/null 2>&1; then
  (cd "$RAYCAST_DIR" && pnpm install --frozen-lockfile)
else
  (cd "$RAYCAST_DIR" && npm ci)
fi

echo "[prepare] Done"
