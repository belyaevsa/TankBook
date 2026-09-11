import XCTest

// MARK: - PJ.22 the lifetime editor and the reminder it proposes

/// Kept as an extension of `EditEntryUITests` (its own file, so the base file
/// stays under the lint ceiling - the `EditEntryRV198UITests` precedent).
///
/// The row's acceptance, end to end: a service line item's **lifetime** can be
/// set on Edit entry, saving it raises the post-save "Remind you next time?"
/// offer, accepting it creates the reminder, and the reminder is on the
/// Reminders list. EN and RU, because the "15 000 km or 12 months" row is where
/// Russian runs longest.
@MainActor
extension EditEntryUITests {

    private func launchOnService(pj22Russian russian: Bool = false) -> XCUIApplication {
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

    /// The oil item's lifetime km field. The seed gives that item 15 000 km / 12
    /// months, so the field is populated and the change is a real edit.
    private func lifetimeKmField(_ app: XCUIApplication) -> XCUIElement {
        app.textFields.matching(identifier: "editEntryServiceItemLifetimeKm").firstMatch
    }

    /// Replaces a text field's contents without the text-selection edit menu
    /// (unreliable on the iOS 26 simulator): tap the field's right edge, delete
    /// the current text one keystroke at a time, type the replacement.
    private func replaceFieldText(in field: XCUIElement, with text: String,
                                  app: XCUIApplication) {
        if app.keyboards.firstMatch.exists { app.swipeDown() }
        var attempts = 0
        while !field.isHittable && attempts < 8 {
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

    private func saveAndWaitForOffer(_ app: XCUIApplication) {
        if app.keyboards.firstMatch.exists { app.swipeDown() }
        let save = app.buttons["editEntrySaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["serviceReminderOfferHeadline"]
            .waitForExistence(timeout: 10),
            "a changed lifetime must raise the offer after the edit saves")
    }

    /// The reminder's title is the record's own first named item, so the merged
    /// list shows the seed's "Oil service incl. filter".
    private func reminderIsOnTheList(_ app: XCUIApplication) -> Bool {
        app.staticTexts["remindersScheduledHeader"].waitForExistence(timeout: 10)
            && app.staticTexts["Oil service incl. filter"].exists
    }

    // MARK: - EN

    func testChangingALifetimeProposesAndAcceptingCreatesTheReminder() {
        let app = launchOnService()

        let km = lifetimeKmField(app)
        XCTAssertTrue(km.waitForExistence(timeout: 10),
                      "the item row must offer a km lifetime field")
        XCTAssertTrue(app.textFields["editEntryServiceItemLifetimeMonths"].firstMatch.exists,
                      "the item row must offer a months lifetime field")
        replaceFieldText(in: km, with: "20000", app: app)

        saveAndWaitForOffer(app)
        // The proposal is a suggestion the user can decline - the peer button is
        // present, never an auto-create (hard rule 13).
        XCTAssertTrue(app.buttons["serviceReminderOfferNotThisTimeButton"].exists)

        let create = app.buttons["serviceReminderOfferCreateButton"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()

        app.terminate()
        app.launchArguments = ["-presentScreen", "remindersAll"]
        app.launch()
        XCTAssertTrue(reminderIsOnTheList(app),
                      "accepting the proposal must create the reminder")
    }

    func testDecliningTheLifetimeProposalCreatesNothing() {
        let app = launchOnService()

        let km = lifetimeKmField(app)
        XCTAssertTrue(km.waitForExistence(timeout: 10))
        replaceFieldText(in: km, with: "20000", app: app)

        saveAndWaitForOffer(app)
        let notThisTime = app.buttons["serviceReminderOfferNotThisTimeButton"]
        XCTAssertTrue(notThisTime.waitForExistence(timeout: 5))
        notThisTime.tap()

        app.terminate()
        app.launchArguments = ["-presentScreen", "remindersAll"]
        app.launch()
        if app.staticTexts["remindersEmptyNewReminderButton"].waitForExistence(timeout: 10) {
            return
        }
        XCTAssertFalse(reminderIsOnTheList(app),
                       "Not this time must NOT create the reminder")
    }

    // MARK: - RU

    func testChangingALifetimeInRussianProposesAndCreatesTheReminder() {
        let app = launchOnService(pj22Russian: true)

        let km = lifetimeKmField(app)
        XCTAssertTrue(km.waitForExistence(timeout: 10),
                      "the lifetime field must render in RU")
        replaceFieldText(in: km, with: "20000", app: app)

        saveAndWaitForOffer(app)
        let create = app.buttons["serviceReminderOfferCreateButton"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()

        app.terminate()
        app.launchArguments = ["-presentScreen", "remindersAll"]
        app.launch()
        XCTAssertTrue(reminderIsOnTheList(app),
                      "the RU round-trip must create the reminder")
    }
}
