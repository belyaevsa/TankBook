import Foundation
import os

/// Drains work that Low Power Mode deferred, the moment the mode ends
/// (docs/SYNC.md -> Low Power Mode: "Resume on the state change, not at next
/// launch"). A device that left the mode hours ago must not still be holding
/// its queue.
///
/// The app owns the work being drained and registers it here as closures - a
/// deferred background sync, a rate pack refresh, a catalog fetch - keyed by an
/// id the registrar completes once the work succeeds. The observer only decides
/// *when* to drain: the injected `PowerStateProvider` says whether the mode has
/// actually ended and the injected `NotificationCenter` carries the state
/// change, so "fires on the state change, not only at launch" is provable
/// without a device. Nothing here reads `ProcessInfo`.
public actor LowPowerResumer {
    /// One unit of deferred work: a closure plus the kind it belongs to, for
    /// diagnostics and for the future passive status row.
    public struct PendingWork: Sendable {
        public let id: UUID
        public let kind: PowerWorkKind
        private let run: @Sendable () async -> Void

        public init(id: UUID, kind: PowerWorkKind,
                    run: @escaping @Sendable () async -> Void) {
            self.id = id
            self.kind = kind
            self.run = run
        }

        func perform() async { await run() }
    }

    private struct State {
        var pending: [UUID: PendingWork] = [:]
    }

    private let powerState: any PowerStateProvider
    private let notificationCenter: NotificationCenter
    private let state = OSAllocatedUnfairLock(initialState: State())
    private var token: NSObjectProtocol?

    public init(powerState: any PowerStateProvider,
                notificationCenter: NotificationCenter = .default) {
        self.powerState = powerState
        self.notificationCenter = notificationCenter
    }

    /// Starts observing `NSProcessInfoPowerStateDidChange`. Idempotent: a
    /// second call replaces the first observer rather than stacking a second.
    public func start() {
        stop()
        token = notificationCenter.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.drainIfNeeded() }
        }
    }

    /// Stops observing and releases the observer token. Pending work is kept,
    /// so a later `start()` still drains it.
    public func stop() {
        if let token {
            notificationCenter.removeObserver(token)
            self.token = nil
        }
    }

    /// Records work that a deferral put off. Re-registering an id replaces the
    /// previous closure, so the registrar can update what should run.
    public func register(_ work: PendingWork) {
        state.withLock { $0.pending[work.id] = work }
    }

    /// Removes pending work once it has run (or is no longer wanted). Safe to
    /// call for an id that was never registered.
    public func complete(id: UUID) {
        _ = state.withLock { $0.pending.removeValue(forKey: id) }
    }

    /// How many units of work are waiting to drain. `nonisolated` because it
    /// reads only the lock-guarded state, so the resume test can await a drain
    /// without an actor hop that would need no suspension.
    public nonisolated var pendingCount: Int {
        state.withLock { $0.pending.count }
    }

    /// Runs every pending unit when the mode is off. When the mode is still on,
    /// everything stays registered - the mode can toggle again without losing
    /// work. Called from the observer; public so tests and the app can also
    /// drain on demand.
    public func drainIfNeeded() async {
        guard !powerState.isLowPowerModeEnabled else { return }
        let toRun = state.withLock { snapshot -> [PendingWork] in
            let values = Array(snapshot.pending.values)
            snapshot.pending.removeAll()
            return values
        }
        for work in toRun {
            await work.perform()
        }
    }
}
