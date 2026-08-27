import Foundation
import TankbookCore

/// The S8 pending -> filled transition, wired for a deterministic UI test and
/// screenshot: `-runRateBackfill` runs `MoneyBackfillService` over the rate
/// store once, a short beat after launch so the pending state can render
/// first, then the caller bumps the toast-center revision so Home/Trends
/// reload (hard rule 2: stats are derived, recomputed on any change).
///
/// The transition itself is SILENT by construction (docs/SYNC.md S8): the
/// service writes the snapshots, nothing posts a toast or banner - the home
/// amount simply appears. This hook exists so the observable transition can be
/// driven without a live rate feed; the product-side trigger (backfill after a
/// rate refresh) is the sync half's concern, and this is the test hook that
/// proves the screens render both sides of it.
@MainActor
enum RateBackfillDebugHook {
    static func runIfRequested(onFilled: @escaping () -> Void) {
        guard ProcessInfo.processInfo.arguments.contains("-runRateBackfill") else { return }
        Task {
            // Let the pending state render (and a test assert it) first - the
            // beat is deliberately wide so the "before" half of the transition
            // is observable, never a race.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let repository = try? AppStore.repository() else { return }
            let result = try? MoneyBackfillService(store: AppRates.store).backfill(repository)
            guard result?.filledCount ?? 0 > 0 else { return }
            onFilled()
        }
    }
}
