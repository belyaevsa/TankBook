import XCTest

/// RV.333: the expense form shows the receipt it was scanned from, takes one
/// more page, opens a page full size, and saves every page with the entry.
@MainActor
final class ExpensePagesRV333UITests: XCTestCase {
    private var fixture: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ExpensePagesRV333UITests.swift
            .deletingLastPathComponent()  // UITests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // ios
            .appendingPathComponent("Spike/ReceiptSpike/fixtures/receipts/receipt-011-samara-diesel-ru.png")
            .path
    }

    override func setUp() {
        continueAfterFailure = false
    }

    private func page(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        app.buttons["expenseEntryPage_\(index)"]
    }

    func testTheScannedReceiptShowsAndAPageIsAddedAndSaved() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedHomeEmptyVehicle",
                               "-presentScreen", "capture", "-cameraStatus", "authorized",
                               "-captureMode", "expense", "-captureFixtureImage", fixture,
                               "-attachReceiptFixtureImage", fixture, "-seedExpenseScan"]
        app.launch()

        let shutter = app.buttons["captureShutterButton"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        shutter.tap()
        let useThis = app.buttons["captureReviewUseButton"]
        XCTAssertTrue(useThis.waitForExistence(timeout: 15))
        useThis.tap()

        XCTAssertTrue(page(app, 0).waitForExistence(timeout: 15),
                      "the expense form must show the receipt it was scanned from")
        let add = app.buttons["expenseEntryAddPageButton"]
        XCTAssertTrue(add.exists, "the expense form must offer Add page")
        add.tap()
        let photos = app.buttons["expenseEntryAddPagePhotos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["expenseEntryAddPageScan"].exists)
        photos.tap()
        XCTAssertTrue(page(app, 1).waitForExistence(timeout: 10), "the added page must be page 2")

        page(app, 1).tap()
        XCTAssertTrue(app.navigationBars["Page 2 of 2"].waitForExistence(timeout: 10),
                      "a page must open full size, named by its place")
        app.buttons["pageViewerClose"].tap()

        let save = app.buttons["expenseEntrySaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()

        let row = app.buttons.matching(identifier: "logEntryButton").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(app.buttons["attachmentPhotoChip_1"].waitForExistence(timeout: 10),
                      "both pages must be saved with the expense")
    }
}
