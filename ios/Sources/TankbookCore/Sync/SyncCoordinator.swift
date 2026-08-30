import Foundation
import os

/// The app-level sync trigger (docs/SYNC.md -> "The Settings sync surface").
/// Wraps the P4.5 `SyncEngine` with the coordination the engine deliberately
/// does not own: **idempotency of the manual "Sync now" trigger** and, since
/// PR.7, **the retry schedule** - a failed cycle that is transient (offline,
/// 5xx, a 429 wait) schedules the next attempt with jittered exponential
/// backoff, honouring the server's `Retry-After` when it sent one. A repeated
/// tap while a cycle is already in flight is inert - it issues no second
/// transport call, never a second push.
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
        // PR.7 retry state: how many consecutive retryable failures have been
        // seen (drives the backoff exponent), the scheduled retry task, and the
        // delay that task is currently sleeping for.
        var retryAttempt = 0
        var retryTask: Task<Void, Never>?
        var pendingRetryDelay: Duration?
    }

    private let engine: SyncEngine
    private let powerState: any PowerStateProvider
    private let state = OSAllocatedUnfairLock(initialState: State())
    /// The jitter source, injected so a test pins the schedule (bounded in
    /// [0, 1] - `SyncRetryPolicy` clamps).
    private let jitter: @Sendable () -> Double
    /// The wait the scheduled retry sleeps on. The real implementation is a
    /// `Task.sleep`; tests inject a gate or a recorder so no schedule assertion
    /// ever waits on a wall clock.
    private let retryWait: @Sendable (Duration) async -> Void

    public init(engine: SyncEngine,
                powerState: any PowerStateProvider = ProcessInfoPowerState(),
                lastSyncDate: Date? = nil,
                jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
                retryWait: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.engine = engine
        self.powerState = powerState
        self.jitter = jitter
        self.retryWait = retryWait
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

    /// The delay the currently scheduled retry is sleeping for, or nil when no
    /// retry is pending. A retryable failure schedules exactly one next cycle
    /// at this delay; a success or a refusal clears it.
    public func scheduledRetryDelay() -> Duration? {
        state.withLock { $0.pendingRetryDelay }
    }

    /// Runs one sync cycle. Inert while a cycle is already in flight: the
    /// returned outcome is the previous one (or an empty one on first call) and
    /// no transport call is made. Offline is not an error - the engine maps a
    /// transport failure to `offline` (or a 5xx to `serverUnavailable`) and the
    /// dirty queue is untouched (docs/SYNC.md S7).
    ///
    /// The trigger is explicit at every call site (docs/SYNC.md -> Low Power
    /// Mode): while the mode is on, an **opportunistic** cycle (`.background`)
    /// defers - the queue is exactly as it was, nothing dropped (hard rule 8) -
    /// and a sync the **user asked for** (`.userInitiated`) always runs. The
    /// automatic triggers (launch, foreground, debounced write, silent nudge)
    /// MUST pass `.background`; the default is `.userInitiated` because every
    /// current caller is a user's own tap, and a deferral bug is worse than a
    /// run bug.
    ///
    /// After a retryable outcome the cycle schedules its own next attempt
    /// (PR.7); after a success or a refusal it clears the backoff so the next
    /// failure starts a fresh curve.
    @discardableResult
    public func syncNow(trigger: PowerWorkTrigger = .userInitiated) async -> SyncOutcome {
        if LowPowerPolicy.defers(work: .syncCycle, trigger: trigger,
                                 lowPowerMode: powerState.isLowPowerModeEnabled) {
            var outcome = SyncOutcome()
            outcome.deferred = true
            return outcome
        }

        let shouldRun = state.withLock { snapshot -> Bool in
            if snapshot.inFlight { return false }
            snapshot.inFlight = true
            return true
        }
        guard shouldRun else {
            return state.withLock { $0.lastOutcome ?? SyncOutcome() }
        }

        let outcome = await engine.synchronize(trigger: trigger)
        state.withLock { snapshot in
            snapshot.lastOutcome = outcome
            if !outcome.offline && !outcome.serverUnavailable {
                snapshot.lastSyncDate = Date()
            }
            snapshot.inFlight = false
        }
        scheduleRetry(after: outcome)
        return outcome
    }

    // MARK: - Retry (PR.7)

    /// Decides the next attempt from the outcome: schedule a jittered-backoff
    /// retry for the transient class, clear the backoff on a success or a
    /// refusal. Only idempotent calls are retried - the whole sync cycle is
    /// idempotent by id + `baseScn` (docs/SYNC.md), so a re-run never double-
    /// pushes. The refusal classes (401/402/410/426/unknown-4xx) are never
    /// retried: they name a next step that is not "try again".
    private func scheduleRetry(after outcome: SyncOutcome) {
        let attempt = state.withLock { $0.retryAttempt }
        let jitterValue = jitter()
        guard let delay = SyncRetryPolicy.delay(after: outcome, attempt: attempt, jitter: jitterValue) else {
            // Not retried: a success or a refusal. Reset so the next failure
            // starts a fresh 1-2-4-8 curve rather than resuming a stale one.
            state.withLock { snapshot in
                snapshot.retryAttempt = 0
                snapshot.retryTask?.cancel()
                snapshot.retryTask = nil
                snapshot.pendingRetryDelay = nil
            }
            return
        }

        let nextAttempt = attempt + 1
        let task = Task { [weak self] in
            await self?.retryWait(delay)
            guard !Task.isCancelled else { return }
            self?.state.withLock { $0.pendingRetryDelay = nil }
            await self?.syncNow(trigger: .background)
        }
        state.withLock { snapshot in
            snapshot.retryAttempt = nextAttempt
            snapshot.retryTask?.cancel()
            snapshot.retryTask = task
            snapshot.pendingRetryDelay = delay
        }
    }
}
