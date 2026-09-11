import XCTest

/// RV.191 - at the real format count (two registered rows since RV.190) RU's
/// longer format subtitles push the dashed dead-end card below the fold, and
/// "Send us the file" - the dead end's own next step (hard rule 7) - is not
/// visible without scrolling. The card is pinned in the bottom inset, so the
/// action is on screen at rest. The assertion is `isHittable`, not `exists`:
/// the action existed below the fold, which is the vacuous trap.
@MainActor
final class ImportRV191UITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    private func assertDeadEndActionReachable(_ app: XCUIApplication,
                                              actionLabel: String) {
        XCTAssertTrue(app.buttons["importFormatRow-mfm"].waitForExistence(timeout: 10),
                      "the shipped format list must render both registered formats")
        XCTAssertTrue(app.buttons["importFormatRow-drivvo"].exists,
                      "the second registered format is the count that clipped the card")
        let action = app.staticTexts[actionLabel]
        XCTAssertTrue(action.waitForExistence(timeout: 5),
                      "the dead-end action line must render ('\(actionLabel)')")

        // The assertion is a FRAME comparison, not only `isHittable`: RV.80
        // measured `isHittable` reporting a clipped element as hittable, so the
        // action must also be laid out entirely inside the window and above the
        // primary bar, or this test would pass on the very defect it targets.
        let window = app.windows.firstMatch
        let bar = app.buttons["importChooseFileButton"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5),
                      "the primary bar is the fixed chrome below the pinned card")
        XCTAssertGreaterThanOrEqual(action.frame.minY, 0,
                                    "the action must not render above the window's top")
        XCTAssertLessThanOrEqual(action.frame.maxY, window.frame.maxY,
                                 "the action must sit inside the window")
        XCTAssertLessThanOrEqual(action.frame.maxY, bar.frame.minY + 1,
                                 "the action must sit above the primary bar, not under it")
        XCTAssertTrue(action.isHittable,
                      "the dead-end action must be visible at rest, not below the fold "
                      + "(the RV.191 defect)")
    }

    func testDeadEndActionIsReachableAtTwoFormatsInRussian() {
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                          "-presentScreen", "importWizard", "-importStubFormats", "shipped"])
        assertDeadEndActionReachable(app, actionLabel: "Отправить файл")
    }

    func testDeadEndActionIsReachableAtTwoFormats() {
        let app = launch(["-presentScreen", "importWizard", "-importStubFormats", "shipped"])
        assertDeadEndActionReachable(app, actionLabel: "Send us the file")
    }
}
