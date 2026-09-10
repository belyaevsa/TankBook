import TankbookCore
import XCTest
@testable import Tankbook

/// The expense edit screen must show, and let the user change, the expense's
/// CATEGORY.
///
/// Product owner, 2026-09-10: *"I opened a service/expense entry, but opened a
/// fillup view with unrelated to it fields"* - the values and money were right,
/// the category was missing, and the screen talked about consumption. The
/// category is not cosmetic: it is what the Log row shows when the expense has
/// no title (RV.187), and for an imported row it is the importer's GUESS from
/// the source file's kind column. A screen that offers the title but not the
/// type lets the user rename a thing whose kind they can neither see nor
/// correct - hard rule 13, which requires a derived value to be editable at the
/// moment it is offered AND afterwards.
@MainActor
final class RV195ExpenseCategoryTests: XCTestCase {

    private let vehicle = TargetCar.newCar(named: "Test car", homeCurrency: .eur).vehicleValue

    private func expense(_ category: ExpenseCategory, title: String = "") -> Expense {
        Expense(
            id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            vehicleId: vehicle.id, date: Date(), odometer: nil,
            money: Money(amount: 12, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .import(source: "drivvo"),
            conflict: .none, purchaseGroupId: nil, category: category, title: title)
    }

    /// The form loads the stored category. It defaulted to `.accessory` for
    /// every expense before, so an insurance row opened as an accessory.
    func testTheFormLoadsTheStoredCategory() {
        let form = EditEntryView.pristineNonFillForm(for: expense(.insurance), vehicle: vehicle)
        XCTAssertEqual(form.category, .insurance)
    }

    /// A custom category survives a round trip through the form.
    func testACustomCategorySurvivesLoading() {
        let form = EditEntryView.pristineNonFillForm(for: expense(.other("wash")),
                                                     vehicle: vehicle)
        XCTAssertEqual(form.category, .other("wash"))
    }

    /// Changing the category makes the screen dirty, so the discard guard and
    /// the save button both see it. A field the save path writes but the dirty
    /// check ignores would lose the edit on a swipe-back (hard rule 8).
    func testChangingTheCategoryCountsAsAnEdit() {
        let entry = expense(.parking)
        var form = EditEntryView.pristineNonFillForm(for: entry, vehicle: vehicle)
        XCTAssertEqual(form, EditEntryView.pristineNonFillForm(for: entry, vehicle: vehicle))
        form.category = .fine
        XCTAssertNotEqual(form, EditEntryView.pristineNonFillForm(for: entry, vehicle: vehicle),
                          "a changed category must read as an unsaved edit")
    }

    /// The menu offers the standard list, and keeps a custom category the list
    /// does not carry - otherwise opening the menu on an imported expense would
    /// silently re-type it.
    func testTheMenuKeepsACustomCategoryInTheList() {
        let standard = EditEntryNonFillView.categoryOptions(including: .parking)
        XCTAssertEqual(standard, ExpenseCategory.entryCases)
        XCTAssertTrue(standard.contains(.parking))

        let custom = EditEntryNonFillView.categoryOptions(including: .other("Техосмотр"))
        XCTAssertEqual(custom.first, .other("Техосмотр"),
                       "a stored custom category stays offered, first")
        XCTAssertEqual(custom.count, ExpenseCategory.entryCases.count + 1)
    }
}

/// RV.193: the Edit-entry receipt strip had RV.183's bug one screen over - it
/// formatted the receipt's date-only PRINTED date with a time, so a scanned
/// entry's strip read "Scanned 9 Sep at 00:00". It now names the capture
/// instant, which is a real instant and does carry a time.
@MainActor
final class RV193ReceiptStripCaptionTests: XCTestCase {

    private let vehicle = TargetCar.newCar(named: "Test car", homeCurrency: .eur).vehicleValue

    private func attachment(printed: Date?, captured: Date) -> Attachment {
        Attachment(id: UUID.v7(), createdAt: captured, updatedAt: captured,
                   kind: .photo,
                   file: LocalFileRef(sha256: String(repeating: "a", count: 64),
                                      relativePath: "receipt.jpg"),
                   extractedTimestamp: printed)
    }

    private func entry() -> Expense {
        Expense(id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
                vehicleId: vehicle.id, date: Date(), odometer: nil, money: nil,
                note: nil, attachments: [], provenance: .receiptScan,
                conflict: .none, purchaseGroupId: nil, category: .parts, title: "Blades")
    }

    /// A receipt printed on a date-only day, captured at a real time: the strip
    /// must show the CAPTURE time, never a fabricated midnight.
    func testTheStripNamesTheCaptureInstantNotThePrintedDate() {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 9
        let printedMidnight = Calendar.current.date(from: components)!
        let captured = printedMidnight.addingTimeInterval(14 * 3600 + 32 * 60)

        let line = ReceiptCardView.scannedLine(
            attachments: [attachment(printed: printedMidnight, captured: captured)],
            entry: entry())

        let text = line
        XCTAssertNotNil(text, "a scanned attachment must produce a caption")
        XCTAssertFalse(text?.contains("12:00 AM") ?? true,
                       "the strip must not print the printed date's fabricated midnight")
        XCTAssertFalse(text?.contains("00:00") ?? true)
        XCTAssertTrue(text?.contains("Captured") ?? false,
                      "the caption names the capture, not the scan's printed date")
    }

    /// An attachment with no recognition pass keeps the "Added <date>" form,
    /// and that one is date-only - so it carries no time either.
    func testAnUnrecognisedAttachmentStillReadsAdded() {
        let line = ReceiptCardView.scannedLine(
            attachments: [attachment(printed: nil, captured: Date())],
            entry: entry())
        XCTAssertTrue(line?.contains("Added") ?? false)
        XCTAssertFalse(line?.contains(":") ?? true, "a date-only value renders no time")
    }

    /// No attachment, no caption - the empty state's own affordance is the
    /// whole message.
    func testNoAttachmentYieldsNoCaption() {
        XCTAssertNil(ReceiptCardView.scannedLine(attachments: [], entry: entry()))
    }
}
