import Foundation

// RV.267: the dismissed-without-save half of the expense scan lifecycle. The
// expense scan stages only memory - a photograph, a pre-fill and a category -
// never a page file, so the cleanup is `ExpenseEntrySession.discard()`: clear
// the hand-off and cancel the in-flight read. Split out of `ExpenseEntryView`
// the way `ServiceEntryView+DiscardPages.swift` split the service cleanup, so
// the behaviour is L1-testable without the sheet.

extension ExpenseEntryView {

    /// Discards the scan a dismissed-without-save sheet leaves staged, so the
    /// next open starts clean. The read is cancelled in the same turn, so a
    /// read landing after the cancel cannot repopulate the session a later
    /// `load` reads. A save does not come here - the view's one dismissal path
    /// guards on `didSave`, and the saved entry's late read must still reach the
    /// inbox.
    @MainActor
    static func discardStagedScan(_ session: ExpenseEntrySession) {
        session.discard()
    }
}
