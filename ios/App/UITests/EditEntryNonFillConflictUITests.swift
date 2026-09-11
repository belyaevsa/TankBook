import XCTest

/// RV.230: the F9a warn on a non-fill EDIT. A service edited into a timeline
/// conflict must render the same amber warn row and the same single Fix the
/// fill-up edit uses - through the shared `F9aWarningRow`/`F9aFixRow` and
/// `F9aFixPresentation` - and correcting the reading must clear the flag.
///
/// Split from `EditEntryUITests` (which the row named) because that class is
/// already over the linter's type-body ceiling; `EditEntryNeighbourhoodUITests`
/// was split out for the same reason. The seed and the surface are identical to
/// what `EditEntryUITests` would have carried.
@MainActor
final class EditEntryNonFillConflictUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(ru: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        // `-seedSettingsSignedIn`: the save-and-reopen step reads the Log on
        // Home, and a guest Home renders no Log (RV.197). Without the seed the
        // test passes only on a Keychain session another run left behind.
        app.launchArguments = ["-homeResetDatabase", "-seedEditEntryServiceConflict",
                               "-seedSettingsSignedIn", "-presentScreen", "editEntry"]
        if ru {
            app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        }
        app.launch()
        return app
    }

    /// Replaces a trailing-aligned text field's contents, assuming the field
    /// already holds keyboard focus (the Fix tap focuses it). Avoids the
    /// text-selection edit menu, unreliable on the iOS 26 simulator.
    private func replaceFocusedText(in field: XCUIElement, with text: String) {
        let current = (field.value as? String) ?? ""
        if !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                                  count: current.count))
        }
        field.typeText(text)
    }

    /// Scrolls an element clear of the pinned save bar's top: `isHittable` is
    /// true UNDER the bar, and a tap there hits Save instead (the PJ.7e failure,
    /// the same helper `EditEntryUITests` uses). The non-fill service form puts
    /// the expanded warn row below the fold, under the bar.
    private func scrollClearOfSaveBar(_ app: XCUIApplication, _ element: XCUIElement) {
        let bar = app.buttons["editEntrySaveButton"]
        var scrolls = 0
        while scrolls < 8 {
            let barTop = bar.exists ? bar.frame.minY : app.windows.firstMatch.frame.maxY
            if element.isHittable && element.frame.maxY < barTop - 8 { return }
            guard let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable })
            else { return }
            let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            from.press(forDuration: 0.05, thenDragTo: to)
            scrolls += 1
        }
    }

    /// The amber row and exactly one Fix; tapping Fix and correcting the
    /// odometer clears the warn live, and the saved entry no longer re-flags.
    func testNonFillEditShowsTheF9aWarnAndSingleFix() {
        let app = launch()

        let warning = app.staticTexts["editEntryNonFillOdometerWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 10),
                      "a conflicting service edit must render the amber F9a warn")
        XCTAssertTrue(warning.label.contains("already recorded"),
                      "the warn must quote the conflicting entry, got '\(warning.label)'")

        // Exactly one fix, and it is the odometer fix - never the fill-up's
        // ranked list (which would also offer a date fix here).
        XCTAssertEqual(app.buttons.matching(identifier: "editEntryNonFillOdometerFixButton").count, 1,
                       "the non-fill warn presents exactly one Fix")
        XCTAssertFalse(app.buttons["manualFillUpOdometerFixDateButton"].exists,
                       "a non-fill conflict must not present the fill-up's date fix")

        // Tapping Fix focuses the odometer; correcting the reading clears the
        // warn live, exactly as the fill-up odometer card behaves.
        let fix = app.buttons["editEntryNonFillOdometerFixButton"]
        scrollClearOfSaveBar(app, fix)
        fix.tap()
        let odometer = app.textFields["editEntryOdometerField"]
        XCTAssertTrue(odometer.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "Fix must focus the odometer")
        replaceFocusedText(in: odometer, with: "118600")
        XCTAssertFalse(warning.waitForExistence(timeout: 3),
                       "a corrected reading must clear the warn")

        // Save and reopen: the flag is gone from the entry, not only the view.
        let save = app.buttons["editEntrySaveButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))

        let reopen = app.buttons.matching(identifier: "logEntryButton").firstMatch
        XCTAssertTrue(reopen.waitForExistence(timeout: 10))
        reopen.tap()
        XCTAssertTrue(app.textFields["editEntryOdometerField"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["editEntryNonFillOdometerWarning"].waitForExistence(timeout: 3),
                       "the corrected entry must not re-flag on reopen")
    }

    /// The same warn in Russian: the quote is a full localised sentence naming
    /// the neighbour, and the one Fix is the localised "Исправить" - RU is where
    /// the longer sentence sits beside the chip.
    func testNonFillEditWarnRendersInRussian() {
        let app = launch(ru: true)

        let warning = app.staticTexts["editEntryNonFillOdometerWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 10),
                      "the RU F9a warn must render")
        XCTAssertTrue(warning.label.contains("уже"),
                      "the RU warn must be the localised sentence, got '\(warning.label)'")
        let fix = app.buttons["editEntryNonFillOdometerFixButton"]
        XCTAssertTrue(fix.exists, "the RU Fix must render")
        XCTAssertEqual(fix.label, "Исправить", "the Fix must be localised, got '\(fix.label)'")
    }
}
