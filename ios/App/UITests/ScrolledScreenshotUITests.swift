import XCTest

/// Screenshots of a state below the fold, which `simctl` cannot scroll to:
/// the test poses the screen, scrolls, and writes the PNG to the host path in
/// `SCROLLED_SHOT_DIR`. Opt-in: skipped unless that variable is set, and run
/// alone - `simctl` and a test run fight over the device.
@MainActor
final class ScrolledScreenshotUITests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    private func shot(_ name: String, args: [String], scrollTo identifier: String) throws {
        let dir = try XCTUnwrap(environment["SCROLLED_SHOT_DIR"])
        let russian = environment["SCROLLED_SHOT_LANG"] == "ru"
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-freezeSyncState",
                               "-AppleLanguages", russian ? "(ru)" : "(en)",
                               "-AppleLocale", russian ? "ru_RU" : "en_US"] + args
        app.launch()
        let target = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        var swipes = 0
        while swipes < 6, target.frame.maxY > app.windows.firstMatch.frame.maxY * 0.8 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        sleep(1)
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name + (russian ? "-ru" : "") + ".png")
        try app.screenshot().pngRepresentation.write(to: url)
    }

    func testMixedReceiptAdBlueRow() throws {
        try XCTSkipUnless(environment["SCROLLED_SHOT_DIR"] != nil, "scrolled screenshots are opt-in")
        try shot("P1.15-mixed-adblue-row",
                 args: ["-seedVehicleForUITests", "-seedVehicleDieselOnly", "-presentScreen", "confirmManual",
                        "-seedConfirmPrefillMixedAdBlue"],
                 scrollTo: "mixedReceiptFooter")
    }
}
