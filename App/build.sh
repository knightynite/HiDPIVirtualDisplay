#!/bin/bash
# Build script for HiDPI Display app

set -e

APP_NAME="HiDPI Display"
BUNDLE_NAME="HiDPIDisplay"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

# Source files
SWIFT_SOURCES="Sources/HiDPIDisplayApp.swift"
OBJC_SOURCES="Sources/VirtualDisplayManager.m"
BRIDGING_HEADER="Sources/BridgingHeader.h"

echo "Building ${APP_NAME}..."

# Create app bundle structure
mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"

# Compile the app
echo "Compiling..."
swiftc \
    -parse-as-library \
    ${SWIFT_SOURCES} \
    ${OBJC_SOURCES} \
    -import-objc-header ${BRIDGING_HEADER} \
    -framework Foundation \
    -framework AppKit \
    -framework CoreGraphics \
    -framework SwiftUI \
    -o "${MACOS}/${BUNDLE_NAME}"

# Copy Info.plist
cp Info.plist "${CONTENTS}/"

# Sign the app with entitlements
echo "Signing..."
codesign --force --sign - --entitlements HiDPIVirtualDisplay.entitlements "${APP_BUNDLE}" || true

echo "Build complete: ${APP_BUNDLE}"
echo ""
echo "To install:"
echo "  cp -r \"${APP_BUNDLE}\" /Applications/"
echo ""
echo "To run:"
echo "  open \"${APP_BUNDLE}\""
