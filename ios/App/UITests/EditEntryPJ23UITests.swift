import XCTest

// MARK: - PJ.23 edit a service's line items

/// Kept as an extension of `EditEntryUITests` (its own file, so the base file
/// stays under the lint ceiling - the `EditEntryRV144UITests` precedent).
///
/// The row's own acceptance, end to end: a service opens showing its LINE
/// ITEMS (the screen used to show only a Vendor field), an item's title can be
/// changed, the change persists, and the Log row - titled from the first named
/// item since [RV.187] - follows it. EN and RU, because the item row is where a
/// localised category label sits beside a cost and Russian runs 20-30% longer.
@MainActor
extension EditEntryUITests {

    private func launchOnService(russian: Bool = false) -> XCUIApplication {
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

    /// Replaces a text field's contents without the text-selection edit menu
    /// (unreliable on the iOS 26 simulator): tap the field's right edge, delete
    /// the current text one keystroke at a time, type the replacement. The
    /// keyboard can cover the lower cards, so it is dropped first.
    private func replaceFieldText(in field: XCUIElement, with text: String,
                                  app: XCUIApplication) {
        if app.keyboards.firstMatch.exists {
            app.swipeDown()
        }
        var attempts = 0
        while field.frame.minY > 300 && attempts < 8 {
            app.scrollViews.firstMatch.swipeUp()
            attempts += 1
        }
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let current = (field.value as? String) ?? ""
        if !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                                  count: current.count))
        }
        field.typeText(text)
    }

    /// The row's acceptance: open a service, change an item's title, save,
    /// reopen and see it - and the Log row follows the edited item.
    func testEditingAServiceItemTitlePersistsAndRenamesTheLogRow() {
        let app = launchOnService()

        let title = app.textFields["editEntryServiceItemTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10),
                      "the service's first line item must be editable")
        XCTAssertEqual(title.value as? String, "Oil service incl. filter",
                       "the stored item title must load into the field")
        replaceFieldText(in: title, with: "Timing belt", app: app)
        XCTAssertEqual(title.value as? String, "Timing belt",
                       "the item title field must hold the edited value")

        let save = app.buttons["editEntrySaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // RV.187 tie: the Log row is titled from the first named line item plus
        // a count of the rest ("Timing belt and 1 more" - the seed has two).
        // Oracle: EntryTitle.serviceTitle -> L10n.serviceItemsTitle.
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10),
                      "saving must return to Home")
        XCTAssertTrue(app.staticTexts["Timing belt and 1 more"].waitForExistence(timeout: 10),
                      "the Log row must follow the edited item title")

        // Reopen and see the edit round-trip.
        let row = app.buttons.matching(identifier: "logEntryButton").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let reopened = app.textFields["editEntryServiceItemTitle"].firstMatch
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        XCTAssertEqual(reopened.value as? String, "Timing belt",
                       "the edited item title must persist across a reopen")
    }

    /// The RU pass: the item row renders its localised labels and the same
    /// round-trip works - the layout check is the committed screenshot, this
    /// proves the fields are reachable and functional in Russian.
    func testEditingAServiceItemTitleInRussian() {
        let app = launchOnService(russian: true)

        let title = app.textFields["editEntryServiceItemTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10),
                      "the line item must render in RU")
        XCTAssertTrue(app.buttons["editEntryServiceItemCategory"].firstMatch.exists,
                      "the category chooser must render in RU")
        replaceFieldText(in: title, with: "Timing belt", app: app)

        app.buttons["editEntrySaveButton"].tap()
        let row = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Timing belt")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "the RU round-trip must save and rename the Log row")
    }
}
