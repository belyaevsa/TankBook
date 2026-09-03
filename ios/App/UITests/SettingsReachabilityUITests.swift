import XCTest

/// RV.21: Settings is reachable from every tab root, not just the Log. The
/// three roots share ONE header treatment (the shared `TabRootHeader`), so the
/// gear's frame must be identical on Log, Trends and Garage - reachability and
/// consistency are one fix.
///
/// The vacuous traps this suite refuses:
/// - a gear that merely EXISTS on each tab - it existed on Log before RV.21,
///   and existence says nothing about position, which is exactly what the
///   product owner reported ("put it at the same places" - the complaint was
///   not that the gear was missing from Log);
/// - asserting only that Settings opens - opening proves half the bug, the
///   frame mismatch was the other half;
/// - testing Log first and assuming the other two follow - Log already worked.
///
/// So the primary gate is GEOMETRY: the gear's frame - origin AND size - must
/// match on all three roots, asserted against Log's, and each root must push
/// Settings onto ITS OWN navigation stack (back returns to the root that pushed,
/// never to the Log).
@MainActor
final class SettingsReachabilityUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A signed-in launch with a car + full history: all three roots render
    /// their real layouts, so the gear is measured on the layout users see, not
    /// on an empty state. The language is explicit (EN) because a prior RU
    /// launch persists `-AppleLanguages` in UserDefaults (P6.13 discipline).
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn",
                               "-seedHomeFullHistory",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    /// The gear on the ACTIVE tab root. Inactive tabs stay in the hierarchy at
    /// opacity 0 but are accessibility-hidden (`tabRoot` in TabRoots.swift), so
    /// exactly one `settingsButton` is exposed at a time.
    private func gear(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["settingsButton"]
    }

    // MARK: - The frame-match gate

    /// The reported bug is position as much as reachability: a gear that exists
    /// on every tab but sits somewhere different per tab is precisely what the
    /// product owner complained about ("the opposite of what was asked"). So
    /// the gear must be present, hittable, and its frame - origin AND size -
    /// must match Log's on each of the other two roots.
    func testGearIsHittableAndFrameMatchesAcrossAllThreeTabRoots() {
        let app = launch()

        // Log: the reference frame.
        let logGear = gear(app)
        XCTAssertTrue(logGear.waitForExistence(timeout: 10),
                      "the Log tab root must carry the Settings gear")
        XCTAssertTrue(logGear.isHittable, "the gear on the Log root must be hittable")
        XCTAssertEqual(logGear.label, "Settings",
                       "the gear must keep its accessibility label on every root")
        let reference = logGear.frame

        // Trends: same row, same place.
        app.buttons["tabbar.trends"].tap()
        XCTAssertTrue(app.staticTexts["trendsHeaderTitle"].waitForExistence(timeout: 5),
                      "the Trends tab root must be on screen")
        let trendsGear = gear(app)
        XCTAssertTrue(trendsGear.waitForExistence(timeout: 5),
                      "the Trends tab root must carry the Settings gear")
        XCTAssertTrue(trendsGear.isHittable, "the gear on the Trends root must be hittable")
        XCTAssertEqual(trendsGear.label, "Settings")
        assertFrame(trendsGear.frame, matches: reference, tab: "Trends")

        // Garage: same row, same place.
        app.buttons["tabbar.garage"].tap()
        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5),
                      "the Garage tab root must be on screen")
        let garageGear = gear(app)
        XCTAssertTrue(garageGear.waitForExistence(timeout: 5),
                      "the Garage tab root must carry the Settings gear")
        XCTAssertTrue(garageGear.isHittable, "the gear on the Garage root must be hittable")
        XCTAssertEqual(garageGear.label, "Settings")
        assertFrame(garageGear.frame, matches: reference, tab: "Garage")
    }

    // MARK: - Each root pushes Settings onto its own stack

    /// Gear -> Settings -> back must land on the LOG root (the tab that pushed).
    func testGearReachesSettingsFromLogAndBackReturnsToLog() {
        let app = launch()
        let logGear = gear(app)
        XCTAssertTrue(logGear.waitForExistence(timeout: 10))

        logGear.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5),
                      "the Log root's gear must reach Settings")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5),
                      "Settings' back must return to the Log root")
    }

    /// Gear -> Settings -> back must land on the TRENDS root - not the Log,
    /// which is the tab that already worked (the wrong-stack trap).
    func testGearReachesSettingsFromTrendsAndBackReturnsToTrends() {
        let app = launch()
        app.buttons["tabbar.trends"].tap()
        let trendsGear = gear(app)
        XCTAssertTrue(trendsGear.waitForExistence(timeout: 5),
                      "the Trends root must carry the gear (the reported bug)")

        trendsGear.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5),
                      "the Trends root's gear must reach Settings")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["trendsHeaderTitle"].waitForExistence(timeout: 5),
                      "Settings pushed from Trends must back to Trends, not the Log")
        XCTAssertFalse(app.staticTexts["homeHeaderTitle"].isHittable,
                       "back from Settings on the Trends stack must never land on the Log root")
    }

    /// Gear -> Settings -> back must land on the GARAGE root.
    func testGearReachesSettingsFromGarageAndBackReturnsToGarage() {
        let app = launch()
        app.buttons["tabbar.garage"].tap()
        let garageGear = gear(app)
        XCTAssertTrue(garageGear.waitForExistence(timeout: 5),
                      "the Garage root must carry the gear (the reported bug)")

        garageGear.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5),
                      "the Garage root's gear must reach Settings")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5),
                      "Settings pushed from Garage must back to Garage, not the Log")
        XCTAssertFalse(app.staticTexts["homeHeaderTitle"].isHittable,
                       "back from Settings on the Garage stack must never land on the Log root")
    }

    // MARK: - Helpers

    /// The three roots must render the gear at the SAME place and size.
    /// Tolerance is 1 pt: sub-point differences are rendering noise; anything
    /// more is a gear in a different spot.
    private func assertFrame(_ actual: CGRect, matches reference: CGRect, tab: String) {
        XCTAssertEqual(actual.origin.x, reference.origin.x, accuracy: 1.0,
                       "\(tab) gear x (\(actual.origin.x)) must match Log's (\(reference.origin.x))")
        XCTAssertEqual(actual.origin.y, reference.origin.y, accuracy: 1.0,
                       "\(tab) gear y (\(actual.origin.y)) must match Log's (\(reference.origin.y))")
        XCTAssertEqual(actual.width, reference.width, accuracy: 1.0,
                       "\(tab) gear width (\(actual.width)) must match Log's (\(reference.width))")
        XCTAssertEqual(actual.height, reference.height, accuracy: 1.0,
                       "\(tab) gear height (\(actual.height)) must match Log's (\(reference.height))")
    }
}
