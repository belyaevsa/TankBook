import XCTest

/// RV.86 - the multi-car mapping gate (docs/TASKS.md RV.86). The mapping tests
/// live in their own file so `ImportUITests.swift` stays under SwiftLint's
/// 700-line file floor while `-only-testing:TankbookUITests/ImportUITests`
/// still picks them up (the same pattern the PJ.10 date-format tests use).
///
/// A multi-car file (the reproduction's shape: a low-odometer Volvo group and a
/// high-odometer AUDI group in one export) must reach a mapping step that ASKS,
/// never guesses - Continue stays disabled until every source car has an
/// explicit destination - and after mapping the two cars' entries land
/// separately. The L1 half (per-lane partition, per-vehicle commit) lives in
/// the core suite; this is the rendered half: the gate appears, the mapping is
/// offered per car, and the garage afterwards reads the RIGHT car's odometer -
/// the exact symptom the owner reported (the Volvo card reading the Audi's
/// 426 220 km).
@MainActor
extension ImportUITests {
    private func liveCarRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(identifier: "garageCarRow")
    }

    private func waitForLiveCarRowCount(_ expected: Int, in app: XCUIApplication,
                                        timeout: TimeInterval = 8) {
        let deadline = Date().addingTimeInterval(timeout)
        while liveCarRows(app).count != expected, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(liveCarRows(app).count, expected,
                       "expected \(expected) live garage rows after \(timeout)s")
    }

    private func openGarage(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["tabbar.garage"].waitForExistence(timeout: 10))
        app.buttons["tabbar.garage"].tap()
        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5))
    }

    /// A multi-car file reaches the `.cars` mapping step with every destination
    /// UNDECIDED: the gate must not funnel into the pre-selected car (the
    /// mutation that defaults the mapping fails here), and Continue stays
    /// disabled until EVERY car is decided, not just the first.
    func testMultiCarFileReachesMappingGateAndNeverDefaults() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportCars"])
        XCTAssertTrue(app.otherElements["importCarsScreen"].waitForExistence(timeout: 10),
                      "a multi-car parse lands on the car-mapping gate")

        // The gate lists each source car with its destination choice.
        XCTAssertTrue(app.otherElements["importCarCard-0"].exists,
                      "the first source car (Volvo) is listed")
        XCTAssertTrue(app.otherElements["importCarCard-1"].exists,
                      "the second source car (AUDI A4) is listed")

        // Nothing is defaulted: Continue is disabled until every car is decided.
        let continueButton = app.buttons["importCarsConfirmButton"]
        XCTAssertTrue(continueButton.exists)
        XCTAssertFalse(continueButton.isEnabled,
                       "Continue must start disabled - the wizard never guesses a mapping")

        // Decide the Volvo into the existing garage car. Continue STILL disabled:
        // the second source car is undecided.
        let card0 = app.otherElements["importCarCard-0"]
        let existingVolvo = card0.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "importCarExisting-0-")).firstMatch
        XCTAssertTrue(existingVolvo.waitForExistence(timeout: 5),
                      "the existing garage car is offered as a destination for the Volvo")
        existingVolvo.tap()
        XCTAssertFalse(continueButton.isEnabled,
                       "Continue stays disabled while any source car is undecided")

        // Decide the AUDI into a new car. Only now may the import proceed.
        app.buttons["importCarNewCar-1"].tap()
        XCTAssertTrue(continueButton.isEnabled,
                      "deciding every car enables Continue")
    }

    /// After mapping a two-car file, each group lands in ITS OWN car - the
    /// garage must read the Volvo's 121 727 km, never the Audi's 426 220 km
    /// (the owner's reported symptom), and the Audi must exist as its own car
    /// with its own odometer.
    func testMultiCarCommitLandsEachCarSeparately() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportCars"])
        XCTAssertTrue(app.otherElements["importCarsScreen"].waitForExistence(timeout: 10))

        // Map Volvo -> the existing garage car, AUDI -> a new car.
        let card0 = app.otherElements["importCarCard-0"]
        let existingVolvo = card0.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "importCarExisting-0-")).firstMatch
        XCTAssertTrue(existingVolvo.waitForExistence(timeout: 5))
        existingVolvo.tap()
        app.buttons["importCarNewCar-1"].tap()

        let continueButton = app.buttons["importCarsConfirmButton"]
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()

        // The wizard dismisses after the commit; the garage then holds both cars.
        XCTAssertTrue(app.buttons["tabbar.garage"].waitForExistence(timeout: 10),
                      "the wizard closes after the import")
        openGarage(app)
        waitForLiveCarRowCount(2, in: app)

        let rows = liveCarRows(app)
        let volvoRow = rows.matching(
            NSPredicate(format: "label CONTAINS %@", "Volvo")).firstMatch
        let audiRow = rows.matching(
            NSPredicate(format: "label CONTAINS %@", "AUDI A4")).firstMatch
        XCTAssertTrue(volvoRow.exists, "the existing car is still in the garage")
        XCTAssertTrue(audiRow.exists, "the new car from the file is in the garage")

        // The reported defect: the Volvo card read the Audi's odometer because
        // both cars' rows landed on one car. After mapping they must not.
        XCTAssertTrue(volvoRow.label.contains("727 km"),
                      "the Volvo reads its own odometer (121 727 km), was '\(volvoRow.label)'")
        XCTAssertFalse(volvoRow.label.contains("220 km"),
                       "the Volvo must NOT carry the Audi's 426 220 km, was '\(volvoRow.label)'")
        XCTAssertTrue(audiRow.label.contains("220 km"),
                      "the Audi reads its own odometer (426 220 km), was '\(audiRow.label)'")
    }

    func testMultiCarMappingGateLocalisesTitleInRussian() {
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                          "-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportCars"])
        XCTAssertTrue(app.otherElements["importCarsScreen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Какие машины импортируем?"].exists,
                      "the RU mapping gate title is localised, never the English key")
        let continueButton = app.buttons["importCarsConfirmButton"]
        XCTAssertTrue(continueButton.exists)
        XCTAssertFalse(continueButton.isEnabled,
                       "RU Continue starts disabled exactly as EN does")
    }

    /// The screenshot seed decides both cars up front (Volvo into the existing
    /// garage car, AUDI into a new one). Pin that state: the merge duplicate
    /// count is on the Volvo's card, and the gate's Continue is live with the
    /// "into M cars" summary - the state the RV.86 screenshots record.
    func testMultiCarDecidedSeedRendersMappedCardsAndDuplicateCount() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportCarsDecided"])
        XCTAssertTrue(app.otherElements["importCarsScreen"].waitForExistence(timeout: 10))

        let continueButton = app.buttons["importCarsConfirmButton"]
        XCTAssertTrue(continueButton.exists)
        XCTAssertTrue(continueButton.isEnabled,
                      "the decided seed leaves every car mapped, so Continue is live")

        // The seeded existing fill matches the file's Volvo row 3, so mapping
        // the Volvo into that car surfaces the S2 duplicate count on its card.
        let duplicateLine = app.descendants(matching: .any)["importCarDuplicate-0"]
        XCTAssertTrue(duplicateLine.waitForExistence(timeout: 5),
                      "merging the Volvo into a car that holds a matching fill shows the duplicate count")
        XCTAssertTrue(app.staticTexts["Landing in 2 cars."].exists,
                      "the gate summary names the two destination cars")
    }
}
