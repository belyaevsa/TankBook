import XCTest

// MARK: - RV.198 add and delete a service line item

/// Kept as an extension of `EditEntryUITests` (its own file, so the base file
/// stays under the lint ceiling - the `EditEntryRV144UITests` precedent).
///
/// The row's own acceptance, end to end: a service opened in Edit entry can
/// GAIN a line item and LOSE one, and the stored record follows. The delete is
/// the half a button-exists assertion cannot prove: the test saves, reopens and
/// reads the rows back, so a delete that removes nothing (the named mutation)
/// stays red. EN and RU, because the add/delete affordance sits on the same row
/// as a cost and Russian runs 20-30% longer.
@MainActor
extension EditEntryUITests {

    private func launchOnService(rv198Russian russian: Bool = false) -> XCUIApplication {
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

    /// Dismiss the keyboard, then scroll the element into the tappable area.
    /// Scrolls until `element` is hittable AND clear of the pinned save bar.
    /// `isHittable` alone is the RV.80/PJ.7e lie: it turns true while the
    /// element's centre still sits under the bar, and the tap lands on Save -
    /// which is exactly how four of these tests started saving instead of
    /// adding once PJ.61 made the item rows taller.
    private func scrollTo(_ element: XCUIElement, app: XCUIApplication) {
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

    private func saveAndWaitForHome(_ app: XCUIApplication) {
        let save = app.buttons["editEntrySaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10),
                      "saving must return to Home")
    }

    private func reopenNewestEntry(_ app: XCUIApplication) {
        let row = app.buttons.matching(identifier: "logEntryButton").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.textFields["editEntryServiceItemTitle"].firstMatch
            .waitForExistence(timeout: 5), "the service must reopen in Edit entry")
    }

    // MARK: - EN

    /// Add a line: tap Add, type a title, save, reopen, see it.
    func testAddingAServiceItemPersists() {
        let app = launchOnService(rv198Russian: false)

        let add = app.buttons["editEntryAddServiceItemButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 10),
                      "the service must offer an add affordance")
        scrollTo(add, app: app)
        add.tap()

        let titles = app.textFields.matching(identifier: "editEntryServiceItemTitle")
        XCTAssertEqual(titles.count, 3, "tapping Add must append one editable row")
        let added = titles.element(boundBy: 2)
        scrollTo(added, app: app)
        added.tap()
        added.typeText("Cabin filter")
        XCTAssertEqual(added.value as? String, "Cabin filter")

        saveAndWaitForHome(app)
        reopenNewestEntry(app)

        let reopened = app.textFields.matching(identifier: "editEntryServiceItemTitle")
        XCTAssertEqual(reopened.count, 3, "the added row must persist across a reopen")
        XCTAssertEqual(reopened.element(boundBy: 2).value as? String, "Cabin filter")
    }

    /// Delete a line: remove the first row, save, reopen, it is gone and the
    /// survivor is intact.
    func testDeletingAServiceItemPersists() {
        let app = launchOnService(rv198Russian: false)

        let deletes = app.buttons.matching(identifier: "editEntryServiceItemDelete")
        XCTAssertTrue(deletes.firstMatch.waitForExistence(timeout: 10),
                      "each line item must offer a delete affordance")
        XCTAssertEqual(deletes.count, 2, "the seed has two line items")
        let first = deletes.firstMatch
        scrollTo(first, app: app)
        first.tap()

        saveAndWaitForHome(app)
        reopenNewestEntry(app)

        let reopened = app.textFields.matching(identifier: "editEntryServiceItemTitle")
        XCTAssertEqual(reopened.count, 1, "the deleted row must be gone after a reopen")
        XCTAssertEqual(reopened.firstMatch.value as? String, "Brake pads front",
                       "the survivor must be the row that was not deleted")
    }

    // MARK: - RU

    /// The RU pass: the same two operations are reachable and functional, and
    /// the localised add label renders. The layout check is the committed
    /// screenshot, this proves the controls work in Russian.
    func testAddingAServiceItemInRussian() {
        let app = launchOnService(rv198Russian: true)

        let add = app.buttons["editEntryAddServiceItemButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 10),
                      "the add affordance must render in RU")
        scrollTo(add, app: app)
        add.tap()

        let titles = app.textFields.matching(identifier: "editEntryServiceItemTitle")
        XCTAssertEqual(titles.count, 3)
        let added = titles.element(boundBy: 2)
        scrollTo(added, app: app)
        added.tap()
        added.typeText("Салонный фильтр")

        saveAndWaitForHome(app)
        reopenNewestEntry(app)

        let reopened = app.textFields.matching(identifier: "editEntryServiceItemTitle")
        XCTAssertEqual(reopened.count, 3, "the added row must persist across a reopen in RU")
        XCTAssertEqual(reopened.element(boundBy: 2).value as? String, "Салонный фильтр")
    }

    func testDeletingAServiceItemInRussian() {
        let app = launchOnService(rv198Russian: true)

        let deletes = app.buttons.matching(identifier: "editEntryServiceItemDelete")
        XCTAssertTrue(deletes.firstMatch.waitForExistence(timeout: 10),
                      "the delete affordance must render in RU")
        let first = deletes.firstMatch
        scrollTo(first, app: app)
        first.tap()

        saveAndWaitForHome(app)
        reopenNewestEntry(app)

        let reopened = app.textFields.matching(identifier: "editEntryServiceItemTitle")
        XCTAssertEqual(reopened.count, 1, "the deleted row must be gone after a reopen in RU")
        XCTAssertEqual(reopened.firstMatch.value as? String, "Brake pads front",
                       "the survivor must be the row that was not deleted")
    }
}
