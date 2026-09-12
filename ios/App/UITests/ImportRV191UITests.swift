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

    // MARK: - RV.227: the "Not yet" chips are clear of the pinned chrome at rest

    /// The "Not yet" chip row is the LAST scroll child: at the real two-format
    /// count the content overflowed by ~30pt, so at the default position only
    /// the top of each capsule showed and the labels sat under the scroll
    /// viewport's clipped edge (the orchestrator's RU screenshot: "four empty
    /// rounded rects with no text"). The vertical padding is now tightened so
    /// the whole block fits at rest in both locales.
    ///
    /// Every assertion is a FRAME comparison, never `isHittable`: RV.80 and
    /// PJ.7e both measured `isHittable` reporting a clipped element as hittable.
    /// The discriminating half is the scroll viewport - a chip below its bottom
    /// edge is clipped even though its window frame looks fine, so the card
    /// comparison alone would pass on the defect (it did, before this test).
    private func assertNotYetChipsClear(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["importFormatRow-mfm"].waitForExistence(timeout: 10),
                      "the shipped format list must render")
        let scroll = app.scrollViews.containing(.staticText, identifier: "Fuelio").element
        XCTAssertTrue(scroll.waitForExistence(timeout: 5),
                      "the import picker's scroll view must contain the Not yet row")
        let card = app.buttons["importNotSupportedCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5),
                      "the pinned dead-end card must render")

        for name in ["Fuelio", "Fuelly", "Spritmonitor", "CarScope"] {
            let chip = app.staticTexts[name]
            XCTAssertTrue(chip.waitForExistence(timeout: 5),
                          "the Not yet chip '\(name)' must render")
            XCTAssertLessThanOrEqual(
                chip.frame.maxY, scroll.frame.maxY + 1,
                "the '\(name)' chip must sit inside the scroll viewport at rest, "
                + "never clipped under its bottom edge (the RV.227 defect)")
            XCTAssertLessThanOrEqual(
                chip.frame.maxY, card.frame.minY + 1,
                "the '\(name)' chip must sit above the pinned dead-end card")
        }
    }

    func testNotYetChipsAreClearOfThePinnedCardInRussian() {
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                          "-presentScreen", "importWizard", "-importStubFormats", "shipped"])
        assertNotYetChipsClear(app)
    }

    func testNotYetChipsAreClearOfThePinnedCard() {
        let app = launch(["-presentScreen", "importWizard", "-importStubFormats", "shipped"])
        assertNotYetChipsClear(app)
    }
}
