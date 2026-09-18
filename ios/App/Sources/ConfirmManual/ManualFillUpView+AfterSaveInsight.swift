import Foundation
import TankbookCore
import UIKit

// MARK: - What the save owes the user after the write

extension ManualFillUpView {
    /// J3 → Done: the save's haptic and its one-liner (`AfterSaveInsight`),
    /// then the lost-photo notice, which outranks the insight because it names
    /// a next step. A save the data cannot describe yet posts no toast but
    /// still tells Home to reload (hard rule 2) - a `.sheet` never re-triggers
    /// the presenter's `.task`, so without it Home shows the pre-save state.
    func postAfterSaveNotices(saved: FillUp, vehicle: Vehicle, repository: TankbookRepository,
                              receiptWrite: ReceiptWriteOutcome) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if let insight = afterSaveInsight(for: saved, vehicle: vehicle, repository: repository) {
            toastCenter.show(AfterSaveInsightMessage.text(for: insight, vehicle: vehicle))
        } else {
            toastCenter.noteEntryChanged()
        }
        reportLostReceiptPhoto(receiptWrite, toastCenter: toastCenter)
    }

    /// The stats over the vehicle's entries AFTER the write, derived the way
    /// Home derives them (S2 single-count included), so the toast's figure is
    /// the one Home shows next.
    private func afterSaveInsight(for saved: FillUp, vehicle: Vehicle,
                                  repository: TankbookRepository) -> AfterSaveInsight? {
        guard let entries = try? repository.liveEntries(forVehicle: vehicle.id) else { return nil }
        let resolved = (try? repository.resolvedDuplicateKeys()) ?? []
        let stats = HomeStats(vehicle: vehicle, entries: entries, duplicateResolutions: resolved)
        return AfterSaveInsight.derive(saved: saved, stats: stats)
    }
}
