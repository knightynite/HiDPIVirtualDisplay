// main.swift
// HiDPI Virtual Display CLI for Samsung G9 and other monitors

import Foundation
import CoreGraphics

// MARK: - CLI Colors

enum ANSIColor: String {
    case reset = "\u{001B}[0m"
    case bold = "\u{001B}[1m"
    case red = "\u{001B}[31m"
    case green = "\u{001B}[32m"
    case yellow = "\u{001B}[33m"
    case blue = "\u{001B}[34m"
    case magenta = "\u{001B}[35m"
    case cyan = "\u{001B}[36m"
}

func colorize(_ text: String, _ color: ANSIColor) -> String {
    return "\(color.rawValue)\(text)\(ANSIColor.reset.rawValue)"
}

// MARK: - Preset Configurations

struct DisplayPreset {
    let name: String
    let description: String
    let framebufferWidth: UInt32
    let framebufferHeight: UInt32
    let logicalWidth: UInt32
    let logicalHeight: UInt32
    let ppi: UInt32
    // refreshRate is detected at runtime from the physical monitor
    // to prevent flicker from rate mismatch

    var isHiDPI: Bool {
        return framebufferWidth == logicalWidth * 2
    }
}

// Built-in presets
let presets: [DisplayPreset] = [
    // Samsung G9 57" (7680x2160 native) - Fractional scaling options
    DisplayPreset(
        name: "g9-57-6144x1728",
        description: "Samsung G9 57\" HiDPI (looks like 6144x1728) - 1.25x more space",
        framebufferWidth: 12288,
        framebufferHeight: 3456,
        logicalWidth: 6144,
        logicalHeight: 1728,
        ppi: 140
    ),
    DisplayPreset(
        name: "g9-57-5908x1662",
        description: "Samsung G9 57\" HiDPI (looks like 5908x1662) - 1.3x",
        framebufferWidth: 11816,
        framebufferHeight: 3324,
        logicalWidth: 5908,
        logicalHeight: 1662,
        ppi: 140
    ),
    DisplayPreset(
        name: "g9-57-5632x1584",
        description: "Samsung G9 57\" HiDPI (looks like 5632x1584) - 1.36x",
        framebufferWidth: 11264,
        framebufferHeight: 3168,
        logicalWidth: 5632,
        logicalHeight: 1584,
        ppi: 140
    ),
    DisplayPreset(
        name: "g9-57-5486x1543",
        description: "Samsung G9 57\" HiDPI (looks like 5486x1543) - 1.4x",
        framebufferWidth: 10972,
        framebufferHeight: 3086,
        logicalWidth: 5486,
        logicalHeight: 1543,
        ppi: 140
    ),
    DisplayPreset(
        name: "g9-57-5297x1490",
        description: "Samsung G9 57\" HiDPI (looks like 5297x1490) - 1.45x",
        framebufferWidth: 10594,
        framebufferHeight: 2980,
        logicalWidth: 5297,
        logicalHeight: 1490,
        ppi: 140
    ),
    DisplayPreset(
        name: "g9-57-5120x1440",
        description: "Samsung G9 57\" HiDPI (looks like 5120x1440) - 1.5x recommended",
        framebufferWidth: 10240,
        framebufferHeight: 2880,
        logicalWidth: 5120,
        logicalHeight: 1440,
        ppi: 140
    ),
    DisplayPreset(
        name: "g9-57-4800x1350",
        description: "Samsung G9 57\" HiDPI (looks like 4800x1350) - 1.6x",
        framebufferWidth: 9600,
        framebufferHeight: 2700,
        logicalWidth: 4800,
        logicalHeight: 1350,
        ppi: 140
    ),
    DisplayPreset(
        name: "g9-57-4389x1234",
        description: "Samsung G9 57\" HiDPI (looks like 4389x1234) - 1.75x",
        framebufferWidth: 8778,
        framebufferHeight: 2468,
        logicalWidth: 4389,
        logicalHeight: 1234,
        ppi: 140
    ),
    DisplayPreset(
        name: "g9-57-3840x1080",
        description: "Samsung G9 57\" native 2x HiDPI (looks like 3840x1080)",
        framebufferWidth: 7680,
        framebufferHeight: 2160,
        logicalWidth: 3840,
        logicalHeight: 1080,
        ppi: 140
    ),

    // Samsung G9 49" (5120x1440 native) - Fractional scaling options
    DisplayPreset(
        name: "g9-49-4096x1152",
        description: "Samsung G9 49\" HiDPI (looks like 4096x1152) - 1.25x more space",
        framebufferWidth: 8192,
        framebufferHeight: 2304,
        logicalWidth: 4096,
        logicalHeight: 1152,
        ppi: 109
    ),
    DisplayPreset(
        name: "g9-49-3938x1108",
        description: "Samsung G9 49\" HiDPI (looks like 3938x1108) - 1.3x",
        framebufferWidth: 7876,
        framebufferHeight: 2216,
        logicalWidth: 3938,
        logicalHeight: 1108,
        ppi: 109
    ),
    DisplayPreset(
        name: "g9-49-3840x1080",
        description: "Samsung G9 49\" HiDPI (looks like 3840x1080) - 1.33x recommended",
        framebufferWidth: 7680,
        framebufferHeight: 2160,
        logicalWidth: 3840,
        logicalHeight: 1080,
        ppi: 109
    ),
    DisplayPreset(
        name: "g9-49-3413x960",
        description: "Samsung G9 49\" HiDPI (looks like 3413x960) - 1.5x",
        framebufferWidth: 6826,
        framebufferHeight: 1920,
        logicalWidth: 3413,
        logicalHeight: 960,
        ppi: 109
    ),
    DisplayPreset(
        name: "g9-49-2926x823",
        description: "Samsung G9 49\" HiDPI (looks like 2926x823) - 1.75x",
        framebufferWidth: 5852,
        framebufferHeight: 1646,
        logicalWidth: 2926,
        logicalHeight: 823,
        ppi: 109
    ),
    DisplayPreset(
        name: "g9-49-2560x720",
        description: "Samsung G9 49\" native 2x HiDPI (looks like 2560x720)",
        framebufferWidth: 5120,
        framebufferHeight: 1440,
        logicalWidth: 2560,
        logicalHeight: 720,
        ppi: 109
    ),

    // 34" Ultrawide (3440x1440 native) - Fractional scaling options
    DisplayPreset(
        name: "uw34-2752x1152",
        description: "34\" ultrawide HiDPI (looks like 2752x1152) - 1.25x more space",
        framebufferWidth: 5504,
        framebufferHeight: 2304,
        logicalWidth: 2752,
        logicalHeight: 1152,
        ppi: 110
    ),
    DisplayPreset(
        name: "uw34-2646x1108",
        description: "34\" ultrawide HiDPI (looks like 2646x1108) - 1.3x",
        framebufferWidth: 5292,
        framebufferHeight: 2216,
        logicalWidth: 2646,
        logicalHeight: 1108,
        ppi: 110
    ),
    DisplayPreset(
        name: "uw34-2293x960",
        description: "34\" ultrawide HiDPI (looks like 2293x960) - 1.5x recommended",
        framebufferWidth: 4586,
        framebufferHeight: 1920,
        logicalWidth: 2293,
        logicalHeight: 960,
        ppi: 110
    ),
    DisplayPreset(
        name: "uw34-1966x823",
        description: "34\" ultrawide HiDPI (looks like 1966x823) - 1.75x",
        framebufferWidth: 3932,
        framebufferHeight: 1646,
        logicalWidth: 1966,
        logicalHeight: 823,
        ppi: 110
    ),
    DisplayPreset(
        name: "uw34-1720x720",
        description: "34\" ultrawide native 2x HiDPI (looks like 1720x720)",
        framebufferWidth: 3440,
        framebufferHeight: 1440,
        logicalWidth: 1720,
        logicalHeight: 720,
        ppi: 110
    ),

    // 38" Ultrawide (3840x1600 native) - Fractional scaling options
    DisplayPreset(
        name: "uw38-3072x1280",
        description: "38\" ultrawide HiDPI (looks like 3072x1280) - 1.25x more space",
        framebufferWidth: 6144,
        framebufferHeight: 2560,
        logicalWidth: 3072,
        logicalHeight: 1280,
        ppi: 110
    ),
    DisplayPreset(
        name: "uw38-2954x1231",
        description: "38\" ultrawide HiDPI (looks like 2954x1231) - 1.3x",
        framebufferWidth: 5908,
        framebufferHeight: 2462,
        logicalWidth: 2954,
        logicalHeight: 1231,
        ppi: 110
    ),
    DisplayPreset(
        name: "uw38-2560x1067",
        description: "38\" ultrawide HiDPI (looks like 2560x1067) - 1.5x recommended",
        framebufferWidth: 5120,
        framebufferHeight: 2134,
        logicalWidth: 2560,
        logicalHeight: 1067,
        ppi: 110
    ),
    DisplayPreset(
        name: "uw38-2194x914",
        description: "38\" ultrawide HiDPI (looks like 2194x914) - 1.75x",
        framebufferWidth: 4388,
        framebufferHeight: 1828,
        logicalWidth: 2194,
        logicalHeight: 914,
        ppi: 110
    ),
    DisplayPreset(
        name: "uw38-1920x800",
        description: "38\" ultrawide native 2x HiDPI (looks like 1920x800)",
        framebufferWidth: 3840,
        framebufferHeight: 1600,
        logicalWidth: 1920,
        logicalHeight: 800,
        ppi: 110
    ),

    // 4K (3840x2160 native) - Fractional scaling options
    DisplayPreset(
        name: "4k-3072x1728",
        description: "4K HiDPI (looks like 3072x1728) - 1.25x more space",
        framebufferWidth: 6144,
        framebufferHeight: 3456,
        logicalWidth: 3072,
        logicalHeight: 1728,
        ppi: 163
    ),
    DisplayPreset(
        name: "4k-2954x1662",
        description: "4K HiDPI (looks like 2954x1662) - 1.3x",
        framebufferWidth: 5908,
        framebufferHeight: 3324,
        logicalWidth: 2954,
        logicalHeight: 1662,
        ppi: 163
    ),
    DisplayPreset(
        name: "4k-2560x1440",
        description: "4K HiDPI (looks like 2560x1440) - 1.5x recommended",
        framebufferWidth: 5120,
        framebufferHeight: 2880,
        logicalWidth: 2560,
        logicalHeight: 1440,
        ppi: 163
    ),
    DisplayPreset(
        name: "4k-2194x1234",
        description: "4K HiDPI (looks like 2194x1234) - 1.75x",
        framebufferWidth: 4388,
        framebufferHeight: 2468,
        logicalWidth: 2194,
        logicalHeight: 1234,
        ppi: 163
    ),
    DisplayPreset(
        name: "4k-1920x1080",
        description: "4K native 2x HiDPI (looks like 1920x1080)",
        framebufferWidth: 3840,
        framebufferHeight: 2160,
        logicalWidth: 1920,
        logicalHeight: 1080,
        ppi: 163
    ),

    // Legacy CLI aliases
    DisplayPreset(
        name: "4k-hidpi",
        description: "4K HiDPI (looks like 1920x1080)",
        framebufferWidth: 3840,
        framebufferHeight: 2160,
        logicalWidth: 1920,
        logicalHeight: 1080,
        ppi: 163
    ),
    DisplayPreset(
        name: "5k-hidpi",
        description: "5K HiDPI (looks like 2560x1440)",
        framebufferWidth: 5120,
        framebufferHeight: 2880,
        logicalWidth: 2560,
        logicalHeight: 1440,
        ppi: 218
    ),
    DisplayPreset(
        name: "1440p-hidpi",
        description: "QHD with HiDPI (looks like 1280x720)",
        framebufferWidth: 2560,
        framebufferHeight: 1440,
        logicalWidth: 1280,
        logicalHeight: 720,
        ppi: 109
    )
]

