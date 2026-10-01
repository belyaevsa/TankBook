import XCTest

// MARK: - PJ.41 "Add expense from this receipt"

/// An entry with a receipt photo offers to log another purchase from the same
/// receipt; an entry without one does not. The action opens the Expense sheet
/// filed with that receipt.
@MainActor
extension EditEntryUITests {

    private var pj41FixturesRoot: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // EditEntryPJ41UITests.swift
            .deletingLastPathComponent()  // UITests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // ios
            .appendingPathComponent("Spike/ReceiptSpike/fixtures")
            .path
    }

    func testAnEntryWithAReceiptOffersAnExpenseFromIt() {
        let fixture = pj41FixturesRoot + "/service/service-004-tireman-peterburi-tyre-change-storage-pdf-ee.png"
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedEditEntryServicePages",
                               "-presentScreen", "editEntry",
                               "-attachReceiptFixtureImage", fixture]
        app.launch()

        let action = app.buttons["editEntryAddExpenseFromReceipt"]
        XCTAssertTrue(action.waitForExistence(timeout: 10),
                      "an entry with a receipt photo must offer an expense from it")
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(action.frame), "the action sits on screen, under the receipt")
        action.tap()
        XCTAssertTrue(app.otherElements["expenseEntryLinkedReceiptNote"].waitForExistence(timeout: 10)
                      || app.staticTexts["expenseEntryLinkedReceiptNote"].exists,
                      "the Expense sheet opens filed with the same receipt")
    }

    func testAnEntryWithoutAReceiptDoesNotOfferIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedEditEntryService",
                               "-presentScreen", "editEntry"]
        app.launch()

        XCTAssertTrue(app.buttons["editEntrySaveButton"].waitForExistence(timeout: 10),
                      "Edit entry must have loaded before the absence means anything")
        XCTAssertFalse(app.buttons["editEntryAddExpenseFromReceipt"].exists,
                       "no photo, no receipt to add an expense from")
    }
}
