import XCTest

// MARK: - RV.88 imported foreign money reaches the car's currency

/// The owner's defect, at L4: import a USD file into a EUR car and Home shows
/// "0 €" beside "N entries pending rates" - forever, because nothing ever asked
/// anyone to resolve the pending rows. RV.88 makes the import commit run the
/// drain over the rows it just wrote (demand fetch + scoped backfill), so the
/// month totals stop being zero IN THE SAME LAUNCH - no relaunch, no manual
/// rate, no other backfill caller. This test asserts the drained end state on
/// the rendered month divider (a "0 €" divider is the defect; a non-zero one is
/// the fix). If the drain call were dropped, nothing fills after the commit and
/// the divider stays "0 €" - the assertion fails.
@MainActor
extension ImportUITests {

    func testImportedUSDIntoEURCarDrainsAndTheMonthTotalIsNotZero() {
        // The mfm fixture is a USD file (2026-06-14..2026-08-24) imported into
        // the seeded EUR Volvo. `-stubRatesEcho` answers /rates/pack for any
        // requested date, so the drain can resolve every row at its own date.
        // Signed in, because the FULL Home layout (with the log's month
        // dividers) is the surface under test - the guest Home has no log.
        let app = launch(["-seedSettingsSignedIn", "-stubRatesEcho",
                          "-presentScreen", "importWizard",
                          "-importStubFormats", "one",
                          "-importStubParse", "mfm", "-seedImportPreview"])
        XCTAssertTrue(app.otherElements["importPreviewScreen"].waitForExistence(timeout: 15),
                      "the preview must be on screen")

        // The file's dates are ambiguous (PJ.10): confirm stays disabled until
        // the date-format question is answered.
        let dateFormat = app.buttons["importDateFormatOption-M/D/YYYY"]
        XCTAssertTrue(dateFormat.waitForExistence(timeout: 10),
                      "the date-format question must appear on the preview")
        dateFormat.tap()

        let confirm = app.buttons["importConfirmButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(confirm.isEnabled, "answering the question enables confirm")
        confirm.tap()

        // Commit dismisses back to the Log tab. The drain (RV.88) converts the
        // USD rows to EUR at their own dates (pending-at-commit is pinned at L1
        // - `commitLeavesForeignRowsPending...`); the month divider that read
        // "0 €" while every row was rate-pending must now carry a REAL euro
        // total - the assertion is the number, not the presence of the divider
        // (a "0 €" divider is exactly the owner's report). If the drain call
        // were dropped, nothing fills after the commit and the divider stays
        // "0 €": the wait fails.
        let divider = app.descendants(matching: .any)["logMonthDivider"].firstMatch
        XCTAssertTrue(divider.waitForExistence(timeout: 15),
                      "Home must render the imported history's month divider")
        let nonZeroEuroTotal = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            guard element.label.contains("€") else { return false }
            return element.label.filter(\.isNumber).contains { $0 != "0" }
        }
        expectation(for: nonZeroEuroTotal, evaluatedWith: divider)
        waitForExpectations(timeout: 15)

        // The F9 footnote must be gone: every imported row drained.
        XCTAssertFalse(app.staticTexts["homePendingRatesFootnote"].exists,
                       "an import that drained leaves no 'entries pending rates' footnote")
    }
}
