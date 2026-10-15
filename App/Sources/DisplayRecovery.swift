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
