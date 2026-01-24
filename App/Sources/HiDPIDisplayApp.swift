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

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var displayManager = VirtualDisplayManager.shared()
    var currentVirtualDisplayID: CGDirectDisplayID = 0
    var popover = NSPopover()

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
        popover.contentSize = NSSize(width: 320, height: 480)
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

        if currentVirtualDisplayID != 0 {
            // Find the G9 display and mirror
            if let g9DisplayID = findG9Display() {
                displayManager.mirrorDisplay(currentVirtualDisplayID, toDisplay: g9DisplayID)
            }
        }
    }

    func destroyVirtualDisplay() {
        if currentVirtualDisplayID != 0 {
            // Stop mirroring first
            if let g9DisplayID = findG9Display() {
                displayManager.stopMirroring(forDisplay: g9DisplayID)
            }
            displayManager.destroyVirtualDisplay(currentVirtualDisplayID)
            currentVirtualDisplayID = 0
        }
    }

    func findG9Display() -> CGDirectDisplayID? {
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
        description: "Looks like 3840x1080",
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
        displayName: "5120x1440 HiDPI",
        description: "Recommended - Good balance",
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
        displayName: "3840x1080 HiDPI",
        description: "More workspace",
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
        displayName: "2560x1080 HiDPI",
        description: "More workspace",
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
        displayName: "2560x1440 HiDPI",
        description: "More workspace",
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
    @ObservedObject var viewModel: MenuViewModel
    let appDelegate: AppDelegate

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        self.viewModel = MenuViewModel(appDelegate: appDelegate)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "display")
                    .font(.title2)
                Text("HiDPI Virtual Display")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color.accentColor.opacity(0.1))

            Divider()

            // Status
            StatusView(viewModel: viewModel)

            Divider()

            // Preset Selection
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(PresetCategory.allCases.filter { $0 != .custom }, id: \.self) { category in
                        let categoryPresets = presets.filter { $0.category == category }
                        if !categoryPresets.isEmpty {
                            PresetCategoryView(
                                category: category,
                                presets: categoryPresets,
                                viewModel: viewModel
                            )
                        }
                    }

                    // Custom Resolution
                    CustomResolutionView(viewModel: viewModel)
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Button("Disable") {
                    viewModel.disableVirtualDisplay()
                }
                .disabled(!viewModel.isActive)

                Spacer()

                Toggle("Start at Login", isOn: $viewModel.launchAtLogin)
                    .toggleStyle(.checkbox)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .padding()
        }
        .frame(width: 320, height: 480)
    }
}

struct StatusView: View {
    @ObservedObject var viewModel: MenuViewModel

    var body: some View {
        HStack {
            Circle()
                .fill(viewModel.isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            if viewModel.isActive {
                VStack(alignment: .leading) {
                    Text("Active: \(viewModel.currentPresetName)")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("Looks like: \(viewModel.currentResolution)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No virtual display active")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct PresetCategoryView: View {
    let category: PresetCategory
    let presets: [DisplayPreset]
    @ObservedObject var viewModel: MenuViewModel

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(category.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(presets) { preset in
                    PresetButton(preset: preset, viewModel: viewModel)
                }
            }
        }
    }
}

struct PresetButton: View {
    let preset: DisplayPreset
    @ObservedObject var viewModel: MenuViewModel

    var isSelected: Bool {
        viewModel.currentPresetName == preset.displayName
    }

    var body: some View {
        Button(action: {
            viewModel.activatePreset(preset)
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.displayName)
                        .font(.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                    Text(preset.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }

                Text("HiDPI")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct CustomResolutionView: View {
    @ObservedObject var viewModel: MenuViewModel
    @State private var isExpanded = false
    @State private var width: String = "5120"
    @State private var height: String = "1440"
    @State private var ppi: String = "140"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Custom Resolution")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 8) {
                    HStack {
                        Text("Looks like:")
                            .font(.caption)
                        TextField("Width", text: $width)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("x")
                        TextField("Height", text: $height)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }

                    HStack {
                        Text("PPI:")
                            .font(.caption)
                        TextField("PPI", text: $ppi)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Spacer()
                        Button("Apply") {
                            if let w = UInt32(width), let h = UInt32(height), let p = UInt32(ppi) {
                                viewModel.activateCustomResolution(width: w, height: h, ppi: p)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    Text("Framebuffer will be \(Int(width) ?? 0 * 2)x\(Int(height) ?? 0 * 2)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }
}

// MARK: - View Model

class MenuViewModel: ObservableObject {
    @Published var isActive = false
    @Published var currentPresetName = ""
    @Published var currentResolution = ""
    @Published var launchAtLogin = false

    let appDelegate: AppDelegate

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        self.launchAtLogin = LaunchAtLoginManager.isEnabled
    }

    func activatePreset(_ preset: DisplayPreset) {
        appDelegate.createVirtualDisplay(preset: preset)
        isActive = true
        currentPresetName = preset.displayName
        currentResolution = preset.resolutionString
    }

    func activateCustomResolution(width: UInt32, height: UInt32, ppi: UInt32) {
        let preset = DisplayPreset(
            name: "custom",
            displayName: "Custom",
            description: "\(width)x\(height)",
            framebufferWidth: width * 2,
            framebufferHeight: height * 2,
            logicalWidth: width,
            logicalHeight: height,
            ppi: ppi,
            refreshRate: 60,
            category: .custom
        )
        activatePreset(preset)
    }

    func disableVirtualDisplay() {
        appDelegate.destroyVirtualDisplay()
        isActive = false
        currentPresetName = ""
        currentResolution = ""
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
        // Create launch agent
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
