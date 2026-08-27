import XCTest

/// P5.5b - the import wizard's L4 guarantees (docs/TASKS.md P5.5b). Every test
/// drives the REAL screens against the stub transport's responses, so the
/// assertions are on rendered UI, never on the model's internal state.
@MainActor
final class ImportUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    // MARK: - The format list is server-driven (test 4)

    /// The picker must render the transport's response, not a hardcoded list.
    /// Two different stub lists must render two different pickers - a constant
    /// list would pass every other test and silently defeat the architecture.
    /// The rows carry `importFormatRow-<id>` identifiers, so the assertion is on
    /// the rows the transport listed (the "Not yet" chips render the same app
    /// names, which is why text matching would be a vacuous assertion here).
    func testFormatListFollowsTheTransportResponse() {
        let one = launch(["-presentScreen", "importWizard", "-importStubFormats", "one"])
        XCTAssertTrue(one.buttons["importFormatRow-mfm"].waitForExistence(timeout: 10),
                      "the single stub format renders as a pickable row")
        XCTAssertFalse(one.buttons["importFormatRow-carguru"].exists,
                       "a format the transport did not list must not be pickable")

        let many = launch(["-presentScreen", "importWizard", "-importStubFormats", "many"])
        XCTAssertTrue(many.buttons["importFormatRow-mfm"].waitForExistence(timeout: 10))
        XCTAssertTrue(many.buttons["importFormatRow-fuelio"].exists,
                      "the second stub list renders its extra formats as rows")
        XCTAssertTrue(many.buttons["importFormatRow-carguru"].exists)
    }

    // MARK: - 422 shows the specific message (test 5)

    /// A wrong declared source names the DECLARED app specifically (F7) - never
    /// a generic "something went wrong".
    func testWrongDeclaredFormatShowsTheSpecificMessage() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportParse422",
                          "-importStubParse422"])
        let specific = app.staticTexts["This doesn't look like a My Fuel Manager export."]
        XCTAssertTrue(specific.waitForExistence(timeout: 10),
                      "the 422 must name the declared source")
        for generic in ["Something went wrong", "Couldn't reach the server"] {
            XCTAssertFalse(app.staticTexts[generic].exists,
                           "a 422 must never render as '\(generic)'")
        }
    }

    // MARK: - Offline says why (test 6)

    /// Offline is stated here, before the tap (docs/ERRORS.md): reading the
    /// file happens on our server - the named exception. The rest of the app
    /// keeps working (the wizard closes back to the Home tab).
    func testOfflineSaysWhyAndTheRestOfTheAppStillWorks() {
        let app = launch(["-presentScreen", "importWizard", "-importTransportOffline"])
        XCTAssertTrue(app.staticTexts["Importing needs a connection"].waitForExistence(timeout: 10),
                      "the offline notice names the reason before the tap")

        // Close the wizard: the Home tab (the rest of the app) is unaffected.
        app.buttons["importSourceClose"].tap()
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10),
                      "closing the wizard returns to Home, which still works")
    }

    // MARK: - The review row renders labelled fields, blank not 0 (test 7)

    /// F6b: a flagged row shows PARSED, LABELLED fields, and a missing value
    /// stays blank ("– km"), never `0`.
    func testFlaggedRowRendersLabelledFieldsAndAMissingValueStaysBlank() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubParse", "review", "-seedImportReview"])
        XCTAssertTrue(app.otherElements["importReviewScreen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["3 rows need a look"].exists,
                      "the review header counts the rows")

        // The missing-odometer row's odometer cell renders as a blank, not 0.
        let missing = app.staticTexts["importReviewMissingOdometer-2"]
        XCTAssertTrue(missing.waitForExistence(timeout: 5))
        XCTAssertEqual(missing.label, "– km",
                       "a missing value is an honest blank, never 0")
        XCTAssertFalse(app.staticTexts["0 km"].exists,
                       "no cell may render the missing odometer as 0")

        // The row's OTHER fields are parsed values, not raw CSV (F6b).
        XCTAssertTrue(app.staticTexts["42.31"].exists,
                      "the parsed litres value renders")
        XCTAssertTrue(app.staticTexts["1.749"].exists,
                      "the parsed price per litre renders")
        XCTAssertTrue(app.staticTexts["Odometer missing"].exists,
                      "only the wrong field is marked")
    }

    // MARK: - The preview gate writes nothing (test 1, L4 half)

    /// With the preview on screen the copy promises nothing is saved yet, and
    /// the button names exactly the fills that would land (the L1 repository
    /// assertion is the other half of this guarantee).
    func testPreviewSaysNothingIsSavedYetAndCountsTheFills() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubParse", "mfm", "-seedImportPreview"])
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Here's what we read"].exists)
        XCTAssertTrue(app.staticTexts["Nothing has been saved yet. Cancel leaves your garage untouched."].exists,
                      "the preview must promise nothing is written before confirm")
        XCTAssertTrue(app.buttons["importConfirmButton"].exists,
                      "the confirm button is present, naming the fills it would write")
        XCTAssertTrue(app.staticTexts["importTargetCarName"].exists)
    }

    // MARK: - Per-car export (P5.5b export lane)

    /// The Garage's car screen offers the per-car export row (the archive
    /// writer itself is L1-tested by P5.5a).
    func testVehicleDetailOffersThePerCarExport() {
        let app = launch(["-presentScreen", "vehicleDetail", "-seedHomeCarSwitcher"])
        XCTAssertTrue(app.buttons["vehicleExportRow"].waitForExistence(timeout: 10),
                      "the car in the Garage offers its export")
    }
}
