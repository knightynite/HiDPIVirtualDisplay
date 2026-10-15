import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case assertion(String)
    var description: String {
        switch self { case .assertion(let message): return message }
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure.assertion(message) }
}

/// Simulates retained preferences while allowing fresh production bindings.
private final class MonitorBindingStorage {
    var identity: PhysicalMonitorIdentity?
    var writes = 0

    init(_ identity: PhysicalMonitorIdentity? = nil) { self.identity = identity }

    func binding() -> PhysicalMonitorBinding {
        PhysicalMonitorBinding(load: { self.identity }, persist: {
            self.identity = $0
            self.writes += 1
        })
    }
}

@main
private struct DisplayRecoveryTests {
    // All monitor and geometry fixtures are synthetic, not captured hardware data.
    static let monitor = PhysicalMonitorIdentity(vendor: 0x4567, model: 0x1001, serial: 1)

    static func main() {
        var passed = 0
        var failed = 0
        func test(_ name: String, _ operation: () throws -> Void) {
            do {
                try operation()
                passed += 1
                print("PASS \(name)")
            } catch {
                failed += 1
                print("FAIL \(name): \(error)")
            }
        }

        test("first manual setup persists its target before an unsuccessful start") {
            let storage = MonitorBindingStorage()
            var persistedBeforeStart = false
            let started = storage.binding().beginManualSetup(candidate: monitor) { target in
                persistedBeforeStart = storage.identity == target
                // Virtual creation or mirroring can fail here, before success.
            }
            try expect(started && persistedBeforeStart, "Setup started before its physical binding was saved")
            try expect(storage.identity == monitor && storage.writes == 1, "Failed first setup lost its target")
        }
        test("retry after recreation retains the first interrupted manual binding") {
            let originalStorage = MonitorBindingStorage()
            originalStorage.binding().beginManualSetup(candidate: monitor) { _ in }
            // Only persisted identity crosses the process/store boundary.
            let recreatedStorage = MonitorBindingStorage(originalStorage.identity)
            let recreatedBinding = recreatedStorage.binding()
            try expect(recreatedBinding.acceptsAutomatic(monitor), "Interrupted setup cannot resume after recreation")
            var retryStarted = false
            recreatedBinding.beginManualSetup(candidate: monitor) { _ in
                retryStarted = recreatedStorage.identity == monitor
            }
            try expect(retryStarted, "Explicit preset retry did not retain a usable binding")
        }
        test("explicit manual setup replaces the previous physical target before restart") {
            let storage = MonitorBindingStorage(monitor)
            let replacement = PhysicalMonitorIdentity(vendor: monitor.vendor, model: monitor.model, serial: monitor.serial + 1)
            var restartSawReplacement = false
            storage.binding().beginManualSetup(candidate: replacement) { target in
                restartSawReplacement = storage.identity == target && target == replacement
            }
            let recreatedBinding = storage.binding()
            try expect(restartSawReplacement && recreatedBinding.acceptsAutomatic(replacement), "Manual target change was not persisted before restart")
            try expect(!recreatedBinding.acceptsAutomatic(monitor), "Old target still authorized automatic recovery")
        }
        test("missing or unknown manual targets never overwrite a saved binding or start setup") {
            let storage = MonitorBindingStorage(monitor)
            let unknowns: [PhysicalMonitorIdentity?] = [nil,
                PhysicalMonitorIdentity(vendor: 0, model: monitor.model, serial: monitor.serial),
                PhysicalMonitorIdentity(vendor: 0x756E6B6E, model: monitor.model, serial: monitor.serial),
                PhysicalMonitorIdentity(vendor: 0x1234, model: monitor.model, serial: monitor.serial),
                PhysicalMonitorIdentity(vendor: monitor.vendor, model: 0, serial: 0)]
            var starts = 0
            for candidate in unknowns {
                try expect(!storage.binding().beginManualSetup(candidate: candidate) { _ in starts += 1 }, "Unknown target started setup")
            }
            try expect(storage.identity == monitor && storage.writes == 0 && starts == 0, "Invalid target changed an existing binding")
            let empty = MonitorBindingStorage()
            try expect(!empty.binding().beginManualSetup(candidate: nil) { _ in starts += 1 }, "Missing first target started setup")
            try expect(empty.identity == nil && empty.writes == 0, "Missing first target created a binding")
        }
        test("automatic recovery rejects an arbitrary monitor and never changes the binding") {
            let storage = MonitorBindingStorage(monitor)
            let mismatch = PhysicalMonitorIdentity(vendor: monitor.vendor, model: monitor.model, serial: monitor.serial + 1)
            let missingSerial = PhysicalMonitorIdentity(vendor: monitor.vendor, model: monitor.model, serial: 0)
            try expect(!storage.binding().acceptsAutomatic(mismatch), "Automatic recovery selected a different serial")
            try expect(!storage.binding().acceptsAutomatic(missingSerial), "Automatic recovery downgraded a saved serial to model matching")
            try expect(!storage.binding().acceptsAutomatic(nil), "Automatic recovery accepted a missing candidate")
            try expect(!MonitorBindingStorage().binding().acceptsAutomatic(monitor), "Automatic recovery created an initial binding")
            try expect(storage.identity == monitor && storage.writes == 0, "Automatic recovery rewrote manual intent")
        }
        test("stored binding uses serial-first matching and validates loaded identities") {
            let storage = MonitorBindingStorage(monitor)
            let modeChanged = PhysicalMonitorIdentity(vendor: monitor.vendor, model: monitor.model + 1, serial: monitor.serial)
            try expect(storage.binding().acceptsAutomatic(modeChanged), "Stored serial did not survive a negotiated model change")
            let withoutSerial = PhysicalMonitorIdentity(vendor: monitor.vendor, model: monitor.model, serial: 0)
            try expect(MonitorBindingStorage(withoutSerial).binding().acceptsAutomatic(monitor), "No-serial binding lost model fallback")
            let unknown = PhysicalMonitorIdentity(vendor: 0, model: monitor.model, serial: monitor.serial)
            try expect(MonitorBindingStorage(unknown).binding().savedIdentity == nil, "Unknown stored identity authorized recovery")
        }

        test("a disappeared monitor preserves pending recovery") {
            var state = DisplayRecoveryState(waiting: false, failures: 1, limit: 3)
            state.missingMonitor()
            try expect(state.waiting && state.failures == 1 && state.canRetry, "Interrupted recovery lost its pending state or failure history")
            try expect(DisplayRecoveryPolicy.action(active: true, monitorMatches: false, virtualOnline: true, mirrorIntact: false) == .wait, "Missing monitor should wait")
        }
        test("create and mirror failures share one bounded retry budget") {
            var state = DisplayRecoveryState(waiting: true, failures: 0, limit: 3)
            state.failed() // Virtual-display creation failed.
            try expect(state.canRetry && state.failures == 1, "Creation failure not counted")
            state.missingMonitor() // A transient detach must not reset the budget.
            state.failed() // Mirroring failed on the next attempt.
            try expect(state.canRetry && state.failures == 2, "Mirror failure did not share the budget")
            state.failed()
            try expect(!state.canRetry && state.failures == 3, "Retry budget is not bounded")
            state.failed()
            try expect(state.failures == 3 && !state.canRetry, "Failures exceeded the retry limit")
            state.succeeded()
            try expect(!state.waiting && state.failures == 0, "Success did not clear recovery state")
        }
        test("recovery policy preserves an intact mirror and reattaches a broken mirror") {
            // Topology cardinality is unchanged; mirror relationship alone drives this decision.
            try expect(DisplayRecoveryPolicy.action(active: true, monitorMatches: true, virtualOnline: true, mirrorIntact: true) == .preserve, "Healthy mirror should survive untouched")
            try expect(DisplayRecoveryPolicy.action(active: true, monitorMatches: true, virtualOnline: true, mirrorIntact: false) == .reattach, "Broken mirror was skipped because display count is unchanged")
            try expect(DisplayRecoveryPolicy.action(active: true, monitorMatches: true, virtualOnline: false, mirrorIntact: false) == .rebuild, "Missing virtual display should rebuild")
        }
        test("recovery honors independent reconnect and crash settings") {
            try expect(!DisplayRecoveryReason.reconnect.isAllowed(autoApply: false, autoRestore: true), "Reconnect ignored its setting")
            try expect(DisplayRecoveryReason.reconnect.isAllowed(autoApply: true, autoRestore: false), "Reconnect used crash setting")
            try expect(!DisplayRecoveryReason.crash.isAllowed(autoApply: true, autoRestore: false), "Crash ignored its setting")
            try expect(DisplayRecoveryReason.crash.isAllowed(autoApply: false, autoRestore: true), "Crash used reconnect setting")
            try expect(DisplayRecoveryReason.active.isAllowed(autoApply: false, autoRestore: false), "Active session maintenance unexpectedly disabled")
        }
        test("periodic checks assess active or waiting sessions only while available") {
            try expect(DisplayRecoveryPolicy.shouldAssess(active: true, waiting: false, settingUp: false, restarting: false, asleep: false), "Active mirror maintenance skipped")
            try expect(DisplayRecoveryPolicy.shouldAssess(active: false, waiting: true, settingUp: false, restarting: false, asleep: false), "Pending recovery skipped")
            try expect(!DisplayRecoveryPolicy.shouldAssess(active: false, waiting: false, settingUp: false, restarting: false, asleep: false), "Disabled idle session was assessed")
            try expect(!DisplayRecoveryPolicy.shouldAssess(active: true, waiting: true, settingUp: true, restarting: false, asleep: false), "Setup should suppress concurrent assessment")
            try expect(!DisplayRecoveryPolicy.shouldAssess(active: true, waiting: true, settingUp: false, restarting: true, asleep: false), "Restart should suppress assessment")
            try expect(!DisplayRecoveryPolicy.shouldAssess(active: true, waiting: true, settingUp: false, restarting: false, asleep: true), "Sleep should defer assessment")
        }
        test("stale generations disable sleep restart and changed monitor cancel delayed work") {
            try expect(DisplayRecoveryPolicy.workIsCurrent(generation: 9, currentGeneration: 9, active: true, restarting: false, asleep: false, monitorMatches: true), "Current work was cancelled")
            try expect(!DisplayRecoveryPolicy.workIsCurrent(generation: 8, currentGeneration: 9, active: true, restarting: false, asleep: false, monitorMatches: true), "Stale generation was accepted")
            try expect(!DisplayRecoveryPolicy.workIsCurrent(generation: 9, currentGeneration: 9, active: false, restarting: false, asleep: false, monitorMatches: true), "Disabled session accepted work")
            try expect(!DisplayRecoveryPolicy.workIsCurrent(generation: 9, currentGeneration: 9, active: true, restarting: true, asleep: false, monitorMatches: true), "Restarting session accepted work")
            try expect(!DisplayRecoveryPolicy.workIsCurrent(generation: 9, currentGeneration: 9, active: true, restarting: false, asleep: true, monitorMatches: true), "Sleeping session accepted work")
            try expect(!DisplayRecoveryPolicy.workIsCurrent(generation: 9, currentGeneration: 9, active: true, restarting: false, asleep: false, monitorMatches: false), "Changed monitor accepted work")
        }

        test("superseding setup releases disconnect debounce and invalidates disabled work") {
            var work = DisplayRecoveryWorkState()
            work.disconnectConfirmationPending = true
            let oldGeneration = work.generation
            work.supersede()
            try expect(!work.disconnectConfirmationPending && work.generation == oldGeneration + 1, "Superseded confirmation left its latch set")
            work.disconnectConfirmationPending = true
            try expect(work.disconnectConfirmationPending, "New confirmation could not be scheduled")
            work.supersede() // Explicit Disable uses the same cancellation state.
            try expect(!work.disconnectConfirmationPending, "Disable left confirmation pending")
            try expect(!DisplayRecoveryPolicy.workIsCurrent(generation: oldGeneration, currentGeneration: work.generation,
                active: false, restarting: false, asleep: false, monitorMatches: true), "Disable accepted obsolete work")
        }
        test("inactive wake preserves pending policy and never creates active intent") {
            try expect(DisplayRecoveryPolicy.wakeReason(active: false, pending: nil) == nil, "Inactive idle wake enabled a session")
            let reason = DisplayRecoveryPolicy.wakeReason(active: false, pending: .reconnect)
            try expect(reason == .reconnect && !reason!.isAllowed(autoApply: false, autoRestore: true), "Wake bypassed reconnect policy")
            try expect(DisplayRecoveryPolicy.wakeReason(active: false, pending: .crash) == .crash, "Wake replaced crash policy")
            try expect(DisplayRecoveryPolicy.wakeReason(active: true, pending: nil) == .active, "Active wake lost maintenance intent")
        }
        test("explicit manual restart works independently of automatic settings") {
            try expect(DisplayRecoveryReason.manual.isAllowed(autoApply: false, autoRestore: false), "Manual preset restart incorrectly used automatic settings")
            try expect(DisplayRecoveryPolicy.wakeReason(active: false, pending: .manual) == .manual, "Wake lost explicit restart intent")
        }

        test("retry limit gates reattach and rebuild while recognizing spontaneous success") {
            try expect(DisplayRecoveryPolicy.action(active: true, monitorMatches: true, virtualOnline: true,
                mirrorIntact: false, failures: 3, limit: 3) == .wait, "Exhausted budget still reattaches")
            try expect(DisplayRecoveryPolicy.action(active: true, monitorMatches: true, virtualOnline: false,
                mirrorIntact: false, failures: 3, limit: 3) == .wait, "Exhausted budget still rebuilds")
            try expect(DisplayRecoveryPolicy.action(active: true, monitorMatches: true, virtualOnline: true,
                mirrorIntact: true, failures: 3, limit: 3) == .preserve, "Spontaneously healed mirror was ignored")
            var state = DisplayRecoveryState(waiting: true, failures: 3, limit: 3)
            state.succeeded() // All three AppDelegate success paths share this transition.
            try expect(!state.waiting && state.failures == 0, "Healthy/reattach success did not clear previous pending budget")
        }

        print("\(passed) passed, \(failed) failed")
        if failed != 0 { exit(1) }
    }
}
