import SwiftUI
import TankbookCore

// RV.37: the viewer reports a delete or replace back here. Split out of
// EditEntryView.swift to keep that file under the linter's file-length limit -
// the same reason Repository+RecentlyDeleted exists. The state it touches is
// internal for this file's reach (see EditEntryView).

extension EditEntryView {

    /// The viewer reports a delete or replace through this. The entry's
    /// attachment list is re-read from the repository (the single source of
    /// truth) WITHOUT reloading the form, so unsaved edits survive a receipt
    /// swap. When the user accepted a re-read, `extraction` is non-nil and the
    /// blank-field suggestions are applied to the form exactly as the attach
    /// flow does - dimmed, blank fields only, never a blind overwrite (hard rule
    /// 13).
    func handleAttachmentChanged(_ extraction: FuelExtraction?) {
        Task { await reloadAttachments() }
        if let extraction, let fillUp, let vehicle {
            let suggestions = ReceiptAttachMerge.suggestions(
                entry: fillForm.blankDetectingEntry(vehicle: vehicle), extraction: extraction)
            fillForm.applyAttachedSuggestions(suggestions, extraction: extraction)
        }
    }

    /// Re-reads the entry's attachment list and the in-memory entry's
    /// `attachments` (so a later Save carries the fresh list, not the stale one
    /// it was loaded with). The form state is deliberately untouched.
    func reloadAttachments() async {
        guard let vehicle else { return }
        do {
            let repository = try AppStore.repository()
            let all = try repository.liveEntries(forVehicle: vehicle.id)
            guard let target = all.first(where: { $0.id == currentEntry?.id }) else { return }
            let ids = target.attachments
            attachments = try repository.liveAttachments().filter { ids.contains($0.id) }
            pendingBlobIDs = Set(attachments.filter { !BlobService.isBlobAvailable($0) }.map(\.id))
            updateInMemoryAttachments(ids)
        } catch {
            AppLog.error(operation: "editEntry.reloadAttachments", category: .ui, error: error)
        }
    }

    private func updateInMemoryAttachments(_ ids: [AttachmentID]) {
        if var fill = fillUp {
            fill.attachments = ids
            fillUp = fill
        } else if var chargeCopy = charge {
            chargeCopy.attachments = ids
            charge = chargeCopy
        } else if var serviceCopy = service {
            serviceCopy.attachments = ids
            service = serviceCopy
        } else if var expenseCopy = expense {
            expenseCopy.attachments = ids
            expense = expenseCopy
        }
    }
}
