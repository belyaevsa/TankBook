import XCTest

/// RV.182 - the catalogue row advertises a tank volume that picking it did not
/// fill on the EDIT screen. The suggestion row is the shared component
/// (`Shared/VehicleCatalogSuggestionsArea.swift`) and renders `· 71 L` on both
/// Add car and Vehicle detail; Add car filled it, Vehicle detail copied only
/// make/model/year. The fix fills the capacity ONLY when the field is blank -
/// an empty field is not a user value (hard rule 13), so a capacity the user
/// typed stays byte-identical, while a blank one takes the figure the row
/// shows.
///
/// Split into an extension so the base `VehicleDetailUITests` body stays under
/// the linter's type-body limit; `-only-testing:.../VehicleDetailUITests`
/// still runs these methods. Each test makes exactly ONE catalogue pick - the
/// typed-unchanged and blank-fill halves are separate runs, so neither depends
/// on re-querying the list after a prior pick.
extension VehicleDetailUITests {

    /// Clears a field's whole value: long-press -> Select All -> delete. Falls
    /// back to deleting the visible characters when the edit menu never appears.
    private func clearText(in field: XCUIElement, app: XCUIApplication) {
        field.tap()
        field.press(forDuration: 1.2)
        if selectAll(in: app) {
            field.typeText(XCUIKeyboardKey.delete.rawValue)
        } else if let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
    }

    /// Scrolls the form back to the top so the Make · model field is hittable
    /// again after a trip down to the capacity card.
    private func scrollToTop(in app: XCUIApplication, maxSwipes: Int = 8) {
        func formScrollView() -> XCUIElement {
            let form = app.scrollViews["vehicleDetailFormScroll"]
            return form.exists ? form : app.scrollViews.firstMatch
        }
        if app.keyboards.firstMatch.exists {
            formScrollView().swipeDown()
        }
        let makeModel = app.textFields["vehicleDetailMakeModelField"]
        var swipes = 0
        while swipes < maxSwipes, !makeModel.isHittable {
            formScrollView().swipeDown()
            swipes += 1
        }
    }

