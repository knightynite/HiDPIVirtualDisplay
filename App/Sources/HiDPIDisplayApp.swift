// G9 Helper
// HiDPI scaling utility for Samsung Odyssey G9 and large monitors
// Created by AL in Dallas

import SwiftUI
import AppKit
import CoreGraphics

func debugLog(_ message: String) {
    NSLog("HiDPI: %@", message)
    // Also write to a file for easier debugging
    let logFile = "/tmp/g9helper.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile) {
            if let handle = FileHandle(forWritingAtPath: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: logFile, contents: data)
        }
    }
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
    private var statusItem: NSStatusItem?
    private var currentPresetName = ""
    private var isActive = false
    private var currentVirtualID: CGDirectDisplayID = 0
    private var targetExternalDisplayID: CGDirectDisplayID = 0  // Track which external display we're mirroring to

    // State persistence keys
    private let kLastPresetKey = "lastActivePreset"
    private let kWasCrashKey = "wasRunningWhenCrashed"
    private let kAutoRestoreKey = "autoRestoreOnCrash"
    private let kAutoApplyOnConnectKey = "autoApplyOnConnect"

    // Track if we're waiting for monitor reconnection
    private var wasDisconnected = false

    // Track if we're in the middle of setting up HiDPI (don't trigger cleanup during setup)
    private var isSettingUp = false

    // Donation link
    private let donationURL = "https://buymeacoffee.com/alcybr"

    // Display change observer
    private var displayObserver: Any?
    private var displayCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("App launched")

        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "HiDPI Display")
        }

        // Restore wasDisconnected state from UserDefaults (persists across restart)
        wasDisconnected = UserDefaults.standard.bool(forKey: kWasDisconnectedKey)
        debugLog("Restored wasDisconnected state: \(wasDisconnected)")

        // Clean up any stale state from previous sessions
        cleanupStaleState()

        // Check for existing virtual display
        checkCurrentState()

        // Check if we should auto-restore after a crash OR after disconnect restart
        checkAndRestoreFromCrash()

        // Build menu
        rebuildMenu()

        // Mark that the app is running (for crash detection)
        UserDefaults.standard.set(true, forKey: kWasCrashKey)

        // Start monitoring for display changes (disconnect detection)
        startDisplayChangeMonitoring()
    }

    func startDisplayChangeMonitoring() {
        // Use NotificationCenter to monitor screen configuration changes
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            debugLog(">>> Display change notification received")
            self?.handleDisplayConfigurationChange()
        }

        // Also add a periodic check as backup (every 3 seconds)
        displayCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.periodicDisplayCheck()
        }

        debugLog("Display change monitoring started (notification + timer)")
    }

    func stopDisplayChangeMonitoring() {
        if let observer = displayObserver {
            NotificationCenter.default.removeObserver(observer)
            displayObserver = nil
        }
        displayCheckTimer?.invalidate()
        displayCheckTimer = nil
        debugLog("Display change monitoring stopped")
    }

    func periodicDisplayCheck() {
        // Don't trigger cleanup during setup
        if isSettingUp { return }

        let realMonitor = findRealPhysicalMonitor()

        // Case 1: HiDPI active but monitor disconnected
        if isActive && realMonitor == nil {
            debugLog(">>> Periodic check: Physical monitor gone - cleaning up")
            wasDisconnected = true
            cleanupAfterDisconnect()
            return
        }

        // Case 2: HiDPI not active, monitor reconnected, auto-apply enabled
        if !isActive && wasDisconnected && realMonitor != nil {
            let autoApply = UserDefaults.standard.bool(forKey: kAutoApplyOnConnectKey)
            if autoApply, let lastPreset = UserDefaults.standard.string(forKey: kLastPresetKey), !lastPreset.isEmpty {
                debugLog(">>> Periodic check: Monitor reconnected - auto-applying \(lastPreset)")
                wasDisconnected = false
                UserDefaults.standard.set(false, forKey: kWasDisconnectedKey)
                restorePreset(lastPreset)
            }
        }
    }

    func handleDisplayConfigurationChange() {
        debugLog("Display configuration changed, checking state...")

        // Don't trigger cleanup during setup
        if isSettingUp {
            debugLog("Setup in progress, skipping disconnect check")
            return
        }

        // Case 1: HiDPI is active, check if physical monitor was disconnected
        if isActive && currentVirtualID != 0 {
            // Only check if the real physical monitor is still connected
            // Don't check mirroring status - macOS can break mirroring unexpectedly
            let realMonitor = findRealPhysicalMonitor()

            if realMonitor == nil {
                debugLog("Physical monitor disconnected (no real monitor found) - cleaning up")
                wasDisconnected = true
                cleanupAfterDisconnect()
                return
            } else {
                debugLog("Physical monitor still connected: \(realMonitor!)")
            }
            return
        }

        // Case 2: HiDPI is not active, check if monitor was reconnected
        let realMonitor = findRealPhysicalMonitor()
        if !isActive && realMonitor != nil && wasDisconnected {
            debugLog("External display reconnected")

            let autoApply = UserDefaults.standard.bool(forKey: kAutoApplyOnConnectKey)
            if autoApply, let lastPreset = UserDefaults.standard.string(forKey: kLastPresetKey), !lastPreset.isEmpty {
                debugLog("Auto-applying last preset: \(lastPreset)")
                wasDisconnected = false
                UserDefaults.standard.set(false, forKey: kWasDisconnectedKey)

                // Delay to let the display settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.restorePreset(lastPreset)
                }
            } else {
                debugLog("Auto-apply disabled or no saved preset")
                wasDisconnected = false
                UserDefaults.standard.set(false, forKey: kWasDisconnectedKey)
            }
        }
    }

    // Find a real physical monitor (not built-in, not a virtual display we created)
    // Our virtual displays use vendor ID 0x1234 - real monitors have real vendor IDs
    func findRealPhysicalMonitor() -> CGDirectDisplayID? {
        var displayList = [CGDirectDisplayID](repeating: 0, count: 32)
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(32, &displayList, &displayCount)

        for i in 0..<Int(displayCount) {
            let displayID = displayList[i]
            let isBuiltin = CGDisplayIsBuiltin(displayID) != 0
            let vendorID = CGDisplayVendorNumber(displayID)
            let size = CGDisplayScreenSize(displayID)

            // Our virtual displays use vendor ID 0x1234 (4660 decimal)
            let isVirtualDisplay = vendorID == 0x1234

            debugLog("  Display \(displayID): builtin=\(isBuiltin), vendor=\(vendorID), virtual=\(isVirtualDisplay), size=\(size.width)mm")

            // Real monitors are: not built-in, not a virtual display (vendor != 0x1234)
            if !isBuiltin && !isVirtualDisplay {
                debugLog("Found real physical monitor: \(displayID) (vendor: \(vendorID))")
                return displayID
            }
        }
        debugLog("No real physical monitor found")
        return nil
    }

    func cleanupAfterDisconnect() {
        debugLog(">>> Starting disconnect cleanup")

        // Move all windows to main display first
        moveAllWindowsToMainDisplay()

        // Mark that we're disconnected (for auto-restore on reconnect)
        UserDefaults.standard.set(true, forKey: kWasDisconnectedKey)

        // The CGVirtualDisplay framework doesn't actually destroy displays when we release
        // the object - they persist until the app terminates. The only reliable way to
        // clean up orphaned virtual displays is to restart the app.
        debugLog(">>> Restarting app to clean up virtual displays...")

        // Relaunch the app
        relaunchApp()
    }

    private let kWasDisconnectedKey = "wasDisconnected"

    func relaunchApp() {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1 && open \"\(Bundle.main.bundlePath)\""]
        task.launch()

        // Terminate current instance
        NSApp.terminate(nil)
    }

    // Disable HiDPI when monitor is disconnected - preserves preset for auto-restore
    func disableHiDPIForDisconnect() {
        debugLog("Disabling HiDPI for disconnect (preserving preset) - currentVirtualID: \(currentVirtualID)")

        let manager = VirtualDisplayManager.shared()

        // Reset ALL mirroring to ensure clean state
        manager.resetAllMirroring()

        // Destroy our virtual display
        manager.destroyAllVirtualDisplays()

        currentVirtualID = 0
        targetExternalDisplayID = 0
        isActive = false
        currentPresetName = ""

        // DO NOT clear saved preset - we want to restore it when monitor reconnects
        debugLog("HiDPI disabled (preset preserved for reconnection)")
    }

    func moveAllWindowsToMainDisplay() {
        debugLog("Moving all windows to main display...")

        // Use AppleScript to move windows since it's more reliable for cross-app windows
        let script = """
            tell application "System Events"
                set allProcesses to every process whose background only is false
                repeat with proc in allProcesses
                    try
                        tell proc
                            repeat with w in windows
                                set position of w to {100, 100}
                            end repeat
                        end tell
                    end try
                end repeat
            end tell
            """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                debugLog("AppleScript error moving windows: \(error)")
            } else {
                debugLog("Windows moved to main display")
            }
        }
    }

    func checkAndRestoreFromCrash() {
        let wasRunning = UserDefaults.standard.bool(forKey: kWasCrashKey)
        let autoRestore = UserDefaults.standard.bool(forKey: kAutoRestoreKey)

        // Default to auto-restore enabled
        if UserDefaults.standard.object(forKey: kAutoRestoreKey) == nil {
            UserDefaults.standard.set(true, forKey: kAutoRestoreKey)
        }

        // Default to auto-apply on reconnect enabled
        if UserDefaults.standard.object(forKey: kAutoApplyOnConnectKey) == nil {
            UserDefaults.standard.set(true, forKey: kAutoApplyOnConnectKey)
        }

        // If we restarted after disconnect (not crash), don't try to restore here
        // Let the reconnect detection handle it when monitor is plugged back in
        if wasDisconnected {
            debugLog("Restarted after disconnect - waiting for monitor reconnection")
            return
        }

        if wasRunning && autoRestore {
            if let lastPreset = UserDefaults.standard.string(forKey: kLastPresetKey),
               !lastPreset.isEmpty {
                // Only restore if external display is connected
                if findExternalDisplay() != nil {
                    debugLog("Detected restart after crash, auto-restoring preset: \(lastPreset)")

                    // Delay restoration to let the system settle
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.restorePreset(lastPreset)
                    }
                } else {
                    debugLog("Detected restart after crash, but no external display - waiting for reconnection")
                    wasDisconnected = true
                    UserDefaults.standard.set(true, forKey: kWasDisconnectedKey)
                }
            }
        }

        // Clear the crash flag (will be set again when app is running)
        UserDefaults.standard.set(false, forKey: kWasCrashKey)
    }

    // Map old preset names to new ones for backwards compatibility
    func migratePresetName(_ oldName: String) -> String {
        let migrations: [String: String] = [
            "g9-native-hidpi": "g9-57-3840x1080",
            "g9-5120x1440": "g9-57-5120x1440",
            "g9-4800x1350": "g9-57-4800x1350",
            "g9-4480x1260": "g9-57-4389x1234",  // closest match
            "g9-49-native": "g9-49-2560x720",
            "g9-49-3840x1080": "g9-49-3840x1080",  // same
            "uw34-2560x1080": "uw34-2293x960",  // closest match
            "4k-native": "4k-1920x1080",
            "4k-2560x1440": "4k-2560x1440",  // same
        ]
        return migrations[oldName] ?? oldName
    }

    func restorePreset(_ presetName: String) {
        let migratedName = migratePresetName(presetName)
        guard let config = presetConfigs[migratedName] else {
            debugLog("ERROR: Unknown preset for restore: \(presetName) (migrated: \(migratedName))")
            return
        }

        // Update saved preset to new name if migrated
        if migratedName != presetName {
            debugLog("Migrated preset name: \(presetName) -> \(migratedName)")
            saveCurrentPreset(migratedName)
        }

        debugLog(">>> Auto-restoring preset: \(presetName)")

        // Mark that we're setting up (don't trigger cleanup during setup)
        isSettingUp = true

        StatusWindowController.shared.show(message: "Restoring display configuration...")

        let manager = VirtualDisplayManager.shared()
        manager.resetAllMirroring()
        manager.destroyAllVirtualDisplays()
        currentVirtualID = 0
        isActive = false
        currentPresetName = ""

        // Schedule creation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            autoreleasepool {
                self?.createVirtualDisplayAsync(config: config)
            }
        }

        // Re-save the preset since we're using it
        saveCurrentPreset(presetName)
    }

    func saveCurrentPreset(_ presetName: String) {
        UserDefaults.standard.set(presetName, forKey: kLastPresetKey)
        UserDefaults.standard.set(true, forKey: kWasCrashKey)
        debugLog("Saved preset for crash recovery: \(presetName)")
    }

    func clearSavedPreset() {
        UserDefaults.standard.removeObject(forKey: kLastPresetKey)
        UserDefaults.standard.set(false, forKey: kWasCrashKey)
        debugLog("Cleared saved preset")
    }

    func cleanupStaleState() {
        debugLog("Cleaning up stale display state...")
        let manager = VirtualDisplayManager.shared()

        // Check if we have an external display connected
        let hasExternalDisplay = findExternalDisplay() != nil
        debugLog("External display connected: \(hasExternalDisplay)")

        // If no external display, move windows to main display first
        // This handles the case where app was killed/crashed while HiDPI was active
        if !hasExternalDisplay {
            debugLog("No external display - moving windows to main display")
            moveAllWindowsToMainDisplay()
        }

        // Reset any existing mirroring that might be left over
        manager.resetAllMirroring()

        // Destroy any virtual displays from previous session
        manager.destroyAllVirtualDisplays()

        debugLog("Stale state cleanup complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        debugLog("App terminating - cleaning up...")

        // Stop monitoring
        stopDisplayChangeMonitoring()

        // Move windows to main display before cleanup
        if isActive {
            moveAllWindowsToMainDisplay()
        }

        // Disable HiDPI but preserve preset for auto-restore on next launch
        disableHiDPIForDisconnect()

        debugLog("Cleanup complete, terminating")
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

        // Samsung G9 57" (7680x2160) presets - ordered by scale factor (smaller = more space)
        let g9Menu = NSMenu()
        addPresetItem(to: g9Menu, preset: "g9-57-6144x1728", title: "6144×1728 (1.25x) - More Space")
        addPresetItem(to: g9Menu, preset: "g9-57-5908x1662", title: "5908×1662 (1.3x)")
        addPresetItem(to: g9Menu, preset: "g9-57-5120x1440", title: "5120×1440 (1.5x) ★ Recommended")
        addPresetItem(to: g9Menu, preset: "g9-57-4800x1350", title: "4800×1350 (1.6x)")
        addPresetItem(to: g9Menu, preset: "g9-57-4389x1234", title: "4389×1234 (1.75x)")
        addPresetItem(to: g9Menu, preset: "g9-57-3840x1080", title: "3840×1080 (2.0x) - Larger Text")

        let g9Item = NSMenuItem(title: "Samsung G9 57\"", action: nil, keyEquivalent: "")
        g9Item.submenu = g9Menu
        menu.addItem(g9Item)

        // Samsung G9 49" (5120x1440) presets
        let g49Menu = NSMenu()
        addPresetItem(to: g49Menu, preset: "g9-49-4096x1152", title: "4096×1152 (1.25x) - More Space")
        addPresetItem(to: g49Menu, preset: "g9-49-3938x1108", title: "3938×1108 (1.3x)")
        addPresetItem(to: g49Menu, preset: "g9-49-3840x1080", title: "3840×1080 (1.33x) ★ Recommended")
        addPresetItem(to: g49Menu, preset: "g9-49-3413x960", title: "3413×960 (1.5x)")
        addPresetItem(to: g49Menu, preset: "g9-49-2926x823", title: "2926×823 (1.75x)")
        addPresetItem(to: g49Menu, preset: "g9-49-2560x720", title: "2560×720 (2.0x) - Larger Text")

        let g49Item = NSMenuItem(title: "Samsung G9 49\"", action: nil, keyEquivalent: "")
        g49Item.submenu = g49Menu
        menu.addItem(g49Item)

        // 34" Ultrawide (3440x1440) presets
        let uwMenu = NSMenu()
        addPresetItem(to: uwMenu, preset: "uw34-2752x1152", title: "2752×1152 (1.25x) - More Space")
        addPresetItem(to: uwMenu, preset: "uw34-2646x1108", title: "2646×1108 (1.3x)")
        addPresetItem(to: uwMenu, preset: "uw34-2293x960", title: "2293×960 (1.5x) ★ Recommended")
        addPresetItem(to: uwMenu, preset: "uw34-1966x823", title: "1966×823 (1.75x)")
        addPresetItem(to: uwMenu, preset: "uw34-1720x720", title: "1720×720 (2.0x) - Larger Text")

        let uwItem = NSMenuItem(title: "34\" Ultrawide (3440×1440)", action: nil, keyEquivalent: "")
        uwItem.submenu = uwMenu
        menu.addItem(uwItem)

        // 38" Ultrawide (3840x1600) presets
        let uw38Menu = NSMenu()
        addPresetItem(to: uw38Menu, preset: "uw38-3072x1280", title: "3072×1280 (1.25x) - More Space")
        addPresetItem(to: uw38Menu, preset: "uw38-2954x1231", title: "2954×1231 (1.3x)")
        addPresetItem(to: uw38Menu, preset: "uw38-2560x1067", title: "2560×1067 (1.5x) ★ Recommended")
        addPresetItem(to: uw38Menu, preset: "uw38-2194x914", title: "2194×914 (1.75x)")
        addPresetItem(to: uw38Menu, preset: "uw38-1920x800", title: "1920×800 (2.0x) - Larger Text")

        let uw38Item = NSMenuItem(title: "38\" Ultrawide (3840×1600)", action: nil, keyEquivalent: "")
        uw38Item.submenu = uw38Menu
        menu.addItem(uw38Item)

        // 4K (3840x2160) presets
        let k4Menu = NSMenu()
        addPresetItem(to: k4Menu, preset: "4k-3072x1728", title: "3072×1728 (1.25x) - More Space")
        addPresetItem(to: k4Menu, preset: "4k-2954x1662", title: "2954×1662 (1.3x)")
        addPresetItem(to: k4Menu, preset: "4k-2560x1440", title: "2560×1440 (1.5x) ★ Recommended")
        addPresetItem(to: k4Menu, preset: "4k-2194x1234", title: "2194×1234 (1.75x)")
        addPresetItem(to: k4Menu, preset: "4k-1920x1080", title: "1920×1080 (2.0x) - Larger Text")

        let k4Item = NSMenuItem(title: "4K Displays (3840×2160)", action: nil, keyEquivalent: "")
        k4Item.submenu = k4Menu
        menu.addItem(k4Item)

        menu.addItem(NSMenuItem.separator())

        // Settings submenu
        let settingsMenu = NSMenu()

        let autoApplyItem = NSMenuItem(title: "Auto-Apply on Reconnect", action: #selector(toggleAutoApply(_:)), keyEquivalent: "")
        autoApplyItem.target = self
        autoApplyItem.state = UserDefaults.standard.bool(forKey: kAutoApplyOnConnectKey) ? .on : .off
        settingsMenu.addItem(autoApplyItem)

        let autoRestoreItem = NSMenuItem(title: "Auto-Restore After Crash", action: #selector(toggleAutoRestore(_:)), keyEquivalent: "")
        autoRestoreItem.target = self
        autoRestoreItem.state = UserDefaults.standard.bool(forKey: kAutoRestoreKey) ? .on : .off
        settingsMenu.addItem(autoRestoreItem)

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About G9 Helper", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc func toggleAutoApply(_ sender: NSMenuItem) {
        let current = UserDefaults.standard.bool(forKey: kAutoApplyOnConnectKey)
        UserDefaults.standard.set(!current, forKey: kAutoApplyOnConnectKey)
        debugLog("Auto-apply on reconnect: \(!current)")
        rebuildMenu()
    }

    @objc func toggleAutoRestore(_ sender: NSMenuItem) {
        let current = UserDefaults.standard.bool(forKey: kAutoRestoreKey)
        UserDefaults.standard.set(!current, forKey: kAutoRestoreKey)
        debugLog("Auto-restore after crash: \(!current)")
        rebuildMenu()
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "G9 Helper"
        alert.informativeText = """
            Version 1.0.4

            Unlock crisp HiDPI scaling on Samsung Odyssey G9 and other large monitors.

            This is free software. If you find it useful, consider buying me a coffee!

            Created by AL in Dallas
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Buy Me a Coffee ☕")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let url = URL(string: donationURL) {
                NSWorkspace.shared.open(url)
            }
        }
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

        guard let config = presetConfigs[presetName] else {
            debugLog("ERROR: Unknown preset \(presetName)")
            return
        }

        // Mark that we're setting up (don't trigger cleanup during setup)
        isSettingUp = true

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

        // Save the preset for crash recovery
        saveCurrentPreset(presetName)

        // Schedule creation after a delay using DispatchQueue instead of Timer
        // This gives us better control over autorelease pool behavior
        debugLog("Scheduling display creation in 1.5 seconds...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            autoreleasepool {
                self?.createVirtualDisplayAsync(config: config)
            }
        }
    }

    // Disable HiDPI when user explicitly requests it - clears preset (no auto-restore)
    func disableHiDPISync() {
        debugLog("Disabling HiDPI (user action) - currentVirtualID: \(currentVirtualID)")

        let manager = VirtualDisplayManager.shared()

        // Reset ALL mirroring to ensure clean state
        manager.resetAllMirroring()

        // Destroy our virtual display
        manager.destroyAllVirtualDisplays()

        currentVirtualID = 0
        targetExternalDisplayID = 0
        isActive = false
        currentPresetName = ""

        // Clear saved preset - user explicitly disabled, don't auto-restore
        clearSavedPreset()

        // Also clear the disconnected flag since user is taking explicit action
        wasDisconnected = false
        UserDefaults.standard.set(false, forKey: kWasDisconnectedKey)

        debugLog("HiDPI disabled (preset cleared)")
    }

    func createVirtualDisplayAsync(config: PresetConfig) {
        debugLog("Creating virtual display: \(config.width)x\(config.height)")

        StatusWindowController.shared.updateStatus("Detecting external display...")

        guard let externalID = findExternalDisplay() else {
            debugLog("ERROR: No external display found")
            isSettingUp = false  // Clear setup flag so reconnect detection works
            StatusWindowController.shared.updateStatus("No external display found")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                StatusWindowController.shared.hide()
            }
            rebuildMenu()
            return
        }
        debugLog("Using external display: \(externalID)")

        StatusWindowController.shared.updateStatus("Creating virtual display...")

        // Create virtual display
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
            isSettingUp = false  // Clear setup flag so reconnect detection works
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

        // Wait for display to initialize
        debugLog("Scheduling mirror in 3 seconds...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            autoreleasepool {
                self?.performMirror(virtualID: virtualID, externalID: externalID, config: config)
            }
        }
    }

    func performMirror(virtualID: CGDirectDisplayID, externalID: CGDirectDisplayID, config: PresetConfig) {
        debugLog("Setting up mirror: \(virtualID) -> \(externalID)")
        let manager = VirtualDisplayManager.shared()
        let success = manager.mirrorDisplay(virtualID, toDisplay: externalID)
        debugLog("Mirror result: \(success)")

        // Setup is complete (whether successful or not)
        isSettingUp = false

        if success {
            isActive = true
            currentPresetName = "\(config.logicalWidth)x\(config.logicalHeight)"
            targetExternalDisplayID = externalID  // Track target for disconnect detection
            StatusWindowController.shared.updateStatus("HiDPI enabled: \(config.logicalWidth)x\(config.logicalHeight)")
            debugLog(">>> HiDPI setup complete, monitoring for disconnect")
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
            let vendorID = CGDisplayVendorNumber(displayID)
            let isVirtualDisplay = vendorID == 0x1234  // Our virtual displays use vendor 0x1234
            let size = CGDisplayScreenSize(displayID)

            debugLog("  Display \(displayID): builtin=\(isBuiltin), vendor=\(vendorID), isVirtual=\(isVirtualDisplay), size=\(size.width)x\(size.height)mm")

            // Skip builtin displays and ANY virtual displays (by vendor ID)
            if !isBuiltin && !isVirtualDisplay {
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
        StatusWindowController.shared.show(message: "Disabling HiDPI...")
        disableHiDPISync()
        rebuildMenu()

        StatusWindowController.shared.updateStatus("HiDPI disabled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            StatusWindowController.shared.hide()
        }
    }

    @objc func quitApp() {
        debugLog("Quit requested by user")

        // Move windows before quitting
        if isActive {
            moveAllWindowsToMainDisplay()
        }

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
    // Samsung G9 57" (7680x2160 native) - Fractional scaling options
    // Scale factor = native / logical, e.g., 7680/5120 = 1.5x
    "g9-57-6144x1728": PresetConfig(name: "G9-57-6144", width: 12288, height: 3456, logicalWidth: 6144, logicalHeight: 1728, ppi: 140, hiDPI: true),  // 1.25x
    "g9-57-5908x1662": PresetConfig(name: "G9-57-5908", width: 11816, height: 3324, logicalWidth: 5908, logicalHeight: 1662, ppi: 140, hiDPI: true),  // 1.3x
    "g9-57-5120x1440": PresetConfig(name: "G9-57-5120", width: 10240, height: 2880, logicalWidth: 5120, logicalHeight: 1440, ppi: 140, hiDPI: true),  // 1.5x (recommended)
    "g9-57-4800x1350": PresetConfig(name: "G9-57-4800", width: 9600, height: 2700, logicalWidth: 4800, logicalHeight: 1350, ppi: 140, hiDPI: true),   // 1.6x
    "g9-57-4389x1234": PresetConfig(name: "G9-57-4389", width: 8778, height: 2468, logicalWidth: 4389, logicalHeight: 1234, ppi: 140, hiDPI: true),   // 1.75x
    "g9-57-3840x1080": PresetConfig(name: "G9-57-3840", width: 7680, height: 2160, logicalWidth: 3840, logicalHeight: 1080, ppi: 140, hiDPI: true),   // 2.0x (native HiDPI)

    // Samsung G9 49" (5120x1440 native) - Fractional scaling options
    "g9-49-4096x1152": PresetConfig(name: "G9-49-4096", width: 8192, height: 2304, logicalWidth: 4096, logicalHeight: 1152, ppi: 109, hiDPI: true),   // 1.25x
    "g9-49-3938x1108": PresetConfig(name: "G9-49-3938", width: 7876, height: 2216, logicalWidth: 3938, logicalHeight: 1108, ppi: 109, hiDPI: true),   // 1.3x
    "g9-49-3840x1080": PresetConfig(name: "G9-49-3840", width: 7680, height: 2160, logicalWidth: 3840, logicalHeight: 1080, ppi: 109, hiDPI: true),   // 1.33x
    "g9-49-3413x960": PresetConfig(name: "G9-49-3413", width: 6826, height: 1920, logicalWidth: 3413, logicalHeight: 960, ppi: 109, hiDPI: true),     // 1.5x (recommended)
    "g9-49-2926x823": PresetConfig(name: "G9-49-2926", width: 5852, height: 1646, logicalWidth: 2926, logicalHeight: 823, ppi: 109, hiDPI: true),     // 1.75x
    "g9-49-2560x720": PresetConfig(name: "G9-49-2560", width: 5120, height: 1440, logicalWidth: 2560, logicalHeight: 720, ppi: 109, hiDPI: true),     // 2.0x (native HiDPI)

    // 34" Ultrawide (3440x1440 native) - Fractional scaling options
    "uw34-2752x1152": PresetConfig(name: "UW34-2752", width: 5504, height: 2304, logicalWidth: 2752, logicalHeight: 1152, ppi: 110, hiDPI: true),     // 1.25x
    "uw34-2646x1108": PresetConfig(name: "UW34-2646", width: 5292, height: 2216, logicalWidth: 2646, logicalHeight: 1108, ppi: 110, hiDPI: true),     // 1.3x
    "uw34-2293x960": PresetConfig(name: "UW34-2293", width: 4586, height: 1920, logicalWidth: 2293, logicalHeight: 960, ppi: 110, hiDPI: true),       // 1.5x (recommended)
    "uw34-1966x823": PresetConfig(name: "UW34-1966", width: 3932, height: 1646, logicalWidth: 1966, logicalHeight: 823, ppi: 110, hiDPI: true),       // 1.75x
    "uw34-1720x720": PresetConfig(name: "UW34-1720", width: 3440, height: 1440, logicalWidth: 1720, logicalHeight: 720, ppi: 110, hiDPI: true),       // 2.0x (native HiDPI)

    // 38" Ultrawide (3840x1600 native) - Fractional scaling options
    "uw38-3072x1280": PresetConfig(name: "UW38-3072", width: 6144, height: 2560, logicalWidth: 3072, logicalHeight: 1280, ppi: 110, hiDPI: true),     // 1.25x
    "uw38-2954x1231": PresetConfig(name: "UW38-2954", width: 5908, height: 2462, logicalWidth: 2954, logicalHeight: 1231, ppi: 110, hiDPI: true),     // 1.3x
    "uw38-2560x1067": PresetConfig(name: "UW38-2560", width: 5120, height: 2134, logicalWidth: 2560, logicalHeight: 1067, ppi: 110, hiDPI: true),     // 1.5x (recommended)
    "uw38-2194x914": PresetConfig(name: "UW38-2194", width: 4388, height: 1828, logicalWidth: 2194, logicalHeight: 914, ppi: 110, hiDPI: true),       // 1.75x
    "uw38-1920x800": PresetConfig(name: "UW38-1920", width: 3840, height: 1600, logicalWidth: 1920, logicalHeight: 800, ppi: 110, hiDPI: true),       // 2.0x (native HiDPI)

    // 4K (3840x2160 native) - Fractional scaling options
    "4k-3072x1728": PresetConfig(name: "4K-3072", width: 6144, height: 3456, logicalWidth: 3072, logicalHeight: 1728, ppi: 163, hiDPI: true),         // 1.25x
    "4k-2954x1662": PresetConfig(name: "4K-2954", width: 5908, height: 3324, logicalWidth: 2954, logicalHeight: 1662, ppi: 163, hiDPI: true),         // 1.3x
    "4k-2560x1440": PresetConfig(name: "4K-2560", width: 5120, height: 2880, logicalWidth: 2560, logicalHeight: 1440, ppi: 163, hiDPI: true),         // 1.5x (recommended)
    "4k-2194x1234": PresetConfig(name: "4K-2194", width: 4388, height: 2468, logicalWidth: 2194, logicalHeight: 1234, ppi: 163, hiDPI: true),         // 1.75x
    "4k-1920x1080": PresetConfig(name: "4K-1920", width: 3840, height: 2160, logicalWidth: 1920, logicalHeight: 1080, ppi: 163, hiDPI: true),         // 2.0x (native HiDPI)
]
