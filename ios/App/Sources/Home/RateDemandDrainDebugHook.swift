#if DEBUG
import Foundation

/// RV.111's deterministic "pending -> checked dead end" beat (screenshot + L4):
/// `-runRateDemandDrain` fires ONE demand drain (`AppRates.drainPendingRows`) a
/// short beat after launch, so the waiting footnote can render first and then -
/// under `-stubRatesEmpty`, where the provider is reached but serves nothing -
/// flip to the dead-end manual-rate copy. Same shape as
/// `RateBackfillDebugHook`; the drain itself is the real product path a
/// "Check for rates" tap runs, and the flip is silent (S8).
@MainActor
enum RateDemandDrainDebugHook {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-runRateDemandDrain") else { return }
        Task {
            // Let the pending state render (and a test assert it) first.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await AppRates.drainPendingRows()
        }
    }
}
#endif
