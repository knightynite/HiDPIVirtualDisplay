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

private func expectError(_ expected: DisplayLayoutError, _ operation: () throws -> Void) throws {
    do {
        try operation()
    } catch let actual as DisplayLayoutError {
        try expect(actual == expected, "Expected \(expected), received \(actual)")
        return
    }
    throw TestFailure.assertion("Expected \(expected), operation succeeded")
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
    static let builtInSize = DisplaySize(width: 1600, height: 1000)
    static let externalSize = DisplaySize(width: 3840, height: 1080)
    static let offset = DisplayPoint(x: -960, y: -1080)

    static func desktops(builtInID: UInt32 = 1, mirrorID: UInt32 = 8,
                         builtInOrigin: DisplayPoint = .zero,
                         externalOrigin: DisplayPoint = offset,
                         uuid: String = "built-in-uuid",
                         builtInSize: DisplaySize = builtInSize,
                         externalSize: DisplaySize = externalSize) -> [DisplayDesktop] {
        [DisplayDesktop(id: builtInID, builtInUUID: uuid, origin: builtInOrigin, size: builtInSize),
         DisplayDesktop(id: mirrorID, builtInUUID: nil, origin: externalOrigin, size: externalSize)]
    }

    static func saved(externalMain: Bool = false, offset: DisplayPoint = offset,
                      schemaVersion: Int = 1, uuid: String = "built-in-uuid",
                      builtInSize: DisplaySize = builtInSize,
                      externalSize: DisplaySize = externalSize) -> DisplayLayoutSnapshot {
        DisplayLayoutSnapshot(schemaVersion: schemaVersion, physicalMonitor: monitor,
            builtInUUID: uuid, externalOffset: offset, builtInSize: builtInSize,
            externalSize: externalSize, externalIsMain: externalMain)
    }

    static func restore(_ snapshot: DisplayLayoutSnapshot = saved(),
                        physical: PhysicalMonitorIdentity? = monitor,
                        topology: [DisplayDesktop] = desktops(), mirrorID: UInt32 = 8,
                        overrideMain: Bool = false) throws -> DisplayLayoutPlan {
        try DisplayLayoutPlanner.restore(snapshot, physical: physical, desktops: topology,
            mirrorMasterID: mirrorID, keepExternalMain: overrideMain)
    }

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

        test("capture and Codable roundtrip persist physical identity and relative geometry only") {
            let snapshot = try DisplayLayoutPlanner.capture(physical: monitor, bound: monitor,
                desktops: desktops(), mirrorMasterID: 8, mainID: 1)
            let data = try JSONEncoder().encode(snapshot)
            try expect(DisplayLayoutSnapshot.decode(data) == snapshot, "Codable roundtrip changed snapshot")
            let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            try expect(Set(object.keys) == Set(["schemaVersion", "physicalMonitor", "builtInUUID", "externalOffset", "builtInSize", "externalSize", "externalIsMain"]), "Unexpected persisted fields, possibly runtime display IDs")
            let identity = object["physicalMonitor"] as! [String: Any]
            try expect(Set(identity.keys) == Set(["vendor", "model", "serial"]), "Runtime IDs entered persistent identity")
            try expect(snapshot.externalOffset == offset, "Captured offset is wrong")
        }
        test("restore resolves fresh runtime IDs after reconnect") {
            let plan = try restore(topology: desktops(builtInID: 41, mirrorID: 108,
                externalOrigin: DisplayPoint(x: 1600, y: 0)), mirrorID: 108)
            try expect(plan.builtInID == 41 && plan.mirrorMasterID == 108, "Restore used old runtime IDs")
            try expect(plan.externalOrigin == offset && plan.builtInOrigin == .zero, "Fresh topology lost saved geometry")
        }
        test("serial match survives the monitor model changing") {
            let changed = PhysicalMonitorIdentity(vendor: monitor.vendor, model: monitor.model + 1, serial: monitor.serial)
            try expect(monitor.matches(changed), "Same serial with changed model should match")
            _ = try restore(physical: changed)
        }
        test("different serial is rejected even when model matches") {
            let other = PhysicalMonitorIdentity(vendor: monitor.vendor, model: monitor.model, serial: monitor.serial + 1)
            try expect(!monitor.matches(other), "Conflicting serial was accepted")
            try expectError(.unknownIdentity) { _ = try restore(physical: other) }
        }
        test("saved serial requires a currently reported serial") {
            let unidentified = PhysicalMonitorIdentity(vendor: monitor.vendor, model: monitor.model, serial: 0)
            try expect(!monitor.matches(unidentified), "Missing serial silently fell back to model")
            try expectError(.unknownIdentity) { _ = try restore(physical: unidentified) }
        }
        test("model fallback is available only when saved serial is unavailable") {
            let noSerial = PhysicalMonitorIdentity(vendor: monitor.vendor, model: monitor.model, serial: 0)
            try expect(noSerial.matches(monitor), "Legacy model fallback did not match")
            try expect(!noSerial.matches(PhysicalMonitorIdentity(vendor: monitor.vendor, model: monitor.model + 1, serial: monitor.serial)), "Model fallback accepted a different model")
        }
        test("wrong vendor and unknown or virtual identities are rejected") {
            for vendor: UInt32 in [0, 0x756E6B6E, 0x1234, monitor.vendor + 1] {
                let other = PhysicalMonitorIdentity(vendor: vendor, model: monitor.model, serial: monitor.serial)
                try expect(!monitor.matches(other), "Invalid vendor matched")
            }
            try expectError(.unknownIdentity) { _ = try restore(physical: nil) }
            try expect(!PhysicalMonitorIdentity(vendor: monitor.vendor, model: 0, serial: 0).isKnown, "Empty identity is considered known")
        }
        test("missing or changed built-in display waits without a layout plan") {
            try expectError(.missingBuiltIn) { _ = try restore(topology: [desktops()[1]]) }
            try expectError(.missingBuiltIn) { _ = try restore(topology: desktops(uuid: "another-built-in")) }
        }
        test("missing mirror master is rejected") {
            try expectError(.missingMirrorMaster) { _ = try restore(mirrorID: 99) }
            try expectError(.missingMirrorMaster) { _ = try restore(mirrorID: 1) }
        }
        test("capture rejects missing built-in or mirror master") {
            try expectError(.missingBuiltIn) {
                _ = try DisplayLayoutPlanner.capture(physical: monitor, bound: monitor,
                    desktops: [desktops()[1]], mirrorMasterID: 8, mainID: 8)
            }
            try expectError(.missingMirrorMaster) {
                _ = try DisplayLayoutPlanner.capture(physical: monitor, bound: monitor,
                    desktops: desktops(), mirrorMasterID: 99, mainID: 1)
            }
        }
        test("logical dimension changes require a newly saved arrangement") {
            try expectError(.dimensionsChanged) {
                _ = try restore(topology: desktops(externalSize: DisplaySize(width: 3200, height: 900)))
            }
            try expectError(.dimensionsChanged) {
                _ = try restore(topology: desktops(builtInSize: DisplaySize(width: 1400, height: 900)))
            }
        }
        test("above offset and built-in primary are restored exactly") {
            let plan = try restore()
            try expect(plan.externalOrigin == DisplayPoint(x: -960, y: -1080), "Above offset was changed")
            try expect(plan.builtInOrigin == .zero, "Built-in primary moved away from origin")
        }
        test("external primary translates both displays without changing relative positions") {
            let topology = desktops(builtInOrigin: DisplayPoint(x: 960, y: 1080), externalOrigin: .zero)
            let snapshot = try DisplayLayoutPlanner.capture(physical: monitor, bound: monitor,
                desktops: topology, mirrorMasterID: 8, mainID: 8)
            try expect(snapshot.externalIsMain, "Capture lost external main display")
            let plan = try restore(snapshot)
            try expect(plan.externalOrigin == .zero, "External primary is not at origin")
            try expect(plan.builtInOrigin == DisplayPoint(x: 960, y: 1080), "Relative position changed during main-display translation")
        }
        test("Keep External as Main overrides a saved built-in primary") {
            let plan = try restore(overrideMain: true)
            try expect(plan.externalOrigin == .zero && plan.builtInOrigin == DisplayPoint(x: 960, y: 1080), "Main-display override ignored")
        }
        test("extra active desktops are never rearranged") {
            let extra = DisplayDesktop(id: 77, builtInUUID: nil, origin: DisplayPoint(x: 6000, y: 0), size: DisplaySize(width: 1920, height: 1080))
            try expectError(.extraDesktops) { _ = try restore(topology: desktops() + [extra]) }
            try expectError(.extraDesktops) {
                _ = try DisplayLayoutPlanner.capture(physical: monitor, bound: monitor,
                    desktops: desktops() + [extra], mirrorMasterID: 8, mainID: 1)
            }
        }
        test("nonfinite fractional and out-of-range coordinates are rejected") {
            for value in [Double.nan, Double.infinity, -Double.infinity, 0.5, Double(Int32.max) + 1, Double(Int32.min) - 1] {
                try expect(!DisplayPoint(x: value, y: 0).isValid, "Invalid coordinate \(value) accepted")
                try expectError(.invalidGeometry) { _ = try restore(saved(offset: DisplayPoint(x: value, y: 0))) }
                try expectError(.invalidGeometry) { _ = try restore(topology: desktops(externalOrigin: DisplayPoint(x: 0, y: value))) }
            }
        }
        test("invalid sizes and empty built-in identity invalidate saved data") {
            for size in [DisplaySize(width: .nan, height: 1080), DisplaySize(width: 3840, height: .infinity), DisplaySize(width: 0, height: 1080), DisplaySize(width: -1, height: 1080), DisplaySize(width: Double(Int32.max) + 1, height: 1080)] {
                try expect(!saved(externalSize: size).isValid, "Invalid dimensions accepted")
                try expectError(.invalidGeometry) { _ = try restore(saved(externalSize: size)) }
            }
            try expect(!saved(uuid: "").isValid, "Empty built-in identity accepted")
        }
        test("capture detects subtraction overflow and invalid main display") {
            let overflow = desktops(builtInOrigin: DisplayPoint(x: Double(Int32.min), y: 0),
                externalOrigin: DisplayPoint(x: Double(Int32.max), y: 0))
            try expectError(.invalidGeometry) {
                _ = try DisplayLayoutPlanner.capture(physical: monitor, bound: monitor,
                    desktops: overflow, mirrorMasterID: 8, mainID: 1)
            }
            try expectError(.invalidGeometry) {
                _ = try DisplayLayoutPlanner.capture(physical: monitor, bound: monitor,
                    desktops: desktops(), mirrorMasterID: 8, mainID: 99)
            }
        }
        test("primary translation detects Int32 negation overflow") {
            let snapshot = saved(externalMain: true, offset: DisplayPoint(x: Double(Int32.min), y: 0))
            try expect(snapshot.isValid, "Boundary snapshot should be valid before translation")
            try expectError(.invalidGeometry) { _ = try restore(snapshot) }
        }
        test("corrupt incomplete and unknown-schema persisted data is rejected") {
            for text in ["not JSON", "{}", "[]", "{\"schemaVersion\":1}"] {
                try expect(DisplayLayoutSnapshot.decode(Data(text.utf8)) == nil, "Corrupt data accepted")
            }
            let future = try JSONEncoder().encode(saved(schemaVersion: 2))
            try expect(DisplayLayoutSnapshot.decode(future) == nil, "Unsupported schema accepted")
            let fractional = try JSONEncoder().encode(saved(offset: DisplayPoint(x: 0.5, y: 0)))
            try expect(DisplayLayoutSnapshot.decode(fractional) == nil, "Invalid decoded geometry accepted")
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
