import XCTest

/// RV.185 - the name of a car the import creates is editable where the car is
/// offered, pre-filled with the derived suggestion (hard rule 13). The assertion
/// is that a TYPED name reaches the saved car, not that a field exists: after
/// confirming, the Garage row carries the typed name.
@MainActor
final class ImportRV185UITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    /// Replaces a text field's contents with `text` (select-all then type over).
    private func replaceText(_ field: XCUIElement, with text: String) {
        field.tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        field.typeText(text)
    }

    private func assertGarageHasCar(_ app: XCUIApplication, named name: String) {
        XCTAssertTrue(app.buttons["tabbar.garage"].waitForExistence(timeout: 10),
                      "the wizard closes after the import")
        app.buttons["tabbar.garage"].tap()
        let row = app.buttons.matching(identifier: "garageCarRow")
            .matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8),
                      "the typed name must reach the saved car, was looking for '\(name)'")
    }

    /// Single-car path: the preview's target-car card offers the new car's name,
    /// pre-filled with the derived suggestion, and a typed name is what the
    /// garage stores. The suggestion here is the neutral default because this
    /// file names no vehicle - **never the format's display name**, which is the
    /// app the file came from and the second half of what RV.185 reported.
    func testSingleCarNewCarNameFieldPrefillsAndSavesTypedName() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportNewCar"])
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10))

        let field = app.textFields["importNewCarNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5),
                      "a new car's name is editable where the car is offered")
        XCTAssertEqual(field.value as? String, "Imported car",
                       "the suggestion is the neutral default, never the exporter's name")

        replaceText(field, with: "My KZT car")
        app.buttons["importConfirmButton"].tap()
        assertGarageHasCar(app, named: "My KZT car")
    }

    /// RU: the same field and flow, with a Cyrillic name, so the typed value
    /// survives the catalogue and the row renders it.
    func testSingleCarNewCarNameFieldIsLocalisedAndSavesInRussian() {
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                          "-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportNewCar"])
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10))

        let field = app.textFields["importNewCarNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(field, with: "Моя машина")
        app.buttons["importConfirmButton"].tap()
        assertGarageHasCar(app, named: "Моя машина")
    }

    /// Multi-car path: the mapping gate's "New car" option offers the name field
    /// per source car, and the typed name is what the new lane's car stores.
    func testMultiCarNewCarNameFieldSavesTypedName() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportCars"])
        XCTAssertTrue(app.otherElements["importCarsScreen"].waitForExistence(timeout: 10))

        // Map card 0 to the existing Volvo, card 1 to a new car.
        let card0 = app.otherElements["importCarCard-0"]
        let existingVolvo = card0.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "importCarExisting-0-")).firstMatch
        XCTAssertTrue(existingVolvo.waitForExistence(timeout: 5))
        existingVolvo.tap()
        app.buttons["importCarNewCar-1"].tap()

        let field = app.textFields["importCarNewCarName-1"]
        XCTAssertTrue(field.waitForExistence(timeout: 5),
                      "the new lane's car name is editable where the car is offered")
        replaceText(field, with: "My Audi")

        let continueButton = app.buttons["importCarsConfirmButton"]
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()
        assertGarageHasCar(app, named: "My Audi")
    }
}
