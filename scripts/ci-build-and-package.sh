#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RAYCAST_DIR="$ROOT_DIR/jojoping-raycast"
BUILD_DIR="$ROOT_DIR/build"
VERSION="${APP_VERSION:-}"

mkdir -p "$BUILD_DIR"

# Clean prior artifacts that could be picked up by glob uploads
rm -f "$BUILD_DIR"/JoJoPing-*.dmg "$BUILD_DIR"/jojoping-raycast-*.zip || true

echo "[build] Building macOS app and creating DMG (version=$VERSION)"
(cd "$ROOT_DIR" && ./scripts/create-dmg.sh)

echo "[build] Building Raycast extension"
(cd "$RAYCAST_DIR" && npx -y @raycast/api@latest build)

# Package Raycast extension directory into a zip suitable for release attachments.
# We include the necessary manifest & build output (the source is fine for Raycast import)
ZIP_NAME="jojoping-raycast-${VERSION:-dev}.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"

# Create zip from the directory contents, excluding node_modules
(
  cd "$RAYCAST_DIR"
  zip -r -9 "$ZIP_PATH" . \
    -x "node_modules/*" \
    -x ".git/*" \
    -x "*.log" \
    -x "pnpm-lock.yaml"
)

echo "[build] Artifacts created:"
ls -lh "$BUILD_DIR" | sed 's/^/[build] /'
