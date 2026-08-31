import XCTest

/// P1.2 Add car screen tests. Each of the three ERRORS.md states is asserted
/// with its next-step affordance present (not just its text): the empty-name
/// warn blocks save and clears live as soon as a name is typed; the odometer
/// warn never blocks save and "confirm it's right" is one tap; the offline
/// catalog hint renders and blocks nothing. Plus: a catalog suggestion copies
/// its values into the form.
@MainActor
final class AddVehicleUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // `-homeResetDatabase` makes every launch deterministic: without it a
        // default launch passes NO arguments, so a pristine device shows
        // Welcome and a dirty device (three cars from earlier suites) hits the
        // free-tier cap - the Add car screen is reachable from neither.
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
    /// until the target is tappable. A focused field's keyboard swallows plain
    /// app swipes, so dismiss it first via the scroll view's own drag
    /// (the screen uses `.scrollDismissesKeyboard(.immediately)`).
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
        let scrollView = app.scrollViews.firstMatch
        if app.keyboards.firstMatch.exists {
            scrollView.swipeDown()
        }
        // `isHittable` tests an element's CENTRE, so it turns true while the
        // element's bottom edge is still under the keyboard or the floating tab
        // bar - the tap then lands on the obstruction. Under load the layout
        // settles later and the race flips, which is why these two tests passed
        // alone and failed in a full suite (HANDOVER: load-sensitive UI tests).
        // Scroll until the element's FRAME clears the keyboard, not until its
        // centre is nominally hittable - the same fix HomeUITests already uses
        // for the floating tab bar.
        var swipes = 0
        while swipes < maxSwipes, !isFullyClear(element, in: app) {
            scrollView.swipeUp()
            swipes += 1
        }
        // Report existence FIRST, and never interpolate `.frame` unguarded: on a
        // missing element XCUITest throws "Failed to get matching snapshot"
        // while building the message, which replaces the real diagnosis with a
        // misleading one. That is what hid this failure's true cause.
        XCTAssertTrue(element.exists,
                      "\(element) does not exist after \(swipes) swipes - it was never scrolled into the hierarchy")
        XCTAssertTrue(element.isHittable, "\(element) exists but never became hittable")
        XCTAssertTrue(isFullyClear(element, in: app),
                      "\(element) is still obstructed after \(swipes) swipes")
    }

    /// KNOWN, NOT FIXED (2026-08-24). `testConfirmItIsRightIsOneTap` and
    /// `testImplausibleOdometerWarnsButNeverBlocksSave` pass on iPhone 17 and
    /// fail on iPhone 17 Pro Max **in isolation**, so this is not the load
    /// sensitivity it was first diagnosed as.
    ///
    /// The frame-clearing fix below is a genuine improvement and was wrongly
    /// credited with fixing these two. The real failure is later and different:
    /// `scrollTo` succeeds, `odometer.tap()` succeeds, and then
    /// `odometer.typeText(...)` fails with "No matches found for Descendants
    /// matching type TextField" - the field leaves the accessibility tree
    /// between the tap and the typing, on that device only. Suspect the form
    /// re-laying out under keyboard avoidance and the element handle going
    /// stale, but that is a hypothesis, not a diagnosis.
    ///
    /// Do not "fix" it by adding sleeps. Reproduce with:
    ///   xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
    ///     -only-testing:TankbookUITests/AddVehicleUITests test
    /// True when the element is hittable AND its whole frame sits above the
    /// keyboard, so a tap cannot land on the obstruction.
    private func isFullyClear(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists, keyboard.frame.height > 0 {
            return element.frame.maxY <= keyboard.frame.minY + 1
        }
        return true
    }

    // MARK: - Error-state 1: empty name on save

    func testEmptyNameBlocksSaveAndReenablesLive() {
        let app = launch()
        openAddCar(app)

        let save = app.buttons["addVehicleSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))

        // Saving with no name is blocked and the warn names its next step.
        save.tap()
        let warning = app.staticTexts["addVehicleNameWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Give the car any name – you can change it later."].exists)
        XCTAssertTrue(app.navigationBars["Add car"].exists, "nothing was saved")

        // Typing a name clears the warn live and re-enables save.
        let name = app.textFields["addVehicleNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("My car")
        XCTAssertFalse(warning.exists)

        save.tap()
        // Save succeeded: back on Garage.
        XCTAssertTrue(app.navigationBars["Garage"].waitForExistence(timeout: 5))
    }

    // MARK: - Error-state 2: odometer missing/implausible

    func testImplausibleOdometerWarnsButNeverBlocksSave() {
        let app = launch()
        openAddCar(app)

        let name = app.textFields["addVehicleNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("My car")

        // A 2015 car reporting 12 km is implausible (docs/ERRORS.md example).
        let makeModel = app.textFields["addVehicleMakeModelField"]
        makeModel.tap()
        makeModel.typeText("Volvo V60 2015")

        let odometer = app.textFields["addVehicleOdometerField"]
        scrollTo(odometer, in: app)
        odometer.tap()
        odometer.typeText("12")

        // The warn renders with its next-step affordance, not just its text.
        let warning = app.staticTexts["addVehicleOdometerWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["That's the total distance the car has driven – check the dashboard."].exists)
        XCTAssertTrue(app.buttons["addVehicleOdometerConfirmButton"].exists)
        XCTAssertTrue(app.buttons["addVehicleOdometerFixButton"].exists)

        // Saving with the warning up must still succeed - the warn never blocks.
        let save = app.buttons["addVehicleSaveButton"]
        scrollTo(save, in: app)
        save.tap()
        XCTAssertTrue(app.navigationBars["Garage"].waitForExistence(timeout: 5))
    }

    func testConfirmItIsRightIsOneTap() {
        let app = launch()
        openAddCar(app)

        let name = app.textFields["addVehicleNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("My car")

        let makeModel = app.textFields["addVehicleMakeModelField"]
        makeModel.tap()
        makeModel.typeText("Volvo V60 2015")

        let odometer = app.textFields["addVehicleOdometerField"]
        scrollTo(odometer, in: app)
        odometer.tap()
        odometer.typeText("12")

        let warning = app.staticTexts["addVehicleOdometerWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 3))

        // One tap on the confirm affordance dismisses the warn.
        let confirm = app.buttons["addVehicleOdometerConfirmButton"]
        scrollTo(confirm, in: app)
        confirm.tap()
        XCTAssertFalse(warning.waitForExistence(timeout: 2))
    }

    // MARK: - Error-state 3: catalog offline (hint, nothing blocks)

    func testCatalogOfflineHintRendersAndBlocksNothing() {
        let app = launch(args: ["-forceCatalogUnavailable"])
        openAddCar(app)

        let hint = app.staticTexts["addVehicleCatalogHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        let hintCopy = "Suggestions unavailable offline – you can fill tank size later in Garage."
        XCTAssertTrue(app.staticTexts[hintCopy].exists)

        // Nothing is blocked: the form still works (continue manually).
        let name = app.textFields["addVehicleNameField"]
        XCTAssertTrue(name.exists)
        name.tap()
        name.typeText("My car")
        let save = app.buttons["addVehicleSaveButton"]
        save.tap()
        XCTAssertTrue(app.navigationBars["Garage"].waitForExistence(timeout: 5))
    }

    // MARK: - Suggestion pre-fill

    func testCatalogSuggestionPrefillsNameAndTankCapacity() {
        let app = launch()
        openAddCar(app)

        let makeModel = app.textFields["addVehicleMakeModelField"]
        XCTAssertTrue(makeModel.waitForExistence(timeout: 5))
        makeModel.tap()
        makeModel.typeText("Volvo V60")

        // A suggestion renders; tapping it copies catalog values into the form.
        let suggestion = app.buttons["addVehicleSuggestion_0"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()

        let name = app.textFields["addVehicleNameField"]
        XCTAssertEqual(name.value as? String, "Volvo V60")

        // Volvo V60 = 71 L (the SCHEMA.md worked example).
        let capacity = app.textFields["addVehicleTankCapacityField"]
        scrollTo(capacity, in: app)
        XCTAssertEqual(capacity.value as? String, "71")
    }

    // MARK: - P2.3c fuel pills: diesel + petrol is discouraged, never blocked

    /// The corrected fuel-kind rule (P2.3c, docs/DESIGN.md): `Vehicle.fuelKinds`
    /// is a suggestion, not a limit (hard rule 13). Diesel + petrol is almost
    /// certainly a misconfigured car, but a wrong configuration is correctable
    /// and is not a data-integrity failure, so the pair must be SAVABLE. The
    /// pill is never disabled; instead the screen flags the unusual fit with a
    /// warning that names the next step. `isEnabled` is the assertion - a
    /// blocked pill is the refusal being removed - and `isSelected` proves the
    /// pair actually persists together.
    func testFuelPillsAllowDieselWithPetrolButWarn() {
        let app = launch()
        openAddCar(app)

        // The locale default is a petrol car, and diesel is selectable beside
        // it - the refusal P2.3b shipped is gone.
        let petrol95 = app.buttons["addVehicleFuelKind_petrol95"]
        scrollTo(petrol95, in: app)
        XCTAssertTrue(petrol95.isSelected, "the locale default is a petrol car")
        XCTAssertTrue(app.buttons["addVehicleFuelKind_diesel"].isEnabled,
                      "diesel must never be blocked beside petrol")
        XCTAssertTrue(app.buttons["addVehicleFuelKind_petrol98"].isEnabled,
                      "petrol grades share a tank and are a real choice")

        // Selecting diesel beside petrol is savable and flags the unusual fit.
        let diesel = app.buttons["addVehicleFuelKind_diesel"]
        diesel.tap()
        XCTAssertTrue(diesel.isSelected, "diesel lands in the selection")
        XCTAssertTrue(petrol95.isSelected, "selecting diesel must not drop the petrol grade")
        let warning = app.staticTexts["addVehicleFuelKindWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 3),
                      "the diesel + petrol pair must be flagged, not silenced")
        XCTAssertTrue(app.staticTexts["Diesel and petrol don't normally share a car – check it."].exists)

        // Dropping diesel clears the warning, and a realistic pair stays quiet.
        diesel.tap()
        XCTAssertFalse(diesel.isSelected)
        XCTAssertFalse(warning.waitForExistence(timeout: 2))
        let lpg = app.buttons["addVehicleFuelKind_lpg"]
        XCTAssertTrue(lpg.isEnabled, "petrol + LPG is a real car")
        lpg.tap()
        XCTAssertTrue(lpg.isSelected, "LPG lands in the selection")
        XCTAssertTrue(petrol95.isSelected, "selecting LPG must not drop the petrol grade")
        XCTAssertFalse(app.staticTexts["addVehicleFuelKindWarning"].exists,
                       "a realistic combination raises no warning")
    }

    func testFuelPillsAllowPetrolWithDieselButWarn() {
        let app = launch()
        openAddCar(app)

        // Drop every selected petrol grade so diesel becomes the selection (the
        // RU locale defaults to 92 + 95, so loop rather than assume one).
        let petrol95 = app.buttons["addVehicleFuelKind_petrol95"]
        scrollTo(petrol95, in: app)
        for identifier in ["addVehicleFuelKind_petrol92",
                           "addVehicleFuelKind_petrol95",
                           "addVehicleFuelKind_petrol98"] {
            let pill = app.buttons[identifier]
            if pill.exists && pill.isSelected {
                pill.tap()
            }
        }
        XCTAssertFalse(petrol95.isSelected, "the petrol grade was dropped")

        // Diesel is selectable, and selecting it blocks nothing.
        let diesel = app.buttons["addVehicleFuelKind_diesel"]
        XCTAssertTrue(diesel.isEnabled, "diesel is selectable once no petrol grade is chosen")
        diesel.tap()
        XCTAssertTrue(diesel.isSelected)

        // Petrol is still selectable beside diesel - the pair is savable and
        // flagged, never refused.
        XCTAssertTrue(petrol95.isEnabled, "petrol must never be blocked beside diesel")
        petrol95.tap()
        XCTAssertTrue(petrol95.isSelected)
        XCTAssertTrue(diesel.isSelected)
        XCTAssertTrue(app.staticTexts["addVehicleFuelKindWarning"].waitForExistence(timeout: 3),
                      "the petrol + diesel pair must be flagged, not silenced")

        // Diesel + LPG is a real conversion: still selectable, and it persists.
        let lpg = app.buttons["addVehicleFuelKind_lpg"]
        XCTAssertTrue(lpg.isEnabled, "diesel + LPG is a real conversion")
        lpg.tap()
        XCTAssertTrue(lpg.isSelected, "LPG lands beside diesel")
        XCTAssertTrue(diesel.isSelected, "selecting LPG must not drop diesel")
    }
}
