import Foundation

/// RV.18 - the minimum interval between opportunistic sync cycles.
///
/// A return to active (`scenePhase == .active`) fires on every foreground
/// transition - dismissing a permission alert, returning from the out-of-process
/// Photos picker, a Control Centre pull, an app-switcher peek - none of which is
/// a moment data changed. Each fires a full pull -> merge -> push cycle, and the
/// launch path fires TWICE (the `.task` launch sync and the launch-time
/// `.active` transition are two separate trigger points, measured ~0.6 s apart).
///
/// A pure decision (docs/TESTING.md L1), never `Date()` read at a call site:
/// the answer is a function of the last-cycle timestamp and `now`, like
/// `SyncSurface`'s status. It gates ONLY the opportunistic (launch/foreground)
/// door. The Settings "Sync now" tap, the retry backoff and the Low Power
/// resumer drain never consult it, so the user can always force a cycle at any
/// moment and a gated cycle still costs freshness, never function (hard rule 1).
public enum OpportunisticSyncPolicy {
    /// The shortest gap between opportunistic cycles. A compiled constant
    /// (docs/PRACTICES.md): a tunable threshold, never a remote or user value.
    public static let minimumInterval: TimeInterval = 30

    /// Whether an opportunistic cycle may run now. `last` is when the previous
    /// opportunistic cycle started (nil = none yet, so run).
    public static func shouldRun(lastOpportunisticSyncAt last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= minimumInterval
    }
}
