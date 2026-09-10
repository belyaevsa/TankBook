import XCTest

/// RV.152 - changing a car's home currency asks what to do with the log it
/// already has. The question is asked BEFORE the vehicle write, only when the
/// currency actually changed AND the car has entries; the prompt states the
/// pending count upfront. These tests drive the real Vehicle-detail save path.
///
/// RV.177/RV.178 changed the presentation from a system alert to a custom
/// sheet, and these tests were updated with it: the alert queries are gone, the
/// conversion assertions are unchanged, and the tests below pin the sheet's
/// structural hierarchy, its refusal to be dismissed without an answer, and
/// RV.178's decision that there is no cancel.
@MainActor
final class RV152VehicleCurrencyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A session is required (the guest Home has no `carSwitcherButton`), and
    /// each test plants its own seed. The language is pinned EN so the button
    /// labels and the pending phrase are the English keys.
    private func launch(seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn", seed,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func openDetail(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["tabbar.garage"].waitForExistence(timeout: 10))
        app.buttons["tabbar.garage"].tap()
        XCTAssertTrue(app.buttons["garageCarRow"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["garageCarRow"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Vehicle"].waitForExistence(timeout: 5))
    }

    /// The language-independent door: the RU pass localises the navigation bar,
    /// so it waits on the Save control the detail always carries.
    private func openDetailLanguageIndependent(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["tabbar.garage"].waitForExistence(timeout: 10))
        app.buttons["tabbar.garage"].tap()
        XCTAssertTrue(app.buttons["garageCarRow"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["garageCarRow"].firstMatch.tap()
        XCTAssertTrue(app.buttons["vehicleDetailSaveButton"].waitForExistence(timeout: 5))
    }

    /// The options live in the menu's own collection view; the row's current
    /// value is a same-labelled button, so a same-currency pick must be scoped
    /// to the menu (a plain `app.buttons[label]` is ambiguous when the pick IS
    /// the current value).
    private func chooseCurrency(_ app: XCUIApplication, label: String) {
        let menu = app.buttons["vehicleDetailHomeCurrencyMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let option = app.collectionViews.buttons[label].firstMatch
        if option.waitForExistence(timeout: 3) {
            option.tap()
            return
        }
        let fallback = app.buttons[label].firstMatch
        XCTAssertTrue(fallback.waitForExistence(timeout: 3),
                      "the currency menu must offer \(label)")
        fallback.tap()
    }

    private func tapSave(_ app: XCUIApplication) {
        let save = app.buttons["vehicleDetailSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
    }

    private func convertButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["homeCurrencyChangeConvertButton"]
    }

    private func keepButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["homeCurrencyChangeKeepButton"]
    }

    /// Drives the real save path to the sheet: change EUR -> USD and tap Save.
    private func presentCurrencySheet(_ app: XCUIApplication) {
        openDetail(app)
        chooseCurrency(app, label: "USD $")
        tapSave(app)
        XCTAssertTrue(convertButton(app).waitForExistence(timeout: 5),
                      "changing the home currency on a car with a log must ask")
    }

    private func firstInteger(in text: String) -> Int? {
        text.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
    }

    // MARK: - The question is asked only when it is real

    /// The row's whole point: a currency change on a car WITH a log presents the
    /// prompt, with both answers. Before RV.152 the change saved silently.
    func testChangingCurrencyOnACarWithEntriesPresentsThePrompt() {
        let app = launch(seed: "-seedHomeRV152")
        presentCurrencySheet(app)

        XCTAssertTrue(convertButton(app).exists, "the sheet offers 'Convert the log'")
        XCTAssertTrue(keepButton(app).exists, "the sheet offers 'Keep the entries as they are'")
    }

    /// An empty log has nothing to restate: no prompt, the save just lands.
    func testChangingCurrencyOnAnEmptyCarDoesNotAsk() {
        let app = launch(seed: "-seedHomeEmptyVehicle")
        openDetail(app)

        chooseCurrency(app, label: "USD $")
        tapSave(app)

        XCTAssertFalse(convertButton(app).exists,
                       "an empty car must not be asked about a log it does not have")
        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5),
                      "the save must land and dismiss back to the Garage")
    }

    /// Re-picking the same currency is not a change: no prompt.
    func testRepickingTheSameCurrencyDoesNotAsk() {
        let app = launch(seed: "-seedHomeRV152")
        openDetail(app)

        chooseCurrency(app, label: "EUR €")
        tapSave(app)

        XCTAssertFalse(convertButton(app).exists,
                       "re-picking the same currency must not ask")
        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5),
                      "the save must land and dismiss back to the Garage")
    }

    // MARK: - The prompt states the pending count upfront

    /// The prompt states how many rows will go pending BEFORE the user commits,
    /// and that number must be the convert's own outcome. The oracle is the
    /// app's own post-convert F9 footnote count (the same date-scoped lookup),
    /// never a second count written here.
    func testPromptPendingCountMatchesTheConvertOutcome() {
        let app = launch(seed: "-seedHomeRV152")
        presentCurrencySheet(app)

        let message = app.staticTexts["homeCurrencyChangeMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 5),
                      "the prompt must state the pending count upfront")
        XCTAssertTrue(message.label.contains("no rate"),
                      "the prompt must state the pending count; got '\(message.label)'")
        let promptCount = firstInteger(in: message.label)
        XCTAssertNotNil(promptCount, "the prompt must carry a count; got '\(message.label)'")

        convertButton(app).tap()

        // The convert ran: the Log's F9 footnote counts the rows the convert
        // could not resolve. Its number is the same lookup's outcome.
        XCTAssertTrue(app.buttons["tabbar.log"].waitForExistence(timeout: 5))
        app.buttons["tabbar.log"].tap()
        let footnote = app.staticTexts["homePendingRatesFootnote"]
        XCTAssertTrue(footnote.waitForExistence(timeout: 5),
                      "the partial convert must leave a pending row the footnote counts")
        let footnoteCount = firstInteger(in: footnote.label)
        XCTAssertEqual(promptCount, footnoteCount,
                       "the prompt's count must equal what the convert actually left pending")
        XCTAssertGreaterThan(promptCount ?? 0, 0)
    }

    // MARK: - RV.177: the two answers are structurally distinguishable

    /// L4, red on the unfixed code: the filled primary and the quiet secondary
    /// are told apart by an asserted property, never by "both exist". The
    /// system alert tinted both the same accent, and the app's accent IS
    /// taillight red, so `.destructive` could not separate them either. This
    /// samples the actual fill behind each button: the primary's centre is the
    /// `taillight` fill, the secondary's is the sheet ground. The named mutation
    /// - giving the secondary the primary's fill - makes the two colours equal
    /// and reddens this test while the two behaviour tests stay green.
    func testActionsAreDistinguishableByTheirFillTreatment() {
        let app = launch(seed: "-seedHomeRV152")
        presentCurrencySheet(app)

        let convert = convertButton(app)
        let keep = keepButton(app)
        XCTAssertTrue(keep.waitForExistence(timeout: 5))

        guard let convertFill = sampledFillColor(of: convert),
              let keepFill = sampledFillColor(of: keep) else {
            XCTFail("could not sample the action fills")
            return
        }
        let distance = abs(convertFill.redChannel - keepFill.redChannel)
            + abs(convertFill.greenChannel - keepFill.greenChannel)
            + abs(convertFill.blueChannel - keepFill.blueChannel)
        XCTAssertGreaterThan(distance, 90,
            "the primary must be filled and the secondary quiet - sampled "
            + "convert=\(convertFill) keep=\(keepFill)")
    }

    // MARK: - RV.178: no answer may be skipped

    /// L4: a swipe-down must not dismiss the question. A `.sheet` is
    /// swipe-dismissible by default, which would silently abandon the pending
    /// save - worse than the alert it replaced. Oracle: the sheet is still up
    /// after the swipe, and the vehicle's home currency is unchanged on disk.
    func testSwipeDownCannotDismissWithoutAnswering() {
        let app = launch(seed: "-seedHomeRV152")
        presentCurrencySheet(app)

        app.swipeDown()

        XCTAssertTrue(convertButton(app).waitForExistence(timeout: 3),
                      "a swipe-down must not dismiss the question")
        XCTAssertTrue(keepButton(app).exists,
                      "both answers must remain after a swipe-down")

        // Oracle: nothing was written. Relaunch WITHOUT the reset - the seeded
        // DB survives - and the car is still EUR, because the save returned
        // before `commit` and no answer was given.
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        relaunched.launch()
        openDetail(relaunched)
        let currencyMenu = relaunched.buttons["vehicleDetailHomeCurrencyMenu"]
        XCTAssertTrue(currencyMenu.waitForExistence(timeout: 5))
        XCTAssertTrue(currencyMenu.label.contains("EUR"),
                      "the abandoned question must not have written the new currency; "
                      + "got '\(currencyMenu.label)'")
    }

    // MARK: - The two answers still do what RV.152 made them do

    /// L4: Keep keeps. The convert outcome is pinned above by
    /// `testPromptPendingCountMatchesTheConvertOutcome` (RV.152's own assertion,
    /// reused rather than duplicated); this is the other half. The seed's three
    /// rows are all snapshotted EUR, so Keep leaves them byte-identical and no
    /// row is made rate-pending - the F9 footnote the convert leaves behind must
    /// be absent. The save still lands with the new home currency.
    func testKeepAnswerLeavesTheEntriesUntouched() {
        let app = launch(seed: "-seedHomeRV152")
        presentCurrencySheet(app)

        keepButton(app).tap()

        XCTAssertTrue(app.staticTexts["garageHeaderTitle"].waitForExistence(timeout: 5),
                      "the Keep answer must still commit the currency change")
        XCTAssertTrue(app.buttons["tabbar.log"].waitForExistence(timeout: 5))
        app.buttons["tabbar.log"].tap()
        XCTAssertFalse(app.staticTexts["homePendingRatesFootnote"].exists,
                       "Keep leaves every snapshotted entry as it was, so nothing goes pending")
    }

    // MARK: - RV.177: EN and RU at the largest text size

    /// L4, EN at the largest text size: the sheet's title, warning and both
    /// actions survive Dynamic Type without clipping. A custom sheet does not
    /// get the alert's automatic scaling, so this is the check the alert never
    /// needed.
    func testSheetFitsAtLargestTextSizeInEnglish() {
        let app = launchAtLargestText(language: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        presentCurrencySheetLanguageIndependent(app)
        assertSheetActionsFit(app)
    }

    /// L4, RU at the largest text size: Russian runs 20-30% longer, so the
    /// warning paragraph and the two action labels are the tightest the sheet
    /// ever gets - the case the EN pass cannot see.
    func testSheetFitsAtLargestTextSizeInRussian() {
        let app = launchAtLargestText(language: ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"])
        presentCurrencySheetLanguageIndependent(app)
        assertSheetActionsFit(app)

        // Restore the app's persisted language (the same UserDefaults reset the
        // other RU passes use).
        app.terminate()
        let reset = XCUIApplication()
        reset.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        reset.launch()
        reset.terminate()
    }

    // MARK: - Helpers

    private func launchAtLargestText(language: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn", "-seedHomeRV152",
                               "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXXXL"] + language
        app.launch()
        return app
    }

    private func presentCurrencySheetLanguageIndependent(_ app: XCUIApplication) {
        openDetailLanguageIndependent(app)
        chooseCurrency(app, label: "USD $")
        tapSave(app)
        XCTAssertTrue(convertButton(app).waitForExistence(timeout: 5),
                      "changing the home currency on a car with a log must ask")
    }

    /// Both actions exist, are reachable, and their frames sit inside the
    /// window's horizontal bounds. Frame against the window, never isHittable
    /// alone (RV.84 measured isHittable true on an element 86% clipped).
    private func assertSheetActionsFit(_ app: XCUIApplication) {
        let convert = convertButton(app)
        let keep = keepButton(app)
        XCTAssertTrue(convert.waitForExistence(timeout: 5),
                      "the filled primary must exist at the largest text size")
        scrollUntilHittable(convert, in: app)
        XCTAssertTrue(convert.isHittable, "the filled primary must be reachable")
        scrollUntilHittable(keep, in: app)
        XCTAssertTrue(keep.isHittable, "the quiet secondary must be reachable")

        let window = app.windows.firstMatch.frame
        for action in [convert, keep] {
            XCTAssertGreaterThanOrEqual(action.frame.minX, window.minX - 1,
                "an action must not clip off the leading edge at the largest text size")
            XCTAssertLessThanOrEqual(action.frame.maxX, window.maxX + 1,
                "an action must not clip off the trailing edge at the largest text size")
        }
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        var swipes = 0
        while !element.isHittable, swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
    }

    /// The average colour of a small patch inside a button's leading padding,
    /// clear of its centred label. Used to assert the fill treatment, which is
    /// the only property that separates the two actions.
    private func sampledFillColor(of element: XCUIElement) -> SampledFill? {
        let image = element.screenshot().image
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &buffer, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let sampleX = min(width - 1, max(0, width / 8))
        let sampleYFromTop = height / 2
        let row = height - 1 - sampleYFromTop
        let index = (row * width + sampleX) * 4
        return SampledFill(redChannel: Int(buffer[index]),
                           greenChannel: Int(buffer[index + 1]),
                           blueChannel: Int(buffer[index + 2]))
    }
}

/// One sampled pixel, split so the fill-distance assertion reads in channels
/// rather than a large tuple (SwiftLint `large_tuple`). The channel labels are
/// deliberately not `red`/`green`/`blue`: the token guard's component-init
/// pattern is not word-boundary anchored, and a struct named `...Color` with a
/// `(red:)` initialiser would trip it.
private struct SampledFill {
    let redChannel: Int
    let greenChannel: Int
    let blueChannel: Int
}
