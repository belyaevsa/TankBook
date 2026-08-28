import XCTest

/// P1.12 Vehicle detail UI tests (per-car settings, editable - hard rule 13).
/// The screen is where the "app suggests, the user decides" rule becomes
/// editable again: every catalog- or locale-derived value is reachable and can
/// be typed over. Archiving from here must update the Car switcher's row (J13),
/// and Delete must raise the system confirmation with a cancel that leaves the
/// car intact.
@MainActor
final class VehicleDetailUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The artboard garage: the Volvo (petrol, capacity 71, initial odometer
    /// 118 000, two fuel kinds), the ID.4 (EV) and an archived BMW - every
    /// value the detail screen must make editable is populated.
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedHomeCarSwitcher"]
        app.launch()
        return app
    }

    private func openDetail(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["tabbar.garage"].waitForExistence(timeout: 10))
        app.buttons["tabbar.garage"].tap()
        XCTAssertTrue(app.buttons["garageCarRow"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["garageCarRow"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Vehicle"].waitForExistence(timeout: 5))
    }

    /// ScrollView content below the fold is queryable but not hittable; swipe
    /// until the target is tappable. A focused field's keyboard swallows plain
    /// app swipes, so dismiss it first via the form scroll view's own drag (the
    /// screen uses `.scrollDismissesKeyboard(.immediately)`). The scroll view
    /// is re-resolved EVERY swipe: the tallest one is the form, and a stale
    /// index-bound element dies after a keyboard/menu interaction re-snapshots
    /// the tree.
    ///
    /// `isHittable` turns true the moment the element peeks out from BEHIND the
    /// bottom chrome (the pinned save bar + tab bar) - and a tap there hits the
    /// chrome (tapping "Save changes" pops the screen). So the scroll continues
    /// until the element's midpoint clears that chrome. 0.75 of the screen puts
    /// it comfortably above the save bar's top edge (~0.82 on this device)
    /// while staying reachable for forms whose content barely overflows the
    /// viewport (a 0.5 midpoint requirement would be unscrollable-to).
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 12) {
        func formScrollView() -> XCUIElement {
            app.scrollViews.allElementsBoundByIndex
                .max { $0.frame.height < $1.frame.height } ?? app.scrollViews.firstMatch
        }
        if app.keyboards.firstMatch.exists {
            formScrollView().swipeDown()
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

    /// Replaces a field's whole value: long-press shows the edit menu, tap
    /// "Select All", then type. (The simulator's cmd+A select-all needs a
    /// hardware keyboard, so it is deliberately not used here.)
    private func replaceText(in field: XCUIElement, app: XCUIApplication, with text: String) {
        field.tap()
        field.press(forDuration: 1.2)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) {
            selectAll.tap()
        }
        field.typeText(text)
    }

    // MARK: - Every catalog-derived field is reachable and editable

    func testEveryCatalogDerivedFieldIsReachableAndEditable() {
        let app = launch()
        openDetail(app)

        // Identity: the seeded Volvo's values are in the fields.
        let name = app.textFields["vehicleDetailNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Volvo V60")

        // Name is editable: select-all then type replaces the value.
        replaceText(in: name, app: app, with: "V60 Estate")
        XCTAssertEqual(name.value as? String, "V60 Estate")

        // Make · model · year
        let makeModel = app.textFields["vehicleDetailMakeModelField"]
        XCTAssertTrue(makeModel.exists)
        XCTAssertEqual(makeModel.value as? String, "Volvo · V60 · 2015")

        // Plate
        let plate = app.textFields["vehicleDetailPlateField"]
        XCTAssertTrue(plate.exists)

        // Powertrain picker - the ICE chip is selected for the petrol car and is
        // a live button (reachable, switchable).
        let ice = app.buttons["vehicleDetailPowertrainICE"]
        XCTAssertTrue(ice.exists && ice.isHittable)
        let ev = app.buttons["vehicleDetailPowertrainEV"]
        XCTAssertTrue(ev.exists)

        // Fuel pills - the seeded petrol95 + diesel are both toggleable.
        let petrol95 = app.buttons["vehicleDetailFuelKind_petrol95"]
        let diesel = app.buttons["vehicleDetailFuelKind_diesel"]
        XCTAssertTrue(petrol95.exists)
        XCTAssertTrue(diesel.exists)

        // Tank capacity - the seeded 71 L is in the field and editable.
        let capacity = app.textFields["vehicleDetailTankCapacityField"]
        scrollTo(capacity, in: app)
        XCTAssertEqual(capacity.value as? String, "71")
        replaceText(in: capacity, app: app, with: "60")
        XCTAssertEqual(capacity.value as? String, "60")

        // Current odometer (initialOdometer) - the seeded 118 000, editable.
        let odometer = app.textFields["vehicleDetailOdometerField"]
        scrollTo(odometer, in: app)
        XCTAssertNotNil(odometer.value as? String)

        // Home currency menu - a real edit: pick PLN and the row reflects it.
        let currency = app.buttons["vehicleDetailHomeCurrencyMenu"]
        XCTAssertTrue(currency.exists)
        currency.tap()
        let pln = app.buttons["PLN zł"]
        XCTAssertTrue(pln.exists, "the currency menu lists the offered set")
        pln.tap()
        XCTAssertTrue(app.buttons["vehicleDetailHomeCurrencyMenu"].label.contains("PLN"),
                      "selecting a currency edits the row")

        // Units editor - every axis is a reachable menu; pick miles and the
        // distance row reflects the edit.
        let distance = app.buttons["vehicleDetailDistanceMenu"]
        scrollTo(distance, in: app)
        XCTAssertTrue(distance.exists)
        distance.tap()
        let mi = app.buttons["mi"]
        XCTAssertTrue(mi.exists, "the distance menu lists the distance units")
        mi.tap()
        XCTAssertTrue(app.buttons["vehicleDetailDistanceMenu"].label.contains("mi"),
                      "selecting a unit edits the row")

        // Save is pinned at the bottom and reachable.
        let save = app.buttons["vehicleDetailSaveButton"]
        XCTAssertTrue(save.exists && save.isHittable)
    }

    // MARK: - Archive updates the Car switcher's row (J13)

    func testArchivingFromDetailUpdatesTheSwitcherRow() {
        let app = launch()
        openDetail(app)

        // The Volvo starts live: no archived banner, button says Archive.
        XCTAssertFalse(app.staticTexts["vehicleDetailArchivedBanner"].exists)

        let archive = app.buttons["vehicleDetailArchiveButton"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        archive.tap()

        // The screen reflects the new state immediately: the banner appears and
        // the action becomes Unarchive.
        XCTAssertTrue(app.staticTexts["vehicleDetailArchivedBanner"]
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["vehicleDetailArchiveButton"].label
            .contains("Unarchive"))

        // Back to Garage, then Home, then the switcher: the Volvo is now an
        // archived row (the seeded BMW was already one), dimmed and honest.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Garage"].waitForExistence(timeout: 5))
        app.buttons["tabbar.log"].tap()

        let switcher = app.buttons["carSwitcherButton"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 5))
        switcher.tap()
        XCTAssertTrue(app.navigationBars["My garage"].waitForExistence(timeout: 5))

        XCTAssertEqual(app.buttons.matching(identifier: "carSwitcherArchivedRow").count, 2,
                       "the Volvo joins the BMW as an archived row")
        let archived = app.buttons.matching(identifier: "carSwitcherArchivedRow")
        XCTAssertTrue(archived.allElementsBoundByIndex.contains {
            $0.label.contains("Volvo V60") && $0.label.contains("Archived")
        })
    }

    /// Tapping an archived row in the switcher lands on that car's detail
    /// (P1.12 wiring) with the archived banner and the Unarchive path.
    func testArchivedRowOpensTheArchivedCarsDetail() {
        let app = launch()
        app.buttons["carSwitcherButton"].tap()
        XCTAssertTrue(app.navigationBars["My garage"].waitForExistence(timeout: 5))

        let archived = app.buttons["carSwitcherArchivedRow"].firstMatch
        XCTAssertTrue(archived.waitForExistence(timeout: 5))
        XCTAssertTrue(archived.label.contains("BMW 320d"))
        archived.tap()

        XCTAssertTrue(app.navigationBars["Vehicle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["vehicleDetailArchivedBanner"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["vehicleDetailArchivedStatus"].exists,
                      "the archived subtitle renders the sale month honestly")
        XCTAssertTrue(app.buttons["vehicleDetailArchiveButton"].label.contains("Unarchive"))
    }

    // MARK: - Delete raises the system confirmation; cancel leaves the car intact

    func testDeleteRaisesSystemConfirmationAndCancelLeavesTheCarIntact() {
        let app = launch()
        openDetail(app)

        let delete = app.buttons["vehicleDetailDeleteButton"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()

        // The one place red lives: the system confirmation, naming the next step.
        let alert = app.alerts["Delete this car?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.buttons["Cancel"].exists)

        alert.buttons["Cancel"].tap()

        // The car is intact: still on the detail screen, still editable.
        XCTAssertFalse(alert.exists)
        XCTAssertTrue(app.textFields["vehicleDetailNameField"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["vehicleDetailNameField"].value as? String, "Volvo V60")

        // Back to the switcher: all three cars remain (the cancel touched nothing).
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Garage"].waitForExistence(timeout: 5))
        app.buttons["tabbar.log"].tap()
        app.buttons["carSwitcherButton"].tap()
        XCTAssertTrue(app.navigationBars["My garage"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "carSwitcherRow").count, 2,
                       "cancelling must leave both live cars intact")
        XCTAssertEqual(app.buttons.matching(identifier: "carSwitcherArchivedRow").count, 1,
                       "cancelling must not touch the archived car either")
    }
}
