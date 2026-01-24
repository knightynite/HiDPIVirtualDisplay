#!/bin/bash
# Create app icon for G9 Helper - Odyssey-style curved monitor with G

set -e

ICON_DIR="AppIcon.iconset"
RESOURCES_DIR="Resources"

mkdir -p "${ICON_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Create icon using Swift and AppKit
cat > /tmp/create_icon.swift << 'SWIFT'
import AppKit

func createIcon(size: Int, scale: Int) -> NSImage {
    let actualSize = size * scale
    let image = NSImage(size: NSSize(width: actualSize, height: actualSize))

    image.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: actualSize, height: actualSize)
    let s = CGFloat(actualSize)

    // Background - dark gradient (gaming aesthetic)
    let bgRect = bounds.insetBy(dx: s * 0.08, dy: s * 0.08)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: s * 0.18, yRadius: s * 0.18)

    let bgGradient = NSGradient(colors: [
        NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0),
        NSColor(red: 0.15, green: 0.12, blue: 0.20, alpha: 1.0)
    ])!
    bgGradient.draw(in: bgPath, angle: -45)

    // Curved ultrawide monitor (Odyssey style)
    let monitorPath = NSBezierPath()

    let monitorWidth = s * 0.75
    let monitorHeight = s * 0.32
    let curveDepth = s * 0.06
    let monitorX = (s - monitorWidth) / 2
    let monitorY = s * 0.42

    // Draw curved monitor shape (concave curve like Odyssey)
    monitorPath.move(to: NSPoint(x: monitorX, y: monitorY))

    // Bottom edge - curved inward
    monitorPath.curve(
        to: NSPoint(x: monitorX + monitorWidth, y: monitorY),
        controlPoint1: NSPoint(x: monitorX + monitorWidth * 0.3, y: monitorY + curveDepth),
        controlPoint2: NSPoint(x: monitorX + monitorWidth * 0.7, y: monitorY + curveDepth)
    )

    // Right edge
    monitorPath.line(to: NSPoint(x: monitorX + monitorWidth, y: monitorY + monitorHeight))

    // Top edge - curved inward
    monitorPath.curve(
        to: NSPoint(x: monitorX, y: monitorY + monitorHeight),
        controlPoint1: NSPoint(x: monitorX + monitorWidth * 0.7, y: monitorY + monitorHeight - curveDepth),
        controlPoint2: NSPoint(x: monitorX + monitorWidth * 0.3, y: monitorY + monitorHeight - curveDepth)
    )

    monitorPath.close()

    // Monitor bezel (dark gray)
    NSColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 1.0).setFill()
    monitorPath.fill()

    // Screen area (slightly inset)
    let screenPath = NSBezierPath()
    let screenInset = s * 0.025
    let screenWidth = monitorWidth - screenInset * 2
    let screenHeight = monitorHeight - screenInset * 2
    let screenX = monitorX + screenInset
    let screenY = monitorY + screenInset
    let screenCurve = curveDepth * 0.8

    screenPath.move(to: NSPoint(x: screenX, y: screenY))
    screenPath.curve(
        to: NSPoint(x: screenX + screenWidth, y: screenY),
        controlPoint1: NSPoint(x: screenX + screenWidth * 0.3, y: screenY + screenCurve),
        controlPoint2: NSPoint(x: screenX + screenWidth * 0.7, y: screenY + screenCurve)
    )
    screenPath.line(to: NSPoint(x: screenX + screenWidth, y: screenY + screenHeight))
    screenPath.curve(
        to: NSPoint(x: screenX, y: screenY + screenHeight),
        controlPoint1: NSPoint(x: screenX + screenWidth * 0.7, y: screenY + screenHeight - screenCurve),
        controlPoint2: NSPoint(x: screenX + screenWidth * 0.3, y: screenY + screenHeight - screenCurve)
    )
    screenPath.close()

    // Screen gradient (blue to purple - gaming RGB aesthetic)
    let screenGradient = NSGradient(colors: [
        NSColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1.0),
        NSColor(red: 0.5, green: 0.2, blue: 0.8, alpha: 1.0)
    ])!
    screenGradient.draw(in: screenPath, angle: 45)

    // RGB accent line at bottom of screen
    let rgbPath = NSBezierPath()
    let rgbY = screenY + s * 0.01
    rgbPath.move(to: NSPoint(x: screenX + screenWidth * 0.1, y: rgbY))
    rgbPath.curve(
        to: NSPoint(x: screenX + screenWidth * 0.9, y: rgbY),
        controlPoint1: NSPoint(x: screenX + screenWidth * 0.35, y: rgbY + screenCurve * 0.5),
        controlPoint2: NSPoint(x: screenX + screenWidth * 0.65, y: rgbY + screenCurve * 0.5)
    )
    rgbPath.lineWidth = s * 0.015

    let rgbGradient = NSGradient(colors: [
        NSColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0),
        NSColor(red: 0.8, green: 0.2, blue: 0.8, alpha: 1.0),
        NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
    ])!

    // Draw RGB line
    NSColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.8).setStroke()
    rgbPath.stroke()

    // Monitor stand
    let standWidth = s * 0.12
    let standHeight = s * 0.1
    let standX = (s - standWidth) / 2
    let standY = monitorY - standHeight + s * 0.02

    let standPath = NSBezierPath()
    standPath.move(to: NSPoint(x: standX + standWidth * 0.3, y: monitorY))
    standPath.line(to: NSPoint(x: standX, y: standY))
    standPath.line(to: NSPoint(x: standX + standWidth, y: standY))
    standPath.line(to: NSPoint(x: standX + standWidth * 0.7, y: monitorY))
    standPath.close()

    NSColor(red: 0.18, green: 0.18, blue: 0.22, alpha: 1.0).setFill()
    standPath.fill()

    // Stand base (wider, curved)
    let baseWidth = s * 0.28
    let baseHeight = s * 0.035
    let baseX = (s - baseWidth) / 2
    let baseY = standY - baseHeight + s * 0.015

    let basePath = NSBezierPath(roundedRect: NSRect(x: baseX, y: baseY, width: baseWidth, height: baseHeight),
                                  xRadius: baseHeight * 0.4, yRadius: baseHeight * 0.4)
    NSColor(red: 0.18, green: 0.18, blue: 0.22, alpha: 1.0).setFill()
    basePath.fill()

    // Draw "G" on screen
    let fontSize = s * 0.22
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let gText = "G"
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let textSize = gText.size(withAttributes: attributes)
    let textX = (s - textSize.width) / 2
    let textY = monitorY + (monitorHeight - textSize.height) / 2 + s * 0.01

    // Text shadow for depth
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.shadowBlurRadius = s * 0.02

    let shadowAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .shadow: shadow
    ]

    gText.draw(at: NSPoint(x: textX, y: textY), withAttributes: shadowAttributes)

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
    let icon1x = createIcon(size: size, scale: 1)
    saveIcon(image: icon1x, path: "AppIcon.iconset/icon_\(size)x\(size).png")

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
