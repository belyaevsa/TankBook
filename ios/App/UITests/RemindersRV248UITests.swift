import XCTest

/// RV.248 - the History surface at the foot of the merged reminders list
/// (docs/JOURNEYS.md J7c -> "Delete", docs/SCREENMAP.md -> "Reminders across
/// cars"). Before this row the dismissal reason was collected, persisted and
/// synced, and read by nothing: the copy said "it stays in your history", and
/// no screen showed it. The gate is end to end - dismiss with a reason and the
/// reason is on the History row; complete one and it appears as history. EN and
/// RU, because the flow runs through the localized list and section header.
@MainActor
extension RemindersUITests {

    private func historyApp(_ language: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedReminderHistory",
                               "-presentScreen", "remindersAll"] + language
        app.launch()
        return app
    }

    /// Scrolls to the History section, which sits at the foot of the list below
    /// the live rows and the "New reminder" card.
    private func scrollToHistory(_ app: XCUIApplication) {
        let header = app.staticTexts["remindersHistoryHeader"]
        var attempts = 0
        while !header.exists && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(header.waitForExistence(timeout: 5),
                      "the History section must be reachable at the foot of the list")
    }

    /// Drives the row menu's dismiss-with-reason flow. The alert's confirm
    /// button carries the localized "Dismiss", so the caller passes it.
    private func dismissWithReason(_ app: XCUIApplication, reason: String,
                                   dismissLabel: String) {
        let menu = app.buttons["reminderRowMenu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()

        let dismiss = app.buttons[dismissLabel].firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        dismiss.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(reason)
        alert.buttons[dismissLabel].tap()
    }

    private func assertDismissedReasonIsOnTheHistoryRow(_ app: XCUIApplication,
                                                        reason: String) {
        scrollToHistory(app)
        XCTAssertTrue(app.staticTexts[reason].waitForExistence(timeout: 5),
                      "the stored dismissal reason must render on its History row")
    }

    func testDismissedReminderReasonAppearsInHistory() {
        let app = historyApp([])
        XCTAssertTrue(app.staticTexts["Insurance renewal"].waitForExistence(timeout: 10))
        dismissWithReason(app, reason: "Renewed early", dismissLabel: "Dismiss")
        assertDismissedReasonIsOnTheHistoryRow(app, reason: "Renewed early")
    }

    func testDismissedReminderReasonAppearsInHistoryInRussian() {
        let app = historyApp(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"])
        XCTAssertTrue(app.staticTexts["Insurance renewal"].waitForExistence(timeout: 10))
        dismissWithReason(app, reason: "Renewed early", dismissLabel: "Отклонить")
        assertDismissedReasonIsOnTheHistoryRow(app, reason: "Renewed early")
    }

    private func assertCompletedReminderBecomesHistory(_ app: XCUIApplication) {
        let complete = app.buttons["reminderCompleteButton"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        complete.tap()

        let skip = app.buttons["reminderCompleteSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        scrollToHistory(app)
        XCTAssertFalse(app.staticTexts["remindersAttentionHeader"].exists,
                       "the completed row must leave the live list")
        XCTAssertTrue(app.staticTexts["Insurance renewal"].waitForExistence(timeout: 5),
                      "the completed reminder must appear as history")
    }

    func testCompletedReminderAppearsInHistory() {
        let app = historyApp([])
        assertCompletedReminderBecomesHistory(app)
    }

    func testCompletedReminderAppearsInHistoryInRussian() {
        let app = historyApp(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"])
        assertCompletedReminderBecomesHistory(app)
    }
}