// MARK: - Helper Functions

/// Detect the refresh rate of an external (non-builtin) display.
/// Returns the rate in Hz, or 60.0 as a safe default.
func detectExternalDisplayRefreshRate() -> Double {
    var displayList = [CGDirectDisplayID](repeating: 0, count: 32)
    var displayCount: UInt32 = 0
    CGGetOnlineDisplayList(32, &displayList, &displayCount)

    for i in 0..<Int(displayCount) {
        let displayID = displayList[i]
        // Skip builtin displays and our virtual displays (vendor 0x1234)
        if CGDisplayIsBuiltin(displayID) != 0 { continue }
        if CGDisplayVendorNumber(displayID) == 0x1234 { continue }

        if let mode = CGDisplayCopyDisplayMode(displayID) {
            let rate = mode.refreshRate
            if rate > 0 {
                print(colorize("Detected external display \(displayID) at \(rate) Hz", .cyan))
                return rate
            }
        }
    }
    print(colorize("Could not detect external display refresh rate, defaulting to 60 Hz", .yellow))
    return 60.0
}

func printUsage() {
    print("""
    \(colorize("HiDPI Virtual Display Manager", .bold))
    \(colorize("For Samsung G9 57\" and other monitors", .cyan))

    \(colorize("USAGE:", .yellow))
        hidpi-virtual-display <command> [options]

    \(colorize("COMMANDS:", .yellow))
        \(colorize("list", .green))                     List all connected displays
        \(colorize("presets", .green))                  Show available presets
        \(colorize("create", .green)) <preset>          Create virtual display from preset
        \(colorize("create-custom", .green))            Create custom virtual display
        \(colorize("mirror", .green)) <source> <target> Mirror source display to target
        \(colorize("unmirror", .green)) <display>       Stop mirroring for display
        \(colorize("destroy", .green)) <display>        Destroy a virtual display
        \(colorize("destroy-all", .green))              Destroy all virtual displays
        \(colorize("keep-alive", .green))               Keep virtual displays alive (run in background)

    \(colorize("EXAMPLES:", .yellow))
        # List displays to find your G9's display ID
        hidpi-virtual-display list

        # Create a virtual display with G9 5120x1440 HiDPI preset
        hidpi-virtual-display create g9-5120x1440

        # Mirror the virtual display (ID from create) to your G9
        hidpi-virtual-display mirror <virtual-id> <g9-id>

        # Custom: Create 6K virtual for ultrawide
        hidpi-virtual-display create-custom 6144 1728 140 true "Custom 6K"

    \(colorize("PRESETS:", .yellow))
    """)

    for preset in presets {
        let hiDPIStr = preset.isHiDPI ? colorize("[HiDPI]", .green) : colorize("[LoDPI]", .yellow)
        print("        \(colorize(preset.name, .cyan))")
        print("            \(preset.description)")
        print("            Framebuffer: \(preset.framebufferWidth)x\(preset.framebufferHeight) \(hiDPIStr)")
        print()
    }

    print(colorize("    NOTES:", .yellow))
    print("""
            - Requires disabling SIP or special entitlements
            - M1/M2 base: max 6144px horizontal HiDPI
            - M1/M2 Pro/Max/Ultra: max 7680px horizontal HiDPI
            - Keep the process running to maintain virtual displays
    """)
}

