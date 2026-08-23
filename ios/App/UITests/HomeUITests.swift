import XCTest

/// P1.4 Home screen tests. Home is mostly NOT the full state, so the substance
/// is the empty and partial states: guest, no car yet, car with zero entries
/// (the "no N/A tiles" assertion), one fill-up with no segment yet (the D4
/// hint), and the full state. The sync-shaped states (S2/S5/S7, reminder
/// banner, guest chrome) are presentation fixtures driven by launch arguments
/// (HomePresentables) because their real data arrives with P4.
///
/// Every Home test resets the database first (`-homeResetDatabase`) so the five
/// states are isolated from each other and from the other suites' seeds.
@MainActor
final class HomeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + args
        app.launch()
        return app
    }

    // MARK: - The five states

    func testGuestStateRendersGuestChrome() {
        let app = launch(args: ["-forceGuestHome", "-seedHomeEmptyVehicle"])

        // GuestHome.dc.html: the capture CTA, the import card and the privacy
        // line are the guest's signature surfaces.
        XCTAssertTrue(app.staticTexts["Scan your first fill-up"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["homeGuestCaptureButton"].exists)
        XCTAssertTrue(app.buttons["homeGuestImportButton"].exists)
        XCTAssertTrue(app.staticTexts[
            "Everything stays on this phone. Sign in later only if you want a second device."].exists)
    }

    func testNoCarYetRoutesToAddCar() {
        let app = launch(args: [])

        // The Add-car path, not an empty dashboard (docs/SCHEMA.md / J1).
        let addCar = app.buttons["homeAddFirstCarButton"]
        XCTAssertTrue(addCar.waitForExistence(timeout: 10))
        addCar.tap()
        XCTAssertTrue(app.navigationBars["Add car"].waitForExistence(timeout: 5))
    }

    func testZeroEntryStateOmitsVitalsAndNoNATiles() {
        let app = launch(args: ["-seedHomeEmptyVehicle"])

        // The garage card is real (baseline odometer from the vehicle), but the
        // data-hungry vitals are OMITTED, not "N/A", "–", "-" or "0.0".
        XCTAssertTrue(app.staticTexts["homeOdometer"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["homeHeadlineValue"].exists)
        XCTAssertFalse(app.staticTexts["homeMonthSpendTile"].exists)
        XCTAssertFalse(app.staticTexts["homeLastPriceTile"].exists)
        XCTAssertFalse(app.staticTexts["homeCostPerKmTile"].exists)

        // The literal no-N/A assertion: no rendered label is one of the
        // placeholder strings.
        let forbidden = ["N/A", "–", "-", "0.0"]
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(labels.allSatisfy { !forbidden.contains($0) },
                      "placeholder tile rendered: \(labels)")
    }

    func testSingleFillShowsD4HintWithCaptureLink() {
        let app = launch(args: ["-seedHomeSingleFill"])

        // docs/ERRORS.md -> Home, row D4: the hint names the next step and the
        // capture link works (it opens the manual form - capture is P2.1).
        let hint = app.staticTexts["homeD4Hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["One more full tank and your consumption appears"].exists)
        XCTAssertFalse(app.staticTexts["homeHeadlineValue"].exists)

        app.buttons["homeD4CaptureButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
    }

    func testFullStateRendersVitalsRecentEntriesAndGroupedOdometer() {
        let app = launch(args: ["-seedHomeFullHistory"])

        // Headline and the two vitals tiles (HomeA artboard).
        let headline = app.staticTexts["homeHeadlineValue"]
        XCTAssertTrue(headline.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["homeMonthSpendTile"].exists)
        XCTAssertTrue(app.staticTexts["homeLastPriceTile"].exists)

        // Recent entries are reachable and route to Edit entry.
        XCTAssertTrue(app.buttons["editEntryButton"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["homeEntryAmount"].firstMatch.exists)

        // The odometer is the shared grouped formatter's output end to end
        // (HANDOVER.md open item 0): thin-space grouped, not "123600".
        let odometer = app.staticTexts["homeOdometer"].firstMatch
        XCTAssertTrue(odometer.exists)
        XCTAssertTrue(odometer.label.contains("123"), "odometer shows \(odometer.label)")
        XCTAssertTrue(odometer.label.contains("\u{2009}"), "odometer not thin-space grouped: \(odometer.label)")
    }

    func testConflictBadgeRoutesToEditEntry() {
        let app = launch(args: ["-seedHomeConflict"])

        // F9a/S3: the amber badge renders on the conflicting entry and routes
        // to Edit entry; the excluded count is footnoted.
        let badge = app.buttons["conflictBadgeButton"]
        XCTAssertTrue(badge.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["homeExcludedFootnote"].exists)
        XCTAssertTrue(app.staticTexts["1 entry excluded"].exists)

        badge.tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5))
    }

    // MARK: - Sync-shaped presentation states (fixtures until P4)

    func testSyncShapedPresentationStatesAreReachable() {
        let app = launch(args: ["-seedHomeEmptyVehicle",
                                "-forceDuplicateCard",
                                "-forceArchivedReturned",
                                "-forceSyncToast",
                                "-forceReminderDue"])

        // S2: possible duplicate, one tap each way.
        XCTAssertTrue(app.staticTexts["Shell, 42.3 L logged twice"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["homeMergeButton"].exists)
        XCTAssertTrue(app.buttons["homeKeepBothButton"].exists)

        // S5: archived car returned via sync, with its next steps.
        XCTAssertTrue(app.buttons["homeDeleteAgainButton"].exists)
        XCTAssertTrue(app.buttons["homeKeepButton"].exists)

        // S7: post-outage sync toast.
        XCTAssertTrue(app.staticTexts["Synced. 2 entries need a look"].waitForExistence(timeout: 5))

        // Reminder due: amber banner with a working View affordance.
        let viewButton = app.buttons["homeReminderViewButton"]
        XCTAssertTrue(viewButton.exists)
        viewButton.tap()
        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 5))
    }
}
