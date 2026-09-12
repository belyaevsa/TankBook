import XCTest

// MARK: - PJ.61 the part-number field on the service item card

/// Kept as an extension of `EditEntryUITests` (its own file, so the base file
/// stays under the lint ceiling - the `EditEntryPJ22UITests` precedent).
///
/// The row's acceptance, end to end: a service line item's **part number** can
/// be read, edited and re-read on Edit entry. EN and RU, because "Номер детали"
/// is the longest label the narrow item card carries.
@MainActor
extension EditEntryUITests {

    private func launchOnService(pj61Russian russian: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-homeResetDatabase", "-seedEditEntryService",
                    "-presentScreen", "editEntry"]
        if russian {
            args += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        }
        app.launchArguments = args
        app.launch()
        return app
    }

    /// The first item's part-number field. The seed gives it "MANN W 712/75".
    private func partNumberField(_ app: XCUIApplication) -> XCUIElement {
        app.textFields.matching(identifier: "editEntryServiceItemPartNumber").firstMatch
    }

    /// Replaces a text field's contents without the text-selection edit menu
    /// (unreliable on the iOS 26 simulator): scroll it into view, tap it, delete
    /// the current text one keystroke at a time, then type the replacement.
    private func replacePartNumber(in field: XCUIElement, with text: String,
                                   app: XCUIApplication) {
        if app.keyboards.firstMatch.exists { app.swipeDown() }
        var attempts = 0
        while !field.isHittable && attempts < 8 {
            app.scrollViews.firstMatch.swipeUp()
            attempts += 1
        }
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let current = (field.value as? String) ?? ""
        if !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                                  count: current.count))
        }
        field.typeText(text)
    }

    private func saveAndReopenNewestEntry(_ app: XCUIApplication) {
        if app.keyboards.firstMatch.exists { app.swipeDown() }
        let save = app.buttons["editEntrySaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))

        let row = app.buttons.matching(identifier: "logEntryButton").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
    }

    func testTheStoredPartNumberRendersAndRoundTripsThroughTheEditor() {
        let app = launchOnService()
        let field = partNumberField(app)
        XCTAssertTrue(field.waitForExistence(timeout: 10),
                      "the item card must render the part-number field")
        XCTAssertEqual(field.value as? String, "MANN W 712/75",
                       "the stored part number must load into the field")

        replacePartNumber(in: field, with: "MAHLE LA 123", app: app)
        saveAndReopenNewestEntry(app)

        let reopened = partNumberField(app)
        XCTAssertTrue(reopened.waitForExistence(timeout: 10))
        XCTAssertEqual(reopened.value as? String, "MAHLE LA 123",
                       "the edited part number must persist across save and reopen")
    }

    func testThePartNumberFieldRendersInRussian() {
        let app = launchOnService(pj61Russian: true)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "editEntryServiceItemPartNumberLabel").firstMatch
            .waitForExistence(timeout: 10),
            "the part-number label must render in RU")
        XCTAssertTrue(partNumberField(app).waitForExistence(timeout: 10),
                      "the part-number field must render in RU")
        XCTAssertEqual(partNumberField(app).value as? String, "MANN W 712/75",
                       "the stored part number must load in RU too")
    }
}
