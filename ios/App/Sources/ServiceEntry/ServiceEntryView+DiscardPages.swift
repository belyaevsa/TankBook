import Foundation
import TankbookCore
import UIKit

// RV.245: the dismissed-without-save half of the scan lifecycle. Pages persist
// at scan start so a deferred read cannot lose them (RV.243); the trade is that
// a sheet closed without a save leaves rows and files with no owning record,
// and the server-side orphan sweep (P4.3) never reaches the device. Split out
// of `ServiceEntryView` so the cleanup is L1-testable without the sheet.

extension ServiceEntryView {

    /// Deletes the invoice pages a dismissed-without-save sheet leaves behind.
    /// `pages` is the form's strip; `pendingPrefill` covers the scan that never
    /// reached the form (the sheet closed before `load` applied it). The
    /// session's in-flight read is cancelled in the same turn, so its late
    /// answer cannot re-offer a page whose row and file are already gone.
    ///
    /// The page row is tombstoned before its file is removed
    /// (`InvoicePageStore.removePage`), so a crash between the two leaves a
    /// tombstone rather than a dangling reference. One failed page does not
    /// strand the rest; the count logged is how many pages the cleanup took.
    ///
    /// A crash BEFORE the dismissal still leaves the staged pages: this path
    /// runs on the way out, so it cannot reach a process that never got there.
    /// A launch sweep over pages with no owning record would be the backstop for
    /// that case; no device-side row owns it today (P4.3 is server-side).
    @MainActor
    static func discardStagedPages(_ pages: [InvoicePage],
                                   pendingPrefill: ServiceEntryPrefill?,
                                   session: ServiceInvoiceSession,
                                   repository: TankbookRepository) {
        let sessionPages = pendingPrefill?.pages ?? []
        session.discard()
        var seen = Set<UUID>()
        let staged = (pages + sessionPages).filter { seen.insert($0.id).inserted }
        guard !staged.isEmpty else { return }
        let store = InvoicePageStore(repository: repository, files: InvoiceAttachmentFiles())
        var removed = 0
        for page in staged {
            do {
                try store.removePage(page.attachment)
                removed += 1
            } catch {
                AppLog.error(operation: "serviceEntry.discardStagedPages",
                             category: .ui, error: error)
            }
        }
        AppLog.shared.emit(InvoicePagesDiscarded(pageCount: removed))
    }
}

// MARK: - Pages (P3.1b)

// The add/remove half of the page strip, beside the discard half above; the
// sheet file sits at the linter's length ceiling.
extension ServiceEntryView {
    func addPage() {
        showDocumentCamera = true
    }

    func handleAddedPages(_ images: [UIImage]) {
        Task {
            let newPages = await ServiceInvoiceScanner.appendPages(images: images)
            pages.append(contentsOf: newPages)
            form.attachments = pages.map(\.attachment.id)
            selectedPageIndex = max(0, pages.count - 1)
        }
    }

    /// Removing a page deletes its file - no orphan (docs/ERRORS.md -> Service &
    /// expenses: "Multi-page scan interrupted" names the next step; here the
    /// user removed a page on purpose, so there is nothing to warn about).
    func removePage(_ page: InvoicePage) {
        pages.removeAll { $0.id == page.id }
        form.attachments = pages.map(\.attachment.id)
        if selectedPageIndex >= pages.count {
            selectedPageIndex = max(0, pages.count - 1)
        }
        do {
            let repository = try AppStore.repository()
            let store = InvoicePageStore(repository: repository, files: InvoiceAttachmentFiles())
            try store.removePage(page.attachment)
        } catch {
            AppLog.error(operation: "serviceEntry.pageRemoval", category: .ui, error: error)
        }
    }

}