func printDisplayList() {
    let manager = VirtualDisplayManager.shared()
    let displays = manager.listAllDisplays()

    print(colorize("\nConnected Displays:", .bold))
    print(String(repeating: "-", count: 80))

    for display in displays {
        guard let dict = display as? [String: Any] else { continue }

        let displayID = dict["id"] as? UInt32 ?? 0
        let width = dict["width"] as? Int ?? 0
        let height = dict["height"] as? Int ?? 0
        let refreshRate = dict["refreshRate"] as? Double ?? 0
        let physWidth = dict["physicalWidth"] as? Double ?? 0
        let physHeight = dict["physicalHeight"] as? Double ?? 0
        let isMain = dict["isMain"] as? Bool ?? false
        let isBuiltin = dict["isBuiltin"] as? Bool ?? false
        let mirrorOf = dict["mirrorOf"] as? UInt32 ?? 0
        let isVirtual = dict["isVirtual"] as? Bool ?? false

        var tags: [String] = []
        if isMain { tags.append(colorize("MAIN", .green)) }
        if isBuiltin { tags.append(colorize("BUILTIN", .blue)) }
        if isVirtual { tags.append(colorize("VIRTUAL", .magenta)) }
        if mirrorOf != 0 { tags.append(colorize("MIRROR->\(mirrorOf)", .yellow)) }

        let tagStr = tags.isEmpty ? "" : " " + tags.joined(separator: " ")

        print("\(colorize("Display \(displayID)", .cyan))\(tagStr)")
        print("    Resolution: \(width)x\(height) @ \(refreshRate)Hz")
        if physWidth > 0 {
            let diagonal = sqrt(pow(physWidth, 2) + pow(physHeight, 2)) / 25.4
            print("    Physical: \(Int(physWidth))x\(Int(physHeight))mm (~\(String(format: "%.1f", diagonal))\")")
        }
        print()
    }
}

