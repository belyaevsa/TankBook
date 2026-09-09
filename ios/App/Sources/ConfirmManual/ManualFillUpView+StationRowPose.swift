#if DEBUG
import Foundation

extension ManualFillUpView {
    /// RV.156 screenshot pose `-seedStationRowSelected`: selects the station the
    /// seed created through the SHARED repository call (ManualFillUpTestSeed) -
    /// the created-and-selected state the row's add flow leaves the user in,
    /// shown without simctl typing. Runs after the suggestion pass, and marks
    /// the pick the user's own so no later suggestion may move it (hard rule 13).
    func applyStationRowCreatedPoseIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seedStationRowSelected") else { return }
        selectedStation = stations.first
        stationChosenByUser = true
    }
}
#endif
