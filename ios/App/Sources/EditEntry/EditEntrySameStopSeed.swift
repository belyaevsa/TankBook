#if DEBUG
import Foundation
import TankbookCore

/// RV.276's same-stop-pair seed entry point, split out of `EditEntryTestSeed`
/// to keep that file under the linter's file-length ceiling (the
/// `EditEntryDeferredReceiptSeed` precedent). The data lives in
/// `TimelineNeighbourhoodTestSeed`, shared with the Home seed.
enum EditEntrySameStopSeed {
    @MainActor
    static func seedIfRequested(arguments: [String]) -> Bool {
        guard arguments.contains("-seedEditEntrySameStopPair") else { return false }
        if arguments.contains("-homeResetDatabase") {
            AppStore.resetForTestsOncePerLaunch()
        }
        guard let repository = try? AppStore.repository() else { return true }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return true }
        TimelineNeighbourhoodTestSeed.seedSameStopPair(repository)
        return true
    }
}
#endif
