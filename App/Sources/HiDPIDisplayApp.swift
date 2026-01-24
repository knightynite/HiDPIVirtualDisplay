// G9 Helper
// A menu bar app for HiDPI scaling on Samsung G9 and other monitors
// Made with love by AL in Dallas

import SwiftUI
import AppKit
import CoreGraphics

func debugLog(_ message: String) {
    NSLog("HiDPI: %@", message)
}

// MARK: - Status Window

class StatusWindowController {
    private var window: NSWindow?
    private var progressIndicator: NSProgressIndicator?
    private var statusLabel: NSTextField?

    static let shared = StatusWindowController()

    private init() {}

    func show(message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.createAndShowWindow(message: message)
        }
    }

    func updateStatus(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel?.stringValue = message
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.window?.close()
            self?.window = nil
        }
    }

    private func createAndShowWindow(message: String) {
        // Create window
        let windowRect = NSRect(x: 0, y: 0, width: 300, height: 120)
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.level = .floating
        window.center()

        // Create content view
        let contentView = NSView(frame: windowRect)

        // App icon or display icon
        let iconView = NSImageView(frame: NSRect(x: 30, y: 45, width: 40, height: 40))
        if let icon = NSImage(systemSymbolName: "display", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 32, weight: .medium)
            iconView.image = icon.withSymbolConfiguration(config)
            iconView.contentTintColor = NSColor.controlAccentColor
        }
        contentView.addSubview(iconView)

        // Progress indicator
        let progress = NSProgressIndicator(frame: NSRect(x: 85, y: 65, width: 20, height: 20))
        progress.style = .spinning
        progress.controlSize = .small
        progress.startAnimation(nil)
        contentView.addSubview(progress)
        self.progressIndicator = progress

        // Title label
        let titleLabel = NSTextField(labelWithString: "G9 Helper")
        titleLabel.frame = NSRect(x: 110, y: 60, width: 160, height: 24)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.textColor = NSColor.labelColor
        contentView.addSubview(titleLabel)

        // Status label
        let statusLabel = NSTextField(labelWithString: message)
        statusLabel.frame = NSRect(x: 30, y: 20, width: 240, height: 20)
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.alignment = .center
        contentView.addSubview(statusLabel)
        self.statusLabel = statusLabel

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}

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
    var currentPresetName = ""
    var isActive = false
    var currentVirtualID: CGDirectDisplayID = 0
    var pendingTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("App launched")

        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "HiDPI Display")
        }

        // Clean up any stale state from previous sessions
        cleanupStaleState()

        // Check for existing virtual display
        checkCurrentState()

        // Build menu
        rebuildMenu()
    }

    func cleanupStaleState() {
        debugLog("Cleaning up stale display state...")
        let manager = VirtualDisplayManager.shared()

        // Reset any existing mirroring that might be left over
        manager.resetAllMirroring()

        // Destroy any virtual displays from previous session
        manager.destroyAllVirtualDisplays()

        debugLog("Stale state cleanup complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        pendingTimer?.invalidate()
        disableHiDPISync()
    }

    func checkCurrentState() {
        // Check if there's an active mirror setup
        var displayList = [CGDirectDisplayID](repeating: 0, count: 32)
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(32, &displayList, &displayCount)

        for i in 0..<Int(displayCount) {
            let displayID = displayList[i]
            let mirrorOf = CGDisplayMirrorsDisplay(displayID)
            if mirrorOf != kCGNullDirectDisplay {
                // Found a display that's mirroring something
                if let mode = CGDisplayCopyDisplayMode(mirrorOf) {
                    let width = mode.width
                    let height = mode.height
                    currentPresetName = "\(width)x\(height)"
                    isActive = true
                    debugLog("Found existing mirror: \(displayID) mirrors \(mirrorOf) at \(width)x\(height)")
                }
                break
            }
        }
    }

    func rebuildMenu() {
        let menu = NSMenu()

        // Status header
        if isActive {
            let statusItem = NSMenuItem(title: "Active: \(currentPresetName)", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
            menu.addItem(NSMenuItem.separator())

            let disableItem = NSMenuItem(title: "Disable HiDPI", action: #selector(disableHiDPIAction), keyEquivalent: "")
            disableItem.target = self
            menu.addItem(disableItem)
            menu.addItem(NSMenuItem.separator())
        } else {
            let statusItem = NSMenuItem(title: "No HiDPI active", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
            menu.addItem(NSMenuItem.separator())
        }

        // Samsung G9 57" presets
        let g9Menu = NSMenu()
        addPresetItem(to: g9Menu, preset: "g9-native-hidpi", title: "Native 2x (3840×1080)")
        addPresetItem(to: g9Menu, preset: "g9-5120x1440", title: "5120×1440 HiDPI (Recommended)")
        addPresetItem(to: g9Menu, preset: "g9-4800x1350", title: "4800×1350 HiDPI")
        addPresetItem(to: g9Menu, preset: "g9-4480x1260", title: "4480×1260 HiDPI")

        let g9Item = NSMenuItem(title: "Samsung G9 57\"", action: nil, keyEquivalent: "")
        g9Item.submenu = g9Menu
        menu.addItem(g9Item)

        // Samsung G9 49" presets
        let g49Menu = NSMenu()
        addPresetItem(to: g49Menu, preset: "g9-49-3840x1080", title: "3840×1080 HiDPI (Recommended)")
        addPresetItem(to: g49Menu, preset: "g9-49-native", title: "Native 2x (2560×720)")

        let g49Item = NSMenuItem(title: "Samsung G9 49\"", action: nil, keyEquivalent: "")
        g49Item.submenu = g49Menu
        menu.addItem(g49Item)

        // 34" Ultrawide presets
        let uwMenu = NSMenu()
        addPresetItem(to: uwMenu, preset: "uw34-2560x1080", title: "2560×1080 HiDPI (Recommended)")

        let uwItem = NSMenuItem(title: "34\" Ultrawide", action: nil, keyEquivalent: "")
        uwItem.submenu = uwMenu
        menu.addItem(uwItem)

        // 4K presets
        let k4Menu = NSMenu()
        addPresetItem(to: k4Menu, preset: "4k-2560x1440", title: "2560×1440 HiDPI (Recommended)")
        addPresetItem(to: k4Menu, preset: "4k-native", title: "Native 2x (1920×1080)")

        let k4Item = NSMenuItem(title: "4K Displays", action: nil, keyEquivalent: "")
        k4Item.submenu = k4Menu
        menu.addItem(k4Item)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About G9 Helper", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "G9 Helper"
        alert.informativeText = "Version 1.0.0\n\nEnables HiDPI (Retina) scaling on Samsung G9 and other monitors.\n\nMade with love by AL in Dallas"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func addPresetItem(to menu: NSMenu, preset: String, title: String) {
        let item = NSMenuItem(title: title, action: #selector(applyPreset(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = preset
        menu.addItem(item)
    }

    @objc func applyPreset(_ sender: NSMenuItem) {
        guard let presetName = sender.representedObject as? String else { return }
        debugLog(">>> Applying preset: \(presetName)")

        // Get preset config
        guard let config = presetConfigs[presetName] else {
            debugLog("ERROR: Unknown preset \(presetName)")
            return
        }

        // Cancel any pending operations
        pendingTimer?.invalidate()
        pendingTimer = nil

        // Show status window
        StatusWindowController.shared.show(message: "Preparing display configuration...")

        // First, completely reset display state
        debugLog("Resetting display configuration...")
        let manager = VirtualDisplayManager.shared()
        manager.resetAllMirroring()
        manager.destroyAllVirtualDisplays()
        currentVirtualID = 0
        isActive = false
        currentPresetName = ""

        // Schedule creation after a delay to let system settle
        debugLog("Scheduling display creation in 1.5 seconds...")
        pendingTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.createVirtualDisplayAsync(config: config)
        }
    }

    func disableHiDPISync() {
        debugLog("Disabling HiDPI sync - currentVirtualID: \(currentVirtualID)")

        let manager = VirtualDisplayManager.shared()

        // Reset ALL mirroring to ensure clean state
        manager.resetAllMirroring()

        // Destroy our virtual display
        manager.destroyAllVirtualDisplays()

        currentVirtualID = 0
        isActive = false
        currentPresetName = ""

        debugLog("HiDPI disabled")
    }

    func createVirtualDisplayAsync(config: PresetConfig) {
        debugLog("Creating virtual display: \(config.width)x\(config.height)")

        StatusWindowController.shared.updateStatus("Detecting external display...")

        guard let externalID = findExternalDisplay() else {
            debugLog("ERROR: No external display found")
            StatusWindowController.shared.updateStatus("No external display found")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                StatusWindowController.shared.hide()
            }
            rebuildMenu()
            return
        }
        debugLog("Using external display: \(externalID)")

        StatusWindowController.shared.updateStatus("Creating virtual display...")

        // Create virtual display on main thread
        let manager = VirtualDisplayManager.shared()
        debugLog("Calling createVirtualDisplay...")
        let virtualID = manager.createVirtualDisplay(
            withWidth: config.width,
            height: config.height,
            ppi: config.ppi,
            hiDPI: config.hiDPI,
            name: config.name,
            refreshRate: 60.0
        )
        debugLog("createVirtualDisplay returned: \(virtualID)")

        if virtualID == 0 || virtualID == UInt32.max {
            debugLog("ERROR: Failed to create virtual display (returned \(virtualID))")
            StatusWindowController.shared.updateStatus("Failed to create virtual display")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                StatusWindowController.shared.hide()
            }
            rebuildMenu()
            return
        }
        debugLog("Created virtual display: \(virtualID)")
        currentVirtualID = virtualID

        StatusWindowController.shared.updateStatus("Configuring display mirror...")

        // Wait for display to initialize using Timer (non-blocking)
        debugLog("Scheduling mirror in 3 seconds...")
        pendingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.performMirror(virtualID: virtualID, externalID: externalID, config: config)
        }
    }

    func performMirror(virtualID: CGDirectDisplayID, externalID: CGDirectDisplayID, config: PresetConfig) {
        debugLog("Setting up mirror: \(virtualID) -> \(externalID)")
        let manager = VirtualDisplayManager.shared()
        let success = manager.mirrorDisplay(virtualID, toDisplay: externalID)
        debugLog("Mirror result: \(success)")

        if success {
            isActive = true
            currentPresetName = "\(config.logicalWidth)x\(config.logicalHeight)"
            StatusWindowController.shared.updateStatus("HiDPI enabled: \(config.logicalWidth)x\(config.logicalHeight)")
        } else {
            debugLog("Mirror failed, cleaning up...")
            manager.destroyVirtualDisplay(virtualID)
            currentVirtualID = 0
            isActive = false
            currentPresetName = ""
            StatusWindowController.shared.updateStatus("Failed to configure display")
        }

        // Hide status window after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            StatusWindowController.shared.hide()
        }

        rebuildMenu()
    }

    func findExternalDisplay() -> CGDirectDisplayID? {
        var displayList = [CGDirectDisplayID](repeating: 0, count: 32)
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(32, &displayList, &displayCount)

        debugLog("findExternalDisplay: found \(displayCount) displays, currentVirtualID=\(currentVirtualID)")

        // Collect candidate displays with their physical sizes
        var candidates: [(id: CGDirectDisplayID, size: CGSize)] = []

        for i in 0..<Int(displayCount) {
            let displayID = displayList[i]
            let isBuiltin = CGDisplayIsBuiltin(displayID) != 0
            let isVirtual = displayID == currentVirtualID
            let size = CGDisplayScreenSize(displayID)

            debugLog("  Display \(displayID): builtin=\(isBuiltin), isOurVirtual=\(isVirtual), size=\(size.width)x\(size.height)mm")

            // Skip builtin displays and our own virtual display
            if !isBuiltin && !isVirtual {
                candidates.append((id: displayID, size: size))
            }
        }

        // Prefer displays with large physical size (real monitors vs virtual)
        // G9 57" is about 1400mm wide, G9 49" is about 1200mm wide
        // Sort by width descending to prefer larger displays
        candidates.sort { $0.size.width > $1.size.width }

        if let best = candidates.first {
            debugLog("  -> Selected external display: \(best.id) (\(best.size.width)mm wide)")
            return best.id
        }

        debugLog("  -> No external display found")
        return nil
    }

    @objc func disableHiDPIAction() {
        pendingTimer?.invalidate()
        pendingTimer = nil

        StatusWindowController.shared.show(message: "Disabling HiDPI...")
        disableHiDPISync()
        rebuildMenu()

        StatusWindowController.shared.updateStatus("HiDPI disabled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            StatusWindowController.shared.hide()
        }
    }

    @objc func quitApp() {
        pendingTimer?.invalidate()
        disableHiDPISync()
        NSApp.terminate(nil)
    }
}