func printPresets() {
    func printPreset(_ preset: DisplayPreset) {
        let hiDPIStr = preset.isHiDPI ? colorize("HiDPI", .green) : colorize("LoDPI", .yellow)
        print("\(colorize(preset.name, .cyan))")
        print("    \(preset.description)")
        print("    Framebuffer: \(preset.framebufferWidth)x\(preset.framebufferHeight)")
        print("    Logical: \(preset.logicalWidth)x\(preset.logicalHeight) [\(hiDPIStr)]")
        print()
    }

    func printPresetSection(_ title: String, presets: [DisplayPreset]) {
        guard !presets.isEmpty else { return }

        print(colorize("\n\(title):", .bold))
        print(String(repeating: "-", count: 60))

        for preset in presets {
            printPreset(preset)
        }
    }

    printPresetSection("Samsung G9 57\" Presets (7680x2160 native)", presets: presets.filter { $0.name.hasPrefix("g9-57-") })
    printPresetSection("Samsung G9 49\" Presets (5120x1440 native)", presets: presets.filter { $0.name.hasPrefix("g9-49-") })
    printPresetSection("34\" Ultrawide Presets (3440x1440 native)", presets: presets.filter { $0.name.hasPrefix("uw34-") })
    printPresetSection("38\" Ultrawide Presets (3840x1600 native)", presets: presets.filter { $0.name.hasPrefix("uw38-") })
    printPresetSection("4K Presets (3840x2160 native)", presets: presets.filter { $0.name.hasPrefix("4k-") && !$0.name.hasSuffix("-hidpi") })
    printPresetSection("Other Legacy CLI Aliases", presets: presets.filter { $0.name.hasSuffix("-hidpi") })
}

