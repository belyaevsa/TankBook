import XCTest

/// The guest-parity journeys (RV.251, PJ.100, PJ.101, PJ.200). They live in an
/// extension of `ColdLaunchJourneyUITests` - same suite, same cold-launch rules
/// (tap the whole path, no navigation seed), split into their own file because
/// the base class is at the linter's type-body ceiling. `launch`,
/// `addCarFromWelcome`, `focusField` and `reveal` are the base class's own
/// helpers.
@MainActor
extension ColdLaunchJourneyUITests {

    /// A SECOND car, typed through the Garage's own Add-car tile - the real path
    /// a guest uses once a car already exists (the Welcome door is gone for good
    /// after the first). No seed: two cars are the state the guest switcher test
    /// exists to reach.
    private func addCarFromGarage(_ app: XCUIApplication, named name: String) {
        let garage = app.buttons["tabbar.garage"]
        XCTAssertTrue(garage.waitForExistence(timeout: 10))
        garage.tap()
        let addCar = app.buttons["garageAddCar"]
        XCTAssertTrue(addCar.waitForExistence(timeout: 10), "the Garage must offer Add car")
        addCar.tap()
        XCTAssertTrue(app.navigationBars["Add car"].waitForExistence(timeout: 5))
        let field = app.textFields["addVehicleNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["addVehicleSaveButton"].tap()
    }

    /// The car switcher's sheet: open it and pick the live car whose row label
    /// contains `name`.
    private func switchToCar(_ app: XCUIApplication, named name: String) {
        let switcher = app.buttons["carSwitcherButton"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 10))
        switcher.tap()
        XCTAssertTrue(app.buttons["carSwitcherAddCar"].waitForExistence(timeout: 5),
                      "the garage sheet must open")
        let row = app.buttons.matching(identifier: "carSwitcherRow")
            .matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "\(name) must be a switcher row")
        row.tap()
    }

    /// RV.251: a guest with two cars switches cars on Home, and the log follows
    /// the selection. Before this row the guest layout rendered no switcher -
    /// only the signed-in header did - so a guest who added a second car from
    /// the Garage could not reach it. The second car is typed through the
    /// Garage, never seeded: two cars are the state the walk exists to reach.
    func testGuestWithTwoCarsSwitchesOnHomeAndTheLogFollows() {
        let app = launch(["-presentWelcome"])
        addCarFromWelcome(app, named: "Volvo")
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10),
                      "adding a car must end onboarding and land on the guest Home")

        // A fill-up on Volvo, so its log has a row no other car carries.
        let typeIt = app.buttons["typeItButton"]
        XCTAssertTrue(typeIt.waitForExistence(timeout: 10))
        typeIt.tap()
        focusField(app, "manualFillUpTotalField").typeText("71.02")
        focusField(app, "manualFillUpLitersField").typeText("42.30")
        app.buttons["manualFillUpSaveButton"].tap()
        XCTAssertTrue(app.buttons["logEntryButton"].firstMatch.waitForExistence(timeout: 10),
                      "the Volvo's fill-up must be in its log")

        // A second car, through the Garage. The new car becomes selected, so its
        // log is empty and Volvo's row is the thing to switch back to.
        addCarFromGarage(app, named: "Golf")
        app.buttons["tabbar.log"].tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))

        // The switcher is the SAME control the signed-in header renders.
        let switcher = app.buttons["carSwitcherButton"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 10),
                      "a guest with two cars must have the car switcher on Home (RV.251)")

        // Switch to Volvo: the log follows the selection.
        switchToCar(app, named: "Volvo")
        XCTAssertTrue(app.buttons["logEntryButton"].firstMatch.waitForExistence(timeout: 10),
                      "the Volvo's log must render after switching to it")

        // Switch to Golf: the log follows again - Volvo's row is gone.
        switchToCar(app, named: "Golf")
        XCTAssertFalse(app.buttons["logEntryButton"].firstMatch.waitForExistence(timeout: 3),
                       "the log must follow the selected car, not keep the other car's rows")
    }

    /// PJ.100: the guest capture card's "Type it" is the SAME split control the
    /// signed-in header renders, so Service and Expense are reachable without an
    /// account (nothing about them is a sync feature, hard rule 1).
    func testGuestTypeItOffersServiceAndExpense() {
        let app = launch(["-presentWelcome"])
        addCarFromWelcome(app, named: "Volvo")
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))

        let menu = app.buttons["typeItMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10),
                      "the guest capture card must carry the signed-in Type-it menu")
        menu.tap()
        let service = app.buttons["Service"]
        XCTAssertTrue(service.waitForExistence(timeout: 5), "the menu must offer Service")
        XCTAssertTrue(app.buttons["Expense"].exists, "the menu must offer Expense")
        service.tap()
        XCTAssertTrue(app.textFields["serviceEntryVendorField"].waitForExistence(timeout: 10),
                      "picking Service must open the service entry form as a guest")
    }

    /// PJ.101: a guest with no car gets the same filled Add-car door the
    /// signed-in no-car Home has. Reached the real way: delete the only car, so
    /// `liveVehicles()` empties and Home falls back to its no-car card. (An
    /// archive does NOT reach this state: `VehicleSelection.resolve` deliberately
    /// keeps showing a car when every car is archived.)
    func testGuestNoCarHomeOffersAddCar() {
        let app = launch(["-presentWelcome"])
        addCarFromWelcome(app, named: "Volvo")
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))

        app.buttons["tabbar.garage"].tap()
        let carRow = app.buttons["garageCarRow"].firstMatch
        XCTAssertTrue(carRow.waitForExistence(timeout: 10))
        carRow.tap()
        let delete = app.buttons["vehicleDetailDeleteButton"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        reveal(app, delete)
        let alert = app.alerts.matching(NSPredicate(format: "label CONTAINS %@", "Volvo")).firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "the delete confirmation must name the car about to go")
        alert.buttons["Delete"].tap()

        app.buttons["tabbar.log"].tap()
        let addCar = app.buttons["homeAddFirstCarButton"]
        XCTAssertTrue(addCar.waitForExistence(timeout: 10),
                      "the guest no-car Home must offer Add car (PJ.101)")
        addCar.tap()
        XCTAssertTrue(app.navigationBars["Add car"].waitForExistence(timeout: 5),
                      "the Add-car door must open the form")
    }

    /// PJ.200: the guest Home carries the permanent Reminders row, so J7d's
    /// discovery surface is not account-gated - the merged list and its "New
    /// reminder" door are reachable without a session. With no reminders the
    /// merged list renders its empty state, whose filled "New reminder" button is
    /// the reachable door.
    func testGuestRemindersRowOpensTheMergedList() {
        let app = launch(["-presentWelcome"])
        addCarFromWelcome(app, named: "Volvo")
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))

        let row = app.buttons["homeRemindersRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "the guest Home must carry the permanent reminders door (PJ.200)")
        row.tap()
        let newReminder = app.buttons["remindersEmptyNewReminderButton"]
        XCTAssertTrue(newReminder.waitForExistence(timeout: 10),
                      "the merged list's New reminder door must be reachable")
        newReminder.tap()
        XCTAssertTrue(app.buttons["reminderFormSaveButton"].waitForExistence(timeout: 10),
                      "New reminder must open the reminder form")
    }
}
