import XCTest

// MARK: - RV.202 give a service a receipt

/// Kept as an extension of `EditEntryUITests` (its own file, so the base file
/// stays under the lint ceiling - the `EditEntryRV198UITests` precedent).
///
/// The row's own acceptance, end to end: a service opened in Edit entry with no
/// attachment offers "Add receipt" (the non-fill form used to render no card at
/// all), takes a photo through the same camera/Photos door the fill-up uses,
/// and the attached receipt then opens in the viewer. The viewer assertion is
/// what a button-exists test cannot prove; EN and RU, because the affordance's
/// label is exactly the short string Russian expands.
@MainActor
extension EditEntryUITests {

    /// The corpus fixtures live on the host; the simulator shares the host
    /// filesystem, so the app under test reads a fixture by its host path -
    /// passed through `-attachReceiptFixtureImage` - and OCRs it for real.
    private var rv202FixturesRoot: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // EditEntryRV202UITests.swift
            .deletingLastPathComponent()  // UITests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // ios
            .appendingPathComponent("Spike/ReceiptSpike/fixtures")
            .path
    }

    private func launchOnServiceWithReceiptFixture(russian: Bool) -> XCUIApplication {
        let fixture = rv202FixturesRoot + "/receipts/receipt-011-samara-diesel-ru.png"
        let app = XCUIApplication()
        var args = ["-homeResetDatabase", "-seedEditEntryService",
                    "-presentScreen", "editEntry",
                    "-attachReceiptFixtureImage", fixture]
        if russian {
            args += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        }
        app.launchArguments = args
        app.launch()
        return app
    }

    /// A service that arrived without a photo must offer "Add receipt", take
    /// one, save, and then open the attached receipt in the viewer. The final
    /// assertion is the VIEWER opening over the reloaded receipt, never merely
    /// that the button existed.
    func testAttachingAReceiptToAServiceOffersAddThenOpensTheViewer() {
        let app = launchOnServiceWithReceiptFixture(russian: false)

        let add = app.buttons["editAddReceiptButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 10),
                      "a service with no receipt must offer 'Add receipt'")
        add.tap()

        // The "Photos" door resolves the fixture directly (the out-of-process
        // picker cannot be driven), so this is the real attach path.
        let photos = app.buttons["Photos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 5))
        photos.tap()

        let ready = app.otherElements["editAttachReady"]
        XCTAssertTrue(ready.waitForExistence(timeout: 15),
                      "the attach must settle into the ready state after OCR")

        let save = app.buttons["editEntrySaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))
        let row = app.buttons.matching(identifier: "logEntryButton").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let chip = app.descendants(matching: .any)
            .matching(identifier: "attachmentPhotoChip").firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10),
                      "the service must render its attached receipt chip after reload")
        chip.tap()
        XCTAssertTrue(app.buttons["attachmentViewerCloseButton"].waitForExistence(timeout: 10),
                      "tapping the chip must open the receipt viewer")
    }

    /// The RU pass: the new "Add receipt" affordance renders its localised
    /// label, and the door it opens still works - the short-string overflow the
    /// EN+RU convention exists to catch (CLAUDE.md).
    func testAttachingAReceiptToAServiceRendersInRussian() {
        let app = launchOnServiceWithReceiptFixture(russian: true)

        let add = app.buttons["editAddReceiptButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 10),
                      "the RU service must offer the add-receipt affordance")
        XCTAssertEqual(add.label, "Добавить чек",
                       "the affordance must carry its Russian label, got '\(add.label)'")
        add.tap()

        let photos = app.buttons["Фото"]
        XCTAssertTrue(photos.waitForExistence(timeout: 5),
                      "the RU source chooser must render its localised Photos button")
        photos.tap()

        let ready = app.otherElements["editAttachReady"]
        XCTAssertTrue(ready.waitForExistence(timeout: 15),
                      "the RU attach must settle into the ready state after OCR")
    }
}
