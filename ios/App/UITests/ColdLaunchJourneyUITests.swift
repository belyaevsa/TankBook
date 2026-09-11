import XCTest

/// RV.165 - the cold-launch journey suite. This is a NEW suite beside the
/// existing UI suites, not a migration of them: those keep their seeds and
/// `-presentScreen` navigation, and this one exists because that shape cannot
/// discover an unreachable screen. A test that starts inside Edit entry can
/// never prove Edit entry is reachable.
///
/// Every test here starts from a cold launch with the database reset and
/// reaches its destination by TAPPING, from the state a real user starts in.
/// No `-presentScreen`, no `-openFirst*`, no tab pre-selection, and no seed for
/// anything the journey exists to create. The launch-argument guard
/// (`JourneyLaunchArgumentGuardTests`) fails the build if that ever regresses.
///
/// The arguments used here are the minimum the untestable seams require, and
/// each is recorded in the guard's reasoned allowlist:
///   - `-homeResetDatabase` - the database reset.
///   - `-presentWelcome` - the fresh-install precondition. It does not navigate
///     and seeds nothing; it runs the REAL onboarding gate even under the seed
///     harness's tabbed-app shortcut, so a clean launch opens on Welcome.
///   - `-cameraStatus authorized` - the simulator has no camera.
///   - `-captureFixtureImage <path>` - the untestable camera frame; the real
///     OCR pipeline still runs over the fixture.
///   - `-seedFillUpScan` - a deterministic local parse, so the save is not
///     gated on OCR accuracy. It substitutes only the parse, never a value the
///     user did not see.
///   - `-feedbackTransportSuccess` / `-feedbackQueueReset` - a deterministic
///     terminal outcome for the Send tap and an empty queue file.
///   - `-AppleLanguages` / `-AppleLocale` - the RU pass.
///
/// These are slow (the full suite runs ~28 min), so they run at a PHASE gate,
/// never per task. docs/TESTING.md -> "The cold-launch journey suite (RV.165)".
@MainActor
final class ColdLaunchJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Launch

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    // MARK: - Shared tap helpers

    /// The bottom of the visible content region: the owned tab bar's top on a
    /// pushed screen, the window's bottom otherwise. `isHittable` is true under
    /// the bar (RV.84), so a tap there lands on the bar, not the target.
    private func visibleBottom(_ app: XCUIApplication) -> CGFloat {
        let window = app.windows.firstMatch.frame
        let tabbar = app.otherElements["tabbar"]
        return tabbar.exists ? tabbar.frame.minY : window.maxY
    }

    /// Swipe the hittable scroll view up until `element` is fully above the
    /// tab bar, then tap it. The stop condition is geometric, never
    /// `isHittable` alone.
    @discardableResult
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement,
                        maxSwipes: Int = 8) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: 10),
                      "\(element.identifier) never appeared")
        var swipes = 0
        while swipes < maxSwipes {
            if element.isHittable && element.frame.maxY < visibleBottom(app) - 8 { break }
            guard let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable })
            else { break }
            let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            from.press(forDuration: 0.05, thenDragTo: to)
            swipes += 1
        }
        XCTAssertTrue(element.isHittable, "\(element.identifier) is on screen but not reachable")
        element.tap()
        return element
    }

    /// Bring a field clear of the pinned Save bar and tap it. Same geometric
    /// stop as `reveal`, anchored to the manual form's save bar.
    @discardableResult
    private func focusField(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "\(identifier) never appeared")
        let bar = app.buttons["manualFillUpSaveButton"]
        var scrolls = 0
        while scrolls < 8 {
            let barTop = bar.exists ? bar.frame.minY : visibleBottom(app)
            if field.isHittable && field.frame.maxY < barTop - 8 { break }
            guard let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable })
            else { break }
            let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            from.press(forDuration: 0.05, thenDragTo: to)
            scrolls += 1
        }
        XCTAssertTrue(field.isHittable, "\(identifier) is on screen but not reachable")
        field.tap()
        return field
    }

    /// The Welcome "Add your car" door, the Add-car form, and its save. This is
    /// the real first-run path a typing user takes; the car is typed, never
    /// seeded.
    private func addCarFromWelcome(_ app: XCUIApplication, named name: String) {
        let addCar = app.buttons["welcomeAddCarButton"]
        XCTAssertTrue(addCar.waitForExistence(timeout: 15),
                      "a clean launch must open on Welcome with the Add-car door")
        addCar.tap()
        XCTAssertTrue(app.navigationBars["Add car"].waitForExistence(timeout: 5))
        let field = app.textFields["addVehicleNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["addVehicleSaveButton"].tap()
    }

    // MARK: - J1 -> J3b: add a car, log a fill-up, set its station

    /// J1 -> J3b (docs/JOURNEYS.md): a first launch with no account adds a car,
    /// logs a fill-up by typing, and names the station it happened at.
    ///
    /// The station door is the point. RV.156 shipped three features onto a
    /// station set a typing user could never populate, and RV.163 later made
    /// that class a build failure - but only a walk proves the door is on the
    /// path. The outcome asserted is the user's: the named station is in the
    /// Garage's Stations list, where the user manages it.
    func testJ1AddCarLogTypedFillUpAndSetItsStation() {
        let app = launch(["-presentWelcome"])
        addCarFromWelcome(app, named: "Volvo")
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10),
                      "adding a car must end onboarding and land on the guest Home")

        // J3b: the peer typed door, offered on the guest Home next to capture.
        let typeIt = app.buttons["homeGuestCaptureButton"]
        XCTAssertTrue(typeIt.waitForExistence(timeout: 10))
        typeIt.tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 10),
                      "the typed door must open the manual fill-up form")

        // The station is named on the entry that created it (RV.156), through
        // the add door an empty station set offers.
        let addStation = app.buttons["manualFillUpAddStationButton"]
        XCTAssertTrue(addStation.waitForExistence(timeout: 10),
                      "an empty station set must offer the add door, never a dead label")
        reveal(app, addStation)
        let alert = app.alerts["Add station"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let nameField = alert.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Prima Auto")
        alert.buttons["Add"].tap()

        let station = app.buttons["manualFillUpStationButton"]
        XCTAssertTrue(station.waitForExistence(timeout: 5),
                      "naming a station must select it on the entry")
        let selected = NSPredicate(format: "label CONTAINS %@", "Prima Auto")
        expectation(for: selected, evaluatedWith: station)
        waitForExpectations(timeout: 5)

        focusField(app, "manualFillUpTotalField").typeText("71.02")
        focusField(app, "manualFillUpLitersField").typeText("42.30")
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.isEnabled, "two typed values must enable Save")
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10),
                      "saving must leave the manual form")

        // The outcome: the station the user named is where the user manages it.
        let garage = app.buttons["tabbar.garage"]
        XCTAssertTrue(garage.waitForExistence(timeout: 5))
        garage.tap()
        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5))
        reveal(app, app.buttons["garageStationsLink"])
        XCTAssertTrue(app.navigationBars["Stations"].waitForExistence(timeout: 5))
        let row = app.buttons["stationListRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                      "the station named on the entry must be in the Stations list")
        XCTAssertTrue(row.label.contains("Prima Auto"),
                      "the list must show the created station, got '\(row.label)'")
    }

    // MARK: - J1 -> J3: a guest logs a fill-up and finds it

    /// RV.197: a user with NO account logs a fill-up and then finds it on Home
    /// and in the Log. This is the exact walk that found the defect - before the
    /// fix the guest Home rendered no log at all, so the entry the guest saved
    /// was never shown again. The launch deliberately carries NO
    /// `-seedSettingsSignedIn`: a session is the thing the defect hid behind,
    /// and seeding one would make the test pass on the broken build.
    ///
    /// Home IS the Log tab (`AppTab` `.log`), so "on Home" and "in the Log" are
    /// the same surface; the Log tab is re-tapped to prove it stays reachable
    /// as a guest, then the entry is opened to prove it is a real, editable row.
    func testGuestColdLaunchLogsAFillUpAndFindsItOnHomeAndInTheLog() {
        let app = launch(["-presentWelcome"])
        addCarFromWelcome(app, named: "Volvo")
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10),
                      "adding a car must end onboarding and land on the guest Home")

        // The guest's one-tap typed door (hard rule 15).
        let typeIt = app.buttons["homeGuestCaptureButton"]
        XCTAssertTrue(typeIt.waitForExistence(timeout: 10),
                      "the guest Home must offer the typed door")
        typeIt.tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 10),
                      "the typed door must open the manual fill-up form")

        focusField(app, "manualFillUpTotalField").typeText("71.02")
        focusField(app, "manualFillUpLitersField").typeText("42.30")
        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.isEnabled, "two typed values must enable Save")
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10),
                      "saving must leave the manual form")

        // The outcome: the guest's saved entry is on Home, in the same log
        // stream the signed-in Home shows (RV.197 - the defect was its absence).
        let entry = app.buttons["logEntryButton"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10),
                      "a guest's saved fill-up must appear on Home, not vanish (RV.197)")
        XCTAssertTrue(app.staticTexts["homeEntryAmount"].firstMatch.exists,
                      "the guest's log row must carry its amount")

        // The Log tab is reachable as a guest and shows the same entry.
        let logTab = app.buttons["tabbar.log"]
        XCTAssertTrue(logTab.waitForExistence(timeout: 5), "the Log tab must be present for a guest")
        logTab.tap()
        XCTAssertTrue(app.buttons["logEntryButton"].firstMatch.waitForExistence(timeout: 5),
                      "the Log tab must still show the entry")

        // The entry is a real row, not decoration: it opens its editor.
        app.buttons["logEntryButton"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 10),
                      "the guest must be able to open the saved entry's editor")
    }

    // MARK: - J3 -> J8b: scan, save, reopen the entry, see the receipt

    /// J3 -> J8b (docs/JOURNEYS.md): a receipt scan is saved with its photo, and
    /// the photo is openable again from the saved entry - walked by a user with
    /// NO account (RV.197). Until that row the guest Home rendered no log, so
    /// this journey could only be walked signed in.
    ///
    /// The assertion is the user's outcome - the receipt is on screen - not
    /// that the attachment row exists. `-captureFixtureImage` stands in for the
    /// camera the simulator does not have; the review, the pipeline, the save
    /// and the viewer are the shipped ones.
    func testJ3ScanSaveReopenEntryAndSeeTheReceipt() {
        let fixture = repoRoot
            .appendingPathComponent("Spike/ReceiptSpike/fixtures/receipts/receipt-011-samara-diesel-ru.png")
            .path
        let app = launch(["-presentWelcome", "-cameraStatus", "authorized",
                          "-captureFixtureImage", fixture, "-seedFillUpScan"])

        // A guest with no car: add one through the real Welcome door, never
        // seeding (RV.197: no session is needed to see the saved entry).
        addCarFromWelcome(app, named: "Volvo")
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))

        // J3: the capture button, the shutter, the review's "Use this".
        let capture = app.buttons["captureButton"]
        XCTAssertTrue(capture.waitForExistence(timeout: 10))
        capture.tap()
        let shutter = app.buttons["captureShutterButton"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10),
                      "the capture cover must offer the shutter")
        shutter.tap()
        let useThis = app.buttons["captureReviewUseButton"]
        XCTAssertTrue(useThis.waitForExistence(timeout: 15),
                      "the shutter must open the review step before anything is read")
        useThis.tap()

        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 15),
                      "Use this must open the Confirm sheet")
        XCTAssertTrue(save.isEnabled, "the seeded scan must resolve enough to save")
        save.tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10),
                      "the scanned fill-up must save and leave capture")

        // J8b: reopen the entry from the Log, then open the receipt from it.
        let entry = app.buttons["logEntryButton"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10),
                      "the saved fill-up must be in the Log")
        entry.tap()
        let chip = app.buttons["attachmentPhotoChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10),
                      "the entry saved from a scan must carry its receipt")
        chip.tap()

        // The user's outcome: the receipt itself is on screen.
        let photo = app.descendants(matching: .any)["attachmentViewerImage"]
        XCTAssertTrue(photo.waitForExistence(timeout: 15),
                      "opening the entry's receipt must show the photo, not an empty viewer")
        XCTAssertTrue(photo.isHittable, "the receipt must be visible in the viewer")
    }

    // MARK: - J13 -> F10: delete a car, find it in Recently deleted

    /// J13 -> F10 (docs/JOURNEYS.md): a car is deleted and is recoverable from
    /// Recently deleted for 30 days. RV.98's defect was a delete alert that
    /// promised Recently deleted while the screen never queried deleted
    /// vehicles; the outcome asserted is that the car is actually there.
    func testJ13DeleteCarAndFindItInRecentlyDeleted() {
        let app = launch(["-presentWelcome"])
        addCarFromWelcome(app, named: "Volvo")
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 10))

        let garage = app.buttons["tabbar.garage"]
        XCTAssertTrue(garage.waitForExistence(timeout: 5))
        garage.tap()
        let carRow = app.buttons["garageCarRow"].firstMatch
        XCTAssertTrue(carRow.waitForExistence(timeout: 10))
        carRow.tap()

        let delete = app.buttons["vehicleDetailDeleteButton"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        reveal(app, delete)
        let alert = app.alerts.matching(NSPredicate(format: "label CONTAINS %@", "Volvo")).firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "the delete confirmation must name the car about to go")
        alert.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 10),
                      "deleting a car must return to the Garage")

        // The Settings door, then Recently deleted, by tapping.
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        reveal(app, app.buttons["settingsRecentlyDeletedRow"])
        XCTAssertTrue(app.navigationBars["Recently deleted"].waitForExistence(timeout: 5))

        let deleted = app.descendants(matching: .any)["recentlyDeletedVehicleRow"].firstMatch
        XCTAssertTrue(deleted.waitForExistence(timeout: 10),
                      "a deleted car must be recoverable in Recently deleted (RV.98)")
        XCTAssertTrue(deleted.label.contains("Volvo") || deleted.staticTexts["Volvo"].exists,
                      "the deleted car's row must name the car, got '\(deleted.label)'")
    }

    // MARK: - Feedback: send it, see it confirmed

    /// Send feedback and see it confirmed, in RU. RV.160's defect was that the
    /// confirmation existed but sat below the fold; the assertion is that the
    /// confirmation is on screen without scrolling, in the language whose copy
    /// runs longest.
    func testFeedbackSendShowsTheConfirmationInRussian() {
        let app = launch(["-feedbackQueueReset", "-feedbackTransportSuccess",
                          "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"])

        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        reveal(app, app.buttons["settingsAboutRow"])
        XCTAssertTrue(app.textViews["feedbackTextEditor"].waitForExistence(timeout: 10),
                      "About must carry the feedback composer")

        reveal(app, app.buttons["feedbackCategory-problem"])
        let editor = app.textViews["feedbackTextEditor"]
        reveal(app, editor)
        editor.typeText("Тест")
        // The consent defaults off; the user turns it on, then sends.
        let consent = app.switches["feedbackConsentToggle"]
        reveal(app, consent)
        if (consent.value as? String) == "0" {
            consent.tap()
        }
        reveal(app, app.buttons["feedbackSendButton"])

        let sent = app.staticTexts["feedbackSent"]
        XCTAssertTrue(sent.waitForExistence(timeout: 15),
                      "sending feedback must surface its confirmation")
        XCTAssertEqual(sent.label, "Спасибо – ваш отзыв уже в пути.",
                       "the RU confirmation must render its full phrase")
        XCTAssertLessThanOrEqual(sent.frame.maxY, visibleBottom(app),
                                 "the confirmation must be on screen, not below the fold (RV.160)")
    }

    // MARK: - Source location

    /// The repository root, so a fixture path can be handed to the app.
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // UITests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // ios
            .deletingLastPathComponent()  // repo root
    }
}
