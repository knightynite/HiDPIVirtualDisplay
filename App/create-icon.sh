#!/bin/bash
# Create app icon for G9 Helper

set -e

ICON_DIR="AppIcon.iconset"
RESOURCES_DIR="Resources"

mkdir -p "${ICON_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Create a simple but nice icon using Swift and AppKit
cat > /tmp/create_icon.swift << 'SWIFT'
import AppKit

func createIcon(size: Int, scale: Int) -> NSImage {
    let actualSize = size * scale
    let image = NSImage(size: NSSize(width: actualSize, height: actualSize))

    image.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: actualSize, height: actualSize)
    let inset = CGFloat(actualSize) * 0.1
    let mainRect = bounds.insetBy(dx: inset, dy: inset)

    // Background gradient (dark blue to purple)
    let gradient = NSGradient(colors: [
        NSColor(red: 0.1, green: 0.1, blue: 0.3, alpha: 1.0),
        NSColor(red: 0.2, green: 0.1, blue: 0.4, alpha: 1.0)
    ])!

    // Rounded rectangle background
    let bgPath = NSBezierPath(roundedRect: mainRect, xRadius: CGFloat(actualSize) * 0.2, yRadius: CGFloat(actualSize) * 0.2)
    gradient.draw(in: bgPath, angle: -45)

    // Monitor outline
    let monitorWidth = CGFloat(actualSize) * 0.7
    let monitorHeight = CGFloat(actualSize) * 0.35
    let monitorX = (CGFloat(actualSize) - monitorWidth) / 2
    let monitorY = CGFloat(actualSize) * 0.4
    let monitorRect = NSRect(x: monitorX, y: monitorY, width: monitorWidth, height: monitorHeight)

    // Monitor bezel
    let bezelPath = NSBezierPath(roundedRect: monitorRect, xRadius: 4, yRadius: 4)
    NSColor(red: 0.3, green: 0.3, blue: 0.35, alpha: 1.0).setFill()
    bezelPath.fill()

    // Monitor screen (gradient to show HiDPI quality)
    let screenInset: CGFloat = CGFloat(actualSize) * 0.02
    let screenRect = monitorRect.insetBy(dx: screenInset, dy: screenInset)
    let screenPath = NSBezierPath(roundedRect: screenRect, xRadius: 2, yRadius: 2)

    let screenGradient = NSGradient(colors: [
        NSColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0),
        NSColor(red: 0.4, green: 0.3, blue: 0.8, alpha: 1.0)
    ])!
    screenGradient.draw(in: screenPath, angle: 45)

    // Monitor stand
    let standWidth = CGFloat(actualSize) * 0.15
    let standHeight = CGFloat(actualSize) * 0.12
    let standX = (CGFloat(actualSize) - standWidth) / 2
    let standY = monitorY - standHeight + 2
    let standRect = NSRect(x: standX, y: standY, width: standWidth, height: standHeight)

    NSColor(red: 0.25, green: 0.25, blue: 0.3, alpha: 1.0).setFill()
    NSBezierPath(rect: standRect).fill()

    // Stand base
    let baseWidth = CGFloat(actualSize) * 0.25
    let baseHeight = CGFloat(actualSize) * 0.03
    let baseX = (CGFloat(actualSize) - baseWidth) / 2
    let baseY = standY - baseHeight + 2
    let baseRect = NSRect(x: baseX, y: baseY, width: baseWidth, height: baseHeight)

    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: 2, yRadius: 2)
    NSColor(red: 0.25, green: 0.25, blue: 0.3, alpha: 1.0).setFill()
    basePath.fill()

    // "2x" text to indicate HiDPI
    let fontSize = CGFloat(actualSize) * 0.15
    let font = NSFont.boldSystemFont(ofSize: fontSize)
    let text = "2x"
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let textSize = text.size(withAttributes: attributes)
    let textX = (CGFloat(actualSize) - textSize.width) / 2
    let textY = monitorY + (monitorHeight - textSize.height) / 2
    text.draw(at: NSPoint(x: textX, y: textY), withAttributes: attributes)

    image.unlockFocus()
    return image
}

func saveIcon(image: NSImage, path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG data")
        return
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: path))
    } catch {
        print("Failed to write: \(error)")
    }
}

// Generate all required sizes
let sizes = [16, 32, 128, 256, 512]

for size in sizes {
    // 1x
    let icon1x = createIcon(size: size, scale: 1)
    saveIcon(image: icon1x, path: "AppIcon.iconset/icon_\(size)x\(size).png")

    // 2x
    let icon2x = createIcon(size: size, scale: 2)
    saveIcon(image: icon2x, path: "AppIcon.iconset/icon_\(size)x\(size)@2x.png")
}

print("Icon images created successfully")
SWIFT

# Run the Swift script to create icons
swift /tmp/create_icon.swift

# Convert iconset to icns
iconutil -c icns "${ICON_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"

# Clean up
rm -rf "${ICON_DIR}"
rm /tmp/create_icon.swift

echo "AppIcon.icns created in ${RESOURCES_DIR}/"
