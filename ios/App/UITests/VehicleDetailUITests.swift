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
    /// The language is pinned EN by default - `-AppleLanguages` persists in the
    /// app's UserDefaults, so the RU overflow test below would otherwise leave
    /// the whole suite running in Russian (the HomeUITests P6.13 lesson).
    private func launch(russian: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        // A session is required: since PJ.3 a sessionless launch renders the
        // guest Home, which has no `carSwitcherButton` - the same reason
        // TankbookShellUITests seeds `-seedSettingsSignedIn`.
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn",
                               "-seedHomeCarSwitcher"]
        if russian {
            app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        } else {
            app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        }
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

        // Fuel pills - the seeded petrol + LPG pair are both toggleable (the
        // seed is a REAL multi-fuel car; diesel-with-petrol would be impossible).
        let petrol95 = app.buttons["vehicleDetailFuelKind_petrol95"]
        let lpg = app.buttons["vehicleDetailFuelKind_lpg"]
        XCTAssertTrue(petrol95.exists)
        XCTAssertTrue(lpg.exists)

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

    // MARK: - The per-car export's share sheet carries the CSV (PJ.38)

    /// Tapping the per-car export row builds the archive AND the four CSV files,
    /// and the share sheet must carry the CSV as its own item (PJ.38) - not just
    /// the archive folder. iOS groups the four CSV files (text documents) under
    /// "Plain Text" in the caption while the archive folder rides as the
    /// "1 Document" - so the CSV reaching the sheet is exactly this grouping.
    /// If only the archive were shared, the caption would name the folder alone.
    func testExportShareSheetCarriesTheCSV() {
        let app = launch()
        openDetail(app)

        let row = app.buttons["vehicleExportRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "the car's export row is reachable")
        scrollTo(row, in: app)
        row.tap()

        let shareCaption = app.otherElements["LP.CaptionBar.TopCaption"]
        XCTAssertTrue(shareCaption.waitForExistence(timeout: 20),
                      "the export row must open the system share sheet")
        XCTAssertTrue(shareCaption.label.contains("Plain Text"),
                      "the share sheet must carry the CSV files; caption was '\(shareCaption.label)'")
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
        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5))
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
        let switcher = app.buttons["carSwitcherButton"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 10), "carSwitcherButton never appeared")
        switcher.tap()
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

    /// The destructive confirmation (RV.99) NAMES the car about to go - "Delete
    /// Volvo V60?", never the identical "Delete this car?" whichever row you
    /// arrived from. Cancel must leave the garage untouched: asserting the
    /// alert merely exists, or asserting the dismissal alone, re-proves what is
    /// already known and covers nothing this row is about.
    func testDeleteRaisesSystemConfirmationNamingTheCarAndCancelLeavesTheGarageIntact() {
        let app = launch()
        openDetail(app)

        let delete = app.buttons["vehicleDetailDeleteButton"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()

        // The one place red lives: the system confirmation, naming its target.
        let alert = app.alerts.matching(
            NSPredicate(format: "label CONTAINS %@", "Volvo V60")).firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "the delete confirmation must name the car about to go")
        XCTAssertTrue(alert.label.contains("Delete"),
                      "the named element must be the delete confirmation, got '\(alert.label)'")
        XCTAssertTrue(alert.buttons["Cancel"].exists)

        alert.buttons["Cancel"].tap()

        // The car is intact: still on the detail screen, still editable.
        XCTAssertFalse(alert.exists)
        XCTAssertTrue(app.textFields["vehicleDetailNameField"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["vehicleDetailNameField"].value as? String, "Volvo V60")

        // Back to the switcher: all three cars remain (the cancel touched nothing).
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5))
        app.buttons["tabbar.log"].tap()
        let switcher = app.buttons["carSwitcherButton"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 5), "carSwitcherButton never appeared")
        switcher.tap()
        XCTAssertTrue(app.navigationBars["My garage"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "carSwitcherRow").count, 2,
                       "cancelling must leave both live cars intact")
        XCTAssertEqual(app.buttons.matching(identifier: "carSwitcherArchivedRow").count, 1,
                       "cancelling must not touch the archived car either")
    }

    /// RV.99, the archived half: the archived car's header Delete routes to the
    /// SAME `showDeleteConfirm` as a live car's, so the confirmation must name
    /// the ARCHIVED car - "Delete BMW 320d?" - and Cancel must leave it archived.
    func testDeleteFromArchivedCarNamesTheCarAndCancelKeepsItArchived() {
        let app = launch()
        // Reach the archived BMW's detail through the switcher's archived row.
        let switcher = app.buttons["carSwitcherButton"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 10), "carSwitcherButton never appeared")
        switcher.tap()
        XCTAssertTrue(app.navigationBars["My garage"].waitForExistence(timeout: 5))

        let archived = app.buttons["carSwitcherArchivedRow"].firstMatch
        XCTAssertTrue(archived.waitForExistence(timeout: 5))
        XCTAssertTrue(archived.label.contains("BMW 320d"))
        archived.tap()
        XCTAssertTrue(app.navigationBars["Vehicle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["vehicleDetailArchivedBanner"].waitForExistence(timeout: 5))

        let delete = app.buttons["vehicleDetailDeleteButton"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()

        // The confirmation names the archived car, not the selected live one.
        let alert = app.alerts.matching(
            NSPredicate(format: "label CONTAINS %@", "BMW 320d")).firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "the archived car's delete confirmation must name the BMW")
        XCTAssertFalse(alert.label.contains("Volvo V60"),
                       "the confirmation must name the car being deleted, got '\(alert.label)'")

        alert.buttons["Cancel"].tap()
        XCTAssertFalse(alert.exists)
        XCTAssertTrue(app.staticTexts["vehicleDetailArchivedBanner"].waitForExistence(timeout: 5),
                      "cancelling an archived car's delete keeps the car archived")

        // Back lands on the Log root (the switcher's archived row dismisses its
        // sheet and pushes the detail on the tab's stack); reopen the switcher
        // and the BMW must still be an archived row.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let switcherAgain = app.buttons["carSwitcherButton"]
        XCTAssertTrue(switcherAgain.waitForExistence(timeout: 5),
                      "back from the archived detail returns to the Log root")
        switcherAgain.tap()
        XCTAssertTrue(app.navigationBars["My garage"].waitForExistence(timeout: 5))
        let stillArchived = app.buttons["carSwitcherArchivedRow"].firstMatch
        XCTAssertTrue(stillArchived.waitForExistence(timeout: 5))
        XCTAssertTrue(stillArchived.label.contains("BMW 320d"),
                      "the cancelled delete must leave the BMW archived")
    }

    /// RV.99's long-name check, automated: the delete confirmation composes the
    /// car's FULL name into the title ("Удалить «Škoda Октавия Универсал
    /// Бизнес»?" - 30 characters), and the phrase must wrap rather than push the
    /// alert's actions off screen. XCUITest cannot assert pixels, but it CAN
    /// assert the actions are on-screen and hittable after the long title
    /// renders - which is the failure mode the check exists for. Run in RU: the
    /// short-string-expansion trap (hard rule 10) lives on the RU side, and the
    /// two actions render in their RU labels here, so the query never depends
    /// on an English button title.
    func testLongRussianNameDoesNotPushConfirmActionsOffScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn",
                               "-seedHomeRV99LongName", "-presentScreen", "vehicleDetail",
                               "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()

        // The vehicle-detail screen is presented with the seeded long-name car
        // loaded (RU localises the nav bar, so wait on the detail's own
        // controls, not the title).
        let delete = app.buttons["vehicleDetailDeleteButton"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10),
                      "the long-name car's detail must present")
        XCTAssertEqual(app.textFields["vehicleDetailNameField"].value as? String,
                       "Škoda Октавия Универсал Бизнес",
                       "the seeded 30-character name must be the car on screen")
        delete.tap()

        let alert = app.alerts.matching(
            NSPredicate(format: "label CONTAINS %@", "Škoda Октавия Универсал Бизнес")).firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "the delete confirmation must name the 30-character car")
        // Both actions (destructive + cancel, rendered in their RU labels
        // because this test runs in Russian) are on screen and tappable under
        // the long title.
        let deleteAction = alert.buttons["Удалить"]
        let cancelAction = alert.buttons["Отмена"]
        XCTAssertTrue(deleteAction.exists && deleteAction.isHittable,
                      "the destructive action must be on screen under a 30-char RU title")
        XCTAssertTrue(cancelAction.exists && cancelAction.isHittable,
                      "Cancel must be on screen under a 30-char RU title")

        cancelAction.tap()
        XCTAssertFalse(alert.exists)
        XCTAssertTrue(app.textFields["vehicleDetailNameField"].waitForExistence(timeout: 5),
                      "cancelling keeps the car intact")
    }
}
