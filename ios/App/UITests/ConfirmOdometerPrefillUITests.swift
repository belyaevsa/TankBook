import XCTest

/// P1.13: the Confirm sheet's pre-filled odometer must arrive grouped, exactly
/// like `ServiceEntry` and Home, all through the same shared `OdometerFormat`.
/// The defect was the Confirm prefill writing raw digits (`119486`) and only
/// grouping on blur, while Home rendered `119 486` from the same formatter -
/// the shared formatter was correct and one screen bypassed it. Kept in their
/// own suite because the ConfirmManual suite is at the file-length ceiling (the
/// NumericInputUITests precedent).
@MainActor
final class ConfirmOdometerPrefillUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A clean database so the seed holds exactly one prior fill at 119 486 km -
    /// the last-known value the Confirm sheet pre-fills.
    private func launchClean() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedVehicleForUITests", "-homeResetDatabase"]
        app.launch()
        return app
    }

    private func openManualForm(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["typeItButton"].waitForExistence(timeout: 10))
        app.buttons["typeItButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
    }

    private func fieldValue(_ app: XCUIApplication, _ identifier: String) -> String {
        (app.textFields[identifier].value as? String) ?? ""
    }

    /// Bring a field on screen and tap it. The stop condition is GEOMETRIC:
    /// `isHittable` is true under the pinned Save bar, and a tap there saves the
    /// sheet (the ConfirmManualUITests rule).
    private func focusField(_ app: XCUIApplication, _ identifier: String) {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "\(identifier) never appeared")
        let bar = app.buttons["manualFillUpSaveButton"]
        var scrolls = 0
        while scrolls < 8 {
            let barTop = bar.exists ? bar.frame.minY : app.windows.firstMatch.frame.maxY
            if field.isHittable && field.frame.maxY < barTop - 8 { break }
            if let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
                from.press(forDuration: 0.05, thenDragTo: to)
            }
            scrolls += 1
        }
        XCTAssertTrue(field.isHittable, "\(identifier) is on screen but not reachable")
        field.tap()
    }

    /// Polls until the field's value settles at `expected`: the blur regrouping
    /// lands asynchronously, and a plain equality assert could read a transient.
    private func waitForFieldValue(_ app: XCUIApplication, _ identifier: String, _ expected: String) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let field = app.textFields[identifier]
        expectation(for: predicate, evaluatedWith: field)
        waitForExpectations(timeout: 5)
    }

    // MARK: - L1: grouped on arrival, type-in-raw / group-on-blur round trip

    /// The pre-filled odometer arrives grouped (`119 486`, never `119486`) and
    /// survives a focus/blur round trip with the parsed value unchanged. A
    /// string-only assert cannot see the P1.13 bug (the grouped STRING is the
    /// same on both screens); this one drives the field through focus and blur.
    func testPrefilledOdometerArrivesGroupedAndSurvivesFocusBlur() {
        let app = launchClean()
        openManualForm(app)

        let odometer = app.textFields["manualFillUpOdometerField"]
        XCTAssertTrue(odometer.waitForExistence(timeout: 5))
        XCTAssertEqual(fieldValue(app, "manualFillUpOdometerField"),
                       "119\u{00A0}486",
                       "the pre-fill must render grouped, was \(fieldValue(app, "manualFillUpOdometerField"))")

        // Focus strips the grouping: raw digits belong in a field being typed
        // into, never grouped display text.
        focusField(app, "manualFillUpOdometerField")
        XCTAssertEqual(fieldValue(app, "manualFillUpOdometerField"), "119486",
                       "focus must strip the grouping for typing")

        // Blur restores it, and the parsed value is unchanged end to end.
        app.swipeDown()
        waitForFieldValue(app, "manualFillUpOdometerField", "119\u{00A0}486")
        XCTAssertEqual(fieldValue(app, "manualFillUpOdometerField")
                           .replacingOccurrences(of: "\u{00A0}", with: ""),
                       "119486",
                       "the round trip must leave the parsed odometer unchanged")
    }

    // MARK: - L4: Confirm and Home render the same figure

    /// The assertion that catches a screen going its own way: Confirm and Home
    /// both render the SAME odometer data through the same shared
    /// `OdometerFormat`, so the grouped figures must be identical. The
    /// `-seedHomeFullHistory` history tops out at 123 600 km: Home's garage
    /// card shows it, and the Confirm sheet's last-known prefill derives from
    /// the same entries - one figure, two surfaces. Home's label carries the
    /// unit; the grouped figure is the part that has to match.
    func testConfirmAndHomeRenderTheSameGroupedOdometer() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn",
                               "-seedHomeFullHistory"]
        app.launch()

        let homeOdometer = app.staticTexts["homeOdometer"].firstMatch
        XCTAssertTrue(homeOdometer.waitForExistence(timeout: 10))
        XCTAssertTrue(homeOdometer.label.contains("123\u{00A0}600"),
                      "Home must render the grouped figure, was '\(homeOdometer.label)'")

        openManualForm(app)
        XCTAssertEqual(fieldValue(app, "manualFillUpOdometerField"),
                       "123\u{00A0}600",
                       "Confirm and Home must render the same grouped figure, "
                           + "was \(fieldValue(app, "manualFillUpOdometerField"))")
    }
}
