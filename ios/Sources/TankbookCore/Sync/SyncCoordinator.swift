import Foundation
import os

/// The app-level sync trigger (docs/SYNC.md -> "The Settings sync surface").
/// Wraps the P4.5 `SyncEngine` with the one piece of coordination the engine
/// deliberately does not own: **idempotency of the manual "Sync now" trigger**.
/// A repeated tap while a cycle is already in flight is inert - it issues no
/// second transport call, never a second push.
///
/// "Sync now" may never be the only path to a synced state (hard rule 1): the
/// automatic cycles (foreground, debounced write, silent APNs nudge) all call
/// `syncNow()` too, so removing the Settings button changes nothing about
/// whether data eventually arrives. The trigger and the transport live here;
/// nothing else in the app may construct a second `SyncEngine`.
///
/// A lock-guarded class rather than an actor because `SyncEngine` and its
/// `TankbookRepository` are not `Sendable` (the GRDB writer is not a Sendable
/// existential), and the idempotency gate is a single boolean - `@unchecked
/// Sendable` with the lock is the honest, minimal isolation for it.
public final class SyncCoordinator: @unchecked Sendable {
    private struct State {
        var inFlight = false
        var lastSyncDate: Date?
        var lastOutcome: SyncOutcome?
    }

    private let engine: SyncEngine
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(engine: SyncEngine, lastSyncDate: Date? = nil) {
        self.engine = engine
        state.withLock { $0.lastSyncDate = lastSyncDate }
    }

    /// True while a cycle is in flight. The "Sync now" row reads this for its
    /// spinner; the idempotency guarantee itself is asserted on the transport
    /// call count (docs/TESTING.md -> the push count, never the button state).
    public var isSyncing: Bool {
        state.withLock { $0.inFlight }
    }

    /// When the last **non-inert** cycle finished, or nil before the first
    /// sync. A failed (offline) cycle does not advance this - the status surface
    /// must not claim "just now" after a transport outage.
    public func lastSyncDate() -> Date? {
        state.withLock { $0.lastSyncDate }
    }

    /// The last non-inert cycle's outcome, for the Settings status surface.
    public func lastOutcome() -> SyncOutcome? {
        state.withLock { $0.lastOutcome }
    }

    /// Runs one sync cycle. Inert while a cycle is already in flight: the
    /// returned outcome is the previous one (or an empty one on first call) and
    /// no transport call is made. Offline is not an error - the engine maps a
    /// transport failure to `transportUnavailable` and the dirty queue is
    /// untouched (docs/SYNC.md S7).
    @discardableResult
    public func syncNow() async -> SyncOutcome {
        let shouldRun = state.withLock { snapshot -> Bool in
            if snapshot.inFlight { return false }
            snapshot.inFlight = true
            return true
        }
        guard shouldRun else {
            return state.withLock { $0.lastOutcome ?? SyncOutcome() }
        }

        let outcome = await engine.synchronize()
        state.withLock { snapshot in
            snapshot.lastOutcome = outcome
            if !outcome.transportUnavailable {
                snapshot.lastSyncDate = Date()
            }
            snapshot.inFlight = false
        }
        return outcome
    }
}
