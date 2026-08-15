#!/bin/bash
# Create a DMG for distribution

set -e

APP_NAME="G9 Helper"
DMG_NAME="G9.Helper"
BUILD_DIR="build"
DMG_DIR="${BUILD_DIR}/dmg"
VERSION="1.2.6"

echo "Creating DMG..."

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
G9 Helper v1.2.6 - Free Software

Unlock crisp HiDPI (Retina) scaling on Samsung Odyssey G9
and other large monitors.

INSTALLATION
1. Drag "G9 Helper.app" to the Applications folder
2. Launch from Applications or Spotlight
3. Look for the display icon in your menu bar

FIRST LAUNCH
macOS may block the app. Right-click and select "Open",
then click "Open" in the dialog.

USAGE
1. Click the display icon in your menu bar
2. Select your monitor type
3. Choose a resolution preset
4. Wait a few seconds for configuration

AUTO-START (Recommended)
For automatic startup and crash recovery, run in Terminal:
  cd /path/to/HiDPIVirtualDisplay/App
  ./install-launchd.sh install

UNINSTALL
1. Click the menu bar icon and select "Quit"
2. Drag the app from Applications to Trash

More info: https://github.com/knightynite/HiDPIVirtualDisplay

---
Created with love by AL in Dallas
EOF

# Create the DMG
rm -f "${BUILD_DIR}/${DMG_NAME}.dmg"
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov -format UDZO \
    "${BUILD_DIR}/${DMG_NAME}.dmg"

# Clean up
rm -rf "${DMG_DIR}"

DMG_FILE="${BUILD_DIR}/${DMG_NAME}.dmg"
echo "DMG created: ${DMG_FILE}"

# Notarize and staple so the DMG installs by double-click on other Macs without
# a Gatekeeper prompt. Requires a stored notarytool credential profile — create
# it once with:
#   xcrun notarytool store-credentials g9-notary \
#       --apple-id <apple-id> --team-id D76ZAFG74A --password <app-specific-password>
# Skips cleanly (leaving a signed-but-unnotarized DMG) when the profile is absent.
NOTARY_PROFILE="${G9_NOTARY_PROFILE:-g9-notary}"
if xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
    echo "Submitting for notarization (profile: ${NOTARY_PROFILE})..."
    xcrun notarytool submit "${DMG_FILE}" --keychain-profile "${NOTARY_PROFILE}" --wait
    echo "Stapling notarization ticket..."
    xcrun stapler staple "${DMG_FILE}"
    xcrun stapler validate "${DMG_FILE}"
    echo "Notarized and stapled."
else
    echo "No notarytool profile '${NOTARY_PROFILE}' found — skipping notarization."
    echo "The DMG is Developer ID signed but NOT notarized (Gatekeeper will still prompt)."
fi

echo ""
echo "File size: $(du -h "${DMG_FILE}" | cut -f1)"
