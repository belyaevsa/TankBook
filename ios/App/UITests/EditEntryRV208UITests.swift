import XCTest

// MARK: - RV.208 the photo for an entry that was never saved

/// The row's user-facing half, end to end. A phone can carry an entry whose
/// receipt photo was never written (RV.173's dangling id); the reference is left
/// in place - "no live Attachment row" is not locally distinguishable from "not
/// pulled yet" (docs/SYNC.md -> Attachments) - so Edit entry must SHOW the
/// missing photo and offer the re-attach door, never render the ordinary empty
/// card that implies there was never a receipt.
///
/// Kept as an extension of `EditEntryUITests` (its own file, so the base file
/// stays under the lint ceiling - the `EditEntryRV202UITests` precedent). EN and
/// RU, because the headline and the next step are exactly the copy that
/// overflows when Russian expands.
@MainActor
extension EditEntryUITests {

    private func launchOnDanglingReceipt(russian: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-homeResetDatabase", "-seedEditEntryDanglingReceipt",
                    "-presentScreen", "editEntry"]
        if russian {
            args += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        }
        app.launchArguments = args
        app.launch()
        return app
    }

    /// The dangling reference is surfaced, not swallowed: the card names the
    /// missing photo and the re-attach door opens the same camera/Photos chooser
    /// the empty card uses. The final assertion is the CHOOSER appearing over
    /// the real card - a test that only checked the button existed would pass a
    /// card whose action does nothing.
    func testAnEntryWhosePhotoWasNeverSavedShowsTheMissingCardAndItsNextStep() {
        let app = launchOnDanglingReceipt(russian: false)

        XCTAssertTrue(app.staticTexts["The photo for this entry was never saved"].waitForExistence(timeout: 10),
                      "an entry with no live attachment row must show the missing-photo card")

        let add = app.buttons["editAddReceiptButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5),
                      "the next step is re-attaching, so the add-receipt door must be offered")
        add.tap()

        XCTAssertTrue(app.buttons["Photos"].waitForExistence(timeout: 5),
                      "the re-attach door must open the same camera/Photos chooser")
    }

    /// The RU pass: the headline and the next step are the copy that overflows
    /// worst when Russian expands, and the re-attach door still works.
    func testAnEntryWhosePhotoWasNeverSavedRendersInRussian() {
        let app = launchOnDanglingReceipt(russian: true)

        XCTAssertTrue(app.staticTexts["Фото для этой записи так и не сохранилось"].waitForExistence(timeout: 10),
                      "the RU entry must show the localised missing-photo headline")

        let add = app.buttons["editAddReceiptButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5),
                      "the RU re-attach door must be offered")
        XCTAssertEqual(add.label, "Добавить чек",
                       "the affordance must carry its Russian label, got '\(add.label)'")
        add.tap()
        XCTAssertTrue(app.buttons["Фото"].waitForExistence(timeout: 5),
                      "the RU re-attach door must open the localised chooser")
    }

    /// The guard against a false positive: an entry whose photo DID save shows
    /// its receipt chip, never the missing card. Without this, a card rendered
    /// for every entry would pass the tests above.
    func testAnEntryWithARealReceiptDoesNotShowTheMissingCard() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedEditEntryScannedExpense",
                               "-presentScreen", "editEntry"]
        app.launch()

        let chip = app.descendants(matching: .any)
            .matching(identifier: "attachmentPhotoChip").firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10),
                      "a saved receipt must render its chip")
        XCTAssertFalse(app.staticTexts["The photo for this entry was never saved"].exists,
                       "a resolved attachment must never render the missing-photo card")
    }
}
