#!/bin/bash
# Build script for HiDPI Display app

set -e

APP_NAME="G9 Helper"
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

# Build a universal binary (arm64 + x86_64) so the app runs on both Apple
# Silicon and Intel Macs. Each arch is compiled and linked separately, then
# combined with lipo. Deployment target matches LSMinimumSystemVersion (12.0).
ARCHS="arm64 x86_64"
DEPLOY_TARGET="12.0"
SLICES=""

for ARCH in ${ARCHS}; do
    TARGET="${ARCH}-apple-macosx${DEPLOY_TARGET}"

    echo "Compiling Objective-C (no ARC) for ${ARCH}..."
    clang -c -fno-objc-arc -fobjc-arc-exceptions \
        -target ${TARGET} \
        -framework Foundation \
        -framework CoreGraphics \
        ${OBJC_SOURCES} \
        -o "${BUILD_DIR}/VirtualDisplayManager-${ARCH}.o"

    echo "Compiling Swift and linking for ${ARCH}..."
    swiftc \
        -target ${TARGET} \
        -parse-as-library \
        ${SWIFT_SOURCES} \
        "${BUILD_DIR}/VirtualDisplayManager-${ARCH}.o" \
        -import-objc-header ${BRIDGING_HEADER} \
        -framework Foundation \
        -framework AppKit \
        -framework CoreGraphics \
        -framework IOKit \
        -framework SwiftUI \
        -o "${BUILD_DIR}/${BUNDLE_NAME}-${ARCH}"

    SLICES="${SLICES} ${BUILD_DIR}/${BUNDLE_NAME}-${ARCH}"
done

# Combine the per-arch executables into one universal binary
echo "Creating universal binary..."
lipo -create ${SLICES} -o "${MACOS}/${BUNDLE_NAME}"
lipo -info "${MACOS}/${BUNDLE_NAME}"

# Copy Info.plist
cp Info.plist "${CONTENTS}/"

# Copy app icon if it exists
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "${RESOURCES}/"
    echo "App icon copied"
fi

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
