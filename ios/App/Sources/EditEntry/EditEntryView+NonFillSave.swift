import Foundation
import TankbookCore

// PJ.23: the non-fill write split out of EditEntryView.swift, which sits at the
// linter's file-length ceiling. The extraction is functional: injecting the
// repository lets the L1 tests drive the EXACT write `saveNonFill` performs and
// read the stored row back, so a dropped line item is caught as data loss.

extension EditEntryView {

    /// The repository write `saveNonFill` performs, with the repository
    /// injected so the L1 tests drive the EXACT same arms and read the stored
    /// row back. The view effects (`toastCenter`, `dismiss`) stay in
    /// `saveNonFill`.
    @MainActor
    static func writeNonFill(_ entry: any Entry, vehicle: Vehicle,
                             form: EditEntryNonFillForm,
                             otherEntries: [any Entry],
                             repository: TankbookRepository) throws {
        var updated = entry
        updated.updatedAt = Date()
        updated.date = form.date
        updated.odometer = form.odometerValue
        updated.money = form.editedMoney(original: entry.money,
                                         homeCurrency: vehicle.homeCurrency)
        updated.note = form.note.isEmpty ? nil : form.note

        // PJ.11: F9a is checked on every write, not just capture. An edit
        // that moves an odometer or a date can break the timeline exactly
        // as a new entry can, and the flag must land with the save - never
        // left to a later read. The stamp never blocks the write (hard rule
        // 13: the user decided; the amber badge surfaces it later).
        let validations = TimelineValidator.validate(entries: otherEntries + [updated],
                                                     vehicle: vehicle)
        let validation = validations.first { $0.entryID == updated.id }
        updated.conflict = validation?.conflict ?? .none
        // RV.104: the validator's acceptance verdict (kept only while it
        // suppresses a real flag) rides the typed copy, so editing a
        // non-fact field cannot resurrect a flag an acceptance holds down.
        updated.flagAcceptance = validation?.acceptance

        switch updated {
        case var charge as ChargeSession:
            charge.provider = form.provider.isEmpty ? nil : form.provider
            if let kWh = Double(form.energyKWh) { charge.energyKWh = kWh }
            charge.conflict = updated.conflict
            charge.flagAcceptance = updated.flagAcceptance
            try repository.upsertChargeSession(charge)
        case var service as ServiceRecord:
            service.vendor = form.vendor.isEmpty ? nil : form.vendor
            // PJ.23: write the line items back - title, category and cost are
            // the row's whole point, and a service opened in Edit used to show
            // only its Vendor while [RV.187] titled its Log row from the first
            // named item. `preserving:` keeps each item's `partNumber` and
            // `lifetime`, which this screen does not edit but must not drop.
            let originalItems = service.items
            service.items = form.items.enumerated().map { index, item in
                item.serviceItem(homeCurrency: vehicle.homeCurrency,
                                 preserving: index < originalItems.count ? originalItems[index] : nil)
            }
            service.conflict = updated.conflict
            service.flagAcceptance = updated.flagAcceptance
            try repository.upsertServiceRecord(service)
        case var expense as Expense:
            expense.title = form.title
            expense.category = form.category
            expense.conflict = updated.conflict
            expense.flagAcceptance = updated.flagAcceptance
            try repository.upsertExpense(expense)
        default:
            break
        }
        resolveEditedMoneyAtCommit(entryID: updated.id, vehicleID: vehicle.id,
                                   repository: repository)
    }

    /// A non-fill edit resolves at commit when it can - the same claim an
    /// import commit's drain has, served by the same SCOPED backfill over the
    /// row just written (docs/SCHEMA.md -> Money, hard rule 3). A currency edit
    /// equal to the car's home was already snapshotted at rate 1 by
    /// `Money.edited` and needs no rate at all; a foreign edit resolves only
    /// when the rate cache holds a row for the entry's OWN day - a miss stays
    /// rate-pending and counted (F9), never an error, never a blocked save, and
    /// never a conversion at today's rate. Cache-only: this makes no fetch, so
    /// it never depends on connectivity (hard rule 1). The row is re-read first
    /// - the backfill must receive the CURRENT row, or a field this save wrote
    /// (the conflict stamp) could be clobbered.
    @MainActor
    static func resolveEditedMoneyAtCommit(entryID: UUID, vehicleID: UUID,
                                           repository: TankbookRepository) {
        guard let current = (try? repository.liveEntries(forVehicle: vehicleID))?
            .first(where: { $0.id == entryID }) else { return }
        _ = try? MoneyBackfillService(store: AppRates.store)
            .backfill(repository, limitedTo: [current])
    }
}
