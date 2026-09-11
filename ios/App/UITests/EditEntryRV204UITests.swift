import XCTest

// MARK: - RV.204 the shared degrade contract, end to end

/// The row's user-facing half: a failed receipt-photo write on Edit entry must
/// DEGRADE on every entry kind - the save the user asked for lands, the shared
/// "could not be kept" toast reports it after the entry is on disk (docs/ERRORS.md
/// -> Edit entry, RV.204), and the old fill-up-only warn row never appears.
///
/// Kept as an extension of `EditEntryUITests` (its own file, so the base file
/// stays under the lint ceiling - the `EditEntryRV202UITests` precedent). EN and
/// RU for both entry kinds, because the toast is the shared long sentence and
/// Russian is where it runs longest.
///
/// The failure is forced by `-seedAttachReceiptWriteFails`: the attach fixture
/// resolves to an empty image, so `jpegData` returns nil exactly as a disk-full
/// or unencodable frame would on Save.
@MainActor
extension EditEntryUITests {

    private func launchOnTypedFillWithFailingAttach(russian: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-homeResetDatabase", "-seedEditEntryTyped",
                    "-presentScreen", "editEntry", "-seedAttachReceiptWriteFails"]
        if russian {
            args += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        }
        app.launchArguments = args
        app.launch()
        return app
    }

    private func launchOnServiceWithFailingAttach(russian: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-homeResetDatabase", "-seedEditEntryService",
                    "-presentScreen", "editEntry", "-seedAttachReceiptWriteFails"]
        if russian {
            args += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        }
        app.launchArguments = args
        app.launch()
        return app
    }

    /// Drive the real attach flow (Add receipt -> Photos -> wait for the OCR to
    /// settle -> Save) and return the app with the save in flight. The source
    /// chooser's "Photos" button is localised, so the caller passes its label.
    private func attachAndSave(_ app: XCUIApplication, photosLabel: String) {
        let add = app.buttons["editAddReceiptButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 10),
                      "an entry with no receipt must offer 'Add receipt'")
        add.tap()
        let photos = app.buttons[photosLabel]
        XCTAssertTrue(photos.waitForExistence(timeout: 5))
        photos.tap()

        let ready = app.otherElements["editAttachReady"]
        XCTAssertTrue(ready.waitForExistence(timeout: 15),
                      "the attach must settle into the ready state after OCR")

        let save = app.buttons["editEntrySaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled, "a failing photo write must never gate the save")
        save.tap()
    }

    private var englishMessage: String {
        "No space to keep the receipt photo – the entry was saved without it. "
            + "Free up space and re-scan it."
    }

    private var russianMessage: String {
        "Не хватило места для фото чека – запись сохранена без него. "
            + "Освободите место и отсканируйте чек снова."
    }

    /// The fill-up edit path: the save lands and the user is told. The old
    /// behaviour blocked and showed `editAttachFailedWarn` with the entry
    /// unchanged - this test fails on that build because the entry never saves.
    func testFailedFillUpEditPhotoWriteDegradesAndTellsTheUser() {
        let app = launchOnTypedFillWithFailingAttach(russian: false)
        attachAndSave(app, photosLabel: "Photos")

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5),
                      "the fill-up edit must save even though its receipt photo could not")
        XCTAssertTrue(app.staticTexts[englishMessage].waitForExistence(timeout: 5),
                      "a lost receipt photo must be reported, never silent (hard rule 8)")
        XCTAssertFalse(app.otherElements["editAttachFailedWarn"].exists,
                       "the old blocking warn row must be gone - RV.204 degrades everywhere")
    }

    func testFailedFillUpEditPhotoWriteTellsTheUserInRussian() {
        let app = launchOnTypedFillWithFailingAttach(russian: true)
        attachAndSave(app, photosLabel: "Фото")

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[russianMessage].waitForExistence(timeout: 5),
                      "the Russian report must render in full, never truncated")
    }

    /// The non-fill path shares the screen, so it shares the contract - the
    /// half RV.202 added and RV.204 aligned the fill-up to.
    func testFailedServiceEditPhotoWriteDegradesAndTellsTheUser() {
        let app = launchOnServiceWithFailingAttach(russian: false)
        attachAndSave(app, photosLabel: "Photos")

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5),
                      "the service edit must save even though its receipt photo could not")
        XCTAssertTrue(app.staticTexts[englishMessage].waitForExistence(timeout: 5),
                      "a lost receipt photo must be reported, never silent (hard rule 8)")
    }

    func testFailedServiceEditPhotoWriteTellsTheUserInRussian() {
        let app = launchOnServiceWithFailingAttach(russian: true)
        attachAndSave(app, photosLabel: "Фото")

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[russianMessage].waitForExistence(timeout: 5),
                      "the Russian report must render in full, never truncated")
    }
}
