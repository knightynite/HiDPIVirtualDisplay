// HiDPIDisplayApp.swift
// A menu bar app for creating HiDPI virtual displays on macOS
// Designed for Samsung G9 57" and other high-resolution monitors

import SwiftUI
import AppKit
import CoreGraphics

@main
struct HiDPIDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusItem: NSStatusItem?
    var displayManager = VirtualDisplayManager.shared()
    var currentVirtualDisplayID: CGDirectDisplayID = 0
    var popover = NSPopover()

    @Published var isActive = false
    @Published var currentPresetName = ""
    @Published var currentResolution = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "HiDPI Display")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Setup popover
        popover.contentSize = NSSize(width: 340, height: 520)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuContentView(appDelegate: self))
    }

    @objc func togglePopover() {
        if let button = statusItem?.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func createVirtualDisplay(preset: DisplayPreset) {
        print("Creating virtual display: \(preset.displayName)")
        print("  Framebuffer: \(preset.framebufferWidth)x\(preset.framebufferHeight)")
        print("  Logical: \(preset.logicalWidth)x\(preset.logicalHeight)")

        // Destroy existing virtual display first
        if currentVirtualDisplayID != 0 {
            destroyVirtualDisplay()
        }

        currentVirtualDisplayID = displayManager.createVirtualDisplay(
            withWidth: preset.framebufferWidth,
            height: preset.framebufferHeight,
            ppi: preset.ppi,
            hiDPI: preset.isHiDPI,
            name: preset.name,
            refreshRate: preset.refreshRate
        )

        print("  Created display ID: \(currentVirtualDisplayID)")

        if currentVirtualDisplayID != 0 {
            // Find the external display and mirror
            if let externalDisplayID = findExternalDisplay() {
                print("  Mirroring to display: \(externalDisplayID)")
                let success = displayManager.mirrorDisplay(currentVirtualDisplayID, toDisplay: externalDisplayID)
                print("  Mirror success: \(success)")

                if success {
                    DispatchQueue.main.async {
                        self.isActive = true
                        self.currentPresetName = preset.displayName
                        self.currentResolution = preset.resolutionString
                    }
                }
            } else {
                print("  No external display found!")
            }
        } else {
            print("  Failed to create virtual display!")
        }
    }

    func destroyVirtualDisplay() {
        print("Destroying virtual display: \(currentVirtualDisplayID)")

        if currentVirtualDisplayID != 0 {
            // Stop mirroring first
            if let externalDisplayID = findExternalDisplay() {
                displayManager.stopMirroring(forDisplay: externalDisplayID)
            }
            displayManager.destroyVirtualDisplay(currentVirtualDisplayID)
            currentVirtualDisplayID = 0

            DispatchQueue.main.async {
                self.isActive = false
                self.currentPresetName = ""
                self.currentResolution = ""
            }
        }
    }

    func findExternalDisplay() -> CGDirectDisplayID? {
        let displays = displayManager.listAllDisplays()
        for display in displays {
            guard let dict = display as? [String: Any],
                  let displayID = dict["id"] as? UInt32,
                  let isVirtual = dict["isVirtual"] as? Bool,
                  !isVirtual else { continue }

            // Return the first non-virtual external display
            let isBuiltin = dict["isBuiltin"] as? Bool ?? false
            if !isBuiltin {
                return CGDirectDisplayID(displayID)
            }
        }
        return nil
    }
}

// MARK: - Display Preset Model

struct DisplayPreset: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let displayName: String
    let description: String
    let framebufferWidth: UInt32
    let framebufferHeight: UInt32
    let logicalWidth: UInt32
    let logicalHeight: UInt32
    let ppi: UInt32
    let refreshRate: Double
    let category: PresetCategory

    var isHiDPI: Bool {
        return framebufferWidth == logicalWidth * 2
    }

    var resolutionString: String {
        return "\(logicalWidth)x\(logicalHeight)"
    }

    var framebufferString: String {
        return "\(framebufferWidth)x\(framebufferHeight)"
    }
}

enum PresetCategory: String, CaseIterable {
    case samsungG9_57 = "Samsung G9 57\""
    case samsungG9_49 = "Samsung G9 49\""
    case ultrawide_34 = "34\" Ultrawide"
    case standard_4k = "4K Displays"
    case custom = "Custom"
}

// MARK: - Preset Definitions

