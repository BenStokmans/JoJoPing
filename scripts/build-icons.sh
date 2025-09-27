#!/bin/zsh

# This script generates the icons for the JoJoPing app and the Raycast extension.
# It takes the base icon.png and creates the necessary sizes for the app icon set
# and the Raycast extension icon.

set -e

# --- Configuration ---

# The base icon file.
SOURCE_ICON="icon.png"

# The path to the Raycast extension icon.
RAYCAST_ICON_PATH="poke-raycast/assets/extension-icon.png"

# The path to the .appiconset directory.
APPICONSET_PATH="Poke/Assets.xcassets/AppIcon.appiconset"

# --- Validation ---

if ! command -v sips &> /dev/null
then
    echo "sips command could not be found. This script requires macOS."
    exit 1
fi

if [ ! -f "$SOURCE_ICON" ]; then
    echo "Source icon not found at $SOURCE_ICON"
    exit 1
fi

# --- Icon Generation ---

echo "Generating Raycast icon..."
sips -z 512 512 "$SOURCE_ICON" --out "$RAYCAST_ICON_PATH"
echo "Raycast icon created at $RAYCAST_ICON_PATH"

echo "Generating AppIcon set..."

# Generate all the required sizes for the app icon set.
# The sizes are based on the standard requirements for a macOS app icon.
sips -z 16 16 "$SOURCE_ICON" --out "$APPICONSET_PATH/icon_16x16.png"
sips -z 32 32 "$SOURCE_ICON" --out "$APPICONSET_PATH/icon_16x16@2x.png"
sips -z 32 32 "$SOURCE_ICON" --out "$APPICONSET_PATH/icon_32x32.png"
sips -z 64 64 "$SOURCE_ICON" --out "$APPICONSET_PATH/icon_32x32@2x.png"
sips -z 128 128 "$SOURCE_ICON" --out "$APPICONSET_PATH/icon_128x128.png"
sips -z 256 256 "$SOURCE_ICON" --out "$APPICONSET_PATH/icon_128x128@2x.png"
sips -z 256 256 "$SOURCE_ICON" --out "$APPICONSET_PATH/icon_256x256.png"
sips -z 512 512 "$SOURCE_ICON" --out "$APPICONSET_PATH/icon_256x256@2x.png"
sips -z 512 512 "$SOURCE_ICON" --out "$APPICONSET_PATH/icon_512x512.png"
sips -z 1024 1024 "$SOURCE_ICON" --out "$APPICONSET_PATH/icon_512x512@2x.png"

echo "AppIcon set generated in $APPICONSET_PATH"

echo "Icon generation complete."
