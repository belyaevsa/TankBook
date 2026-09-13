import TankbookCore
import XCTest
@testable import Tankbook

/// RV.248 - the History row's composed caption (docs/JOURNEYS.md J7c ->
/// "Delete"). The dismissal reason is the row's caption; a completion that
/// logged an entry names that entry through the shared `EntryTitle`, never a
/// bare "Completed" while better text exists. The query half (terminal rows
/// come back with their reason and entry id) is pinned in the package suite
/// (`ReminderHistoryTests`); this is the display half, which cannot run without
/// the app target's `EntryTitle`/`L10n`.
@MainActor
final class RV248ReminderHistoryTests: XCTestCase {

    private func terminal(_ title: String, status: ReminderStatus) -> Reminder {
        ReminderLifecycle.makeReminder(
            vehicleId: UUID.v7(), title: title, category: .oil,
            dueDate: Date(), dueOdometer: nil, recurrence: nil, status: status)
    }

    private func item(_ title: String, status: ReminderStatus,
                      entryTitle: String?, count: Int) -> ReminderHistoryItem {
        ReminderHistoryItem(reminder: terminal(title, status: status),
                            entryTitle: entryTitle, completionCount: count)
    }

    /// The stored reason IS the dismissed row's caption - the value the screen
    /// collected, now read back (the row's headline claim).
    func testDismissalReasonIsTheRowCaption() {
        let row = item("Winter tires", status: .dismissed(reason: "Sold the tires"),
                       entryTitle: nil, count: 0)
        XCTAssertEqual(ReminderHistoryFormat.caption(for: row), "Sold the tires")
    }

    /// A dismissal without a reason still reads as history, not an empty row.
    func testDismissalWithoutAReasonSaysDismissed() {
        let row = item("Winter tires", status: .dismissed(reason: nil),
                       entryTitle: nil, count: 0)
        XCTAssertFalse(ReminderHistoryFormat.caption(for: row).isEmpty,
                       "a reason-less dismissal must not render an empty caption")
        XCTAssertNotEqual(ReminderHistoryFormat.caption(for: row), "Sold the tires")
    }

    /// A done row names the entry its completion logged, so the user can see
    /// what the reminder became - and the caption is not just "Completed".
    func testDoneRowNamesTheEntryItBecame() {
        let row = item("Oil change", status: .done(entryId: UUID.v7()),
                       entryTitle: "Bosch Service", count: 1)
        let caption = ReminderHistoryFormat.caption(for: row)
        XCTAssertTrue(caption.contains("Bosch Service"),
                      "the done row must name its entry; was \(caption)")
    }

    /// A completion that skipped the cost log has no entry to name and must
    /// not fabricate one.
    func testDoneWithoutAnEntryDoesNotNameOne() {
        let row = item("Oil change", status: .done(entryId: nil),
                       entryTitle: nil, count: 1)
        let caption = ReminderHistoryFormat.caption(for: row)
        XCTAssertFalse(caption.isEmpty)
        XCTAssertFalse(caption.contains("·"),
                       "a skipped cost log has no entry, so no entry clause; was \(caption)")
    }
}
