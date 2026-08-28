import Foundation
import os
import TankbookCore

/// The app's one Low Power Mode seam (P6.8, docs/SYNC.md -> Low Power Mode).
/// Owns the single injected `PowerStateProvider` and the single `LowPowerResumer`
/// built over it, and hands both to every consumer so the policy is consulted by
/// the same state everywhere: the sync coordinator (background-cycle deferral),
/// the blob gate inside the engine, the rate store's refresh, and the Settings
/// status surface.
///
/// The power state is **always injected, never `ProcessInfo` read at a call
/// site** (docs/SYNC.md -> "The power state is an injected value"): the only
/// place `ProcessInfo.processInfo.isLowPowerModeEnabled` appears is inside
/// `ProcessInfoPowerState` in core. The DEBUG/test `-forceLowPower` launch
/// argument swaps in a mutable double so UI tests can render and toggle the
/// state a real device decides - the same hook pattern as the `-seed*` flags.
@MainActor
final class AppPower {
    /// The state the whole app consults. A test launch can force it on; a real
    /// launch uses `ProcessInfoPowerState`, which reads the device fresh on every
    /// query so the deferral decision tracks the mode while foregrounded.
    let powerState: any PowerStateProvider

    /// Drains work the mode deferred the moment the mode ends - resume on the
    /// state change, not at next launch (docs/SYNC.md). Started once here.
    let resumer: LowPowerResumer

    /// The DEBUG/test double when `-forceLowPower` was passed, kept so a test
    /// can end the mode mid-run (which posts the power-state-change notification
    /// the resumer and the surface both observe). Nil in production.
    #if DEBUG
    private let testState: MutablePowerState?
    #endif

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-forceLowPower") {
            let mutable = MutablePowerState(lowPower: true)
            testState = mutable
            powerState = mutable
        } else {
            testState = nil
            powerState = ProcessInfoPowerState()
        }
        #else
        powerState = ProcessInfoPowerState()
        #endif
        resumer = LowPowerResumer(powerState: powerState)
        Task { await resumer.start() }
        #if DEBUG
        scheduleAutoEndIfRequested()
        #endif
    }

    #if DEBUG
    /// `-endLowPowerAfter <seconds>` flips the forced state off mid-run and
    /// posts the state-change notification, so a UI test can watch the deferred
    /// reason vanish (and the resumer drain) without owning a device in Low
    /// Power Mode. Inert in production and without `-forceLowPower`.
    private func scheduleAutoEndIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-endLowPowerAfter"),
              arguments.indices.contains(index + 1),
              let seconds = Double(arguments[index + 1]),
              let mutable = testState else { return }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            mutable.isLowPowerModeEnabled = false
            NotificationCenter.default.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        }
    }
    #endif
}

/// The app-side test double for `PowerStateProvider`: a lock-guarded boolean a
/// test flips, so "the mode is on/off" is a launch decision, never the host's
/// state. Reachable only through `AppPower`'s DEBUG launch-argument hooks; the
/// real app always uses `ProcessInfoPowerState`. DEBUG-only so the double never
/// ships in a release build.
#if DEBUG
final class MutablePowerState: PowerStateProvider, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)

    init(lowPower: Bool) { lock.withLock { $0 = lowPower } }

    var isLowPowerModeEnabled: Bool {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}
#endif
