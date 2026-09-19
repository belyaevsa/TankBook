import XCTest

/// RV.122 - the reminder chip strip on Home. Four seeded reminders, three of
/// them due, so the assertions are about WHICH chips and in WHAT order, with
/// the door last; the scheduled one must not appear; tapping a chip lands on
/// its reminder and tapping the door on the merged list; with nothing due the
/// strip is absent, never empty.
@MainActor
final class HomeReminderChipsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String], russian: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"]
            + (russian ? ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"] : []) + arguments
        app.launch()
        return app
    }

    /// The chips in strip order: their accessibility labels, left to right.
    private func chipLabels(_ app: XCUIApplication) -> [String] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "homeReminderChip"))
            .allElementsBoundByIndex
            .sorted { $0.frame.minX < $1.frame.minX }
            .map(\.label)
    }

    private func dueChipsInOrderWithTheDoorLast(russian: Bool) {
        let app = launch(["-seedHomeReminderChips"], russian: russian)
        let strip = app.descendants(matching: .any)["homeReminderChips"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10), "three due reminders must render the strip")

        let labels = chipLabels(app)
        XCTAssertEqual(labels.count, 4, "three due chips and the door: \(labels)")
        XCTAssertTrue(labels[0].hasPrefix("Tyre change"), "the overdue one first: \(labels)")
        XCTAssertTrue(labels[1].hasPrefix("Insurance renewal"), "then the date due in 12 days: \(labels)")
        XCTAssertTrue(labels[2].hasPrefix("Oil change"), "then the distance due in 420 km: \(labels)")
        XCTAssertEqual(labels[3], russian ? "Все напоминания" : "All reminders", "the door is the last chip")
        XCTAssertFalse(labels.contains { $0.hasPrefix("Inspection") }, "a reminder not yet due is not a chip")

        // Each chip says what and when or how far, in its own terms.
        XCTAssertTrue(labels[0].contains(russian ? "Просрочено" : "Overdue"),
                      "an overdue chip says so in words: \(labels[0])")
        XCTAssertTrue(labels[1].contains(russian ? "через 12 дней" : "in 12 days"), labels[1])
        XCTAssertTrue(labels[2].contains(russian ? "через 420 км" : "in 420 km"),
                      "a distance reminder measures from the current odometer: \(labels[2])")
    }

    func testDueChipsRenderInDueOrderWithTheDoorLast() {
        dueChipsInOrderWithTheDoorLast(russian: false)
    }

    func testDueChipsRenderInDueOrderWithTheDoorLastInRussian() {
        dueChipsInOrderWithTheDoorLast(russian: true)
    }

    func testAChipOpensItsReminder() {
        let app = launch(["-seedHomeReminderChips"])
        XCTAssertTrue(app.descendants(matching: .any)["homeReminderChips"].waitForExistence(timeout: 10))

        let oil = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
                                                   "homeReminderChip_", "Oil change")).firstMatch
        XCTAssertTrue(oil.exists)
        oil.tap()
        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 5), "a chip lands in Reminders")
        XCTAssertTrue(app.staticTexts["Oil change"].waitForExistence(timeout: 5),
                      "the landing holds the tapped reminder")
    }

    func testTheDoorChipOpensTheMergedList() {
        let app = launch(["-seedHomeReminderChips"])
        let door = app.buttons["homeReminderChipAll"]
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()
        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 5), "the door opens the merged list")
        XCTAssertTrue(app.staticTexts["Inspection"].waitForExistence(timeout: 5),
                      "the merged list holds the scheduled reminder the strip did not show")
    }

    func testNothingDueMeansNoStripAtAll() {
        let app = launch(["-seedHomeRemindersNothingDue"])
        XCTAssertTrue(app.buttons["homeRemindersRow"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["homeReminderChips"].exists, "no strip, not an empty one")
        XCTAssertFalse(app.buttons["homeReminderChipAll"].exists, "no lone door either - the calm row is the door")
    }
}
