import XCTest

/// RV.62 - Expense-mode capture. Reported: a receipt photographed in Expense
/// mode ran the recognition and then landed on a blank expense form - the work
/// was done and discarded. These tests drive the real capture flow (shutter ->
/// the RV.5 review -> "Use this") in Expense mode with a CANNED recognition
/// (`ExpenseScanTestSeed`), and assert what the user SEES: the field value,
/// never that a form appeared.
///
/// The canned recognition deliberately carries liters / unitPrice / fuelKind
/// too - the fill-up recogniser's own output - so these tests prove those
/// fields never reach the expense form. The L1 boundary (`ExpensePrefill`,
/// core) makes that structural; these assert the pixels agree.
@MainActor
final class ExpenseCaptureUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A corpus receipt: the review step must show SOME photo before "Use this"
    /// (the canned recognition replaces OCR, never the review).
    private var fixture: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ExpenseCaptureUITests.swift
            .deletingLastPathComponent()  // UITests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // ios
            .appendingPathComponent("Spike/ReceiptSpike/fixtures/receipts")
            .appendingPathComponent("receipt-011-samara-diesel-ru.png")
            .path
    }

    private func captureExpense(_ seed: String) -> XCUIApplication {
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture),
                      "the corpus fixture is missing: \(fixture)")
        let app = XCUIApplication()
        // No session: RV.197 made the guest Home render the same log stream the
        // signed-in Home does, so these tests assert their saved rows as a
        // guest. Before that fix they needed `-seedSettingsSignedIn` (or they
        // passed on a Keychain session another run left behind); the seed is
        // gone because the guest layout now has the Log.
        app.launchArguments = ["-homeResetDatabase", "-seedHomeEmptyVehicle",
                               "-presentScreen", "capture", "-cameraStatus", "authorized",
                               "-captureMode", "expense", "-captureFixtureImage", fixture,
                               seed]
        app.launch()
        XCTAssertTrue(app.buttons["captureCloseButton"].waitForExistence(timeout: 10),
                      "the capture cover must be present")
        return app
    }

    /// The real capture path: shutter -> review -> "Use this".
    private func shootAndUse(_ app: XCUIApplication) {
        let shutter = app.buttons["captureShutterButton"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10), "captureShutterButton never appeared")
        shutter.tap()
        let useThis = app.buttons["captureReviewUseButton"]
        XCTAssertTrue(useThis.waitForExistence(timeout: 15),
                      "the RV.5 review must appear after the shutter")
        useThis.tap()
    }

    private func fieldValue(_ app: XCUIApplication, _ identifier: String) -> String {
        (app.textFields[identifier].value as? String) ?? ""
    }

    /// A field is BLANK when its text is empty OR still shows its placeholder
    /// (an empty SwiftUI TextField exposes its placeholder as the `value` - the
    /// amount field reads "0.00" while blank). The collapse is safe here: a
    /// pre-fill is never a literal zero, because the extraction maps nil to nil
    /// and zeroes a total before it can leak (core, L1).
    private func isFieldBlank(_ app: XCUIApplication, _ identifier: String) -> Bool {
        let field = app.textFields[identifier]
        let value = (field.value as? String) ?? ""
        let placeholder = field.placeholderValue ?? ""
        return value.isEmpty || (!placeholder.isEmpty && value == placeholder)
    }

    /// The pre-fill must land in the AMOUNT FIELD - asserting the form opened
    /// passes against the bug. Assert the value, that it is editable, and that
    /// the fill-up confirm sheet is nowhere on screen.
    func testExpenseModeScanOpensTheExpenseFormWithTheTotalPrefilledAndEditable() {
        let app = captureExpense("-seedExpenseScan")
        shootAndUse(app)

        let amount = app.textFields["expenseEntryAmountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 15),
                      "an Expense-mode scan must land on the expense entry form")
        XCTAssertEqual(fieldValue(app, "expenseEntryAmountField"), "71.02",
                       "the recognised total must pre-fill the amount field")
        XCTAssertTrue(amount.isEnabled, "a pre-filled amount is default input, never read-only")

        // Not the fill-up confirm sheet - the pre-fill went to the EXPENSE form.
        XCTAssertFalse(app.textFields["manualFillUpTotalField"].exists,
                       "the expense scan must not present the fill-up confirm sheet")
        XCTAssertFalse(app.textFields["manualFillUpLitersField"].exists,
                       "the expense scan must not present the fill-up liters field")

        // Editable at the moment it is offered (hard rule 13): type and the
        // value changes.
        amount.tap()
        amount.typeText("0")
        XCTAssertNotEqual(fieldValue(app, "expenseEntryAmountField"), "71.02",
                          "a pre-filled amount must stay editable")
    }

    /// An extraction that resolves nothing lands the EMPTY expense form and no
    /// error (hard rule 7) - the same contract the fill-up path honours.
    func testExpenseModeScanThatResolvesNothingOpensTheEmptyFormWithNoError() {
        let app = captureExpense("-seedExpenseScanEmpty")
        shootAndUse(app)

        let amount = app.textFields["expenseEntryAmountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 15),
                      "an empty extraction must still open the expense form, never an error")
        XCTAssertTrue(isFieldBlank(app, "expenseEntryAmountField"),
                      "an extraction that resolved nothing pre-fills no amount")
        XCTAssertTrue(isFieldBlank(app, "expenseEntryTitleField"),
                      "an extraction that resolved nothing pre-fills no title")
        XCTAssertFalse(app.alerts.firstMatch.exists,
                       "an empty extraction is not an error - no alert may appear")
    }

    /// The honesty gate behind the carried currency: the expense form is
    /// home-currency only, so a total the recognition priced in another
    /// currency must not be offered as if it were home money. The field stays
    /// blank for the user to type - a scan never mints a wrong-currency fact.
    func testForeignTotalIsNotOfferedAsHomeCurrency() {
        let app = captureExpense("-seedExpenseScanForeign")
        shootAndUse(app)

        let amount = app.textFields["expenseEntryAmountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 15))
        XCTAssertTrue(isFieldBlank(app, "expenseEntryAmountField"),
                      "a 289.50 PLN total must not pre-fill a home-EUR amount field")
        XCTAssertFalse(app.alerts.firstMatch.exists,
                       "a currency the form cannot express is not an error")
    }

    /// RV.200: an Expense-mode scan reads the KIND of expense and offers it as
    /// a suggestion - preselected and editable (hard rule 13). The parking seed
    /// carries a ticket's OCR lines, so the SHIPPED vocabulary produces the
    /// category; the test asserts the form's category control reads "Parking"
    /// and that the user can change it before saving.
    func testExpenseModeScanPreselectsTheInferredCategoryAndStaysEditable() {
        let app = captureExpense("-seedExpenseScanParking")
        shootAndUse(app)

        let category = app.buttons["expenseEntryCategory"]
        XCTAssertTrue(category.waitForExistence(timeout: 15),
                      "an Expense-mode scan must land on the expense entry form")
        XCTAssertTrue(categoryShows(app, "Parking"),
                      "a parking scan must preselect Parking; control label was '\(category.label)'")

        // Editable at the moment it is offered (hard rule 13): choose another
        // category and the control changes.
        category.tap()
        let toll = app.buttons["Toll"].exists ? app.buttons["Toll"] : app.staticTexts["Toll"]
        XCTAssertTrue(toll.waitForExistence(timeout: 5),
                      "the category menu must offer the other kinds")
        toll.tap()
        XCTAssertTrue(categoryShows(app, "Toll"),
                      "the suggested category must stay editable; control label was '\(category.label)'")
    }

    /// The category control's value, however SwiftUI exposes it (the Menu's own
    /// label or the text it renders).
    private func categoryShows(_ app: XCUIApplication, _ label: String) -> Bool {
        app.buttons["expenseEntryCategory"].label.contains(label)
            || app.staticTexts[label].exists
    }

    /// PJ.28 - the whole remaining row: a scanned expense KEEPS its receipt.
    /// The pre-fill half shipped in RV.62 (asserting it here is the row's named
    /// vacuous trap); this drives the real capture -> save -> entry path and
    /// asserts the photo is attached to the SAVED expense and opens full-size
    /// from it, the way a fill-up's receipt does. The chip is a control, so
    /// "the photo is there" is proven by opening it, never by a paperclip.
    func testScannedExpenseSavesWithItsReceiptOpenableFromTheSavedEntry() {
        let app = captureExpense("-seedExpenseScan")
        shootAndUse(app)

        // A title is one peer path, not a requirement (RV.206): the scan is
        // saved with a typed title here to prove the receipt rides the save.
        let title = app.textFields["expenseEntryTitleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 15),
                      "an Expense-mode scan must land on the expense entry form")
        title.tap()
        title.typeText("Wiper blades")
        app.buttons["expenseEntrySaveButton"].tap()

        // The save returns to Home with the expense in the log.
        let row = app.buttons["logEntryButton"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15),
                      "the saved expense must appear in the log")
        row.tap()

        // The entry's receipt strip renders the attached photo as a tappable
        // control (the receipt is reachable, not merely referenced).
        let chip = app.buttons["attachmentPhotoChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15),
                      "the saved expense must carry its receipt photo (PJ.28)")
        XCTAssertTrue(chip.isHittable,
                      "the receipt must be a control the user can tap")
        chip.tap()

        // And it opens full-size, exactly as a fill-up's receipt does.
        let image = app.descendants(matching: .any)["attachmentViewerImage"]
        XCTAssertTrue(image.waitForExistence(timeout: 10),
                      "tapping the receipt must open the attachment viewer")
        XCTAssertTrue(image.isHittable,
                      "the full-size photo must be visible, not merely present")
    }

    /// RV.206 - a scan that read the category and the amount must be saveable
    /// WITHOUT typing. This drives the real capture -> save -> Log path and
    /// asserts the entry is in the Log and its row is named from the category
    /// (RV.187). Asserting the button is enabled alone would pass while the
    /// save still demanded a title - the vacuous trap this row names.
    func testAScanThatReadCategoryAndAmountSavesWithoutTypingAndAppearsInTheLog() {
        let app = captureExpense("-seedExpenseScanParking")
        shootAndUse(app)

        let category = app.buttons["expenseEntryCategory"]
        XCTAssertTrue(category.waitForExistence(timeout: 15),
                      "an Expense-mode scan must land on the expense entry form")
        XCTAssertTrue(categoryShows(app, "Parking"),
                      "the parking scan must preselect Parking; control was '\(category.label)'")
        XCTAssertFalse(isFieldBlank(app, "expenseEntryAmountField"),
                       "the parking scan must pre-fill the amount it read")

        // No title is typed: the category names the row, so Save is reachable.
        let save = app.buttons["expenseEntrySaveButton"]
        XCTAssertTrue(save.isEnabled,
                      "a scan that read a category and an amount must be saveable")
        save.tap()

        let row = app.buttons["logEntryButton"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15),
                      "the scanned expense must appear in the log without a title")
        XCTAssertTrue(row.label.contains("Parking"),
                      "the Log row must be named from the category (RV.187); was '\(row.label)'")
    }
}
