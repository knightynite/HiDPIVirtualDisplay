import Foundation

/// Physical identity only: CoreGraphics runtime display IDs never enter saved data.
struct PhysicalMonitorIdentity: Codable, Equatable {
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32

    var isKnown: Bool { vendor != 0 && vendor != 0x756E6B6E && vendor != 0x1234 && (serial != 0 || model != 0) }

    func matches(_ other: Self) -> Bool {
        guard isKnown, other.isKnown, vendor == other.vendor else { return false }
        // Product ID can change with negotiated modes; a reported serial wins.
        if serial != 0 { return other.serial != 0 && serial == other.serial }
        return model != 0 && model == other.model
    }
}


/// The manual selection boundary persists a known target before any display
/// creation or process restart. Automatic recovery can only reuse that binding.
/// Injected storage keeps the same boundary testable without user preferences.
struct PhysicalMonitorBinding {
    let load: () -> PhysicalMonitorIdentity?
    let persist: (PhysicalMonitorIdentity) -> Void

    var savedIdentity: PhysicalMonitorIdentity? {
        guard let identity = load(), identity.isKnown else { return nil }
        return identity
    }

    @discardableResult
    func beginManualSetup(candidate: PhysicalMonitorIdentity?, start: (PhysicalMonitorIdentity) -> Void) -> Bool {
        guard let candidate = candidate, candidate.isKnown else { return false }
        persist(candidate)
        start(candidate)
        return true
    }

    func acceptsAutomatic(_ candidate: PhysicalMonitorIdentity?) -> Bool {
        guard let saved = savedIdentity, let candidate = candidate else { return false }
        return saved.matches(candidate)
    }
}

struct DisplayPoint: Codable, Equatable {
    let x: Double
    let y: Double
    static let zero = DisplayPoint(x: 0, y: 0)
    var isValid: Bool {
        [x, y].allSatisfy { $0.isFinite && $0.rounded() == $0 && $0 >= Double(Int32.min) && $0 <= Double(Int32.max) }
    }
}

struct DisplaySize: Codable, Equatable {
    let width: Double
    let height: Double
    var isValid: Bool { width.isFinite && height.isFinite && width > 0 && height > 0 && width <= Double(Int32.max) && height <= Double(Int32.max) }
}

/// Runtime-only topology. Only independent, active desktops belong in this list.
struct DisplayDesktop: Equatable {
    let id: UInt32
    let builtInUUID: String?
    let origin: DisplayPoint
    let size: DisplaySize
}

struct DisplayLayoutSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let physicalMonitor: PhysicalMonitorIdentity
    let builtInUUID: String
    let externalOffset: DisplayPoint
    let builtInSize: DisplaySize
    let externalSize: DisplaySize
    let externalIsMain: Bool

    var isValid: Bool {
        schemaVersion == 1 && physicalMonitor.isKnown && !builtInUUID.isEmpty && externalOffset.isValid && builtInSize.isValid && externalSize.isValid
    }

    static func decode(_ data: Data) -> Self? {
        guard let snapshot = try? JSONDecoder().decode(Self.self, from: data), snapshot.isValid else { return nil }
        return snapshot
    }
}

enum DisplayLayoutError: String, Error {
    case unknownIdentity = "Monitor identity is unavailable or does not match."
    case missingBuiltIn = "Built-in display is missing or changed (clamshell is not supported)."
    case missingMirrorMaster = "The active mirror desktop is not ready."
    case extraDesktops = "Arrangement requires exactly the built-in and mirror desktops; other desktops are left untouched."
    case dimensionsChanged = "Logical display sizes changed. Arrange displays and save again."
    case invalidGeometry = "Saved or current geometry is invalid."
}

struct DisplayLayoutPlan: Equatable {
    let builtInID: UInt32
    let mirrorMasterID: UInt32
    let builtInOrigin: DisplayPoint
    let externalOrigin: DisplayPoint
}

enum DisplayLayoutPlanner {
    static func capture(physical: PhysicalMonitorIdentity, bound: PhysicalMonitorIdentity,
                        desktops: [DisplayDesktop], mirrorMasterID: UInt32, mainID: UInt32) throws -> DisplayLayoutSnapshot {
        guard bound.matches(physical) else { throw DisplayLayoutError.unknownIdentity }
        guard let builtIn = desktops.first(where: { $0.builtInUUID != nil }) else { throw DisplayLayoutError.missingBuiltIn }
        guard let external = desktops.first(where: { $0.id == mirrorMasterID }), external.id != builtIn.id else { throw DisplayLayoutError.missingMirrorMaster }
        guard desktops.count == 2, Set(desktops.map(\.id)).count == 2 else { throw DisplayLayoutError.extraDesktops }
        guard builtIn.origin.isValid, external.origin.isValid, mainID == builtIn.id || mainID == external.id else { throw DisplayLayoutError.invalidGeometry }
        let snapshot = DisplayLayoutSnapshot(schemaVersion: 1, physicalMonitor: physical,
            builtInUUID: builtIn.builtInUUID!,
            externalOffset: DisplayPoint(x: external.origin.x - builtIn.origin.x, y: external.origin.y - builtIn.origin.y),
            builtInSize: builtIn.size, externalSize: external.size, externalIsMain: mainID == external.id)
        guard snapshot.isValid else { throw DisplayLayoutError.invalidGeometry }
        return snapshot
    }

