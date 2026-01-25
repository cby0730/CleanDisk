#!/bin/bash

# Configuration
APP_NAME="CleanDisk"
SCHEME="CleanDisk"
BUILD_DIR="build"
DMG_NAME="${APP_NAME}_Installer.dmg"
APP_ICON_SET="CleanDisk/Assets.xcassets/AppIcon.appiconset"
GENERATED_ICNS="build/AppIcon.icns"

# Helper to generate ICNS
generate_icns() {
    echo "Generating ICNS file..."
    ICONSET_DIR="temp.iconset"
    mkdir -p "$ICONSET_DIR"

    # Mapping files - relying on standard sizes if available or just using the largest one for all if lazy, 
    # but let's try to map correctly based on the file list we saw:
    # 1024x1024 -> icon_512x512@2x.png
    # 512x512 -> icon_512x512.png, icon_256x256@2x.png
    # 256x256 -> icon_256x256.png, icon_128x128@2x.png
    # 128x128 -> icon_128x128.png
    # 32x32 -> icon_32x32.png, icon_16x16@2x.png
    # 16x16 -> icon_16x16.png
    
    # We saw names like CleanDiskApp_1024x1024.png
    
    cp "$APP_ICON_SET/CleanDiskApp_1024x1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
    cp "$APP_ICON_SET/CleanDiskApp_512x512.png"   "$ICONSET_DIR/icon_512x512.png"
    cp "$APP_ICON_SET/CleanDiskApp_512x512.png"   "$ICONSET_DIR/icon_256x256@2x.png"
    cp "$APP_ICON_SET/CleanDiskApp_256x256.png"   "$ICONSET_DIR/icon_256x256.png"
    cp "$APP_ICON_SET/CleanDiskApp_256x256.png"   "$ICONSET_DIR/icon_128x128@2x.png"
    cp "$APP_ICON_SET/CleanDiskApp_128x128.png"   "$ICONSET_DIR/icon_128x128.png"
    cp "$APP_ICON_SET/CleanDiskApp_32x32.png"     "$ICONSET_DIR/icon_32x32.png"
    cp "$APP_ICON_SET/CleanDiskApp_32x32.png"     "$ICONSET_DIR/icon_16x16@2x.png"
    cp "$APP_ICON_SET/CleanDiskApp_16x16.png"     "$ICONSET_DIR/icon_16x16.png"

    iconutil -c icns "$ICONSET_DIR" -o "$GENERATED_ICNS"
    rm -rf "$ICONSET_DIR"
    
    if [ -f "$GENERATED_ICNS" ]; then
        echo "ICNS generated successfully."
        return 0
    else
        echo "Failed to generate ICNS."
        return 1
    fi
}

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting packaging process for ${APP_NAME}...${NC}"

# Check if create-dmg is installed
if ! command -v create-dmg &> /dev/null; then
    echo -e "${RED}Error: create-dmg is not installed.${NC}"
    echo "Please install it using Homebrew:"
    echo "brew install create-dmg"
    exit 1
fi

# Clean previous build
echo "Cleaning previous build..."
rm -rf "$BUILD_DIR" 2>/dev/null || true
mkdir -p "$BUILD_DIR"

# Build the app
echo -e "${GREEN}Building ${APP_NAME}...${NC}"
xcodebuild -scheme "$SCHEME" \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
           archive \
           -quiet

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed.${NC}"
    exit 1
fi

# Extract the app from archive
echo "Extracting app from archive..."
cp -r "$BUILD_DIR/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app" "$BUILD_DIR/"

# Check if app exists
if [ ! -d "$BUILD_DIR/$APP_NAME.app" ]; then
    echo -e "${RED}Error: App not found at $BUILD_DIR/$APP_NAME.app${NC}"
    exit 1
fi

# Remove existing DMG
if [ -f "$DMG_NAME" ]; then
    echo "Removing specific existing DMG..."
    rm "$DMG_NAME"
fi

# Create DMG
echo -e "${GREEN}Creating DMG...${NC}"

# Generate ICNS if needed
if [ ! -f "$GENERATED_ICNS" ]; then
    generate_icns
fi

# Basic create-dmg command with drag-and-drop to Applications
create-dmg \
  --volname "${APP_NAME} Installer" \
  --volicon "$GENERATED_ICNS" \
  --background-color "#2c2c2c" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 175 190 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 425 190 \
  --no-internet-enable \
  "$DMG_NAME" \
  "$BUILD_DIR/$APP_NAME.app"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Success! DMG created at $(pwd)/$DMG_NAME${NC}"
    
    # Cleanup temporary ICNS file
    if [ -f "$GENERATED_ICNS" ]; then
        echo "Cleaning up temporary files..."
        rm "$GENERATED_ICNS"
    fi
    
    # Post-process DMG to hide .VolumeIcon.icns
    echo "Optimizing DMG appearance..."
    hdiutil attach "$DMG_NAME" -mountpoint "/Volumes/${APP_NAME}_temp" -nobrowse -quiet 2>/dev/null
    if [ -d "/Volumes/${APP_NAME}_temp" ]; then
        # Hide .VolumeIcon.icns file
        if [ -f "/Volumes/${APP_NAME}_temp/.VolumeIcon.icns" ]; then
            SetFile -a V "/Volumes/${APP_NAME}_temp/.VolumeIcon.icns" 2>/dev/null || \
            chflags hidden "/Volumes/${APP_NAME}_temp/.VolumeIcon.icns" 2>/dev/null
        fi
        hdiutil detach "/Volumes/${APP_NAME}_temp" -quiet 2>/dev/null
    fi
    
    open .
else
    echo -e "${RED}Failed to create DMG.${NC}"
    exit 1
fi
