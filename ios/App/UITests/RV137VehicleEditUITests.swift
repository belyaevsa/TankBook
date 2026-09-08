import XCTest

/// RV.137 - the catalogue picker on the Vehicle detail edit screen, plus the
/// fuel-chip visibility defect from the same screenshot.
///
/// The edit screen's Make · model row was a bare `TextField`: typing a make
/// offered no suggestions, so a user who mistyped on Add had to retype by hand,
/// forever. The fix reuses the Add-car suggester (one implementation - a second
/// one is the duplication RV.129 names) so a pick fills make, model and year as
/// text the user owns and records no catalogue identifier (the permanence
/// decision in VehicleDetailView's header).
///
/// The same screenshot showed the fuel chips clipped behind the pinned Save
/// bar while the keyboard was up. The bar is a `safeAreaInset(edge: .bottom)`
/// - the one region that does not scroll - so a chip underneath it is
/// unreachable mid-edit, not merely below the fold (the RV.84 class). The fix
/// steps the bar aside while a field is focused, so the form owns the whole
/// space above the keyboard. Every assertion is a FRAME check, never
/// `isHittable`, which RV.84 measured returning true for an element ~86%
/// clipped.
@MainActor
final class RV137VehicleEditUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // The artboard garage: the Volvo V60 (petrol95 + LPG, 71 L, ICE) as the
        // first Garage row, an ID.4 EV and an archived BMW. Language pinned EN;
        // -AppleLanguages persists, so the RU overflow check must not leak into
        // later suites.
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn",
                               "-seedHomeCarSwitcher",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    /// Opens the first Garage row's Vehicle detail (the seeded Volvo).
    private func openDetail(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["tabbar.garage"].waitForExistence(timeout: 10))
        app.buttons["tabbar.garage"].tap()
        XCTAssertTrue(app.buttons["garageCarRow"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["garageCarRow"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Vehicle"].waitForExistence(timeout: 5))
    }

    /// Replaces a field's whole value (long-press -> Select All -> type). The
    /// simulator's cmd+A needs a hardware keyboard, so it is deliberately not
    /// used here (the VehicleDetailUITests pattern).
    private func replaceText(in field: XCUIElement, app: XCUIApplication, with text: String) {
        field.tap()
        field.press(forDuration: 1.2)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) {
            selectAll.tap()
        }
        field.typeText(text)
    }

    /// The six fuel chips the seeded ICE Volvo offers (the powertrain's allowed
    /// set: the selected petrol95 + LPG union the full ICE kind list).
    private var chipIdentifiers: [String] {
        ["diesel", "petrol95", "petrol98", "lpg", "cng", "e85"]
    }

    // MARK: - L4: typing a make on the edit screen offers suggestions, and a
    // pick sets make, model and year

    /// Typing "Lada" into the detail's Make · model field must mount the SAME
    /// suggestion list Add car offers (row 0 is the Granta, per the pinned
    /// ranking in CatalogTests), and tapping a row must write make · model ·
    /// year into the field exactly as typing would - and nothing else: the name
    /// is not renamed, and no catalogue id is stored. Saving and reopening the
    /// car must show the picked values, which is the assertion that the pick
    /// reached the structured make/model/year of the stored `Vehicle` and not
    /// merely the field's display text.
    func testTypingAMakeOffersSuggestionsAndPickingSetsMakeModelYear() {
        let app = launch()
        openDetail(app)

        let makeModel = app.textFields["vehicleDetailMakeModelField"]
        XCTAssertTrue(makeModel.waitForExistence(timeout: 5))
        XCTAssertEqual(makeModel.value as? String, "Volvo · V60 · 2015",
                       "the seeded Volvo's make/model/year must be loaded")

        replaceText(in: makeModel, app: app, with: "Lada")

        let first = app.buttons["vehicleDetailSuggestion_0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5),
                      "typing a make on the edit screen must mount the suggestion list")
        // Precondition: the keyboard is up while the row is tapped - the exact
        // state the report was filed in.
        XCTAssertTrue(app.keyboards.firstMatch.exists,
                      "the make·model field must keep the keyboard up while typing")
        XCTAssertTrue(first.isHittable,
                      "precondition: row 0 must be tappable without scrolling")

        // The pick must fill make, model and year as text the user owns. The
        // Granta's model-year range is open-ended, so the pick lands on the
        // current year, exactly as Add car pre-fills it.
        first.tap()
        let picked = makeModel.value as? String ?? ""
        XCTAssertTrue(picked.hasPrefix("Lada · Granta ·"),
                      "picking a suggestion must set make · model · year, got '\(picked)'")
        let year = picked.replacingOccurrences(of: "Lada · Granta · ", with: "")
        XCTAssertNotNil(Int(year), "the picked text must carry a four-digit year, got '\(picked)'")

        // A pick fills the model row ONLY: the name is not renamed (unlike Add
        // car, where the name defaults from make + model on an empty form).
        XCTAssertEqual(app.textFields["vehicleDetailNameField"].value as? String, "Volvo V60",
                       "an edit-screen pick must not rename the car")

        // The list unmounts once the field holds the accepted text, so the user
        // can see what they just chose.
        XCTAssertFalse(app.buttons["vehicleDetailSuggestion_0"].waitForExistence(timeout: 2),
                       "the suggestion list must unmount once a value is chosen")

        // Save, reopen the car, and read the make/model/year back off the
        // stored Vehicle - the assertion that the pick reached the record.
        let save = app.buttons["vehicleDetailSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5),
                      "the Save bar must return once the keyboard is dismissed")
        save.tap()
        XCTAssertTrue(app.buttons["garageCarRow"].firstMatch.waitForExistence(timeout: 5),
                      "saving returns to the Garage")

        app.buttons["garageCarRow"].firstMatch.tap()
        XCTAssertTrue(makeModel.waitForExistence(timeout: 5))
        XCTAssertEqual(makeModel.value as? String, picked,
                       "the saved vehicle must carry the picked make · model · year")
        XCTAssertEqual(app.textFields["vehicleDetailNameField"].value as? String, "Volvo V60",
                       "saving a pick must leave the name untouched")
    }

    // MARK: - L4: with the keyboard up, every fuel chip is fully visible

    /// The same screenshot's second defect: with the make·model field focused,
    /// the fuel chips sat behind the pinned Save bar (which floats above the
    /// keyboard in a non-scrolling inset) - row 1 fully hidden, row 2 peeking
    /// out below it. Every assertion is a FRAME check: each chip must sit fully
    /// above the keyboard's top edge (so neither the keyboard nor any bar above
    /// it can cover it) and fully inside the window. `isHittable` is never the
    /// assertion - RV.84 measured it reporting true for an element ~86% clipped.
    /// The Save bar is asserted only as a geometry bound when it is present: if
    /// a future change floats the bar above the keyboard again while a field is
    /// focused, the chips drop behind it and the frame comparison fails.
    func testEveryFuelChipFullyVisibleWithTheKeyboardUp() {
        let app = launch()
        openDetail(app)

        // Focus the make·model field without editing: the loaded text is the
        // accepted text, so no suggestion list mounts and the fuel section sits
        // at its natural place under the identity card.
        let makeModel = app.textFields["vehicleDetailMakeModelField"]
        XCTAssertTrue(makeModel.waitForExistence(timeout: 5))
        makeModel.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5),
                      "focusing the make·model field must raise the keyboard")

        let window = app.windows.firstMatch
        for identifier in chipIdentifiers {
            let chip = app.buttons["vehicleDetailFuelKind_\(identifier)"]
            XCTAssertTrue(chip.waitForExistence(timeout: 5),
                          "the \(identifier) chip must render")
            XCTAssertGreaterThanOrEqual(chip.frame.minY, 0,
                                        "\(identifier): chip must not render above the window")
            XCTAssertLessThanOrEqual(chip.frame.maxY, keyboard.frame.minY + 1,
                                     "\(identifier): chip must sit fully above the keyboard, "
                                     + "chip bottom \(chip.frame.maxY) vs keyboard top \(keyboard.frame.minY)")
            XCTAssertLessThanOrEqual(chip.frame.maxY, window.frame.maxY,
                                     "\(identifier): chip must be inside the window")
        }

        // The Save bar is the only chrome that could sit between the chips and
        // the keyboard. It has stepped aside while the field is focused; if it
        // is present anyway, every chip must clear it.
        let save = app.buttons["vehicleDetailSaveButton"]
        if save.exists {
            for identifier in chipIdentifiers {
                let chip = app.buttons["vehicleDetailFuelKind_\(identifier)"]
                XCTAssertLessThanOrEqual(chip.frame.maxY, save.frame.minY + 1,
                                         "\(identifier): chip must sit above the Save bar, never behind it")
            }
        }
    }
}
