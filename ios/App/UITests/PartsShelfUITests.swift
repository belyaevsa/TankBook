import XCTest

/// P3.2 parts shelf + install linking UI tests (docs/JOURNEYS.md J7b). The shelf
/// shows the visible "on shelf" state; the ServiceEntry Link row offers a shelf
/// part and the service shows it after linking; and the ordinary service sheet
/// is unchanged when the shelf is empty.
@MainActor
final class PartsShelfUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        // The reset travels with every seed: seeds are idempotent and silently
        // do nothing on a populated database, which renders a different screen
        // while the assertion still looks plausible.
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    // MARK: - The shelf

    func testShelfRendersItsOnShelfParts() {
        let app = launch(["-seedPartsShelf", "-presentScreen", "partsShelf"])
        XCTAssertTrue(app.staticTexts["Oil filter"].waitForExistence(timeout: 10),
                      "the shelf lists an on-shelf part by its title")
        XCTAssertTrue(app.staticTexts["Brake pads front"].exists)
        XCTAssertTrue(app.staticTexts["On shelf"].firstMatch.exists,
                      "the on-shelf state is visible, not silent")
    }

    func testShelfEmptyStateNamesItsNextStep() {
        let app = launch(["-presentScreen", "partsShelf"])
        XCTAssertTrue(app.otherElements["partsShelfEmptyState"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Parts you buy sit here until installed"].exists)
    }

    // MARK: - The Link row

    func testLinkRowOffersAShelfPartAndTheServiceShowsItLinked() {
        let app = launch(["-seedServiceEntryLink", "-presentScreen", "serviceEntry"])
        // The oil service offers the oil filter first (suggestion matching): a
        // Link affordance per on-shelf part.
        let linkButton = app.buttons["serviceEntryLinkPartButton"].firstMatch
        XCTAssertTrue(linkButton.waitForExistence(timeout: 10),
                      "the Link row offers a shelf part")
        let offer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Oil filter'")).firstMatch
        XCTAssertTrue(offer.exists, "the offer names the part")

        // Accepting the link moves the part from the offer into the "Linked"
        // state on the service - both visible, the link is not silent.
        linkButton.tap()
        XCTAssertTrue(app.buttons["serviceEntryUnlinkPartButton"].waitForExistence(timeout: 5),
                      "the service shows the part as linked after accepting")
        XCTAssertTrue(app.staticTexts["Linked"].exists)
    }

    func testOrdinaryServiceSheetIsUnchangedWhenTheShelfIsEmpty() {
        let app = launch(["-seedServiceEntry", "-presentScreen", "serviceEntry"])
        XCTAssertTrue(app.textFields["serviceEntryVendorField"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["serviceEntryLinkPartButton"].exists,
                       "an empty shelf adds no Link row to the service sheet")
        XCTAssertFalse(app.staticTexts["Parts on your shelf"].exists)
    }

    // MARK: - The Expense entry (the peer path, hard rule 15)

    func testPartsModeOpensTheExpenseEntry() {
        let app = launch(["-seedServiceEntry", "-presentScreen", "serviceEntry"])
        XCTAssertTrue(app.buttons["serviceEntryModeParts"].waitForExistence(timeout: 10))
        app.buttons["serviceEntryModeParts"].tap()

        XCTAssertTrue(app.textFields["expenseEntryTitleField"].waitForExistence(timeout: 5),
                      "tapping Parts opens the Expense entry as a peer of the service path")
        XCTAssertTrue(app.buttons["expenseEntrySaveButton"].exists)
    }
}
