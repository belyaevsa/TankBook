import XCTest

// MARK: - RV.199 the line sum beside the independently-editable Amount

/// Kept as an extension of `EditEntryUITests` (its own file, so the base file
/// stays under the lint ceiling - the `EditEntryRV198UITests` precedent).
///
/// The row's own acceptance, end to end: a service opened in Edit entry shows
/// its line sum, adding a line moves that sum, and the mismatch with the Amount
/// is stated and then clears when the Amount is typed to match. The stored
/// Amount is never derived (hard rule 13), which is why the assertion is that
/// the mismatch CLEARS, not that the total was rewritten. EN and RU, because a
/// sum plus a mismatch sentence on one card is where Russian's 20-30% length
/// bites.
@MainActor
extension EditEntryUITests {

    private func launchOnServiceRV199(russian: Bool) -> XCUIApplication {
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

    /// Scrolls until `element` is hittable AND clear of the pinned save bar -
    /// `isHittable` alone turns true while the element's centre is still under
    /// the bar and the tap lands on Save (the RV.80/PJ.7e lie; see
    /// EditEntryRV198UITests.scrollTo).
    private func scrollToRV199(_ element: XCUIElement, app: XCUIApplication) {
        if app.keyboards.firstMatch.exists { app.swipeDown() }
        let bar = app.buttons["editEntrySaveButton"]
        func clearOfBar() -> Bool {
            guard bar.exists else { return true }
            return !element.frame.intersects(bar.frame)
        }
        var attempts = 0
        while (!element.isHittable || !clearOfBar()) && attempts < 10 {
            let scroll = app.scrollViews.firstMatch
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
            attempts += 1
        }
    }

    /// Waits for a static text's LABEL to become `label` - `waitForExistence`
    /// cannot see a label change on an element that already exists.
    private func waitForLabel(_ element: XCUIElement, _ label: String,
                              timeout: TimeInterval = 6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.label == label { return true }
            usleep(100_000)
        }
        return false
    }

    /// Replaces the Amount field's contents: tap the trailing edge, delete the
    /// current digits, type the replacement.
    private func replaceAmountRV199(_ app: XCUIApplication, with text: String) {
        let field = app.textFields["editEntryAmountField"]
        scrollToRV199(field, app: app)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let current = (field.value as? String) ?? ""
        if !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                                  count: current.count))
        }
        field.typeText(text)
    }

    /// Add a line to the seeded service and give it a cost of 50.00.
    private func addLineRV199(_ app: XCUIApplication) {
        let add = app.buttons["editEntryAddServiceItemButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 10),
                      "the service must offer an add affordance")
        scrollToRV199(add, app: app)
        add.tap()
        let costs = app.textFields.matching(identifier: "editEntryServiceItemCost")
        let addedCost = costs.element(boundBy: costs.count - 1)
        scrollToRV199(addedCost, app: app)
        addedCost.tap()
        addedCost.typeText("50.00")
    }

    // MARK: - EN

    func testLineSumMovesWithAnAddedItemAndTheMismatchClearsWhenTheAmountMatches() {
        let app = launchOnServiceRV199(russian: false)

        let sum = app.staticTexts["editEntryLineSumValue"]
        XCTAssertTrue(sum.waitForExistence(timeout: 10),
                      "the money card must state the line sum")
        XCTAssertTrue(waitForLabel(sum, "148.00\u{00A0}€"),
                      "the seed's lines sum to 148.00 - got \(sum.label)")
        XCTAssertFalse(app.staticTexts["editEntryLineSumMismatch"].exists,
                       "the seed's Amount equals its lines, so no mismatch is stated")

        addLineRV199(app)

        XCTAssertTrue(waitForLabel(app.staticTexts["editEntryLineSumValue"], "198.00\u{00A0}€"),
                      "the sum must move to include the added 50.00 line")
        XCTAssertTrue(app.staticTexts["editEntryLineSumMismatch"].waitForExistence(timeout: 5),
                      "the Amount still says 148.00, so the mismatch must be stated")

        replaceAmountRV199(app, with: "198.00")
        XCTAssertFalse(app.staticTexts["editEntryLineSumMismatch"].waitForExistence(timeout: 2),
                       "typing the Amount to match the sum must clear the mismatch")
    }

    // MARK: - RU

    /// The RU pass: the same figure, the localised "Позиции" label and the
    /// mismatch sentence are reachable and functional. The layout check is the
    /// committed screenshot, this proves the controls work in Russian.
    func testLineSumMovesWithAnAddedItemInRussian() {
        let app = launchOnServiceRV199(russian: true)

        let sum = app.staticTexts["editEntryLineSumValue"]
        XCTAssertTrue(sum.waitForExistence(timeout: 10),
                      "the line sum must render in RU")
        XCTAssertTrue(waitForLabel(sum, "148.00\u{00A0}€"))

        addLineRV199(app)

        XCTAssertTrue(waitForLabel(app.staticTexts["editEntryLineSumValue"], "198.00\u{00A0}€"),
                      "the sum must move in RU too")
        XCTAssertTrue(app.staticTexts["editEntryLineSumMismatch"].waitForExistence(timeout: 5),
                      "the mismatch must be stated in RU")

        replaceAmountRV199(app, with: "198.00")
        XCTAssertFalse(app.staticTexts["editEntryLineSumMismatch"].waitForExistence(timeout: 2),
                       "typing the Amount to match must clear the mismatch in RU too")
    }
}