    /// The mounted catalogue row whose label names `text` (a make, model or the
    /// volume it advertises). The rows are indexed, not named, so a test that
    /// needs a specific entry finds it by its own content - the ranking's row 0
    /// is not stable across queries.
    private func suggestionRow(in app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "vehicleDetailSuggestion_", text)).firstMatch
    }

    /// Waits for the catalogue row whose label contains `text` to mount and
    /// returns it, so a caller can assert on its advertised figure BEFORE
    /// tapping (the row unmounts the moment the pick applies).
    private func mountedRow(_ text: String, in app: XCUIApplication) -> XCUIElement {
        let row = suggestionRow(in: app, containing: text)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the '\(text)' row must mount")
        return row
    }

    // MARK: - EN

    /// RV.182 (EN, litres), the more important half: a capacity the user typed
    /// is a fact and must stay byte-identical across a pick whose row
    /// advertises a different figure (hard rule 13).
    func testSuggestionPickLeavesATypedTankUnchanged() {
        let app = launch()
        openDetail(app)

        let makeModel = app.textFields["vehicleDetailMakeModelField"]
        let capacity = app.textFields["vehicleDetailTankCapacityField"]
        XCTAssertTrue(makeModel.waitForExistence(timeout: 5))
        scrollTo(capacity, in: app)
        replaceText(in: capacity, app: app, with: "60")
        XCTAssertEqual(capacity.value as? String, "60")

        scrollToTop(in: app)
        replaceText(in: makeModel, app: app, with: "Lada")
        let granta = mountedRow("Granta", in: app)
        XCTAssertTrue(granta.label.contains("50"), "the row advertises its tank; label '\(granta.label)'")
        granta.tap()

        scrollTo(capacity, in: app)
        XCTAssertEqual(capacity.value as? String, "60",
                       "a pick must never overwrite a capacity the user typed (hard rule 13)")
    }

    /// RV.182 (EN, litres): the suggestion row renders `· 71 L`, so a pick on a
    /// car whose capacity is EMPTY must fill 71 - the figure the row displays.
    func testSuggestionPickFillsABlankTank() {
        let app = launch()
        openDetail(app)

        let makeModel = app.textFields["vehicleDetailMakeModelField"]
        let capacity = app.textFields["vehicleDetailTankCapacityField"]
        XCTAssertTrue(makeModel.waitForExistence(timeout: 5))
        scrollTo(capacity, in: app)
        clearText(in: capacity, app: app)
        XCTAssertEqual(capacity.value as? String, "", "precondition: the capacity is empty")

        scrollToTop(in: app)
        replaceText(in: makeModel, app: app, with: "Volvo")
        let v60 = mountedRow("V60", in: app)
        XCTAssertTrue(v60.label.contains("71"), "the row advertises its tank; label '\(v60.label)'")
        v60.tap()

        scrollTo(capacity, in: app)
        XCTAssertEqual(capacity.value as? String, "71",
                       "a blank capacity must take the volume the suggestion row displays")
    }

    /// RV.182 (EN, gallons): the row renders the catalogue's litres in the car's
    /// own volume unit, so a US-gallons car must be filled with the gallons
    /// figure the row shows (~13.2 for the Granta's 50 L) - a litres-only test
    /// cannot see a half-conversion (RV.69).
    func testSuggestionPickFillsABlankTankInGallons() {
        let app = launch()
        openDetail(app)

        let makeModel = app.textFields["vehicleDetailMakeModelField"]
        let capacity = app.textFields["vehicleDetailTankCapacityField"]
        XCTAssertTrue(makeModel.waitForExistence(timeout: 5))

        let volumeMenu = app.buttons["vehicleDetailVolumeMenu"]
        scrollTo(volumeMenu, in: app)
        volumeMenu.tap()
        let gallons = app.buttons["gal (US)"]
        XCTAssertTrue(gallons.waitForExistence(timeout: 5), "the volume menu must offer US gallons")
        gallons.tap()

        clearText(in: capacity, app: app)
        XCTAssertEqual(capacity.value as? String, "", "precondition: the capacity is empty")
        scrollToTop(in: app)
        replaceText(in: makeModel, app: app, with: "Lada")
        let granta = mountedRow("Granta", in: app)
        XCTAssertTrue(granta.label.contains("13.2"), "the row advertises gallons; label '\(granta.label)'")
        granta.tap()

        scrollTo(capacity, in: app)
        XCTAssertEqual(capacity.value as? String, "13.2",
                       "a blank capacity must take the gallons figure the suggestion row displays")
    }

    // MARK: - RU

    /// RV.182 (RU, litres): the typed-unchanged half in Russian - the locale
    /// where the edit menu and the volume unit are localised (hard rule 10).
    func testSuggestionPickLeavesATypedTankUnchangedInRussian() {
        let app = launch(russian: true)
        openDetail(app)

        let makeModel = app.textFields["vehicleDetailMakeModelField"]
        let capacity = app.textFields["vehicleDetailTankCapacityField"]
        XCTAssertTrue(makeModel.waitForExistence(timeout: 5))
        scrollTo(capacity, in: app)
        replaceText(in: capacity, app: app, with: "60")
        XCTAssertEqual(capacity.value as? String, "60")

        scrollToTop(in: app)
        replaceText(in: makeModel, app: app, with: "Lada")
        mountedRow("Granta", in: app).tap()

        scrollTo(capacity, in: app)
        XCTAssertEqual(capacity.value as? String, "60",
                       "RU: a pick must never overwrite a capacity the user typed")
    }

    /// RV.182 (RU, litres): the blank-fill half in Russian.
    func testSuggestionPickFillsABlankTankInRussian() {
        let app = launch(russian: true)
        openDetail(app)

        let makeModel = app.textFields["vehicleDetailMakeModelField"]
        let capacity = app.textFields["vehicleDetailTankCapacityField"]
        XCTAssertTrue(makeModel.waitForExistence(timeout: 5))
        scrollTo(capacity, in: app)
        clearText(in: capacity, app: app)
        XCTAssertEqual(capacity.value as? String, "", "precondition: the capacity is empty")

        scrollToTop(in: app)
        replaceText(in: makeModel, app: app, with: "Volvo")
        mountedRow("V60", in: app).tap()

        scrollTo(capacity, in: app)
        XCTAssertEqual(capacity.value as? String, "71",
                       "RU: a blank capacity must take the volume the suggestion row displays")
    }

    /// RV.182 (RU, gallons): the gallons menu label and the edit menu are both
    /// localised in RU, so this run proves the fill still lands on the row's
    /// displayed figure under the RU unit labels.
    func testSuggestionPickFillsABlankTankInGallonsInRussian() {
        let app = launch(russian: true)
        openDetail(app)

        let makeModel = app.textFields["vehicleDetailMakeModelField"]
        let capacity = app.textFields["vehicleDetailTankCapacityField"]
        XCTAssertTrue(makeModel.waitForExistence(timeout: 5))

        let volumeMenu = app.buttons["vehicleDetailVolumeMenu"]
        scrollTo(volumeMenu, in: app)
        volumeMenu.tap()
        let gallons = app.buttons["гал (США)"]
        XCTAssertTrue(gallons.waitForExistence(timeout: 5), "the RU volume menu must offer US gallons")
        gallons.tap()

        clearText(in: capacity, app: app)
        XCTAssertEqual(capacity.value as? String, "", "precondition: the capacity is empty")
        scrollToTop(in: app)
        replaceText(in: makeModel, app: app, with: "Lada")
        mountedRow("Granta", in: app).tap()

        scrollTo(capacity, in: app)
        XCTAssertEqual(capacity.value as? String, "13.2",
                       "RU: a blank capacity must take the gallons figure the suggestion row displays")
    }
}
