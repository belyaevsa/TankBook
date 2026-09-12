import XCTest

/// P6.1b: J9's anomaly insight card in the Log (docs/JOURNEYS.md J9,
/// docs/ERRORS.md -> Home). The engine (P6.1a) merged and nothing rendered it;
/// this suite pins the surface: the card renders ONLY on a real engine verdict,
/// states the magnitude and the compared window in the text, dismisses in one
/// tap (which persists across relaunch), acts by creating a real reminder due
/// next year and opening it for edit, and is never an alert or a modal
/// (hard rule 8).
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
    /// this test expects to see. A signed-in session is required too: since
    /// PJ.3 a sessionless launch renders the guest Home, whose layout has no
    /// anomaly card - the card lives only in the signed-in full layout (the
    /// same reason TankbookShellUITests seeds `-seedSettingsSignedIn`).
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn"] + arguments
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

    // MARK: - Test 3: dismiss is one tap and persists across a relaunch

    /// "Dismiss" is one tap: no sheet, no reason. The card leaves and a
    /// relaunch without a database wipe keeps the same vehicle and the same
    /// cause, so the card stays away - the engine suppresses a dismissed cause,
    /// and the store remembers only the dismissal, never the verdict (hard rule
    /// 2, RV.240).
    func testDismissPersistsAcrossRelaunch() {
        let app = launch(["-seedHomeAnomaly", "-anomalyDismissalReset"])
        XCTAssertTrue(cardElement(app).waitForExistence(timeout: 10))

        // Expand, then dismiss in one tap.
        let toggle = app.buttons["homeAnomalyToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "homeAnomalyToggle never appeared")
        toggle.tap()
        let dismiss = app.buttons["homeAnomalyDismissButton"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        XCTAssertEqual(dismiss.label, "Dismiss",
                       "the one-tap dismiss must not promise a reason: \(dismiss.label)")
        dismiss.tap()

        // One tap, no sheet: the card leaves immediately.
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: cardElement(app))
        waitForExpectations(timeout: 5)
        XCTAssertFalse(cardElement(app).exists, "a dismissed cause must leave the Log")
        XCTAssertTrue(app.sheets.allElementsBoundByIndex.isEmpty,
                      "dismiss must be one tap, never a sheet")

        // Relaunch WITHOUT `-homeResetDatabase`: the database (same vehicle,
        // same fills) and the UserDefaults dismissal both survive, so the card
        // must not return for this cause.
        app.terminate()
        let relaunch = XCUIApplication()
        relaunch.launchArguments = ["-seedHomeAnomaly", "-seedSettingsSignedIn"]
        relaunch.launch()

        XCTAssertTrue(relaunch.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))
        XCTAssertFalse(cardElement(relaunch).exists,
                       "a dismissed cause must stay dismissed across a relaunch")
    }

    // MARK: - Test 4: act creates a reminder due next year, opened for edit

    /// "Act" creates a service reminder due at the shared default - one year
    /// out, never today (RV.268) - and opens it for edit so the date is seen
    /// and changeable (hard rule 13). Asserted by the reminder's OWN form
    /// showing a future date, then by the reminder landing in the list. The
    /// card also leaves: a card with only "act" is the nag J9 forbids.
    func testActCreatesAReminderDueNextYearAndOpensItForEdit() {
        let app = launch(["-seedHomeAnomaly", "-anomalyDismissalReset"])
        XCTAssertTrue(cardElement(app).waitForExistence(timeout: 10))

        let toggle = app.buttons["homeAnomalyToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "homeAnomalyToggle never appeared")
        toggle.tap()
        let act = app.buttons["homeAnomalyActButton"]
        XCTAssertTrue(act.waitForExistence(timeout: 5))
        act.tap()

        // The created reminder opens for edit.
        XCTAssertTrue(app.navigationBars["Edit reminder"].waitForExistence(timeout: 10),
                      "act must open the created reminder for edit")
        let title = app.textFields["reminderFormTitleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Check fuel consumption")

        // Its date is next year, never today.
        let dateButton = app.buttons["reminderFormDateButton"]
        XCTAssertTrue(dateButton.waitForExistence(timeout: 5))
        let nextYear = Calendar.current.component(.year, from: Date()) + 1
        XCTAssertTrue(dateButton.label.contains(String(nextYear)),
                      "the act reminder must be due next year (\(nextYear)): \(dateButton.label)")

        // Save returns to Home; the reminder is in the list under its future
        // date.
        app.buttons["reminderFormSaveButton"].tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))

        let remindersRow = app.buttons["homeRemindersRow"]
        XCTAssertTrue(remindersRow.waitForExistence(timeout: 5))
        remindersRow.tap()
        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Check fuel consumption"].waitForExistence(timeout: 5),
                      "act must create a real reminder row")
        XCTAssertTrue(textContaining(app, String(nextYear)).exists,
                      "the reminder must be listed under its future date (\(nextYear))")
    }

    // MARK: - Test 5: never an alert, never a modal

    /// J9: "never a push alarm" and hard rule 8 (conflicts surface as badges
    /// where the data lives, never modals at sync time). The card is inline in
    /// the Log - no alert, no sheet, no cover - both collapsed and expanded,
    /// and dismiss is one tap with no sheet at all (RV.240).
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

        let toggle = app.buttons["homeAnomalyToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "homeAnomalyToggle never appeared")
        toggle.tap()
        XCTAssertTrue(app.buttons["homeAnomalyActButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.allElementsBoundByIndex.isEmpty,
                      "expanding the evidence must not present an alert either")
    }

    // MARK: - Test 6: Russian

    /// The card renders translated copy in Russian - the magnitude phrase
    /// ("Расход вырос на 21% по сравнению с прошлым годом", where "расход"
    /// governs "вырос"), the window caption and the one-tap Dismiss button are
    /// full localised phrases. This is the check that catches a
    /// `Text(_: String)` blind spot - the gate cannot see a key that IS present
    /// but renders English.
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

        // The one-tap dismiss is localised too.
        let toggle = app.buttons["homeAnomalyToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "homeAnomalyToggle never appeared")
        toggle.tap()
        let dismiss = app.buttons["homeAnomalyDismissButton"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        XCTAssertEqual(dismiss.label, "Отклонить")
    }

    // MARK: - Test 7: the evidence is money, never a guessed cause

    /// The expanded card's evidence line is what the drift costs per month at
    /// the driver's own most recent price (docs/VISION.md -> "What we will not
    /// tell a driver"). The card cannot see a motorway week, an idling hour or
    /// a different driver, so it states the money and names NO cause, and it
    /// stays an inline card: dismissible, never blocking.
    func testExpandedCardShowsCostAndNoCause() {
        let app = launch(["-seedHomeAnomaly", "-anomalyDismissalReset"])
        XCTAssertTrue(cardElement(app).waitForExistence(timeout: 10))

        let toggle = app.buttons["homeAnomalyToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "homeAnomalyToggle never appeared")
        toggle.tap()

        // The money line is present, phrased as one full localised sentence.
        let cost = app.staticTexts["homeAnomalyCost"]
        XCTAssertTrue(cost.waitForExistence(timeout: 5),
                      "the expanded card must show what the drift costs")
        XCTAssertTrue(cost.label.contains("more per month at today's prices"),
                      "cost line was \(cost.label)")
        XCTAssertTrue(cost.label.contains("€"),
                      "the money line must carry the home currency: \(cost.label)")

        // The cause line is gone - the phrase that claims what the app cannot
        // know appears nowhere, collapsed or expanded.
        XCTAssertFalse(textContaining(app, "Likely causes").exists,
                       "the card must not name causes it cannot know")
        XCTAssertFalse(textContaining(app, "tire pressure").exists,
                       "the card must not name causes it cannot know")

        // Still dismissible and non-blocking: expanding never presents an alert
        // or a sheet, and the act/dismiss affordances are right there.
        XCTAssertTrue(app.alerts.allElementsBoundByIndex.isEmpty,
                      "the expanded evidence must not present an alert")
        XCTAssertTrue(app.sheets.allElementsBoundByIndex.isEmpty,
                      "the expanded evidence must not present a sheet")
        XCTAssertTrue(app.buttons["homeAnomalyActButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["homeAnomalyDismissButton"].waitForExistence(timeout: 5))
    }

    /// The Russian cost phrase is long ("Примерно на 14.89 € в месяц больше по
    /// текущим ценам") and RU runs 20-30% longer than EN, so the line must be
    /// asserted by its RENDERED text, not by the card existing - a truncated or
    /// English fallback would otherwise pass. The RU causes phrase must be gone
    /// too (the gate cannot see a key that renders English).
    func testExpandedCardCostLineRendersInRussian() {
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                          "-seedHomeAnomaly", "-anomalyDismissalReset"])
        XCTAssertTrue(cardElement(app).waitForExistence(timeout: 10))

        let toggle = app.buttons["homeAnomalyToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "homeAnomalyToggle never appeared")
        toggle.tap()

        let cost = app.staticTexts["homeAnomalyCost"]
        XCTAssertTrue(cost.waitForExistence(timeout: 5),
                      "the expanded card must show the Russian cost line")
        XCTAssertTrue(cost.label.contains("в месяц больше по текущим ценам"),
                      "cost line was \(cost.label)")
        XCTAssertFalse(cost.label.contains("more per month"),
                       "the RU cost line must not fall back to English: \(cost.label)")
        XCTAssertFalse(textContaining(app, "Вероятные причины").exists,
                       "the RU card must not name causes it cannot know")
    }
}
