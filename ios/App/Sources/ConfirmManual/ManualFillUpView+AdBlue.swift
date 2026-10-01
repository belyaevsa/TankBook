import SwiftUI
import TankbookCore
import UIKit

// The AdBlue chip's save and the save-bar label, split out of
// ManualFillUpView.swift for the linter's file-length ceiling.

extension ManualFillUpView {
    /// The save-bar label. On a mixed receipt it counts the accepted Expenses
    /// ("Save fill-up + 1 expense"); the AdBlue chip saves a top-up, and says so.
    func saveTitle() -> String {
        if form.isAdBlue { return L10n.localize("Save AdBlue") }
        guard case .mixed(let lines, _, _) = detection else {
            return L10n.localize("Save fill-up")
        }
        let accepted = lines.filter { acceptedLineIDs.contains($0.id) }.count
        if accepted > 0 {
            return String(localized: "Save fill-up + \(accepted) expenses")
        }
        return L10n.localize("Save fill-up")
    }

    /// Writes the `AdBlueFill` the AdBlue chip saves, then closes the sheet the
    /// way a fill-up save does: Home is told to reload (a `.sheet` never
    /// re-triggers the presenter's `.task`) and a lost receipt photo is
    /// reported. The fuel-only after-save steps (the station's bought
    /// defaults, the consumption insight) do not apply to a top-up.
    func saveAdBlue(vehicle: Vehicle, derived: ManualFillUpMath.Derived, receiptWrite: ReceiptWriteOutcome,
                    provenance: Provenance, purchaseGroupId: UUID?, source: MutationSource,
                    repository: TankbookRepository) throws {
        var adBlue = buildAdBlueFill(vehicle: vehicle, derived: derived,
                                     attachments: receiptWrite.sharedIDs, provenance: provenance)
        adBlue.purchaseGroupId = purchaseGroupId
        try loggedWrite(AppLog.shared, op: .create, entityType: AdBlueFill.entityType,
                        entityId: adBlue.id, source: source) { try repository.upsertAdBlueFill(adBlue) }
        hasUnsavedChanges = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        toastCenter.noteEntryChanged()
        reportLostReceiptPhoto(receiptWrite, toastCenter: toastCenter)
        gatewaySession.markSaved(entryID: adBlue.id)
        Task { await notificationCoordinator.reconcile(vehicleId: vehicle.id) }
        dismiss()
        onSaved?()
    }

    /// The top-up: the form's numbers, date, odometer and station, no fuel
    /// kind and no tank state; the conflict flag is stamped by the same
    /// validator, so its odometer still orders the timeline.
    func buildAdBlueFill(vehicle: Vehicle, derived: ManualFillUpMath.Derived,
                         attachments: [AttachmentID], provenance: Provenance) -> AdBlueFill {
        let now = Date()
        let money = convertForSave(Money(amount: derived.total, currency: form.currency,
                                         homeCurrency: vehicle.homeCurrency))
        var candidate = AdBlueFill(
            id: entryId, createdAt: now, updatedAt: now, vehicleId: vehicle.id,
            date: form.date, odometer: form.odometerValue, money: money,
            attachments: attachments, provenance: provenance,
            volumeL: derived.volumeL, unitPrice: derived.unitPrice, stationId: selectedStation?.id)
        let validations = TimelineValidator.validate(entries: existingEntries + [candidate],
                                                     vehicle: vehicle)
        candidate.conflict = validations.first { $0.entryID == candidate.id }?.conflict ?? .none
        return candidate
    }
}
