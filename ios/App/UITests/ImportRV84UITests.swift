import XCTest

/// RV.84 - the two import-source RU layout defects (the 422 card clipping, and
/// the dead-end card's action line dropping below the fold). Lives in its own
/// file so `ImportUITests.swift` stays under the file-length floor (the same
/// pattern `ImportRV68UITests` uses).
///
/// Both defects share one screen and were measured, not guessed:
/// - The parse-error card used to live in the safe-area-inset bottom bar, the
///   one region that does not scroll. RU's longer text makes the 422 card the
///   tallest parse-error card (~150pt with the help link), so in RU the inset
///   stole so much of the ScrollView's budget that the content clipped at the
///   fold (EN fit by luck, 13-30pt of RU overflow). The card now LEADS the
///   scroll content under the title.
/// - With the card leading the scroll, RU's taller content can still push the
///   dead-end "Send us the file" card - the error's own next step (hard rule 7)
///   - below the fold. In the parse-error moment it is therefore ordered
///   directly under the list, above the "Not yet" teaser.
///
/// Every assertion is a FRAME comparison against the window, never `isHittable`
/// - which reported a clipped element as hittable in exactly this state (RV.80
/// measured it).
@MainActor
final class ImportRV84UITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    private func russian(_ arguments: [String]) -> XCUIApplication {
        launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"] + arguments)
    }

    private func assertFullyOnScreen(_ element: XCUIElement,
                                     app: XCUIApplication,
                                     _ message: String) {
        let tabbar = app.otherElements["tabbar"]
        XCTAssertTrue(tabbar.waitForExistence(timeout: 5),
                      "the owned tab bar is on screen")
        XCTAssertGreaterThanOrEqual(element.frame.minY, 0,
                                    "\(message): element must not render above the window's top")
        XCTAssertLessThanOrEqual(element.frame.maxY, tabbar.frame.minY + 1,
                                 "\(message): element must render entirely above the tab bar, "
                                 + "never clipped at the fold")
    }

    // MARK: - RV.84 defect A: the whole 422 card is on screen in RU

    /// The link is the lowest element of the 422 card, so the whole card is on
    /// screen when the link is. The discriminating half: the card renders ABOVE
    /// the first format row - a mutation that returns it to the bottom inset
    /// drops the link below the list (and re-starts the clipping) and fails.
    func test422CardAndHelpLinkFullyOnScreenInRussian() {
        let app = russian(["-presentScreen", "importWizard",
                           "-importStubFormats", "one", "-seedImportParse422",
                           "-importStubParse422"])
        let link = app.descendants(matching: .any)["import422Help"]
        XCTAssertTrue(link.waitForExistence(timeout: 15),
                      "the RU 422 card's help link must render")
        let body = app.staticTexts["Выберите другое приложение из списка или пришлите файл."]
        XCTAssertTrue(body.waitForExistence(timeout: 5),
                      "the RU 422 message body must render")

        assertFullyOnScreen(link, app: app,
                            "the RU 422 help link must be fully on screen at rest")
        assertFullyOnScreen(body, app: app,
                            "the RU 422 message must be fully on screen at rest")

        let row = app.buttons["importFormatRow-mfm"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertLessThan(link.frame.minY, row.frame.minY,
                          "the 422 card must render above the format list, never in fixed "
                          + "bottom chrome (a card whose height follows the locale must not "
                          + "live in the non-scrolling inset)")
    }

    func test422CardAndHelpLinkFullyOnScreen() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportParse422",
                          "-importStubParse422"])
        let link = app.descendants(matching: .any)["import422Help"]
        XCTAssertTrue(link.waitForExistence(timeout: 15))
        assertFullyOnScreen(link, app: app,
                            "the EN 422 help link must be fully on screen at rest")
        let row = app.buttons["importFormatRow-mfm"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertLessThan(link.frame.minY, row.frame.minY,
                          "the EN 422 card must render above the format list")
    }

    // MARK: - RV.84 defect B: the dead-end action stays on screen in RU

    /// With the tallest parse-error card (the 422) showing, RU must still show
    /// the dead-end card's action line at rest. Three frame assertions: fully
    /// inside the window, above the fixed primary bar, and not overlapped by
    /// the parse-error card.
    func testDeadEndActionStaysOnScreenWithThe422CardInRussian() {
        let app = russian(["-presentScreen", "importWizard",
                           "-importStubFormats", "one", "-seedImportParse422",
                           "-importStubParse422"])
        let link = app.descendants(matching: .any)["import422Help"]
        XCTAssertTrue(link.waitForExistence(timeout: 15),
                      "the RU 422 card must be showing (the state under test)")
        let action = app.staticTexts["Отправить файл"]
        XCTAssertTrue(action.waitForExistence(timeout: 10),
                      "the RU dead-end action line ('Отправить файл') must render")

        assertFullyOnScreen(action, app: app,
                            "the RU dead-end action must be fully on screen at rest")

        // The primary bar is the only fixed chrome below the scroll now - the
        // action must sit above it, never hidden under it.
        let bar = app.buttons["importChooseFileButton"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(action.frame.maxY, bar.frame.minY + 1,
                                 "the RU dead-end action must sit above the fixed primary bar "
                                 + "at rest - if the 'Not yet' teaser is ordered above the card "
                                 + "again, RU pushes the action under the bar")

        // The parse card and the dead-end card must not overlap: the 422 card
        // (whose lowest element is the help link) ends above the action line.
        XCTAssertLessThanOrEqual(link.frame.maxY, action.frame.minY + 1,
                                 "the 422 card and the dead-end card must not overlap - each "
                                 + "must be fully readable (the old inset layout ran the 422 "
                                 + "card over the dead-end action in RU)")
    }

    func testDeadEndActionStaysOnScreenWithThe422Card() {
        let app = launch(["-presentScreen", "importWizard",
                          "-importStubFormats", "one", "-seedImportParse422",
                          "-importStubParse422"])
        let link = app.descendants(matching: .any)["import422Help"]
        XCTAssertTrue(link.waitForExistence(timeout: 15))
        let action = app.staticTexts["Send us the file"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        assertFullyOnScreen(action, app: app,
                            "the EN dead-end action must be fully on screen at rest")
        let bar = app.buttons["importChooseFileButton"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(action.frame.maxY, bar.frame.minY + 1,
                                 "the EN dead-end action must sit above the fixed primary bar")
        XCTAssertLessThanOrEqual(link.frame.maxY, action.frame.minY + 1,
                                 "the EN 422 card and the dead-end card must not overlap")
    }
}
