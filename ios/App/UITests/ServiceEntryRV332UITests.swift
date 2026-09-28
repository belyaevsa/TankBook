import XCTest

// MARK: - RV.332 the service form's pages: open one, and a typed service's invoice

/// A page on the service form opens full size, and a service started by
/// typing has its own door for the invoice - the scanner or a photo already in
/// Photos - which lands the page in the strip.
@MainActor
extension ServiceEntryUITests {

    private var rv332Fixture: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ServiceEntryRV332UITests.swift
            .deletingLastPathComponent()  // UITests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // ios
            .appendingPathComponent("Spike/ReceiptSpike/fixtures/service/"
                                    + "service-004-tireman-peterburi-tyre-change-storage-pdf-ee.png")
            .path
    }

    func testTypedServiceAddsItsInvoiceAndOpensThePage() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedVehicleForUITests",
                               "-presentScreen", "serviceEntry",
                               "-attachReceiptFixtureImage", rv332Fixture]
        app.launch()

        let door = app.buttons["serviceEntryAddInvoiceButton"]
        XCTAssertTrue(door.waitForExistence(timeout: 10),
                      "a typed service must offer a door for its invoice")
        door.tap()
        XCTAssertTrue(app.buttons["serviceEntryAddInvoiceScan"].waitForExistence(timeout: 5),
                      "the door must offer the scanner")
        app.buttons["serviceEntryAddInvoicePhotos"].tap()

        let page = app.buttons["serviceEntryPage_0"]
        XCTAssertTrue(page.waitForExistence(timeout: 15), "the picked invoice must become page 1")
        XCTAssertFalse(app.buttons["serviceEntryAddInvoiceButton"].exists,
                       "the strip takes the door's place once a page exists")

        page.tap()
        XCTAssertTrue(app.buttons["pageViewerClose"].waitForExistence(timeout: 10),
                      "tapping a page must open it full size")
        app.buttons["pageViewerClose"].tap()

        // A second page joins the strip and the viewer steps between them.
        app.buttons["serviceEntryAddPageButton"].tap()
        XCTAssertTrue(app.buttons["serviceEntryAddPagePhotos"].waitForExistence(timeout: 5))
        app.buttons["serviceEntryAddPagePhotos"].tap()
        let second = app.buttons["serviceEntryPage_1"]
        XCTAssertTrue(second.waitForExistence(timeout: 15), "the added page must be page 2")
        second.tap()
        XCTAssertTrue(app.navigationBars["Page 2 of 2"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["pageViewerPrevious"].isEnabled)
    }
}