func createFromPreset(_ presetName: String) -> CGDirectDisplayID {

    guard let preset = presets.first(where: { $0.name == presetName }) else {
        print(colorize("Error: Unknown preset '\(presetName)'", .red))
        print("Use 'presets' command to see available presets")
        return CGDirectDisplayID(kCGNullDirectDisplay)
    }

    let manager = VirtualDisplayManager.shared()

    // Match the physical monitor's refresh rate to prevent flicker
    let refreshRate = detectExternalDisplayRefreshRate()

    print(colorize("Creating virtual display from preset: \(preset.name)", .cyan))
    print("    Framebuffer: \(preset.framebufferWidth)x\(preset.framebufferHeight)")
    print("    Logical: \(preset.logicalWidth)x\(preset.logicalHeight)")
    print("    HiDPI: \(preset.isHiDPI)")
    print("    Refresh Rate: \(refreshRate) Hz")

    let displayID = manager.createVirtualDisplay(
        withWidth: preset.framebufferWidth,
        height: preset.framebufferHeight,
        ppi: preset.ppi,
        hiDPI: preset.isHiDPI,
        name: preset.name,
        refreshRate: refreshRate
    )

    if displayID == kCGNullDirectDisplay {
        print(colorize("Failed to create virtual display!", .red))
        print("Make sure you have the necessary entitlements or SIP disabled.")
    } else {
        print(colorize("Created virtual display with ID: \(displayID)", .green))
        print("\nNext steps:")
        print("    1. Run: hidpi-virtual-display list")
        print("    2. Find your G9's display ID")
        print("    3. Run: hidpi-virtual-display mirror \(displayID) <g9-display-id>")
    }

    return displayID
}

func createCustomDisplay(width: UInt32, height: UInt32, ppi: UInt32, hiDPI: Bool, name: String) -> CGDirectDisplayID {
    let manager = VirtualDisplayManager.shared()

    // Match the physical monitor's refresh rate to prevent flicker
    let refreshRate = detectExternalDisplayRefreshRate()

    print(colorize("Creating custom virtual display:", .cyan))
    print("    Size: \(width)x\(height)")
    print("    PPI: \(ppi)")
    print("    HiDPI: \(hiDPI)")
    print("    Name: \(name)")
    print("    Refresh Rate: \(refreshRate) Hz")

    let displayID = manager.createVirtualDisplay(
        withWidth: width,
        height: height,
        ppi: ppi,
        hiDPI: hiDPI,
        name: name,
        refreshRate: refreshRate
    )

    if displayID == kCGNullDirectDisplay {
        print(colorize("Failed to create virtual display!", .red))
    } else {
        print(colorize("Created virtual display with ID: \(displayID)", .green))
    }

    return displayID
}