let presets: [DisplayPreset] = [
    // Samsung G9 57" (7680x2160)
    DisplayPreset(
        name: "g9-57-native-hidpi",
        displayName: "Native 2x HiDPI",
        description: "Looks like 3840x1080 - Largest UI",
        framebufferWidth: 7680,
        framebufferHeight: 2160,
        logicalWidth: 3840,
        logicalHeight: 1080,
        ppi: 140,
        refreshRate: 60,
        category: .samsungG9_57
    ),
    DisplayPreset(
        name: "g9-57-5120x1440",
        displayName: "5120x1440 HiDPI ★",
        description: "Recommended - Best balance",
        framebufferWidth: 10240,
        framebufferHeight: 2880,
        logicalWidth: 5120,
        logicalHeight: 1440,
        ppi: 140,
        refreshRate: 60,
        category: .samsungG9_57
    ),
    DisplayPreset(
        name: "g9-57-4800x1350",
        displayName: "4800x1350 HiDPI",
        description: "Slightly larger UI",
        framebufferWidth: 9600,
        framebufferHeight: 2700,
        logicalWidth: 4800,
        logicalHeight: 1350,
        ppi: 140,
        refreshRate: 60,
        category: .samsungG9_57
    ),
    DisplayPreset(
        name: "g9-57-4480x1260",
        displayName: "4480x1260 HiDPI",
        description: "Larger UI elements",
        framebufferWidth: 8960,
        framebufferHeight: 2520,
        logicalWidth: 4480,
        logicalHeight: 1260,
        ppi: 140,
        refreshRate: 60,
        category: .samsungG9_57
    ),
    DisplayPreset(
        name: "g9-57-4096x1152",
        displayName: "4096x1152 HiDPI",
        description: "Even larger UI",
        framebufferWidth: 8192,
        framebufferHeight: 2304,
        logicalWidth: 4096,
        logicalHeight: 1152,
        ppi: 140,
        refreshRate: 60,
        category: .samsungG9_57
    ),

    // Samsung G9 49" (5120x1440)
    DisplayPreset(
        name: "g9-49-native-hidpi",
        displayName: "Native 2x HiDPI",
        description: "Looks like 2560x720",
        framebufferWidth: 5120,
        framebufferHeight: 1440,
        logicalWidth: 2560,
        logicalHeight: 720,
        ppi: 109,
        refreshRate: 60,
        category: .samsungG9_49
    ),
    DisplayPreset(
        name: "g9-49-3840x1080",
        displayName: "3840x1080 HiDPI ★",
        description: "Recommended - More workspace",
        framebufferWidth: 7680,
        framebufferHeight: 2160,
        logicalWidth: 3840,
        logicalHeight: 1080,
        ppi: 109,
        refreshRate: 60,
        category: .samsungG9_49
    ),
    DisplayPreset(
        name: "g9-49-3440x960",
        displayName: "3440x960 HiDPI",
        description: "Balanced workspace",
        framebufferWidth: 6880,
        framebufferHeight: 1920,
        logicalWidth: 3440,
        logicalHeight: 960,
        ppi: 109,
        refreshRate: 60,
        category: .samsungG9_49
    ),

    // 34" Ultrawide (3440x1440)
    DisplayPreset(
        name: "uw34-native-hidpi",
        displayName: "Native 2x HiDPI",
        description: "Looks like 1720x720",
        framebufferWidth: 3440,
        framebufferHeight: 1440,
        logicalWidth: 1720,
        logicalHeight: 720,
        ppi: 110,
        refreshRate: 60,
        category: .ultrawide_34
    ),
    DisplayPreset(
        name: "uw34-2560x1080",
        displayName: "2560x1080 HiDPI ★",
        description: "Recommended - More workspace",
        framebufferWidth: 5120,
        framebufferHeight: 2160,
        logicalWidth: 2560,
        logicalHeight: 1080,
        ppi: 110,
        refreshRate: 60,
        category: .ultrawide_34
    ),

    // Standard 4K
    DisplayPreset(
        name: "4k-native-hidpi",
        displayName: "Native 2x HiDPI",
        description: "Looks like 1920x1080",
        framebufferWidth: 3840,
        framebufferHeight: 2160,
        logicalWidth: 1920,
        logicalHeight: 1080,
        ppi: 163,
        refreshRate: 60,
        category: .standard_4k
    ),
    DisplayPreset(
        name: "4k-2560x1440",
        displayName: "2560x1440 HiDPI ★",
        description: "Recommended - More workspace",
        framebufferWidth: 5120,
        framebufferHeight: 2880,
        logicalWidth: 2560,
        logicalHeight: 1440,
        ppi: 163,
        refreshRate: 60,
        category: .standard_4k
    ),
]

// MARK: - SwiftUI Views

