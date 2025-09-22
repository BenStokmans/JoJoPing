#!/usr/bin/env bash
set -euo pipefail

# Determine repo root relative to this script
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# ================================
# CONFIG
# ================================
SCHEME="Poke"                        # Xcode scheme name
PROJECT="Poke.xcodeproj"             # .xcodeproj filename
CONFIGURATION="Release"                  # Build configuration
DESTINATION="generic/platform=macOS"    # Build destination
BUNDLE_ID="com.bstokmans.Poke"       # Bundle identifier
APP_NAME="Poke"                      # Final .app name (without .app)
OUTPUT_DIR="$ROOT_DIR/build"             # Where to put artifacts

# Note: Notarization is not covered here; can be added later if needed.

# ================================
# FUNCTIONS
# ================================
timestamp() { date +"%Y-%m-%d %H:%M:%S"; }

log() { echo "[$(timestamp)] $*"; }

# Read or set CFBundleShortVersionString from Info.plist in built app
get_app_version() {
  local app_path="$1"
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$app_path/Contents/Info.plist" 2>/dev/null || echo "0.0.0"
}

set_app_version() {
  local app_path="$1"
  local new_version="$2"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $new_version" \
    "$app_path/Contents/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $new_version" \
    "$app_path/Contents/Info.plist"
}

# ================================
# PREPARATION
# ================================
mkdir -p "$OUTPUT_DIR"
BUILD_DIR="$OUTPUT_DIR/$CONFIGURATION"
ARCHIVE_PATH="$OUTPUT_DIR/$SCHEME.xcarchive"

# Clean previous artifacts
rm -rf "$BUILD_DIR" "$ARCHIVE_PATH"

# ================================
# BUILD
# ================================
log "Starting build for scheme: $SCHEME"

# Build the project using xcodebuild
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$OUTPUT_DIR/DerivedData" \
  -archivePath "$ARCHIVE_PATH" \
  clean archive \
  CODE_SIGN_STYLE=${CI:+Manual} \
  CODE_SIGNING_ALLOWED=${CI:+NO} \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=NO

# Export the archived app to .app in build directory
EXPORT_PATH="$BUILD_DIR"
rm -rf "$EXPORT_PATH"
mkdir -p "$EXPORT_PATH"

log "Exporting .app from archive"

# Unpack the app from .xcarchive
APP_PATH_IN_ARCHIVE="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
if [[ ! -d "$APP_PATH_IN_ARCHIVE" ]]; then
  log "Error: App not found in archive at $APP_PATH_IN_ARCHIVE"
  exit 1
fi
cp -R "$APP_PATH_IN_ARCHIVE" "$EXPORT_PATH/"

APP_PATH="$EXPORT_PATH/$APP_NAME.app"

# ================================
# DETERMINE VERSION AND DMG NAME
# ================================
if [[ -n "${APP_VERSION:-}" ]]; then
  log "Overriding app version to: $APP_VERSION"
  set_app_version "$APP_PATH" "$APP_VERSION"
fi

VERSION="$(get_app_version "$APP_PATH")"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

log "Built app version: $VERSION"
log "Will create DMG: $DMG_PATH"

# -------- CREATE DMG --------
# Create a staging folder for DMG contents
STAGE="$OUTPUT_DIR/dmg_stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"

# Optionally add Applications symlink so users can drag-drop
ln -s /Applications "$STAGE/Applications"

# Copy app into staging
cp -R "$APP_PATH" "$STAGE/"

# Create the DMG
log "Creating DMG..."
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -fs HFS+J \
  -format UDZO \
  "$DMG_PATH"

log "DMG created at: $DMG_PATH"

# -------- SUMMARY --------
log "Done."
log "App: $APP_PATH"
log "DMG: $DMG_PATH"
