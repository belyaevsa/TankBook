import XCTest

/// PJ.61 - the part-number field on the CREATE door's service item card. The
/// same shared `ServiceItemPartNumberField` the edit door uses (one view, two
/// doors), so this guards that the create card renders and loads it too. EN and
/// RU, because "Номер детали" is the longest label the narrow card carries.
@MainActor
extension ServiceEntryUITests {

    private func launchWithPartNumber(russian: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-homeResetDatabase", "-seedServiceEntryLifetime",
                    "-presentScreen", "serviceEntry"]
        if russian {
            args += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        }
        app.launchArguments = args
        app.launch()
        return app
    }

    private func partNumberField(_ app: XCUIApplication) -> XCUIElement {
        app.textFields.matching(identifier: "editEntryServiceItemPartNumber").firstMatch
    }

    func testTheCreateCardRendersThePartNumberField() {
        let app = launchWithPartNumber()
        let field = partNumberField(app)
        XCTAssertTrue(field.waitForExistence(timeout: 10),
                      "the create item card must render the part-number field")
        XCTAssertEqual(field.value as? String, "MANN W 712/75",
                       "the seeded part number must load into the create field")
    }

    func testTheCreateCardRendersThePartNumberFieldInRussian() {
        let app = launchWithPartNumber(russian: true)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "editEntryServiceItemPartNumberLabel").firstMatch
            .waitForExistence(timeout: 10),
            "the part-number label must render on the create card in RU")
        XCTAssertTrue(partNumberField(app).waitForExistence(timeout: 10),
                      "the part-number field must render on the create card in RU")
    }
}
