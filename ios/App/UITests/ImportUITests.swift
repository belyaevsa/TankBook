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

    // MARK: - One header, not two (P6.15a)

    /// The artboard draws ONE header row ("Back | Review import | Cancel"); the
    /// system nav bar must be hidden, or a second "Import" title stacks above
    /// it. Sibling tabs keep their own hidden root bars in the tree, so count
    /// THIS screen's bar - zero of them - and check the wizard's own header
    /// title is the one that renders.
    func testPreviewHasExactlyOneHeader() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubParse", "mfm", "-seedImportPreview"])
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.navigationBars.matching(NSPredicate(format: "identifier == %@", "Import")).count, 0,
                       "the system 'Import' bar must not stack above the preview's own header")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Review import")).count, 1,
                       "the wizard's own header title renders once, as its own single header")
        XCTAssertTrue(app.buttons["importHeaderBack"].exists,
                      "the wizard's own Back affordance is present")
    }

    // MARK: - An unreadable row shows the original line, never our JSON (P6.15c)

    /// F6b says an unparseable row shows its raw line - the line the USER's file
    /// contained, not our wire envelope. The review seed renders a genuinely
    /// broken row (row 6: 6/31/2026): the screen must show that CSV line and no
    /// `entityType` or `{` anywhere.
    func testUnreadableRowShowsTheOriginalLineNotOurJSON() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubParse", "review", "-seedImportReview"])
        XCTAssertTrue(app.otherElements["importReviewScreen"].waitForExistence(timeout: 10))
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertFalse(labels.contains { $0.contains("entityType") },
                       "an unreadable row must never render our wire envelope")
        XCTAssertFalse(labels.contains { $0.contains("{") },
                       "an unreadable row must never render serialized JSON")
        let originalLine = #"6/31/2026;40;117000;72.00;USD;2;F;100;Shell;"Volvo""#
        XCTAssertTrue(app.staticTexts[originalLine].exists,
                      "the original delimited source line renders for the unparsed row")
    }

    // MARK: - RU review actions stack, not hyphenate (P6.15b)

    /// RU's 20-30% expansion makes «Исправить / Импортировать как есть /
    /// Пропустить» wider than the card, so the compact one-line row is rejected
    /// and the actions stack onto separate lines. This asserts the RENDERED
    /// frames differ vertically - a real layout statement, not the vacuous "the
    /// label text is unhyphenated" check that reads the string the view was
    /// given. Mid-word hyphenation itself is pixels, so the RU screenshot is the
    /// other half of this guarantee.
    func testReviewActionsStackInRussianInsteadOfSharingOneLine() {
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                          "-presentScreen", "importWizard",
                          "-importStubParse", "review", "-seedImportReview"])
        XCTAssertTrue(app.otherElements["importReviewScreen"].waitForExistence(timeout: 10))
        let row = app.otherElements["importReviewRow-3"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the cross-check row is on screen")
        let fix = row.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Исправить")).firstMatch
        let importAsIs = row.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Импортировать как есть")).firstMatch
        let leaveOut = row.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Пропустить")).firstMatch
        XCTAssertTrue(fix.exists && importAsIs.exists && leaveOut.exists,
                      "all three RU actions are present")
        let lines = Set([fix.frame.minY, importAsIs.frame.minY, leaveOut.frame.minY])
        XCTAssertTrue(lines.count >= 2,
                      "RU review actions must stack onto separate lines, not share one hyphenating row")
    }

    // MARK: - The date-format question (PJ.10)

    /// The parser's M/D guess must not stand silently: the preview ASKS the
    /// `dateFormat` question once (docs/JOURNEYS.md F6), confirm stays disabled
    /// until it is answered, and answering enables it. The seeded mfm parse
    /// carries an 8-row ambiguity, so the subtitle names the real count.
    func testDateFormatQuestionShowsOnceAndGatesConfirm() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubParse", "mfm", "-seedImportPreview"])
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10))

        let question = app.otherElements["importDateFormatQuestion"]
        XCTAssertTrue(question.waitForExistence(timeout: 5),
                      "the date-format question renders on the preview")
        XCTAssertEqual(app.otherElements.matching(identifier: "importDateFormatQuestion").count, 1,
                       "the question is asked once per file, never per row")
        XCTAssertEqual(app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Date format matters – 8 dates read either way.")).count, 1,
            "the question's subtitle names the counted rows, once")

        XCTAssertFalse(app.buttons["importConfirmButton"].isEnabled,
                       "confirm stays disabled until the date-format question is answered")

        app.buttons["importDateFormatOption-D/M/YYYY"].tap()
        XCTAssertTrue(app.buttons["importConfirmButton"].isEnabled,
                      "answering the question enables confirm")
    }

    func testDateFormatQuestionGatesConfirmInRussian() {
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                          "-presentScreen", "importWizard",
                          "-importStubParse", "mfm", "-seedImportPreview"])
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10))

        let subtitle = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Формат дат важен – 8 дат читаются двояко."))
        XCTAssertEqual(subtitle.count, 1,
                       "the RU question subtitle renders once, naming the counted rows")
        XCTAssertFalse(app.buttons["importConfirmButton"].isEnabled,
                       "RU confirm stays disabled until answered")
        app.buttons["importDateFormatOption-D/M/YYYY"].tap()
        XCTAssertTrue(app.buttons["importConfirmButton"].isEnabled,
                      "answering the question enables confirm in Russian")
    }

    // MARK: - Non-fuel rows commit as what they are (PJ.9)

    /// A parsed service row gets its own action and commits as a ServiceRecord,
    /// which then shows in the Log (hard rule 8: shown, not silently dropped).
    func testNonFuelRowImportsAsAServiceAndShowsInTheLog() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportService"])
        XCTAssertTrue(app.otherElements["importReviewScreen"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.staticTexts["Import as service"].waitForExistence(timeout: 5),
                      "the non-fuel row offers the import-as-service action")

        app.buttons["importReviewDoneButton"].tap()
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10))
        app.buttons["importConfirmButton"].tap()

        XCTAssertTrue(app.staticTexts["Service"].waitForExistence(timeout: 10),
                      "the committed service entry renders in the Log")
    }

    func testNonFuelRowImportsAsAServiceAndShowsInTheLogInRussian() {
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                          "-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportService"])
        XCTAssertTrue(app.otherElements["importReviewScreen"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.staticTexts["Импортировать как сервис"].waitForExistence(timeout: 5),
                      "the RU non-fuel row offers the import-as-service action")

        app.buttons["importReviewDoneButton"].tap()
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 10))
        app.buttons["importConfirmButton"].tap()

        XCTAssertTrue(app.staticTexts["Сервис"].waitForExistence(timeout: 10),
                      "the committed service entry renders in the Russian Log")
    }

    // MARK: - The flagged-order row (PJ.11)

    /// F9a is checked on the import path BEFORE anything is written: the seeded
    /// parse carries a real MFM-style `9` odometer row, and the review list
    /// must show it badged "Breaks the timeline" with its Fix and "Import
    /// as-is" affordances - the row is committable as flagged (hard rule 13),
    /// never silently accepted or repaired.
    func testFlaggedOrderRowAppearsInTheReviewList() {
        let app = launch(["-presentScreen", "importWizard", "-seedImportTimeline"])
        XCTAssertTrue(app.otherElements["importReviewScreen"].waitForExistence(timeout: 10))

        let row = app.otherElements["importReviewRow-2"]
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                      "the 9 row lands in the review list, never silently in the ready set")
        XCTAssertTrue(app.staticTexts["Breaks the timeline"].exists,
                      "the timeline-conflict badge names the violation")
        XCTAssertTrue(app.descendants(matching: .any)["importReviewTimelineDetail"].firstMatch.exists,
                      "the amber detail renders under the badge (the F9a warning)")
        XCTAssertTrue(app.staticTexts["Fix"].exists,
                      "Fix is the next step - the odometer is the field to correct (hard rule 7)")
        XCTAssertTrue(app.staticTexts["Import as-is"].exists,
                      "importing the flagged row as-is stays allowed (hard rule 13)")
    }

    func testFlaggedOrderRowAppearsInTheReviewListInRussian() {
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                          "-presentScreen", "importWizard", "-seedImportTimeline"])
        XCTAssertTrue(app.otherElements["importReviewScreen"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.staticTexts["Нарушает хронологию"].waitForExistence(timeout: 5),
                      "the RU badge names the timeline break")
        XCTAssertTrue(app.staticTexts["Исправить"].exists,
                      "Fix is localised in Russian")
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
