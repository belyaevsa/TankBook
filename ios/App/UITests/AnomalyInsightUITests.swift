import XCTest

/// P6.1b: J9's anomaly insight card in the Log (docs/JOURNEYS.md J9,
/// docs/ERRORS.md -> Home). The engine (P6.1a) merged and nothing rendered it;
/// this suite pins the surface: the card renders ONLY on a real engine verdict,
/// states the magnitude and the compared window in the text, dismisses with a
/// reason (which persists across relaunch), acts by creating a real reminder,
/// and is never an alert or a modal (hard rule 8).
///
/// The vacuous traps this suite refuses:
/// - The absent case is asserted FIRST - the engine abstains by design, so a
///   card that renders unconditionally would be the common-path bug.
/// - Every positive test asserts the card's TEXT (magnitude, both windows), not
///   just that a card exists - the classic way a localization bug stays green.
/// - "Act" is asserted by the reminder existing afterwards, never by a tapped
///   button's visual state.
/// - No `#expect(true)` anywhere.
@MainActor
final class AnomalyInsightUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Every anomaly test starts from a wiped database. `-anomalyDismissalReset`
    /// also clears the UserDefaults dismissal store (which survives
    /// `-homeResetDatabase`), so a prior test's dismissal can never hide a card
    /// this test expects to see.
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    private func cardElement(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "homeAnomalyCard").firstMatch
    }

    private func textContaining(_ app: XCUIApplication, _ substring: String) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", substring)).firstMatch
    }

    // MARK: - Test 1: the absent case (the common path)

    /// No anomaly, no card. The engine abstains on a history younger than ~12
    /// months (no seasonally-aligned baseline), so a full-but-short log renders
    /// no card at all - this is the assertion that proves the card is not
    /// unconditional.
    func testNoAnomalyShowsNoCard() {
        let app = launch(["-seedHomeFullHistory"])

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10),
                      "the Log screen must render")
        XCTAssertFalse(cardElement(app).exists,
                       "a log without a 12-month baseline must not render an anomaly card")
        XCTAssertFalse(textContaining(app, "Consumption is up").exists,
                       "no drift text anywhere - the absent case is silent")
    }

    // MARK: - Test 2: the card states the drift and the compared window

    /// An anomaly renders the card with the magnitude AND the compared window
    /// in the text - the number is falsifiable only if the reader can see what
    /// it was measured against (the trailing 90 days vs the same 90 days one
    /// year earlier). The exact strings are the engine's numbers, never
    /// recomputed in the view (hard rule 2).
    func testAnomalyRendersCardWithMagnitudeAndComparedWindow() {
        let app = launch(["-seedHomeAnomaly", "-anomalyDismissalReset"])

        XCTAssertTrue(cardElement(app).waitForExistence(timeout: 10))

        // The headline: the engine's magnitude as a whole percent (21% from a
        // 0.2093 fraction) in one full localised phrase.
        let title = app.staticTexts["homeAnomalyTitle"]
        XCTAssertTrue(title.exists)
        XCTAssertEqual(title.label, "Consumption is up 21% vs a year ago",
                       "title was \(title.label)")

        // The caption names BOTH windows with both values in the car's unit.
        let caption = app.staticTexts["homeAnomalyCaption"]
        XCTAssertTrue(caption.exists)
        XCTAssertTrue(caption.label.contains("Last 90 days"),
                      "rolling window missing from: \(caption.label)")
        XCTAssertTrue(caption.label.contains("a year earlier"),
                      "baseline window missing from: \(caption.label)")
        XCTAssertTrue(caption.label.contains("6.5"), "rolling value missing: \(caption.label)")
        XCTAssertTrue(caption.label.contains("5.4"), "baseline value missing: \(caption.label)")
        XCTAssertTrue(caption.label.contains("L/100km"),
                      "the drift must be stated in the vehicle's own unit: \(caption.label)")
    }

    // MARK: - Test 3: dismiss-with-reason persists across a relaunch

    /// "It's winter" records an `AnomalyDismissal`; the card leaves. A relaunch
    /// without a database wipe keeps the same vehicle and the same cause, so
    /// the card stays away - the engine suppresses a dismissed cause, and the
    /// store remembers only the dismissal, never the verdict (hard rule 2).
    func testDismissWithReasonPersistsAcrossRelaunch() {
        let app = launch(["-seedHomeAnomaly", "-anomalyDismissalReset"])
        XCTAssertTrue(cardElement(app).waitForExistence(timeout: 10))

        // Expand, then dismiss with a reason from the sheet.
        app.buttons["homeAnomalyToggle"].tap()
        let dismiss = app.buttons["homeAnomalyDismissButton"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        dismiss.tap()

        let sheetTitle = app.staticTexts["anomalyDismissTitle"]
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(sheetTitle.label, "Why is consumption higher?")
        app.buttons["anomalyDismissReasonWinter"].tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: cardElement(app))
        waitForExpectations(timeout: 5)
        XCTAssertFalse(cardElement(app).exists, "a dismissed cause must leave the Log")

        // Relaunch WITHOUT `-homeResetDatabase`: the database (same vehicle,
        // same fills) and the UserDefaults dismissal both survive, so the card
        // must not return for this cause.
        app.terminate()
        let relaunch = XCUIApplication()
        relaunch.launchArguments = ["-seedHomeAnomaly"]
        relaunch.launch()

        XCTAssertTrue(relaunch.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))
        XCTAssertFalse(cardElement(relaunch).exists,
                       "a dismissed cause must stay dismissed across a relaunch")
    }

    // MARK: - Test 4: act creates a real reminder

    /// "Act" creates a service reminder - asserted by the reminder EXISTING in
    /// the Reminders list afterwards, never by a button's visual state. The
    /// card also leaves: a card with only "act" is the nag J9 forbids.
    /// PJ.4: the reminder is due TODAY (the act anchors it at `Date()`), so the
    /// REAL banner derives it and its View affordance is the door to the list -
    /// no `-forceReminderDue` fixture remains.
    func testActCreatesAReminder() {
        let app = launch(["-seedHomeAnomaly", "-anomalyDismissalReset"])
        XCTAssertTrue(cardElement(app).waitForExistence(timeout: 10))

        app.buttons["homeAnomalyToggle"].tap()
        let act = app.buttons["homeAnomalyActButton"]
        XCTAssertTrue(act.waitForExistence(timeout: 5))
        act.tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: cardElement(app))
        waitForExpectations(timeout: 5)

        // The reminder exists on the Reminders list (reached via the real
        // banner's View affordance, derived from the just-created reminder).
        let view = app.buttons["homeReminderViewButton"]
        XCTAssertTrue(view.waitForExistence(timeout: 5),
                      "acting must derive the banner from the new reminder")
        view.tap()
        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Check fuel consumption"].waitForExistence(timeout: 5),
                      "act must create a real reminder row, not just leave the card")
    }

    // MARK: - Test 5: never an alert, never a modal

    /// J9: "never a push alarm" and hard rule 8 (conflicts surface as badges
    /// where the data lives, never modals at sync time). The card is inline in
    /// the Log - no alert, no sheet, no cover - both collapsed and expanded.
    /// The dismissal sheet is user-initiated from the card's own button; it is
    /// never presented automatically.
    func testCardIsInlineAndPresentsNoAlert() {
        let app = launch(["-seedHomeAnomaly", "-anomalyDismissalReset"])
        XCTAssertTrue(cardElement(app).waitForExistence(timeout: 10))

        XCTAssertTrue(app.alerts.allElementsBoundByIndex.isEmpty,
                      "an anomaly must never present an alert")
        XCTAssertTrue(app.sheets.allElementsBoundByIndex.isEmpty,
                      "the card must be inline in the Log, never a presented sheet")
        XCTAssertTrue(textContaining(app, "Average consumption").exists
                        || app.staticTexts["homeHeadlineValue"].exists,
                      "the Log screen must still be visible behind the card")

        app.buttons["homeAnomalyToggle"].tap()
        XCTAssertTrue(app.buttons["homeAnomalyActButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.allElementsBoundByIndex.isEmpty,
                      "expanding the evidence must not present an alert either")
    }

    // MARK: - Test 6: Russian

    /// The card renders translated copy in Russian - the magnitude phrase
    /// ("Расход вырос на 21% по сравнению с прошлым годом", where "расход"
    /// governs "вырос") and the window caption are full localised phrases, and
    /// the dismiss sheet's reasons are localised too. This is the check that
    /// catches a `Text(_: String)` blind spot - the gate cannot see a key that
    /// IS present but renders English.
    func testCardRendersInRussian() {
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                          "-seedHomeAnomaly", "-anomalyDismissalReset"])
        XCTAssertTrue(cardElement(app).waitForExistence(timeout: 10))

        let title = app.staticTexts["homeAnomalyTitle"]
        XCTAssertTrue(title.exists)
        XCTAssertTrue(title.label.contains("Расход вырос на 21%"),
                      "title was \(title.label)")
        XCTAssertTrue(title.label.contains("по сравнению с прошлым годом"),
                      "title was \(title.label)")

        let caption = app.staticTexts["homeAnomalyCaption"]
        XCTAssertTrue(caption.exists)
        XCTAssertTrue(caption.label.contains("Последние 90 дней"),
                      "caption was \(caption.label)")
        XCTAssertTrue(caption.label.contains("год назад"),
                      "caption was \(caption.label)")

        // The dismissal sheet's reasons are localised too ("Зима").
        app.buttons["homeAnomalyToggle"].tap()
        XCTAssertTrue(app.buttons["homeAnomalyDismissButton"].waitForExistence(timeout: 5))
        app.buttons["homeAnomalyDismissButton"].tap()
        XCTAssertTrue(app.buttons["anomalyDismissReasonWinter"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["anomalyDismissReasonWinter"].label, "Зима")
    }
}