struct MenuContentView: View {
    @ObservedObject var appDelegate: AppDelegate
    @State private var customWidth: String = "5120"
    @State private var customHeight: String = "1440"
    @State private var customPPI: String = "140"
    @State private var showCustom = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "display.2")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("HiDPI Virtual Display")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color.accentColor.opacity(0.1))

            Divider()

            // Status
            HStack {
                Circle()
                    .fill(appDelegate.isActive ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)

                if appDelegate.isActive {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active: \(appDelegate.currentPresetName)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Looks like: \(appDelegate.currentResolution)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("No virtual display active")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if appDelegate.isActive {
                    Button("Disable") {
                        appDelegate.destroyVirtualDisplay()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(appDelegate.isActive ? Color.green.opacity(0.1) : Color.clear)

            Divider()

            // Preset Selection
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(PresetCategory.allCases.filter { $0 != .custom }, id: \.self) { category in
                        let categoryPresets = presets.filter { $0.category == category }
                        if !categoryPresets.isEmpty {
                            PresetSection(
                                category: category,
                                presets: categoryPresets,
                                appDelegate: appDelegate
                            )
                        }
                    }

                    // Custom Resolution Section
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: { withAnimation { showCustom.toggle() } }) {
                            HStack {
                                Image(systemName: showCustom ? "chevron.down" : "chevron.right")
                                    .font(.caption)
                                Text("Custom Resolution")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)

                        if showCustom {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Looks like:")
                                        .font(.caption)
                                        .frame(width: 70, alignment: .leading)
                                    TextField("Width", text: $customWidth)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 70)
                                    Text("×")
                                    TextField("Height", text: $customHeight)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 70)
                                }

                                HStack {
                                    Text("PPI:")
                                        .font(.caption)
                                        .frame(width: 70, alignment: .leading)
                                    TextField("PPI", text: $customPPI)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 70)

                                    Spacer()

                                    Button("Apply Custom") {
                                        applyCustomResolution()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }

                                if let w = UInt32(customWidth), let h = UInt32(customHeight) {
                                    Text("Framebuffer: \(w * 2)×\(h * 2)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Button("Quit") {
                    appDelegate.destroyVirtualDisplay()
                    NSApp.terminate(nil)
                }

                Spacer()

                Link("GitHub", destination: URL(string: "https://github.com")!)
                    .font(.caption)
            }
            .padding()
        }
        .frame(width: 340, height: 520)
    }

    func applyCustomResolution() {
        guard let w = UInt32(customWidth),
              let h = UInt32(customHeight),
              let p = UInt32(customPPI) else { return }

        let preset = DisplayPreset(
            name: "custom-\(w)x\(h)",
            displayName: "Custom \(w)×\(h)",
            description: "Custom resolution",
            framebufferWidth: w * 2,
            framebufferHeight: h * 2,
            logicalWidth: w,
            logicalHeight: h,
            ppi: p,
            refreshRate: 60,
            category: .custom
        )
        appDelegate.createVirtualDisplay(preset: preset)
    }
}

struct PresetSection: View {
    let category: PresetCategory
    let presets: [DisplayPreset]
    @ObservedObject var appDelegate: AppDelegate
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(category.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(presets) { preset in
                        PresetRow(preset: preset, appDelegate: appDelegate)
                    }
                }
            }
        }
    }
}

struct PresetRow: View {
    let preset: DisplayPreset
    @ObservedObject var appDelegate: AppDelegate

    var isSelected: Bool {
        appDelegate.currentPresetName == preset.displayName
    }

    var body: some View {
        Button(action: {
            print("Button clicked: \(preset.displayName)")
            appDelegate.createVirtualDisplay(preset: preset)
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.displayName)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .bold : .regular)
                        .foregroundColor(isSelected ? .accentColor : .primary)
                    Text(preset.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - Launch at Login

class LaunchAtLoginManager {
    static var isEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: "launchAtLogin")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "launchAtLogin")
            if newValue {
                enableLaunchAtLogin()
            } else {
                disableLaunchAtLogin()
            }
        }
    }

    static func enableLaunchAtLogin() {
        let launchAgentPath = NSHomeDirectory() + "/Library/LaunchAgents/com.hidpi.virtualdisplay.plist"
        let appPath = Bundle.main.bundlePath

        let plist: [String: Any] = [
            "Label": "com.hidpi.virtualdisplay",
            "ProgramArguments": [appPath + "/Contents/MacOS/HiDPIDisplay"],
            "RunAtLoad": true,
            "KeepAlive": false
        ]

        let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try? data?.write(to: URL(fileURLWithPath: launchAgentPath))
    }

    static func disableLaunchAtLogin() {
        let launchAgentPath = NSHomeDirectory() + "/Library/LaunchAgents/com.hidpi.virtualdisplay.plist"
        try? FileManager.default.removeItem(atPath: launchAgentPath)
    }
}
