import XCTest

/// P3.4 Reminders screen tests (L4, docs/TESTING.md). The list renders both
/// groups from the seed; the empty state reads as calm, not broken; and the
/// form saves and returns to the list with the new reminder visible. Each test
/// wipes the database first (`-homeResetDatabase`) so the seed is deterministic
/// regardless of test order - a seed is idempotent and silently no-ops on a
/// populated database.
@MainActor
final class RemindersUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-presentScreen", "reminders"] + arguments
        app.launch()
        return app
    }

    func testListRendersBothGroupsFromSeed() {
        let app = launch(["-seedReminders"])

        XCTAssertTrue(app.staticTexts["remindersAttentionHeader"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["remindersScheduledHeader"].exists)

        // The attention row carries the artboard's literal "12 days" chip -
        // asserted against the literal, never recomputed (the seed fixes the
        // due date at now + 12 days).
        let chip = app.staticTexts["reminderChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertEqual(chip.label, "12 days", "chip was \(chip.label)")

        XCTAssertTrue(app.buttons["reminderCompleteButton"].exists)
        XCTAssertTrue(app.buttons["remindersNewReminderButton"].exists)
        XCTAssertTrue(app.staticTexts["Insurance renewal"].exists)
        XCTAssertTrue(app.staticTexts["Oil change"].exists)
        XCTAssertTrue(app.staticTexts["Winter tires"].exists)
    }

    func testEmptyStateRenders() {
        let app = launch([])

        XCTAssertTrue(app.staticTexts["No reminders yet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["reminderEmptyState"].exists)
        // The empty state is a calm starting point, not a dead end: the "New
        // reminder" action is still there.
        XCTAssertTrue(app.buttons["remindersNewReminderButton"].exists)
        XCTAssertFalse(app.staticTexts["remindersAttentionHeader"].exists)
        XCTAssertFalse(app.staticTexts["remindersScheduledHeader"].exists)
    }

    func testFormSavesAndReturnsToTheList() {
        let app = launch(["-seedReminders"])

        let newButton = app.buttons["remindersNewReminderButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))
        newButton.tap()

        let title = app.textFields["reminderFormTitleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Brake check")

        app.buttons["reminderFormAddDateButton"].tap()

        let save = app.buttons["reminderFormSaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // Returns to the list with the new reminder visible.
        XCTAssertTrue(app.staticTexts["remindersAttentionHeader"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Brake check"].waitForExistence(timeout: 5))
    }

    func testCompleteOpensTheSheetAndSkipRecurs() {
        let app = launch(["-seedReminders"])

        // Every row carries a complete affordance; the attention row sorts
        // first, so the first match is the seeded "Insurance renewal".
        let complete = app.buttons["reminderCompleteButton"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        complete.tap()

        // The completion sheet opens (not a direct `.done` - P3.5).
        let skip = app.buttons["reminderCompleteSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reminderCompleteTypeAmount"].exists)

        skip.tap()

        // Skipping (`.done(nil)`) moves the row out of the attention group:
        // the chip is gone. The seeded reminder recurs every 12 months, so the
        // NEXT occurrence appears in Scheduled, anchored at the completion date
        // (docs/SCHEMA.md lifecycle: old rows become history, the next row is
        // new).
        XCTAssertTrue(app.staticTexts["remindersScheduledHeader"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["reminderChip"].exists,
                       "the completed attention row must leave the group")
        XCTAssertTrue(app.staticTexts["Insurance renewal"].exists,
                      "the recurring reminder's next occurrence is already scheduled")
    }

    func testSkipMovesANonRecurringRowIntoHistory() {
        let app = launch(["-seedReminders"])

        // Scheduled order is Winter tires (45 d), Inspection (~7 mo), Oil
        // change (~18 mo) - so the second complete button is the non-recurring
        // Winter tires row.
        let complete = app.buttons.matching(identifier: "reminderCompleteButton").element(boundBy: 1)
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        complete.tap()

        let skip = app.buttons["reminderCompleteSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        // A non-recurring reminder has no next occurrence: the row is gone,
        // now history ("oil changed 3× on time" - docs/SCHEMA.md).
        XCTAssertFalse(app.staticTexts["Winter tires"].waitForExistence(timeout: 3),
                       "a non-recurring reminder leaves the list when completed")
    }

    // MARK: - PJ.4 the Vehicle detail door (SCREENMAP.md: Reminders is reached
    // from "Home banner, VehicleDetail, push notification")

    /// The second door to the Reminders screen does not depend on anything
    /// being due: the Vehicle detail reminders row is always there, like Tire
    /// sets. A car with NO reminders still reaches the same list via it.
    func testVehicleDetailRowReachesTheRemindersScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedHomeCarSwitcher"]
        app.launch()

        // Garage tab → the Volvo's detail screen.
        XCTAssertTrue(app.buttons["tabbar.garage"].waitForExistence(timeout: 10))
        app.buttons["tabbar.garage"].tap()
        let carRow = app.buttons["garageCarRow"].firstMatch
        XCTAssertTrue(carRow.waitForExistence(timeout: 5))
        carRow.tap()
        XCTAssertTrue(app.navigationBars["Vehicle"].waitForExistence(timeout: 5))

        // The row sits below the fold on this screen; scroll the form until the
        // reminders link is hittable clear of the pinned save bar (the same
        // geometry the Vehicle detail suite uses: midpoint above 0.75 height).
        let remindersRow = app.buttons["vehicleDetailRemindersLink"]
        func formScrollView() -> XCUIElement {
            app.scrollViews.allElementsBoundByIndex
                .max { $0.frame.height < $1.frame.height } ?? app.scrollViews.firstMatch
        }
        let clearPoint = app.frame.height * 0.75
        var swipes = 0
        while swipes < 10, !remindersRow.isHittable || remindersRow.frame.midY > clearPoint {
            formScrollView().swipeUp()
            swipes += 1
        }
        XCTAssertTrue(remindersRow.isHittable && remindersRow.frame.midY <= clearPoint,
                      "the reminders row never reached a tappable position")

        remindersRow.tap()
        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 5),
                      "the Vehicle detail reminders row must reach the Reminders screen")
        XCTAssertTrue(app.staticTexts["No reminders yet"].waitForExistence(timeout: 5),
                      "the seeded car has no reminders - the list's empty state is the honest landing")
    }

    // MARK: - PJ.5 the notification deep link (SCREENMAP.md -> the deep link)

    /// A tapped reminder notification routes to Reminders with THAT reminder's
    /// completion sheet surfaced. The replay identifier names the seed's
    /// attention reminder by its fixed id (ReminderTestSeed.deepLinkReminderID);
    /// the assertion that the sheet is the insurance one - not whichever row is
    /// first - is what pins that the route carried the reminder id, not merely
    /// the screen.
    func testReplayedReminderTapLandsOnRemindersWithItsCompletionSheet() {
        let reminderID = "0D4B0F2A-3E1C-4B6A-9C5D-8E7F1A2B3C4D"
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedReminders",
                               "-replayNotificationResponse", "reminder.\(reminderID).date"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 10),
                      "a tapped reminder notification must land on the Reminders screen")
        XCTAssertTrue(app.buttons["reminderCompleteSkip"].waitForExistence(timeout: 5),
                      "that reminder's completion sheet must be surfaced by the tap")
        XCTAssertTrue(app.staticTexts["Insurance renewal – done"].exists,
                      "the sheet is the REMINDER the identifier named, not whichever row is first")
        XCTAssertTrue(app.buttons["tabbar.log"].isSelected,
                      "the Reminders screen is pushed on the Log tab - a tapped reminder must select it")
    }

    /// An unknown or malformed identifier is inert (hard rule 7): the app opens
    /// to its normal state, routes nowhere, and never dead-ends. The Home root
    /// (seeded with a car so `homeOdometer` renders) is what is in frame - not
    /// a stray screen.
    func testReplayedUnknownTapIsInert() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedHomeFullHistory",
                               "-replayNotificationResponse", "not-a-notification"]
        app.launch()

        XCTAssertTrue(app.staticTexts["homeOdometer"].waitForExistence(timeout: 10),
                      "an unknown identifier must open the app to its normal Home")
        XCTAssertFalse(app.navigationBars["Reminders"].exists,
                       "an unknown identifier must not route anywhere")
        XCTAssertTrue(app.buttons["tabbar.log"].isSelected,
                      "an unknown identifier must leave the launch tab selected, not switch it")
    }

    func testTypeAmountLandsInTheEntryWithThePrefill() {
        let app = launch(["-seedReminderComplete"])

        let complete = app.buttons["reminderCompleteButton"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        complete.tap()

        let typeAmount = app.buttons["reminderCompleteTypeAmount"]
        XCTAssertTrue(typeAmount.waitForExistence(timeout: 5))
        typeAmount.tap()

        // The ServiceEntry sheet opens carrying the reminder's pre-fill:
        // title, category and the current odometer.
        let itemTitle = app.textFields["serviceEntryItemTitle"].firstMatch
        XCTAssertTrue(itemTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(itemTitle.value as? String, "Oil change",
                       "the reminder title arrives as the item title")

        let odometer = app.textFields["serviceEntryOdometerField"]
        XCTAssertTrue(odometer.exists)
        XCTAssertTrue((odometer.value as? String)?.contains("119") == true,
                      "the current odometer arrives pre-filled; was \(String(describing: odometer.value))")

        // The pre-fill is editable (hard rule 13): every field is a default
        // input, never read-only.
        XCTAssertTrue(itemTitle.isEnabled, "the pre-filled title must stay editable")
        XCTAssertTrue(odometer.isEnabled, "the pre-filled odometer must stay editable")
    }

    // MARK: - PJ.7 the delete alert states the 30-day truth

    /// Deleting a reminder tombstones it (`softDeleteReminder`) - the 30-day
    /// undo holds exactly as for an entry, and the alert says so (hard rule 8:
    /// nothing lost silently). It is a confirmation, never a warning: the
    /// message must state the window and must NOT claim the delete is
    /// permanent. Mutation guards: restoring "this can't be undone", or
    /// dropping the 30-day claim, both fail here.
    func testDeleteAlertStatesTheThirtyDayTruth() {
        let app = launch(["-seedReminders"])

        let menu = app.buttons["reminderRowMenu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()

        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()

        let alert = app.alerts["Delete reminder?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        // A wrapped alert message is exposed as one element PER LINE, so the
        // visible lines are joined before matching (the Account suite's pattern).
        let message = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(message.contains("30 days"),
                      "the alert must state the 30-day undo window; was: \(message)")
        XCTAssertFalse(message.contains("can't be undone"),
                       "the alert must not claim the delete is permanent; was: \(message)")
    }

    // MARK: - P3.6 notification permission

    /// The one-time denied card (docs/ERRORS.md -> Reminders) renders when
    /// notification permission is denied and reminders exist.
    func testNotificationDeniedCardRenders() {
        let app = launch(["-notificationStatus", "denied", "-seedReminders"])

        XCTAssertTrue(app.otherElements["remindersDeniedCard"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Reminders can't notify you – they'll only show here."].exists)
        XCTAssertTrue(app.buttons["remindersPermissionEnableButton"].exists)
        XCTAssertTrue(app.buttons["remindersPermissionFineButton"].exists)
    }

    /// Nothing is notification-gated (hard rule 1): a reminder created while
    /// notifications are denied still saves and still shows in the list.
    func testReminderSavesDespiteNotificationsDenied() {
        let app = launch(["-notificationStatus", "denied", "-seedReminders"])

        // The denied card pushes "New reminder" beneath the owned tab bar, and
        // `isHittable` does not model that occlusion (the same caveat as the
        // pinned save bar): a tap then lands on the bar / the row above and
        // opens that row's EDIT form. Scroll the action clear of the bar first,
        // the way a user would.
        let newButton = app.buttons["remindersNewReminderButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))
        let tabBar = app.otherElements["tabbar"]
        var attempts = 0
        while attempts < 10,
              !newButton.isHittable || newButton.frame.maxY > tabBar.frame.minY + 1 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(newButton.frame.maxY <= tabBar.frame.minY + 1,
                      "New reminder (\(newButton.frame)) overlaps the tab bar (\(tabBar.frame))")
        newButton.tap()

        // Prove the form is NEW, not a row's edit form: the title opens empty
        // and the Add-date button renders (the form carries no due date). The
        // failure this guards against opened the seeded "Oil change" edit form
        // ("Edit reminder", title pre-filled, due date "Feb 29, 2028").
        let title = app.textFields["reminderFormTitleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let titleValue = title.value as? String
        XCTAssertTrue(titleValue == nil || titleValue == "",
                      "a new reminder must open with an empty title, was \(String(describing: titleValue))")
        XCTAssertTrue(app.buttons["reminderFormAddDateButton"].exists,
                      "a new reminder must open with no due date")
        title.tap()
        title.typeText("Brake check")

        app.buttons["reminderFormAddDateButton"].tap()

        let save = app.buttons["reminderFormSaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(app.staticTexts["Brake check"].waitForExistence(timeout: 10),
                      "a reminder saved under a denied notification state still shows in the list")
    }
}
