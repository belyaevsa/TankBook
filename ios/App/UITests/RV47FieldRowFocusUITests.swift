import XCTest

/// RV.47: tapping a field's label must focus its input. The reported bug: a
/// user clicks the field's NAME - "Odometer", "Note" - and nothing happens,
/// because `FieldRow` was an inert HStack and an empty, placeholder-less text
/// field collapses to a near-zero-width target on the row's right edge. The
/// fix makes the WHOLE row (label, the gap beside it, value) the tap target
/// that focuses its field, on every screen `FieldRow` fed. So these tests
/// assert BEHAVIOUR on two screens (Confirm, Edit entry) and never mere
/// existence: tapping the label or the gap must put the keyboard up with the
/// caret in THAT field, a picker row must stay inert, and the focusable row
/// must be >= 44pt tall (the accessibility floor is the measurable half of
/// this bug - a row that regresses to a collapsed strip is exactly the state
/// the user could not find).
@MainActor
final class RV47FieldRowFocusUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Launch + navigation

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + args
        app.launch()
        return app
    }

    /// The typed door on Home, exactly as ConfirmManualUITests opens it: the
    /// seeded car pre-fills the odometer, so the empty-field case below clears
    /// it first (the vacuous-trap rule: a pre-filled field was always wide and
    /// hittable; the broken state is the empty one).
    private func openConfirmManual(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["typeItButton"].waitForExistence(timeout: 10))
        app.buttons["typeItButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
    }

    private func openNewestFillEdit(_ app: XCUIApplication) {
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 10),
                      "Edit entry did not load its fill form")
    }

    /// Scroll an element clear of the pinned save bar's top. `isHittable` is
    /// true UNDER the bar (the accessibility tree does not model the
    /// `safeAreaInset` overlay), and a tap there hits Save - the PJ.7e lesson.
    private func scrollClearOfSaveBar(_ app: XCUIApplication, _ element: XCUIElement,
                                      barIdentifier: String) {
        let bar = app.buttons[barIdentifier]
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

    private func keyboardUp(_ app: XCUIApplication) -> Bool {
        app.keyboards.firstMatch.waitForExistence(timeout: 3)
    }

    private func fieldValue(_ app: XCUIApplication, _ identifier: String) -> String {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        return (element.value as? String) ?? ""
    }

    // MARK: - Confirm (numeric row, empty)

    /// Make the odometer genuinely EMPTY: the seed pre-fills the last known
    /// reading, and a field that already shows a wide value was always
    /// hittable - the bug is the collapsed empty field. Focus it directly,
    /// delete everything, then blur so the row sits in the broken state the
    /// fix targets.
    private func emptyOdometerOnConfirm(_ app: XCUIApplication) {
        let field = app.textFields["manualFillUpOdometerField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        scrollClearOfSaveBar(app, field, barIdentifier: "manualFillUpSaveButton")
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(keyboardUp(app), "the odometer must focus to be cleared")
        let current = (field.value as? String) ?? ""
        if !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        XCTAssertTrue((fieldValue(app, "manualFillUpOdometerField")).isEmpty,
                      "the odometer must be empty before the label-tap assertion")
        // Blur: the form scroll dismisses the keyboard; the empty collapsed
        // field is now the state the user could not find.
        app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable })?.swipeDown()
        XCTAssertFalse(keyboardUp(app), "the keyboard must be down before tapping the label")
    }

    /// The odometer row's label text, on screen and clear of the save bar.
    private func odometerLabel(_ app: XCUIApplication) -> XCUIElement {
        let label = app.staticTexts["Odometer"]
        XCTAssertTrue(label.waitForExistence(timeout: 5), "the Odometer label must render")
        scrollClearOfSaveBar(app, label, barIdentifier: "manualFillUpSaveButton")
        XCTAssertTrue(label.isHittable, "the Odometer label must be reachable")
        return label
    }

    func testTappingConfirmOdometerLabelFocusesTheEmptyField() {
        let app = launch(["-seedVehicleForUITests"])
        openConfirmManual(app)
        emptyOdometerOnConfirm(app)

        let label = odometerLabel(app)
        label.tap()

        XCTAssertTrue(keyboardUp(app),
                      "tapping the label must put the keyboard up (the field is focused)")
        let odometer = app.textFields["manualFillUpOdometerField"]
        odometer.typeText("120000")
        XCTAssertEqual(fieldValue(app, "manualFillUpOdometerField"), "120000",
                       "the caret must be in the odometer field, not elsewhere")
    }

    func testTappingConfirmOdometerGapFocusesTheEmptyField() {
        let app = launch(["-seedVehicleForUITests"])
        openConfirmManual(app)
        emptyOdometerOnConfirm(app)

        // RV.10's geometry: a point in the empty stretch BETWEEN the label and
        // the trailing value - dead before the fix, live now.
        let label = odometerLabel(app)
        let gapTap = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: label.frame.maxX + 40, dy: label.frame.midY))
        gapTap.tap()

        XCTAssertTrue(keyboardUp(app),
                      "tapping the gap beside the label must focus the field")
        let odometer = app.textFields["manualFillUpOdometerField"]
        odometer.typeText("120000")
        XCTAssertEqual(fieldValue(app, "manualFillUpOdometerField"), "120000",
                       "the caret must be in the odometer field after a gap tap")
    }

    // MARK: - Confirm (picker row must stay inert)

    func testTappingConfirmFuelLabelDoesNotStealFocusOrBecomeButton() {
        let app = launch(["-seedVehicleForUITests"])
        openConfirmManual(app)

        // The Fuel row's value is a picker (menu/chips) with its own tap
        // behaviour: the row must stay INERT - tapping its label neither opens
        // the keyboard nor trips the picker.
        let fuelLabel = app.staticTexts["Fuel"]
        XCTAssertTrue(fuelLabel.waitForExistence(timeout: 5), "the Fuel label must render")
        scrollClearOfSaveBar(app, fuelLabel, barIdentifier: "manualFillUpSaveButton")
        XCTAssertTrue(fuelLabel.isHittable, "the Fuel label must be reachable")
        fuelLabel.tap()

        XCTAssertFalse(keyboardUp(app),
                       "a picker row's label must not focus any field")
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].exists,
                      "the sheet must be unchanged after the tap")
    }

    // MARK: - Confirm (the 44pt floor, measured on the row)

    func testFocusableRowIsAtLeast44PtTall() {
        let app = launch(["-seedVehicleForUITests"])
        openConfirmManual(app)

        // The row is an accessibility container (the whole row is the tap
        // target), so its FRAME is measurable - and the frame, not the
        // collapsed empty field's frame, is the hit target the floor applies
        // to. A regression to a collapsed strip fails right here.
        let row = app.otherElements["manualFillUpOdometerRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the focusable row must be exposed")
        scrollClearOfSaveBar(app, row, barIdentifier: "manualFillUpSaveButton")
        XCTAssertTrue(row.isHittable, "the row must be reachable to be measured")
        XCTAssertGreaterThanOrEqual(row.frame.height, 44,
                                    "the hit target must meet the 44pt floor, was \(row.frame.height)")
    }

    // MARK: - Edit entry (numeric + text rows on a second screen)

    /// The typed-fill edit: odometer 119 486 pre-filled, note empty. The point
    /// of fixing the shared component is that it lands on every screen, so a
    /// second screen's rows must answer the same taps.
    private func openEditEntryTyped(_ app: XCUIApplication) {
        openNewestFillEdit(app)
    }

    func testTappingEditOdometerLabelFocusesTheNumericField() {
        let app = launch(["-seedEditEntryTyped", "-presentScreen", "editEntry"])
        openEditEntryTyped(app)

        let label = app.staticTexts["Odometer"]
        XCTAssertTrue(label.waitForExistence(timeout: 5), "the Edit Odometer label must render")
        scrollClearOfSaveBar(app, label, barIdentifier: "editEntrySaveButton")
        XCTAssertTrue(label.isHittable, "the Edit Odometer label must be reachable")
        label.tap()

        XCTAssertTrue(keyboardUp(app),
                      "tapping the Edit Odometer label must focus the field")
        let odometer = app.textFields["manualFillUpOdometerField"]
        odometer.typeText("0")
        let value = fieldValue(app, "manualFillUpOdometerField")
        XCTAssertTrue(value.hasSuffix("0") && value.count > 6,
                      "typing must land in the odometer field, got '\(value)'")
    }

    func testTappingEditNoteLabelFocusesTheTextField() {
        let app = launch(["-seedEditEntryTyped", "-presentScreen", "editEntry"])
        openEditEntryTyped(app)

        let label = app.staticTexts["Note"]
        XCTAssertTrue(label.waitForExistence(timeout: 5), "the Note label must render")
        scrollClearOfSaveBar(app, label, barIdentifier: "editEntrySaveButton")
        XCTAssertTrue(label.isHittable, "the Note label must be reachable")
        label.tap()

        XCTAssertTrue(keyboardUp(app),
                      "tapping the Note label must focus the note field")
        let note = app.descendants(matching: .any).matching(identifier: "editEntryNoteField").firstMatch
        note.typeText("highway")
        let value = (note.value as? String) ?? ""
        XCTAssertTrue(value.contains("highway"),
                      "typing must land in the note field, got '\(value)'")
    }
}
