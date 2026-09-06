#if DEBUG
import Foundation
import TankbookCore

/// RV.72 test seam: with `-resolveFlaggedInPlace`, clears the conflict on one
/// flagged entry a moment after the list appears and bumps the toast-center
/// revision - **without any navigation**.
///
/// This is the case the pop-back test cannot reach. Returning from Edit entry
/// also fires `.onAppear`, so an appear-only reload passes that flow while
/// missing what the revision observation exists for: data that changes while
/// the list stays on screen (a sync merge resolving a flag, the Inbox
/// retiring one). The orchestrator's mutation proved the gap - `.onAppear`
/// instead of `.onChange(of: revision)` left the whole suite green.
enum FlaggedEntriesTestSeed {
    @MainActor
    static func resolveOneInPlaceIfRequested(_ toastCenter: AppToastCenter) async {
        guard ProcessInfo.processInfo.arguments.contains("-resolveFlaggedInPlace") else { return }
        // Long enough that the test can observe the STARTING count first: the
        // assertion is that the list goes 2 -> 1 without navigation, and a
        // resolution that lands before the first query makes the test fail for
        // the wrong reason (it never sees 2).
        try? await Task.sleep(for: .seconds(4))
        guard let repository = try? AppStore.repository() else { return }
        for vehicle in (try? repository.liveVehicles()) ?? [] {
            for entry in (try? repository.liveEntries(forVehicle: vehicle.id)) ?? []
            where entry.conflict != .none {
                if var fill = entry as? FillUp {
                    fill.conflict = .none
                    fill.updatedAt = Date()
                    try? repository.upsertFillUp(fill)
                    toastCenter.noteEntryChanged()
                    return
                }
            }
        }
    }
}
#endif