// MARK: - Preset Configurations

struct PresetConfig {
    let name: String
    let width: UInt32      // Framebuffer width
    let height: UInt32     // Framebuffer height
    let logicalWidth: UInt32
    let logicalHeight: UInt32
    let ppi: UInt32
    let hiDPI: Bool
}

let presetConfigs: [String: PresetConfig] = [
    // Samsung G9 57" (7680x2160)
    "g9-native-hidpi": PresetConfig(name: "G9-Native", width: 7680, height: 2160, logicalWidth: 3840, logicalHeight: 1080, ppi: 140, hiDPI: true),
    "g9-5120x1440": PresetConfig(name: "G9-5120", width: 10240, height: 2880, logicalWidth: 5120, logicalHeight: 1440, ppi: 140, hiDPI: true),
    "g9-4800x1350": PresetConfig(name: "G9-4800", width: 9600, height: 2700, logicalWidth: 4800, logicalHeight: 1350, ppi: 140, hiDPI: true),
    "g9-4480x1260": PresetConfig(name: "G9-4480", width: 8960, height: 2520, logicalWidth: 4480, logicalHeight: 1260, ppi: 140, hiDPI: true),

    // Samsung G9 49" (5120x1440)
    "g9-49-native": PresetConfig(name: "G9-49-Native", width: 5120, height: 1440, logicalWidth: 2560, logicalHeight: 720, ppi: 109, hiDPI: true),
    "g9-49-3840x1080": PresetConfig(name: "G9-49-3840", width: 7680, height: 2160, logicalWidth: 3840, logicalHeight: 1080, ppi: 109, hiDPI: true),

    // 34" Ultrawide
    "uw34-2560x1080": PresetConfig(name: "UW34-2560", width: 5120, height: 2160, logicalWidth: 2560, logicalHeight: 1080, ppi: 110, hiDPI: true),

    // 4K
    "4k-native": PresetConfig(name: "4K-Native", width: 3840, height: 2160, logicalWidth: 1920, logicalHeight: 1080, ppi: 163, hiDPI: true),
    "4k-2560x1440": PresetConfig(name: "4K-2560", width: 5120, height: 2880, logicalWidth: 2560, logicalHeight: 1440, ppi: 163, hiDPI: true),
]
