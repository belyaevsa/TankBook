import XCTest

/// RV.78 - a fired reminder must be actionable from its notification
/// (docs/NOTIFICATIONS.md -> the actions, design/screens/
/// ReminderNotification.dc.html). The banner carries **Mark done** and
/// **Push a week**; these tests replay a response through the SAME decision
/// path a real `didReceive` response takes (`-replayNotificationAction`, which
/// drives `UNNotificationScheduler.replayForTests` -> the delegate's `handle`),
/// then assert on the reminder's resulting state, never on the handler having
/// been called.
///
/// Vacuous traps this suite is built against:
/// - asserting the actions are *registered* without exercising a response
///   (registration is L2, in `TankbookTests`; here every test REPLAYS a
///   response and asserts what it did);
/// - a **Mark done** that completes silently and skips the cost log - it must
///   open the completion sheet (J7c: declining is first-class but stays the
///   user's choice);
/// - a completed reminder that leaves its notification armed (the disarm is
///   pinned at L2 against the real center);
/// - a snooze that moves nothing (the due-date movement is the UI state).
@MainActor
final class RemindersNotificationActionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The seed's attention "Insurance renewal" (ReminderTestSeed.deepLinkReminderID).
    private let insuranceID = "0D4B0F2A-3E1C-4B6A-9C5D-8E7F1A2B3C4D"

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    // MARK: - Push a week

    /// Responding with **Push a week** moves the fired reminder's due date out
    /// of its attention window: the seeded "Insurance renewal" (due in 12
    /// days, the only attention row) leaves "Needs attention" and sits under
    /// "Scheduled" - a week later, still active, never completed. Snooze needs
    /// no screen: no completion sheet surfaces.
    func testSnoozeResponseMovesTheFiredReminderOutOfAttention() {
        let app = launch(["-presentScreen", "reminders", "-seedReminders",
                          "-replayNotificationAction", "snooze",
                          "reminder.\(insuranceID).date"])

        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 10),
                      "snooze must leave the user on the Reminders screen it opened into")

        // No sheet: snooze is the one action that needs no screen.
        XCTAssertFalse(app.buttons["reminderCompleteSkip"].waitForExistence(timeout: 2),
                       "snooze must not open the completion sheet")

        // The reminder is still ACTIVE - snooze is not a silent complete.
        XCTAssertTrue(app.staticTexts["Insurance renewal"].exists,
                      "snoozed reminder must remain on the list")

        // It left the attention group (the only attention row was insurance)
        // and now sits in Scheduled, its due pushed a week.
        XCTAssertFalse(app.staticTexts["remindersAttentionHeader"].waitForExistence(timeout: 3),
                       "the snoozed reminder must leave 'Needs attention'")
        XCTAssertTrue(app.staticTexts["remindersScheduledHeader"].waitForExistence(timeout: 3),
                      "the snoozed reminder must move to 'Scheduled'")
        XCTAssertFalse(app.staticTexts["reminderChip"].exists,
                       "no attention chip remains - nothing is due in the window")
    }

    /// A snooze on an identifier no reminder answers (deleted since the
    /// notification was scheduled) is inert (hard rule 7): the app opens
    /// normally, routes nowhere, and nothing is silently mutated.
    func testSnoozeResponseForAnUnknownReminderIsInert() {
        let app = launch(["-seedHomeFullHistory",
                          "-replayNotificationAction", "snooze",
                          "reminder.\(UUID().uuidString).date"])

        XCTAssertTrue(app.staticTexts["homeOdometer"].waitForExistence(timeout: 10),
                      "an unresolvable snooze must open the app to its normal Home")
        XCTAssertFalse(app.navigationBars["Reminders"].exists,
                       "an unresolvable snooze must not route anywhere")
    }

    // MARK: - Mark done

    /// Responding with **Mark done** opens the app on the completion sheet for
    /// THAT reminder - it never completes silently, because declining the cost
    /// log is first-class but stays the user's choice (J7c, the artboard's own
    /// sentence). The sheet is then driven to the state it always produces:
    /// Skip lands a `.done(nil)` history row and, for the seeded recurring
    /// reminder, schedules the next occurrence.
    func testMarkDoneOpensTheCompletionSheetAndSkipProducesTheSheetState() {
        let app = launch(["-seedReminders",
                          "-replayNotificationAction", "complete",
                          "reminder.\(insuranceID).date"])

        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 10),
                      "Mark done must land on the Reminders screen")
        XCTAssertTrue(app.buttons["reminderCompleteSkip"].waitForExistence(timeout: 5),
                      "Mark done must open the completion sheet - never a silent .done(nil)")
        XCTAssertTrue(app.buttons["reminderCompleteTypeAmount"].exists,
                      "the cost log choice must be present")
        XCTAssertTrue(app.staticTexts["Insurance renewal – done"].exists,
                      "the sheet is the reminder the action named, not whichever row is first")

        // Skip - the same tap that completes from the sheet itself. The
        // reminder leaves attention; its recurring next occurrence is
        // scheduled. This is exactly the state the sheet produces, because the
        // action went through the sheet.
        app.buttons["reminderCompleteSkip"].tap()

        XCTAssertFalse(app.staticTexts["remindersAttentionHeader"].waitForExistence(timeout: 5),
                       "completing through the Mark done door must end the attention state")
        XCTAssertTrue(app.staticTexts["remindersScheduledHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Insurance renewal"].waitForExistence(timeout: 5),
                      "the recurring reminder's next occurrence is scheduled, exactly as a sheet Skip produces")
    }

    /// Mark done on a notification whose reminder was deleted since it was
    /// scheduled is a landing, not a dead end and never a detour (hard rule 7):
    /// the plain merged list shows, no completion sheet surfaces.
    func testMarkDoneForADeletedReminderLandsOnThePlainList() {
        let deleted = "7A9B8C7D-6E5F-4A3B-8C2D-1E0F9A8B7C6D"
        let app = launch(["-seedRemindersDeepLink",
                          "-replayNotificationAction", "complete",
                          "reminder.\(deleted).date"])

        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 10),
                      "a stale Mark done must still land on Reminders")
        XCTAssertFalse(app.buttons["reminderCompleteSkip"].waitForExistence(timeout: 3),
                       "a deleted reminder must not surface a completion flow")
        XCTAssertTrue(app.staticTexts["remindersAttentionHeader"].waitForExistence(timeout: 5),
                      "the plain list is what is in frame")
    }

    /// An unknown identifier under Mark done is inert (hard rule 7): the app
    /// opens normally and routes nowhere - the same contract a plain tap has.
    func testMarkDoneForAnUnknownNotificationIsInert() {
        let app = launch(["-seedHomeFullHistory",
                          "-replayNotificationAction", "complete",
                          "not-a-notification"])

        XCTAssertTrue(app.staticTexts["homeOdometer"].waitForExistence(timeout: 10),
                      "an unresolvable Mark done must open the app to its normal Home")
        XCTAssertFalse(app.navigationBars["Reminders"].exists,
                       "an unresolvable Mark done must not route anywhere")
    }
}
