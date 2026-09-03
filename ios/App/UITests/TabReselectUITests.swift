import XCTest

/// RV.31 L4: re-tapping the ACTIVE tab returns that tab to its root (the
/// standard iOS re-tap convention), and it never silently discards a
/// half-typed Edit entry (hard rule 8). The three load-bearing behaviours are
/// asserted by VALUE, not by dialog existence:
/// - no edits made: the re-tap pops immediately and NO dialog appears;
/// - an edit made: the re-tap asks first, and Cancel leaves the entry open
///   with the typed value STILL IN THE FIELD - a version that discards on
///   Cancel passes an existence-only check, and one that pops without asking
///   fails the moment the field is asserted;
/// - a DIFFERENT tab still switches tabs and preserves the open entry.
/// The mechanism is shared by all three tabs, so Trends and Garage each get a
/// pop-to-root case; neither has a pushed edit route today, so the dirty guard
/// is exercised on the Log, where Edit entry is pushed.
@MainActor
final class TabReselectUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The D1 golden history (`-seedHomeEditHistory`) so an Edit entry has a
    /// real fill to open, and `-presentScreen editEntry` pushes it onto the
    /// Log stack without a row tap (the tab bar is present either way - the
    /// point of the bug report).
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedHomeEditHistory",
                               "-presentScreen", "editEntry"]
        app.launch()
        return app
    }

    // MARK: - No edits: pop immediately, no dialog

    func testRetapActiveTabWithNoEditsReturnsToLogRootImmediately() {
        let app = launch()
        let total = app.textFields["manualFillUpTotalField"]
        XCTAssertTrue(total.waitForExistence(timeout: 10),
                      "the pushed Edit entry must be open before the re-tap")

        app.buttons["tabbar.log"].tap()

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5),
                      "re-tapping the active Log tab must return to the Log root")
        XCTAssertFalse(total.exists,
                       "the pushed Edit entry must be gone after the pop")
        XCTAssertFalse(app.alerts["Discard changes?"].exists,
                       "a clean re-tap must pop immediately, never ask")
    }

    // MARK: - An edit made: ask first, and Cancel keeps the typed value

    func testRetapActiveTabWithEditsAsksAndCancelKeepsTheTypedValue() {
        let app = launch()
        let total = app.textFields["manualFillUpTotalField"]
        XCTAssertTrue(total.waitForExistence(timeout: 10))

        // A real edit: replace the total. "60.00" breaks the cross-check on the
        // seeded fill (42.30 L x 1.679 = 71.02) - which is fine, save-anyway
        // exists; what matters is that the field now holds a NEW value.
        replaceText(in: total, with: "60.00", app: app)
        dismissKeyboardIfPresent(app)
        XCTAssertEqual(total.value as? String, "60.00",
                       "the edit must land in the field before the re-tap")

        // Re-tap the active tab: with unsaved work it must ASK, not pop.
        app.buttons["tabbar.log"].tap()
        let alert = app.alerts["Discard changes?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "a re-tap that would throw away an edit must ask first")

        // Cancel leaves the entry open AND the typed value in the field. A
        // version that discards anyway passes an existence-only check.
        alert.buttons["Keep editing"].tap()
        XCTAssertTrue(total.waitForExistence(timeout: 5),
                      "Cancel must leave the entry open")
        XCTAssertEqual(total.value as? String, "60.00",
                       "Cancel must keep the typed value in the field, got "
                       + "'\(total.value as? String ?? "nil")'")
        XCTAssertFalse(app.staticTexts["homeHeaderTitle"].exists,
                       "Cancel must not have popped back to the Log root")

        // Re-tap again and this time Discard: the tab returns to its root.
        app.buttons["tabbar.log"].tap()
        let second = app.alerts["Discard changes?"]
        XCTAssertTrue(second.waitForExistence(timeout: 5),
                      "the second re-tap must ask again - the edit is still there")
        second.buttons["Discard"].tap()

        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5),
                      "Discard must return to the Log root")
        XCTAssertFalse(total.exists,
                       "the Edit entry must be gone after Discard")
    }

    // MARK: - A different tab: ordinary switch, entry preserved

    func testSwitchingToAnotherTabWhileEditingPreservesTheEntry() {
        let app = launch()
        let total = app.textFields["manualFillUpTotalField"]
        XCTAssertTrue(total.waitForExistence(timeout: 10))

        // Tapping a DIFFERENT tab is an ordinary switch - the Edit entry must
        // stay pushed (each tab keeps its own stack).
        app.buttons["tabbar.garage"].tap()
        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5),
                      "the Garage tab must open")

        app.buttons["tabbar.log"].tap()
        XCTAssertTrue(total.waitForExistence(timeout: 5),
                      "switching away and back must keep the Edit entry open")
        XCTAssertFalse(app.alerts["Discard changes?"].exists,
                       "an ordinary tab switch must never ask")
    }

    // MARK: - The mechanism on the other two tabs (no pushed edit route there)

    /// Trends and Garage share the re-tap pop mechanic even though neither has
    /// a pushed edit route today. The dirty guard is consulted per-tab: the
    /// Log stack BELOW can hold a half-typed Edit entry while the user works
    /// on Trends, and re-tapping Trends must pop Trends - and must NOT ask
    /// about - or pop - the hidden Log entry.
    func testRetapTrendsPopsItsPushedScreenAndIgnoresADirtyLogEntry() {
        let app = launch()

        // Make the pushed Log entry DIRTY before leaving the Log tab, so a
        // cross-tab leak of the dirty signal would fire here.
        let total = app.textFields["manualFillUpTotalField"]
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        replaceText(in: total, with: "60.00", app: app)
        dismissKeyboardIfPresent(app)
        XCTAssertEqual(total.value as? String, "60.00")

        app.buttons["tabbar.trends"].tap()
        XCTAssertTrue(app.staticTexts["trendsHeaderTitle"].waitForExistence(timeout: 5))
        let gear = app.buttons["settingsButton"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5),
                      "Settings must be pushed on the Trends stack")

        app.buttons["tabbar.trends"].tap()

        XCTAssertTrue(app.staticTexts["trendsHeaderTitle"].waitForExistence(timeout: 5),
                      "re-tapping Trends must pop back to the Trends root")
        XCTAssertFalse(app.navigationBars["Settings"].exists,
                       "the pushed Settings screen must be gone")
        XCTAssertFalse(app.alerts["Discard changes?"].exists,
                       "the dirty entry lives on the LOG stack - re-tapping Trends "
                       + "must never ask about it")
    }

    func testRetapGaragePopsItsPushedScreenToRoot() {
        let app = launch()
        app.buttons["tabbar.garage"].tap()
        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5))
        let row = app.buttons.matching(identifier: "garageCarRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.navigationBars["Vehicle"].waitForExistence(timeout: 5),
                      "Vehicle detail must be pushed on the Garage stack")

        app.buttons["tabbar.garage"].tap()

        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5),
                      "re-tapping Garage must pop back to the Garage root")
        XCTAssertFalse(app.navigationBars["Vehicle"].exists,
                       "the pushed Vehicle detail must be gone")
        XCTAssertFalse(app.alerts["Discard changes?"].exists,
                       "a non-form pop must never ask")
    }

    // MARK: - Helpers

    /// Replaces a text field's contents without the text-selection edit menu
    /// (unreliable on the iOS 26 simulator): drop the keyboard, bring the
    /// field into the upper half (a trailing-aligned field too close to the
    /// bottom cannot summon the number pad), tap the right edge so the cursor
    /// lands at the end, delete the current text one keystroke at a time, then
    /// type the replacement. Same pattern as EditEntryUITests.
    private func replaceText(in field: XCUIElement, with text: String, app: XCUIApplication) {
        dismissKeyboardIfPresent(app)
        var attempts = 0
        while field.frame.minY > 300 && attempts < 8 {
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

    /// The Edit entry's scroll view dismisses the keyboard on scroll
    /// (`.scrollDismissesKeyboard(.immediately)`); a swipe-down does it without
    /// needing a keyboard key. The tab bar is COVERED by the keyboard while it
    /// is up, so a re-tap needs the keyboard gone first.
    private func dismissKeyboardIfPresent(_ app: XCUIApplication) {
        if app.keyboards.firstMatch.exists {
            app.swipeDown()
        }
    }
}
