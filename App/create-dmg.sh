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

# Notarize the app bundle and staple the ticket to it BEFORE packaging, so the
# copy that ends up in /Applications carries its own ticket. Stapling only the
# DMG leaves the dragged-out app relying on Gatekeeper reaching Apple to look
# the ticket up, which fails on a machine that is offline the first time it
# runs the app. Requires a stored notarytool credential profile — create it
# once with:
#   xcrun notarytool store-credentials g9-notary \
#       --apple-id <apple-id> --team-id D76ZAFG74A --password <app-specific-password>
# Skips cleanly (leaving a signed-but-unnotarized build) when the profile is absent.
NOTARY_PROFILE="${G9_NOTARY_PROFILE:-g9-notary}"
HAVE_NOTARY=0
if xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
    HAVE_NOTARY=1
    APP_ZIP="${BUILD_DIR}/${DMG_NAME}-app.zip"
    echo "Notarizing the app bundle (profile: ${NOTARY_PROFILE})..."
    rm -f "${APP_ZIP}"
    # ditto keeps the bundle's symlinks and extended attributes intact; zip -r
    # would flatten them and invalidate the signature.
    /usr/bin/ditto -c -k --keepParent "${BUILD_DIR}/${APP_NAME}.app" "${APP_ZIP}"
    xcrun notarytool submit "${APP_ZIP}" --keychain-profile "${NOTARY_PROFILE}" --wait
    rm -f "${APP_ZIP}"
    xcrun stapler staple "${BUILD_DIR}/${APP_NAME}.app"
    xcrun stapler validate "${BUILD_DIR}/${APP_NAME}.app"
    echo "App notarized and stapled."
else
    echo "No notarytool profile '${NOTARY_PROFILE}' found — skipping notarization."
fi

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

# Notarize and staple the DMG as well, so the disk image itself opens without a
# prompt. The app inside already carries its own ticket from the step above.
if [ "${HAVE_NOTARY}" = "1" ]; then
    echo "Submitting the DMG for notarization..."
    xcrun notarytool submit "${DMG_FILE}" --keychain-profile "${NOTARY_PROFILE}" --wait
    echo "Stapling notarization ticket..."
    xcrun stapler staple "${DMG_FILE}"
    xcrun stapler validate "${DMG_FILE}"
    echo "DMG notarized and stapled."
else
    echo "The DMG is Developer ID signed but NOT notarized (Gatekeeper will still prompt)."
fi

echo ""
echo "File size: $(du -h "${DMG_FILE}" | cut -f1)"
