#!/bin/bash
# Create a styled DMG with drag-to-install layout

set -e

APP_NAME="G9 Helper"
DMG_NAME="G9.Helper"
BUILD_DIR="build"
DMG_TEMP="${BUILD_DIR}/dmg_temp"
DMG_FINAL="${BUILD_DIR}/${DMG_NAME}.dmg"
VOLUME_NAME="${APP_NAME}"

echo "Creating styled DMG..."

# Build the app first
./build.sh

# Clean up any existing temp files
rm -rf "${DMG_TEMP}"
rm -f "${DMG_FINAL}"
rm -f "${BUILD_DIR}/${DMG_NAME}-temp.dmg"

# Create temp directory structure
mkdir -p "${DMG_TEMP}"
cp -r "${BUILD_DIR}/${APP_NAME}.app" "${DMG_TEMP}/"
ln -s /Applications "${DMG_TEMP}/Applications"

# Create instructions file
cat > "${DMG_TEMP}/INSTALL.txt" << 'EOF'
===============================================
  G9 Helper - Installation Instructions
===============================================

STEP 1: INSTALL
  Drag "G9 Helper.app" to the "Applications" folder

STEP 2: FIRST LAUNCH (Security Warning)
  macOS will show a security warning because this
  app is not from the App Store.

  To open the app, use ONE of these methods:

  METHOD A (Easiest):
    1. Right-click on "G9 Helper" in Applications
    2. Select "Open" from the menu
    3. Click "Open" in the dialog that appears

  METHOD B (System Settings):
    1. Open System Settings
    2. Go to Privacy & Security
    3. Scroll down to Security section
    4. Click "Open Anyway" next to G9 Helper

STEP 3: USE
  1. Look for the display icon in your menu bar
  2. Click it and select your monitor type
  3. Choose a resolution preset
  4. Wait a few seconds for HiDPI to activate

===============================================
  GitHub:  https://github.com/knightynite/HiDPIVirtualDisplay
===============================================
EOF

# Calculate size needed
APP_SIZE=$(du -sm "${BUILD_DIR}/${APP_NAME}.app" | cut -f1)
DMG_SIZE=$((APP_SIZE + 5))

# Create temporary DMG
hdiutil create -srcfolder "${DMG_TEMP}" -volname "${VOLUME_NAME}" \
    -fs HFS+ -fsargs "-c c=64,a=16,e=16" \
    -format UDRW -size ${DMG_SIZE}m "${BUILD_DIR}/${DMG_NAME}-temp.dmg"

# Mount the temporary DMG
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "${BUILD_DIR}/${DMG_NAME}-temp.dmg" | egrep '^/dev/' | sed 1q | awk '{print $1}')
MOUNT_POINT="/Volumes/${VOLUME_NAME}"

echo "Mounted at: ${MOUNT_POINT}"
sleep 2

# Set window properties with AppleScript
osascript << EOF
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 760, 500}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100
        set position of item "${APP_NAME}.app" of container window to {120, 160}
        set position of item "Applications" of container window to {420, 160}
        set position of item "INSTALL.txt" of container window to {270, 310}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
EOF

sleep 1
sync

# Unmount
hdiutil detach "${DEVICE}" -force

# Convert to compressed final DMG
hdiutil convert "${BUILD_DIR}/${DMG_NAME}-temp.dmg" -format UDZO \
    -imagekey zlib-level=9 -o "${DMG_FINAL}"

# Clean up
rm -rf "${DMG_TEMP}"
rm -f "${BUILD_DIR}/${DMG_NAME}-temp.dmg"

echo ""
echo "=========================================="
echo "  DMG created: ${DMG_FINAL}"
echo "  File size: $(du -h "${DMG_FINAL}" | cut -f1)"
echo "=========================================="
