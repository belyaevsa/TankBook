import XCTest

/// P6.18b UI tests: the update requirement's surface (docs/CONFIG.md -> "App
/// version and the update notice").
///
/// The three shapes, pinned as BEHAVIOUR, never as decoration:
/// - `.recommended` (**soft**): a dismissible row in Settings -> About, quiet.
/// - `.required` (**hard**): a non-dismissible notice on the server-backed
///   surfaces only (sync, cloud extract, import parse), naming its next step.
/// - Under `.required` everything local still works - the load-bearing test
///   below is a real journey: open the manual form, type the numbers, save,
///   and assert the entry exists in the log. The defect this task guards
///   against is a screen refusing to save, not a missing label, so the journey
///   asserts the entry, never that a button "isEnabled".
///
/// The requirement is seeded the honest way: the debug override sets the two
/// THRESHOLDS (`-configAppUpdate min latest`) and the running version is
/// injected (`-configRunningVersion`), so `.required`/`.recommended` are
/// DERIVED exactly as a real signed document would derive them - never forced.
/// `.required`  = running 1.0.0 below min 1.2.0.
/// `.recommended` = running 1.3.0 above min 1.2.0, below latest 1.4.0.
@MainActor
final class UpdateRequirementUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    private func launchRU(_ arguments: [String]) -> XCUIApplication {
        launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"] + arguments)
    }

    /// The seeded `.required` requirement (running 1.0.0 below min 1.2.0).
    private let requiredArgs = ["-configAppUpdate", "1.2.0", "1.4.0",
                                "-configRunningVersion", "1.0.0"]

    /// The seeded `.recommended` requirement (running 1.3.0 between the two).
    private let recommendedArgs = ["-configAppUpdate", "1.2.0", "1.4.0",
                                   "-configRunningVersion", "1.3.0"]

    private let requiredMessageEN = "This version of Tankbook is out of date – sync, cloud reading "
        + "and import are paused. Update the app to use them again."
    private let requiredMessageRU = "Эта версия Tankbook устарела – синхронизация, облачное "
        + "распознавание и импорт приостановлены. Обновите приложение, чтобы использовать их снова."

    private func notice(_ app: XCUIApplication) -> XCUIElement {
        app.otherElements["updateRequiredNotice"]
    }

    /// A SwiftUI `Link` is exposed as a button element, but the type is not a
    /// contract worth betting a test on - query by identifier across all
    /// element kinds.
    private func updateButton(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["updateRecommendedButton"]
    }

    /// XCUITest refuses a string identifier longer than 128 characters, and the
    /// RU notice exceeds that - long-message lookups go through a label
    /// predicate instead of the `staticTexts["..."]` subscript.
    private func messageText(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    // MARK: - .recommended: the dismissible About row

    func testRecommendedShowsDismissibleRowInAbout() {
        let app = launch(["-presentScreen", "about"] + recommendedArgs)

        let row = app.otherElements["updateRecommendedRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "the recommended update row must render in About")
        XCTAssertTrue(app.staticTexts["A newer version of Tankbook is available."].exists)
        // Quiet: no required notice, no upsell wording.
        XCTAssertFalse(notice(app).exists)
        XCTAssertFalse(app.staticTexts["Tankbook Pro"].exists)

        // Dismissible: the row goes away, and nothing else moves.
        let close = app.buttons["updateRecommendedDismiss"]
        XCTAssertTrue(close.exists, "the row must be dismissible")
        close.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5),
                      "dismissing the recommended row must remove it")
    }

    func testRecommendedButtonAppearsOnlyWhenAnAppIdExists() {
        // No app id - the situation today: no dead button.
        let noStore = launch(["-presentScreen", "about"] + recommendedArgs)
        XCTAssertTrue(noStore.otherElements["updateRecommendedRow"].waitForExistence(timeout: 10))
        XCTAssertFalse(updateButton(noStore).exists,
                       "without an app id the row must not offer a button that goes nowhere")

        // With an app id the button appears.
        let withStore = launch(["-presentScreen", "about"] + recommendedArgs
                               + ["-configAppStoreID", "1234567890"])
        XCTAssertTrue(updateButton(withStore).waitForExistence(timeout: 10),
                      "with an app id the update button must appear")
    }

    func testRecommendedIsQuietNoModalNoUpsell() {
        let app = launch(["-presentScreen", "about"] + recommendedArgs)
        XCTAssertTrue(app.otherElements["updateRecommendedRow"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.sheets.firstMatch.exists)
        for forbidden in ["pro", "price", "upgrade", "$"] {
            XCTAssertFalse(app.staticTexts["A newer version of Tankbook is available."]
                            .label.lowercased().contains(forbidden))
        }
    }

    // MARK: - .required: the non-dismissible notice on server-backed surfaces

    func testRequiredShowsNoticeOnSyncSurface() {
        let app = launch(["-presentScreen", "settings", "-seedSettingsSynced"] + requiredArgs)

        XCTAssertTrue(notice(app).waitForExistence(timeout: 10),
                      "the required notice must render on the sync surface")
        let message = messageText(app, requiredMessageEN)
        XCTAssertTrue(message.exists)
        XCTAssertFalse(app.buttons["settingsSyncNowButton"].exists,
                       "the sync affordance is replaced, never left dead")
        // Never a modal (hard rule 8), never an upsell (hard rule 7).
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.sheets.firstMatch.exists)
        let label = message.label.lowercased()
        for forbidden in ["pro", "tier", "price", "upgrade", "$"] {
            XCTAssertFalse(label.contains(forbidden),
                           "the required notice must not upsell: '\(forbidden)'")
        }
    }

    func testRequiredShowsNoticeOnImportSurface() {
        let app = launch(["-presentScreen", "importWizard"] + requiredArgs)

        XCTAssertTrue(notice(app).waitForExistence(timeout: 10),
                      "the required notice must render on the import (parse) surface")
        XCTAssertFalse(app.buttons["importChooseFileButton"].exists,
                       "the parse affordance is replaced, never left dead")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testRequiredShowsNoticeOnCloudExtractSurface() {
        // A scan with a photo is the cloud-extract surface: the gateway reading
        // is withheld and the notice renders in its place.
        let app = launch(["-presentScreen", "confirmManual",
                          "-seedGateway", "-seedConfirmPrefill",
                          "-seedVehicleForUITests"] + requiredArgs)

        XCTAssertTrue(notice(app).waitForExistence(timeout: 10),
                      "the required notice must render on the cloud-extract surface")
        XCTAssertFalse(app.staticTexts["gatewayTimeoutMessage"].exists,
                       "with no request in flight there is no 3 s budget message")
    }

    func testRequiredNoticeNeverAppearsOnThePureManualForm() {
        // The typed form is not a server-backed surface: under `.required` it
        // is clean - no notice, nothing withheld (hard rule 1, "nothing else
        // changes").
        let app = launch(["-presentScreen", "confirmManual"] + requiredArgs
                         + ["-seedVehicleForUITests"])
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 10))
        XCTAssertFalse(notice(app).exists,
                       "the required notice belongs on server-backed surfaces only")
    }

    // MARK: - The load-bearing journey: a fill-up still saves under .required

    func testFillUpStillSavesUnderRequired() {
        // `-seedSettingsSignedIn` pins the session the journey needs: Home's
        // `typeItButton` (and the log stream the final assertion reads) live in
        // the signed-in layout, never the guest chrome. Without it the launch
        // renders the guest Home - a real state since PJ.3 - and the button the
        // test taps is `homeGuestCaptureButton`, not `typeItButton`.
        let app = launch(requiredArgs + ["-seedVehicleForUITests", "-seedSettingsSignedIn"])
        XCTAssertTrue(app.buttons["typeItButton"].waitForExistence(timeout: 10))

        // The journey, not a state assertion: open the manual form, type the
        // numbers, save, and assert the entry EXISTS in the log. `-homeResetDatabase`
        // gives a known state: one seeded prior fill, so after the save the log
        // must hold exactly two.
        app.buttons["typeItButton"].tap()
        let total = focusField(app, "manualFillUpTotalField")
        total.typeText("71.02")
        let liters = focusField(app, "manualFillUpLitersField")
        liters.typeText("42.30")

        let save = app.buttons["manualFillUpSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        // Back on Home, the log reloads (the save bumps the toastCenter
        // revision) and holds the prior seeded fill plus this one. Poll the
        // count: the reload is async.
        XCTAssertTrue(app.staticTexts["homeHeaderTitle"].waitForExistence(timeout: 5))
        let rows = app.buttons.matching(identifier: "logEntryButton")
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline && rows.count != 2 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(rows.count, 2,
                       "expected the prior seeded fill plus the new one, found \(rows.count)")
    }

    // MARK: - RU renders the same shapes (the localization-blind-spot guard)

    func testRecommendedRendersInRussian() {
        let app = launchRU(["-presentScreen", "about"] + recommendedArgs)
        XCTAssertTrue(app.otherElements["updateRecommendedRow"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Доступна новая версия Tankbook."].exists)
    }

    func testRequiredRendersInRussianOnTheSyncSurface() {
        let app = launchRU(["-presentScreen", "settings", "-seedSettingsSynced"] + requiredArgs)
        XCTAssertTrue(notice(app).waitForExistence(timeout: 10))
        let message = messageText(app, requiredMessageRU)
        XCTAssertTrue(message.exists)
        // No upsell wording in RU either (hard rule 7).
        let label = message.label
        for forbidden in ["Про", "цена", "тариф", "$", "подписк", "премиум"] {
            XCTAssertFalse(label.contains(forbidden),
                           "the required notice must not upsell in RU: '\(forbidden)'")
        }
    }

    // MARK: - Journey helpers (the save-bar and keyboard traps from
    // ConfirmManualUITests, applied because `isHittable` does not model the
    // pinned save bar's occlusion).

    @discardableResult
    private func focusField(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "\(identifier) never appeared")
        // Dismiss the keyboard and scroll the field clear, on the SHEET'S OWN
        // scroll view. The trap (from ConfirmManualUITests): a drag started
        // under the keyboard is eaten by it, so anchor the drag in the visible
        // region above the pinned save bar - that both dismisses the keyboard
        // and reveals the field.
        var scrolls = 0
        while !field.isHittable && scrolls < 8 {
            if let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
                from.press(forDuration: 0.05, thenDragTo: to)
            }
            scrolls += 1
        }
        XCTAssertTrue(field.isHittable, "\(identifier) is on screen but not reachable")
        field.tap()
        return field
    }
}

private extension XCUIElement {
    /// Waits for the element to disappear, polling `exists`. A predicate
    /// expectation over the `exists` keypath does not re-evaluate on
    /// `XCUIElement`, so a plain polling loop is the reliable form here.
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return !exists
    }
}
