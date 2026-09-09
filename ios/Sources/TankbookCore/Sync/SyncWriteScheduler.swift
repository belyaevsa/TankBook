import Foundation

/// RV.157 - the debounced write trigger (docs/SYNC.md: the cycle is "triggered
/// on app foreground, after every local write (debounced), and by push
/// notification nudge"). The write half: a local write pokes the scheduler, a
/// burst of pokes within `window` coalesces into exactly one cycle, and the
/// cycle runs through the app's single sync door - it is never a second path.
///
/// The scheduler is deliberately **policy-less about sync itself**: it owns the
/// debounce timing and the "is a cycle still worth running" re-check, and it
/// delegates everything else to injected closures. The app wires:
///
/// - `run`: the ONE sync door (`AppSync.runSync(.background)`), never a second
///   `SyncEngine`.
/// - `isArmed`: signed in AND the config gate allows server-backed work. A
///   guest's write is a cheap no-op - nothing is scheduled, no cycle starts and
///   finds nothing (a signed-out write must not poke the transport at all).
/// - `isBusy`: a cycle is in flight. A poke that lands mid-cycle is not lost:
///   the fire is re-armed to run once the in-flight cycle ends.
/// - `hasWork`: there are dirty rows. A poke from a write that dirtied nothing
///   (an exchange-rate cache write, a device-local duplicate resolution) must
///   not start a cycle that has nothing to push - the fire is a no-op.
/// - `isRetryPending`: PR.7 has already scheduled the next attempt (backoff).
///   The retry owns the queue; a fire now would only fight the schedule (and a
///   server `Retry-After`), so the poke is absorbed by the pending retry.
///
/// **Low Power Mode** is handled here, in the scheduler, not in `run`: when a
/// fire would run while the mode is on, the cycle is registered with the
/// injected `LowPowerResumer` (kind `.syncCycle`) instead of running - the same
/// deferral the foreground pass gets from `AppSync.runSync`, but owned by the
/// trigger so it is testable in core without the app. When the mode ends the
/// resumer drains the registered cycle, and `run` executes with the mode off.
/// The save itself is never deferred - `noteWrite` returns immediately
/// regardless (hard rule 1: a save stays local and immediate whatever the sync
/// does).
///
/// `@MainActor`: every producer is app-UI (`AppSync` is `@MainActor`), the
/// injected closures read `@MainActor` state, and `run` is the app's own
/// `@MainActor` sync door. Core stays testable - the L1/L3 suites drive it with
/// real repositories, coordinators, transports and a `LowPowerResumer` under
/// `swift test`.
@MainActor
public final class SyncWriteScheduler {
    /// The quiet window after the LAST poke before a cycle may fire. A compiled
    /// constant (docs/PRACTICES.md): a tunable threshold, never a remote or user
    /// value. Chosen at 3 s - long enough that a burst of writes (an entry save
    /// that also stamps a station and an attachment, an import commit, a rate
    /// backfill) folds into one cycle, short enough that a saved edit reaches
    /// another device within seconds rather than sitting until the next
    /// foreground (the latency this row exists to remove).
    public static let debounceWindow: Duration = .seconds(3)

    /// The work a fire performs: one sync cycle through the app's single door.
    /// Set by the app; nil keeps an un-wired embedding inert.
    public var run: (@MainActor () async -> Void)?

    /// Whether a write may schedule anything at all (signed in + config gate).
    /// False = the poke is a cheap no-op (a guest, or `.required` pausing push).
    public var isArmed: @MainActor () -> Bool = { false }

    /// Whether a cycle is already in flight. A fire while busy re-arms instead
    /// of running or dropping.
    public var isBusy: @MainActor () -> Bool = { false }

    /// Whether a fire has anything to do. Checked again at fire time so a poke
    /// whose write dirtied nothing (or whose dirty rows a just-finished cycle
    /// already pushed) costs no cycle.
    public var hasWork: @MainActor () -> Bool = { false }

    /// Whether PR.7 backoff has already scheduled the next attempt. When true a
    /// fire defers to that retry rather than fighting the schedule.
    public var isRetryPending: @MainActor () -> Bool = { false }

    /// The power state consulted at fire time. Optional so an un-wired embedding
    /// (or a test that never flips the mode) can stay inert. The app passes its
    /// single injected state, never `ProcessInfo` read here.
    public let powerState: (any PowerStateProvider)?

    /// Drains the cycle a fire deferred while Low Power Mode was on. The app
    /// passes the resumer it already shares with the foreground pass.
    public let resumer: LowPowerResumer?

    /// The id the deferred cycle is registered under. The app passes the SAME
    /// id `AppSync.runSync` registers its own deferred cycle under, so a write
    /// trigger deferral and a foreground deferral inside one Low Power session
    /// replace each other instead of stacking two drains.
    public let deferredWorkID: UUID

    private let window: Duration
    private var pendingTask: Task<Void, Never>?
    private var wantsRun = false

    public init(window: Duration = SyncWriteScheduler.debounceWindow,
                powerState: (any PowerStateProvider)? = nil,
                resumer: LowPowerResumer? = nil,
                deferredWorkID: UUID = UUID()) {
        self.window = window
        self.powerState = powerState
        self.resumer = resumer
        self.deferredWorkID = deferredWorkID
    }

    /// A local write happened. Coalescing: a poke while a fire is already
    /// scheduled only marks "still wanted" - it does not start a second timer,
    /// so a burst inside the window becomes exactly one cycle.
    public func noteWrite() {
        guard isArmed() else { return }
        wantsRun = true
        guard pendingTask == nil else { return }
        scheduleFire()
    }

    private func scheduleFire() {
        let window = self.window
        let task = Task { [weak self] in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled else { return }
            await self?.fire()
        }
        pendingTask = task
    }

    /// Fires one cycle when the write is still worth one. `wantsRun` is cleared
    /// here, not in `noteWrite`, so a poke that arrives while a cycle is in
    /// flight (or while a retry owns the queue) is not silently absorbed: the
    /// fire re-arms and the re-check decides.
    private func fire() async {
        pendingTask = nil
        guard wantsRun else { return }
        wantsRun = false
        guard isArmed() else { return }
        guard hasWork() else { return }
        guard !isRetryPending() else { return }

        // Low Power Mode defers an opportunistic cycle (docs/SYNC.md -> Low
        // Power Mode table): register it with the resumer so it drains the
        // moment the mode ends. The save already returned - nothing is gated.
        if let powerState, let resumer,
           LowPowerPolicy.defers(work: .syncCycle, trigger: .background,
                                 lowPowerMode: powerState.isLowPowerModeEnabled) {
            let work = LowPowerResumer.PendingWork(id: deferredWorkID, kind: .syncCycle) { [weak self] in
                await self?.runDeferredCycle()
            }
            await resumer.register(work)
            return
        }

        if isBusy() {
            // A cycle is in flight; this poke's rows may or may not have been in
            // its push snapshot. Re-arm once it has drained so nothing waits for
            // the next foreground (the exact latency this row removes).
            wantsRun = true
            scheduleFire()
            return
        }
        await run?()
    }

    /// Runs the cycle a Low Power deferral registered with the resumer. The
    /// mode has ended (the resumer only drains then), so `run` executes now.
    private func runDeferredCycle() async {
        guard isArmed() else { return }
        guard hasWork() else { return }
        await run?()
    }
}
