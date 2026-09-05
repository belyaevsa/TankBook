import XCTest

/// RV.67: the Add-car suggestion list was mounted ONLY while the Make·model
/// field held focus (`AddVehicleSections.swift: focus == .makeModel`), and the
/// whole form sits in a ScrollView that dismisses the keyboard immediately on
/// the first drag (`.scrollDismissesKeyboard(.immediately)` clears
/// `@FocusState`) - so the list unmounted MID-GESTURE, during the very scroll
/// needed to reach the lower rows of a five-row match. The fix decouples
/// visibility from focus: the list stays mounted while the field text reads as
/// a query and unmounts on apply/clear (`ModelSuggestionGate`). These tests
/// assert the BEHAVIOUR - reachable AND applied - never that "a list appeared"
/// (it always appeared; being unreachable was the bug), and never the first row
/// (it needs no scroll and passed before). The keyboard is deliberately up
/// through the scroll: that is the state the bug lives in.
@MainActor
final class RV67SuggestionScrollUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // `-homeResetDatabase` makes every launch deterministic (empty garage,
        // no session): the Add car screen is reachable from the Garage tab and
        // a saved car lands in a garage that holds exactly that car.
        app.launchArguments = ["-homeResetDatabase"] + args
        app.launch()
        return app
    }

    private func openAddCar(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["tabbar.garage"].waitForExistence(timeout: 10))
        app.buttons["tabbar.garage"].tap()
        XCTAssertTrue(app.buttons["garageAddCar"].waitForExistence(timeout: 5))
        app.buttons["garageAddCar"].tap()
        XCTAssertTrue(app.navigationBars["Add car"].waitForExistence(timeout: 5))
    }

    /// ScrollView content below the fold is queryable but not hittable; swipe
    /// until the target is reachable. A focused field's keyboard swallows
    /// plain app swipes, so the first drag dismisses it - which is exactly the
    /// gesture that used to unmount the list being scrolled to.
    ///
    /// The drag must target the TALLEST scroll view, not `firstMatch`: with the
    /// suggestion list up, the accessibility tree exposes several full-screen
    /// scroll views (the underlying tab roots stay mounted) plus stray small
    /// ones (measured on iPhone 17: a 44pt frame at the keyboard's top edge) -
    /// `firstMatch` can be any of them, and a swipe on a 44pt target never
    /// reaches the form. The tallest view is re-resolved every swipe.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
        func formScrollView() -> XCUIElement {
            app.scrollViews.allElementsBoundByIndex
                .max { $0.frame.height < $1.frame.height } ?? app.scrollViews.firstMatch
        }
        if app.keyboards.firstMatch.exists {
            formScrollView().swipeDown()
        }
        var swipes = 0
        while swipes < maxSwipes, !element.isHittable {
            formScrollView().swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.exists,
                      "\(element) does not exist after \(swipes) swipes - it was never scrolled into the hierarchy")
        XCTAssertTrue(element.isHittable, "\(element) exists but never became hittable")
    }

    /// Replaces a field's whole value (long-press -> Select All -> type). The
    /// simulator's cmd+A needs a hardware keyboard, so it is deliberately not
    /// used here.
    private func replaceText(in field: XCUIElement, app: XCUIApplication, with text: String) {
        field.tap()
        field.press(forDuration: 1.2)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) {
            selectAll.tap()
        }
        field.typeText(text)
    }

    /// Scroll an element on the pushed Vehicle detail clear of its pinned save
    /// bar (the detail screen's own form scroll view; no keyboard is up when
    /// arriving from Garage).
    private func scrollDetailTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 12) {
        func formScrollView() -> XCUIElement {
            app.scrollViews.allElementsBoundByIndex
                .max { $0.frame.height < $1.frame.height } ?? app.scrollViews.firstMatch
        }
        let clearPoint = app.frame.height * 0.75
        var swipes = 0
        while swipes < maxSwipes, !element.isHittable || element.frame.midY > clearPoint {
            formScrollView().swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.isHittable && element.frame.midY <= clearPoint,
                      "\(element) never reached a tappable position clear of the save bar")
    }

    // MARK: - The headline: scroll the form, tap the LAST suggestion

    /// Typing "Lada" mounts five rows (the Add-car limit); the last row (the
    /// Vesta - index order is the `CatalogSuggester` tie-break, pinned in
    /// `CatalogTests.ladaQueryRanksFiveRowsWithVestaLast`) starts UNDER the
    /// keyboard on iPhone 17 (measured: rows 0-3 sit above it, row 4 does not),
    /// so reaching it requires the scroll that used to destroy the list. The
    /// assertion is that the vehicle is SAVED with that row's pre-filled 55 L
    /// tank, read back off its Vehicle detail - reachable AND applied, never
    /// merely "a list appeared".
    func testScrollingToLastSuggestionSavesVehicleWithItsTank() {
        let app = launch()
        openAddCar(app)

        let makeModel = app.textFields["addVehicleMakeModelField"]
        XCTAssertTrue(makeModel.waitForExistence(timeout: 5))
        makeModel.tap()
        makeModel.typeText("Lada")

        let last = app.buttons["addVehicleSuggestion_4"]
        XCTAssertTrue(last.waitForExistence(timeout: 5), "the suggestion list must mount")
        // Precondition, so the test cannot go vacuous: with the keyboard raised
        // the LAST row is under it, and reaching it REQUIRES the scroll that
        // used to destroy the list.
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists, "the model field must keep the keyboard up while typing")
        XCTAssertGreaterThan(last.frame.maxY, keyboard.frame.minY + 1,
                             "precondition: the last suggestion must start under the keyboard, "
                             + "or this test passes without exercising the scroll")

        // The scroll that dismisses the keyboard must not unmount the list
        // being reached for (the bug: it unmounted mid-gesture).
        scrollTo(last, in: app)
        last.tap()

        // Applied: the row's values landed in the form (Vesta pre-fills a 55 L
        // tank - the SCHEMA.md worked-value pattern).
        let name = app.textFields["addVehicleNameField"]
        XCTAssertEqual(name.value as? String, "Lada Vesta")
        let capacity = app.textFields["addVehicleTankCapacityField"]
        scrollTo(capacity, in: app)
        XCTAssertEqual(capacity.value as? String, "55",
                       "the tapped row's pre-filled tank must be in the form")

        // Save, then read the tank back off the SAVED vehicle in its detail.
        // (An empty odometer raises only a warn that never blocks save.)
        app.buttons["addVehicleSaveButton"].tap()
        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5),
                      "the car was saved back to the Garage")
        let garageRow = app.buttons.matching(identifier: "garageCarRow").firstMatch
        XCTAssertTrue(garageRow.waitForExistence(timeout: 5))
        XCTAssertTrue(garageRow.label.contains("Lada Vesta"),
                      "the saved car is the one the suggestion created")
        garageRow.tap()
        XCTAssertTrue(app.navigationBars["Vehicle"].waitForExistence(timeout: 5))

        let detailCapacity = app.textFields["vehicleDetailTankCapacityField"]
        XCTAssertTrue(detailCapacity.waitForExistence(timeout: 5))
        scrollDetailTo(detailCapacity, in: app)
        XCTAssertEqual(detailCapacity.value as? String, "55",
                       "the vehicle was created with the tapped suggestion's tank")
        // Hard rule 13's second half: the applied value stays editable later.
        replaceText(in: detailCapacity, app: app, with: "60")
        XCTAssertEqual(detailCapacity.value as? String, "60",
                       "the pre-filled tank is a default the user can edit")
    }

    // MARK: - A visible row applies on the FIRST tap

    /// Pins the suspected sibling: the row's `Button` fires `onApply`, and a
    /// tap that cleared focus before it registered would land on nothing (the
    /// list unmounts on focus loss). Row 0 of a five-row "Lada" match is fully
    /// above the keyboard, so this isolates the tap itself from the scroll bug:
    /// one tap, no scroll, no retry, and the row's values are in the form.
    func testVisibleSuggestionAppliesOnFirstTap() {
        let app = launch()
        openAddCar(app)

        let makeModel = app.textFields["addVehicleMakeModelField"]
        XCTAssertTrue(makeModel.waitForExistence(timeout: 5))
        makeModel.tap()
        makeModel.typeText("Lada")

        let first = app.buttons["addVehicleSuggestion_0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        // Precondition: the target row is genuinely VISIBLE (no scroll needed).
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists, "the model field must keep the keyboard up")
        XCTAssertTrue(first.isHittable, "precondition: row 0 must be tappable with no scroll")
        XCTAssertLessThanOrEqual(first.frame.maxY, keyboard.frame.minY + 1,
                                 "precondition: row 0 must sit fully above the keyboard")

        first.tap()
        XCTAssertEqual((app.textFields["addVehicleNameField"].value as? String), "Lada Granta",
                       "the visible row applied on the first tap")
        let capacity = app.textFields["addVehicleTankCapacityField"]
        scrollTo(capacity, in: app)
        XCTAssertEqual(capacity.value as? String, "50",
                       "row 0 (Lada Granta) pre-fills its 50 L tank")
    }

    // MARK: - After apply the list is gone and the values stay editable

    /// The list must unmount the moment a value is chosen - the user must be
    /// able to SEE what they just picked - while the chosen values stay
    /// visible and editable (hard rule 13: a default input, never a fact).
    func testAppliedSuggestionDismissesListAndValuesStayEditable() {
        let app = launch()
        openAddCar(app)

        let makeModel = app.textFields["addVehicleMakeModelField"]
        XCTAssertTrue(makeModel.waitForExistence(timeout: 5))
        makeModel.tap()
        makeModel.typeText("Lada")
        let first = app.buttons["addVehicleSuggestion_0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()

        // The list is gone immediately after apply.
        XCTAssertFalse(app.buttons["addVehicleSuggestion_0"].waitForExistence(timeout: 2),
                       "the suggestion list must unmount once a value is chosen")
        XCTAssertFalse(app.buttons["addVehicleSuggestion_4"].exists,
                       "no row of the list may survive an apply")

        // The chosen values are visible in the form...
        XCTAssertEqual((app.textFields["addVehicleNameField"].value as? String), "Lada Granta")
        let capacity = app.textFields["addVehicleTankCapacityField"]
        scrollTo(capacity, in: app)
        XCTAssertEqual(capacity.value as? String, "50")

        // ...and editable again right there (defaults, never facts).
        replaceText(in: capacity, app: app, with: "45")
        XCTAssertEqual(capacity.value as? String, "45",
                       "the pre-filled tank stays editable after apply")
    }

    // MARK: - RV.47 regression: label tap still focuses the field

    /// RV.67 touches the same screen RV.47 fixed (the whole-row tap target in
    /// `FocusableFieldRow`). Tapping the Make·model row's LABEL must still
    /// focus the field and put the caret in it - a label tap is how a typist
    /// reaches an empty field whose text strip is near-invisible.
    func testTappingMakeModelLabelStillFocusesTheField() {
        let app = launch()
        openAddCar(app)

        let label = app.staticTexts["Make · model · year"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3),
                      "tapping the label must raise the keyboard")
        let makeModel = app.textFields["addVehicleMakeModelField"]
        makeModel.typeText("Volvo V60")
        XCTAssertEqual(makeModel.value as? String, "Volvo V60",
                       "the caret must be in the make·model field after a label tap")
    }
}