func mirrorDisplays(source: CGDirectDisplayID, target: CGDirectDisplayID) {
    let manager = VirtualDisplayManager.shared()

    print(colorize("Mirroring display \(source) to \(target)...", .cyan))

    if manager.mirrorDisplay(source, toDisplay: target) {
        print(colorize("Mirror configured successfully!", .green))
        print("Your G9 should now show the virtual display content with HiDPI scaling.")
    } else {
        print(colorize("Failed to configure mirror!", .red))
    }
}

func unmirrorDisplay(_ displayID: CGDirectDisplayID) {
    let manager = VirtualDisplayManager.shared()

    print(colorize("Stopping mirror for display \(displayID)...", .cyan))

    if manager.stopMirroring(forDisplay: displayID) {
        print(colorize("Mirror stopped successfully!", .green))
    } else {
        print(colorize("Failed to stop mirror!", .red))
    }
}

func destroyDisplay(_ displayID: CGDirectDisplayID) {
    let manager = VirtualDisplayManager.shared()
    manager.destroyVirtualDisplay(displayID)
    print(colorize("Virtual display \(displayID) destroyed.", .green))
}

func destroyAllDisplays() {
    let manager = VirtualDisplayManager.shared()
    manager.destroyAllVirtualDisplays()
    print(colorize("All virtual displays destroyed.", .green))
}

func keepAlive() {
    print(colorize("Keeping virtual displays alive...", .cyan))
    print("Press Ctrl+C to exit and destroy all virtual displays.\n")

    // Set up signal handler
    signal(SIGINT) { _ in
        print(colorize("\n\nCleaning up...", .yellow))
        VirtualDisplayManager.shared().destroyAllVirtualDisplays()
        print(colorize("Done. Exiting.", .green))
        exit(0)
    }

    // Run the run loop
    RunLoop.main.run()
}

// MARK: - Main

let args = CommandLine.arguments

if args.count < 2 {
    printUsage()
    exit(0)
}

let command = args[1]

switch command {
case "list":
    printDisplayList()

case "presets":
    printPresets()

case "create":
    if args.count < 3 {
        print(colorize("Error: Missing preset name", .red))
        print("Usage: hidpi-virtual-display create <preset-name>")
        exit(1)
    }
    let displayID = createFromPreset(args[2])
    if displayID != kCGNullDirectDisplay {
        keepAlive()
    }

case "create-custom":
    if args.count < 7 {
        print(colorize("Error: Missing arguments", .red))
        print("Usage: hidpi-virtual-display create-custom <width> <height> <ppi> <hidpi:true/false> <name>")
        exit(1)
    }
    guard let width = UInt32(args[2]),
          let height = UInt32(args[3]),
          let ppi = UInt32(args[4]) else {
        print(colorize("Error: Invalid numeric arguments", .red))
        exit(1)
    }
    let hiDPI = args[5].lowercased() == "true"
    let name = args[6]
    let displayID = createCustomDisplay(width: width, height: height, ppi: ppi, hiDPI: hiDPI, name: name)
    if displayID != kCGNullDirectDisplay {
        keepAlive()
    }

case "mirror":
    if args.count < 4 {
        print(colorize("Error: Missing display IDs", .red))
        print("Usage: hidpi-virtual-display mirror <source-id> <target-id>")
        exit(1)
    }
    guard let source = UInt32(args[2]),
          let target = UInt32(args[3]) else {
        print(colorize("Error: Invalid display IDs", .red))
        exit(1)
    }
    mirrorDisplays(source: CGDirectDisplayID(source), target: CGDirectDisplayID(target))

case "unmirror":
    if args.count < 3 {
        print(colorize("Error: Missing display ID", .red))
        print("Usage: hidpi-virtual-display unmirror <display-id>")
        exit(1)
    }
    guard let displayID = UInt32(args[2]) else {
        print(colorize("Error: Invalid display ID", .red))
        exit(1)
    }
    unmirrorDisplay(CGDirectDisplayID(displayID))

case "destroy":
    if args.count < 3 {
        print(colorize("Error: Missing display ID", .red))
        print("Usage: hidpi-virtual-display destroy <display-id>")
        exit(1)
    }
    guard let displayID = UInt32(args[2]) else {
        print(colorize("Error: Invalid display ID", .red))
        exit(1)
    }
    destroyDisplay(CGDirectDisplayID(displayID))

case "destroy-all":
    destroyAllDisplays()

case "keep-alive":
    keepAlive()

case "help", "-h", "--help":
    printUsage()

default:
    print(colorize("Unknown command: \(command)", .red))
    printUsage()
    exit(1)
}
