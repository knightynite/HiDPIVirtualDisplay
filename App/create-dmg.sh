#!/bin/bash
# Create a DMG for distribution

set -e

APP_NAME="HiDPI Display"
DMG_NAME="HiDPI.Display"
BUILD_DIR="build"
DMG_DIR="${BUILD_DIR}/dmg"
VERSION="1.0.0"

echo "📦 Creating DMG..."

# Build the app first
./build.sh

# Create DMG directory
rm -rf "${DMG_DIR}"
mkdir -p "${DMG_DIR}"

# Copy app to DMG directory
cp -r "${BUILD_DIR}/${APP_NAME}.app" "${DMG_DIR}/"

# Create symlink to Applications
ln -s /Applications "${DMG_DIR}/Applications"

# Create README
cat > "${DMG_DIR}/README.txt" << 'EOF'
HiDPI Display v1.0.0

Installation:
1. Drag "HiDPI Display.app" to the Applications folder
2. Launch from Applications or Spotlight
3. Look for the display icon in your menu bar

For more information, visit:
https://github.com/yourusername/HiDPIVirtualDisplay

Note: This app uses private macOS APIs and may require
special permissions. If you encounter issues, try
right-clicking the app and selecting "Open".
EOF

# Create the DMG
rm -f "${BUILD_DIR}/${DMG_NAME}.dmg"
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov -format UDZO \
    "${BUILD_DIR}/${DMG_NAME}.dmg"

# Clean up
rm -rf "${DMG_DIR}"

echo "✅ DMG created: ${BUILD_DIR}/${DMG_NAME}.dmg"
echo ""
echo "File size: $(du -h "${BUILD_DIR}/${DMG_NAME}.dmg" | cut -f1)"
