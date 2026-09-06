import XCTest

/// RV.77 - the "Remind you next time?" offer that appears after a manual
/// service save (docs/JOURNEYS.md J7d "Just did it"). The three gates:
/// 1. saving a service record whose category has an interval OFFERS the
///    reminder (never auto-creates it);
/// 2. ACCEPTING creates it - anchored at the record;
/// 3. "Not this time" creates NOTHING - a silent auto-create would pass an
///    acceptance-only suite, and the whole point of the row is that the offer
///    is a proposal the user accepts, edits or ignores (hard rule 13).
@MainActor
final class ServiceReminderOfferUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Opens the ServiceEntry sheet pre-filled with a titled OIL item (the
    /// seed's "Oil service incl. filter") and the odometer, so the test only
    /// taps Save. The oil category is what makes the offer apply.
    private func launchServiceEntry(_ app: XCUIApplication) {
        app.launchArguments = ["-homeResetDatabase",
                               "-seedVehicleForUITests",
                               "-seedServiceEntry",
                               "-presentScreen", "serviceEntry"]
        app.launch()
    }

    private func saveAndWaitForOffer(_ app: XCUIApplication) {
        let save = app.buttons["serviceEntrySaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        XCTAssertTrue(app.staticTexts["serviceReminderOfferHeadline"]
            .waitForExistence(timeout: 10),
            "the offer sheet must appear after the oil service saves")
    }

    /// The reminder's accessibility id on the Reminders list row; the created
    /// reminder is titled with the record's own words, so the merged list shows
    /// the seed's "Oil service incl. filter".
    private func reminderTitleOnList(_ app: XCUIApplication) -> Bool {
        app.staticTexts["remindersScheduledHeader"].waitForExistence(timeout: 10)
            && app.staticTexts["Oil service incl. filter"].exists
    }

    // MARK: - The offer appears

    /// The screenshot hook (`-presentServiceReminderOffer`, which presents the
    /// offer over a seeded just-saved oil service) must render the SAME sheet a
    /// real save produces - this test guards that the seeded capture and the
    /// flow cannot drift apart.
    func testScreenshotHookPresentsTheOfferOverTheSeededLog() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase",
                               "-seedServiceReminderOffer",
                               "-presentServiceReminderOffer"]
        app.launch()

        XCTAssertTrue(app.staticTexts["serviceReminderOfferHeadline"]
            .waitForExistence(timeout: 10),
            "the screenshot hook must present the offer sheet")
        XCTAssertTrue(app.textFields["serviceReminderOfferKmField"].exists)
        XCTAssertTrue(app.textFields["serviceReminderOfferMonthsField"].exists)
        XCTAssertTrue(app.buttons["serviceReminderOfferCreateButton"].exists)
        XCTAssertTrue(app.buttons["serviceReminderOfferNotThisTimeButton"].exists)
    }

    func testSavingAServiceRecordWithAnIntervalCategoryOffersTheReminder() {
        let app = XCUIApplication()
        launchServiceEntry(app)
        saveAndWaitForOffer(app)

        // The interval fields are visible AND editable - a suggestion, not a
        // fact (hard rule 13). Their prefill comes from the curated oil
        // interval (15,000 km / 12 months).
        let km = app.textFields["serviceReminderOfferKmField"]
        XCTAssertTrue(km.exists, "the km interval field must be present")
        XCTAssertTrue(km.isEnabled, "the offered interval must be editable")
        let months = app.textFields["serviceReminderOfferMonthsField"]
        XCTAssertTrue(months.exists)
        XCTAssertTrue(months.isEnabled)

        XCTAssertTrue(app.buttons["serviceReminderOfferCreateButton"].exists,
                      "the offer must propose, never auto-create")
        XCTAssertTrue(app.buttons["serviceReminderOfferNotThisTimeButton"].exists,
                      "declining is a peer button, not a dismiss X")
    }

    // MARK: - Accepting creates the reminder, anchored at the record

    func testAcceptingCreatesTheReminderAnchoredAtTheRecord() {
        let app = XCUIApplication()
        launchServiceEntry(app)
        saveAndWaitForOffer(app)

        let create = app.buttons["serviceReminderOfferCreateButton"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()

        // The offer closes and the reminder is live: reopen the app onto the
        // merged Reminders list (the DB persisted; no reset on this launch).
        app.terminate()
        app.launchArguments = ["-presentScreen", "remindersAll"]
        app.launch()
        XCTAssertTrue(reminderTitleOnList(app),
                      "accepting must create a scheduled reminder titled with the record")
    }

    // MARK: - Not this time creates nothing

    func testNotThisTimeCreatesNothing() {
        let app = XCUIApplication()
        launchServiceEntry(app)
        saveAndWaitForOffer(app)

        let notThisTime = app.buttons["serviceReminderOfferNotThisTimeButton"]
        XCTAssertTrue(notThisTime.waitForExistence(timeout: 5))
        notThisTime.tap()

        // The offer dismisses with no write behind it - a silent auto-create
        // would leave a reminder on the list, and this row forbids exactly that.
        XCTAssertFalse(app.staticTexts["serviceReminderOfferHeadline"]
            .waitForExistence(timeout: 2),
            "the offer must dismiss on Not this time")

        app.terminate()
        app.launchArguments = ["-presentScreen", "remindersAll"]
        app.launch()
        // The vehicle seeded for the entry still exists; an empty list is the
        // honest state after declining (no reminders were seeded).
        if app.staticTexts["remindersEmptyNewReminderButton"].waitForExistence(timeout: 10) {
            return
        }
        XCTAssertFalse(reminderTitleOnList(app),
                       "Not this time must NOT create the reminder")
    }
}
