import XCTest

// MARK: - RV.331 every page of an entry, and one more

/// An entry kept as several pages shows every one, the viewer steps between
/// them, and "Add page" takes one more after the first - the service a
/// workshop invoice becomes has three pages, not one.
@MainActor
extension EditEntryUITests {

    private var rv331FixturesRoot: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // EditEntryRV331UITests.swift
            .deletingLastPathComponent()  // UITests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // ios
            .appendingPathComponent("Spike/ReceiptSpike/fixtures")
            .path
    }

    private func launchOnServicePages() -> XCUIApplication {
        let fixture = rv331FixturesRoot + "/service/service-004-tireman-peterburi-tyre-change-storage-pdf-ee.png"
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedEditEntryServicePages",
                               "-presentScreen", "editEntry",
                               "-attachReceiptFixtureImage", fixture]
        app.launch()
        return app
    }

    func testEveryPageShowsAndTheViewerStepsBetweenThem() {
        let app = launchOnServicePages()

        let first = app.buttons["attachmentPhotoChip"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), "page 1 must show")
        XCTAssertTrue(app.buttons["attachmentPhotoChip_1"].exists, "page 2 must show")
        XCTAssertTrue(app.buttons["attachmentPhotoChip_2"].exists, "page 3 must show")

        app.buttons["attachmentPhotoChip_2"].tap()
        let previous = app.buttons["attachmentViewerPreviousPage"]
        XCTAssertTrue(previous.waitForExistence(timeout: 10),
                      "a multi-page entry's viewer must offer the other pages")
        XCTAssertFalse(app.buttons["attachmentViewerNextPage"].isEnabled, "page 3 of 3 has no next")
        XCTAssertTrue(app.navigationBars["Page 3 of 3"].exists, "the viewer names the page on screen")
        previous.tap()
        XCTAssertTrue(app.navigationBars["Page 2 of 3"].waitForExistence(timeout: 5),
                      "previous must step to page 2")
    }

    func testAddPageTakesOneMoreAfterTheFirst() {
        let app = launchOnServicePages()

        let add = app.buttons["editAddPageButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 10),
                      "an entry that has pages must still offer Add page")
        add.tap()
        let photos = app.buttons["Photos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 5))
        photos.tap()

        XCTAssertTrue(app.otherElements["editAttachReady"].waitForExistence(timeout: 20),
                      "the added page must settle before Save")
        let save = app.buttons["editEntrySaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))
        let row = app.buttons.matching(identifier: "logEntryButton").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["attachmentPhotoChip_3"].waitForExistence(timeout: 10),
                      "the added page must be the entry's fourth after save")
    }
}