    static func restore(_ saved: DisplayLayoutSnapshot, physical: PhysicalMonitorIdentity?,
                        desktops: [DisplayDesktop], mirrorMasterID: UInt32,
                        keepExternalMain: Bool) throws -> DisplayLayoutPlan {
        guard saved.isValid else { throw DisplayLayoutError.invalidGeometry }
        guard let physical = physical, saved.physicalMonitor.matches(physical) else { throw DisplayLayoutError.unknownIdentity }
        guard let builtIn = desktops.first(where: { $0.builtInUUID == saved.builtInUUID }) else { throw DisplayLayoutError.missingBuiltIn }
        guard let external = desktops.first(where: { $0.id == mirrorMasterID }), external.id != builtIn.id else { throw DisplayLayoutError.missingMirrorMaster }
        guard desktops.count == 2, Set(desktops.map(\.id)).count == 2 else { throw DisplayLayoutError.extraDesktops }
        guard builtIn.size == saved.builtInSize, external.size == saved.externalSize else { throw DisplayLayoutError.dimensionsChanged }
        guard builtIn.origin.isValid, external.origin.isValid else { throw DisplayLayoutError.invalidGeometry }
        let externalMain = keepExternalMain || saved.externalIsMain
        let builtinOrigin = externalMain ? DisplayPoint(x: -saved.externalOffset.x, y: -saved.externalOffset.y) : .zero
        let externalOrigin = externalMain ? .zero : saved.externalOffset
        guard builtinOrigin.isValid, externalOrigin.isValid else { throw DisplayLayoutError.invalidGeometry }
        return DisplayLayoutPlan(builtInID: builtIn.id, mirrorMasterID: external.id,
                                 builtInOrigin: builtinOrigin, externalOrigin: externalOrigin)
    }
}

enum DisplayRecoveryReason: String {
    case reconnect, crash, active, manual
    func isAllowed(autoApply: Bool, autoRestore: Bool) -> Bool {
        switch self {
        case .reconnect: return autoApply
        case .crash: return autoRestore
        case .active, .manual: return true // Explicit restart or maintenance of a session explicitly enabled by the user.
        }
    }
}

struct DisplayRecoveryState {
    var waiting: Bool
    var failures: Int
    let limit: Int
    var canRetry: Bool { waiting && failures < limit }
    mutating func missingMonitor() { waiting = true }
    mutating func failed() { waiting = true; failures = min(failures + 1, limit) }
    mutating func succeeded() { waiting = false; failures = 0 }
}

enum DisplayRecoveryPolicy {
    enum Action { case wait, preserve, reattach, rebuild }
    static func wakeReason(active: Bool, pending: DisplayRecoveryReason?) -> DisplayRecoveryReason? {
        active ? .active : pending
    }
    static func action(active: Bool, monitorMatches: Bool, virtualOnline: Bool, mirrorIntact: Bool,
                       failures: Int = 0, limit: Int = 3) -> Action {
        guard active, monitorMatches else { return .wait }
        if virtualOnline && mirrorIntact { return .preserve }
        guard failures < limit else { return .wait }
        return virtualOnline ? .reattach : .rebuild
    }
    // Display count is intentionally irrelevant: mirror relationships can break without a count change.
    static func shouldAssess(active: Bool, waiting: Bool, settingUp: Bool, restarting: Bool, asleep: Bool) -> Bool {
        (active || waiting) && !settingUp && !restarting && !asleep
    }
    static func workIsCurrent(generation: Int, currentGeneration: Int, active: Bool, restarting: Bool, asleep: Bool, monitorMatches: Bool) -> Bool {
        generation == currentGeneration && active && !restarting && !asleep && monitorMatches
    }
}

/// Shared cancellation state: superseding setup also releases the disconnect
/// debounce latch, so a cancelled confirmation cannot suppress future checks.
struct DisplayRecoveryWorkState {
    private(set) var generation = 0
    var disconnectConfirmationPending = false
    mutating func supersede() {
        generation += 1
        disconnectConfirmationPending = false
    }
}
