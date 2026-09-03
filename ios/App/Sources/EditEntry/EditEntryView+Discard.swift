import SwiftUI
import TankbookCore

// RV.31: the "does this pushed Edit entry hold unsaved work" signal behind the
// active-tab re-tap discard guard (see `PushedFormDirtyPreference`).
// Split out of EditEntryView.swift to keep that file under the linter's
// file-length limit - the same reason EditEntryView+Attachment.swift exists.

extension EditEntryView {

    /// True while this pushed Edit entry holds work a pop would throw away.
    /// The baseline is the form AS IT LOADED from the stored entry - NOT the
    /// Confirm-sheet heuristic (`ManualFillUpFormState.hasEdits`), whose
    /// "deviated from the vehicle defaults" yardstick would mark a stored
    /// partial fill or a second fuel kind as an edit the user never made. Here
    /// an entry is dirty only when the live form differs from the pristine
    /// reload, the note changed, or a receipt attach is still held in memory
    /// (a photo that only Save writes - hard rule 8).
    ///
    /// Read every render by the `.preference` in `body`; the tab host consults
    /// the published value when the ACTIVE tab is re-tapped.
    var entryHasUnsavedChanges: Bool {
        if loadFailed { return false }
        if let fillUp, let vehicle {
            let pristine = Self.pristineFillForm(for: fillUp, vehicle: vehicle)
            return note != (fillUp.note ?? "")
                || fillForm != pristine
                || attachImage != nil
        }
        if let entry = currentEntry, let vehicle {
            return nonFillForm != Self.pristineNonFillForm(for: entry, vehicle: vehicle)
        }
        return false
    }

    /// The fill form exactly as `reloadData` loads it (`load(from:vehicle:)`):
    /// the discard baseline for a fill entry. Both the loader and this builder
    /// read the SAME stored `FillUp`, so an unedited entry always compares
    /// equal and pops immediately - no dialog, per the RV.31 fence.
    static func pristineFillForm(for fill: FillUp, vehicle: Vehicle) -> ManualFillUpFormState {
        var form = ManualFillUpFormState()
        form.load(from: fill, vehicle: vehicle)
        return form
    }

    /// The non-fill form exactly as `loadNonFill` loads it - its single source
    /// of truth since the RV.31 refactor, so the loader and the discard
    /// baseline cannot drift.
    static func pristineNonFillForm(for entry: any Entry, vehicle: Vehicle) -> EditEntryNonFillForm {
        var form = EditEntryNonFillForm()
        form.amount = entry.money.map {
            ManualFillUpFormat.decimal($0.amount, fractionDigits: 2)
        } ?? ""
        form.currency = entry.money?.currency ?? vehicle.homeCurrency
        form.date = entry.date
        form.odometer = entry.odometer.map(OdometerFormat.grouped) ?? ""
        form.note = entry.note ?? ""
        switch entry {
        case let charge as ChargeSession:
            form.energyKWh = charge.energyKWh == 0
                ? "" : ManualFillUpFormat.decimal(charge.energyKWh, fractionDigits: 1)
            form.provider = charge.provider ?? ""
        case let service as ServiceRecord:
            form.vendor = service.vendor ?? ""
        case let expense as Expense:
            form.title = expense.title
        default:
            break
        }
        return form
    }
}
