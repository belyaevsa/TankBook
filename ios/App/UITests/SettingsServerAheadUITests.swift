import XCTest

/// P6.11 UI tests: a server that has moved ahead of this client surfaces on the
/// Settings account card as **version-first** copy - update, never an upsell
/// (hard rule 7, and simply true: there is no Pro tier) - and `.rateLimited` is
/// a wait, not a failure (docs/SYNC.md -> "The Settings sync surface"). No
/// modal (hard rule 8), no screen gated (hard rule 1), and a refused push
/// leaves the queue dirty (S7).
///
/// The four outcomes - 426 `.upgradeRequired`, 402 `.tierRefused`, an unknown
/// 4xx `.refused(status:)`, and 429 `.rateLimited(retryAfterSeconds:)` - each
/// render their own message; collapsing them into one is the shortcut this
/// suite exists to catch (the core half makes the distinction for a reason).
@MainActor
final class SettingsServerAheadUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase"] + arguments
        app.launch()
        return app
    }

    private func launchSettings(seed: String) -> XCUIApplication {
        launch(["-presentScreen", "settings", seed])
    }

    private func launchSettingsRU(seed: String) -> XCUIApplication {
        launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                "-presentScreen", "settings", seed])
    }

    /// The notice element for each of the four seeds: quiet (`settingsSyncNotice`)
    /// for `.rateLimited`, attention (`settingsSyncNoticeAttention`) otherwise.
    private func noticeElement(for seed: String, in app: XCUIApplication) -> XCUIElement {
        seed == "-seedSettingsRateLimited"
            ? app.staticTexts["settingsSyncNotice"]
            : app.staticTexts["settingsSyncNoticeAttention"]
    }

    /// The four server-ahead seeds, in the order the core half classifies them.
    private let seeds = ["-seedSettingsUpgradeRequired", "-seedSettingsTierRefused",
                         "-seedSettingsRefused", "-seedSettingsRateLimited"]

    // MARK: - Each of the four outcomes renders its own distinct message

    func testUpgradeRequiredRendersItsOwnMessage() {
        let app = launchSettings(seed: "-seedSettingsUpgradeRequired")
        let element = noticeElement(for: "-seedSettingsUpgradeRequired", in: app)
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        XCTAssertEqual(element.label,
                       "This needs a newer version of Tankbook – update to sync")
    }

    func testTierRefusedRendersItsOwnMessage() {
        let app = launchSettings(seed: "-seedSettingsTierRefused")
        let element = noticeElement(for: "-seedSettingsTierRefused", in: app)
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        XCTAssertEqual(element.label,
                       "A newer version of Tankbook is needed for this account")
    }

    func testUnknownRefusedRendersItsOwnMessage() {
        let app = launchSettings(seed: "-seedSettingsRefused")
        let element = noticeElement(for: "-seedSettingsRefused", in: app)
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        XCTAssertEqual(element.label,
                       "Tankbook needs an update – the server has moved ahead")
    }

    func testRateLimitedRendersItsOwnMessage() {
        let app = launchSettings(seed: "-seedSettingsRateLimited")
        let element = noticeElement(for: "-seedSettingsRateLimited", in: app)
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        XCTAssertEqual(element.label, "Retrying in 2 minutes")
    }

    func testFourOutcomeMessagesArePairwiseDistinct() {
        var labels: [String] = []
        for seed in seeds {
            let app = launchSettings(seed: seed)
            let element = noticeElement(for: seed, in: app)
            XCTAssertTrue(element.waitForExistence(timeout: 10), "\(seed) renders its notice")
            labels.append(element.label)
        }
        XCTAssertEqual(Set(labels).count, labels.count,
                       "the four outcomes must not collapse into one message: \(labels)")
    }

    // MARK: - .rateLimited is a wait, not a failure

    func testRateLimitedHasNoUpdatePromptAndNoAttentionStyling() {
        let app = launchSettings(seed: "-seedSettingsRateLimited")
        let element = noticeElement(for: "-seedSettingsRateLimited", in: app)
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        XCTAssertEqual(element.label, "Retrying in 2 minutes")

        // No update prompt: the message reads as a wait, never "go update".
        for forbidden in ["update", "newer version", "refused", "failed", "error"] {
            XCTAssertFalse(element.label.lowercased().contains(forbidden),
                           ".rateLimited must not read as a failure: '\(forbidden)' in '\(element.label)'")
        }
        // No error styling: the quiet identifier, never the attention one.
        XCTAssertTrue(app.staticTexts["settingsSyncNotice"].exists)
        XCTAssertFalse(app.staticTexts["settingsSyncNoticeAttention"].exists,
                       ".rateLimited must carry no attention styling")
    }

    // MARK: - No upsell anywhere, EN and RU (hard rule 7)

    func testNoUpsellWordingInEnglish() {
        for seed in seeds {
            let app = launchSettings(seed: seed)
            let element = noticeElement(for: seed, in: app)
            XCTAssertTrue(element.waitForExistence(timeout: 10), "\(seed) renders its notice")
            for forbidden in ["pro", "tier", "price", "$", "upgrade"] {
                XCTAssertFalse(element.label.lowercased().contains(forbidden),
                               "\(seed) must not upsell: '\(forbidden)' in '\(element.label)'")
            }
        }
    }

    func testNoUpsellWordingInRussian() {
        for seed in seeds {
            let app = launchSettingsRU(seed: seed)
            let element = noticeElement(for: seed, in: app)
            XCTAssertTrue(element.waitForExistence(timeout: 10), "\(seed) renders its RU notice")
            let label = element.label
            for forbidden in ["Про", "цена", "тариф", "$", "подписк", "премиум"] {
                XCTAssertFalse(label.contains(forbidden),
                               "\(seed) must not upsell in RU: '\(forbidden)' in '\(label)'")
            }
        }
    }

    // MARK: - Never a modal (hard rule 8)

    func testNeverAModalForAnyOutcome() {
        for seed in seeds {
            let app = launchSettings(seed: seed)
            let element = noticeElement(for: seed, in: app)
            XCTAssertTrue(element.waitForExistence(timeout: 10), "\(seed) renders its notice")
            XCTAssertFalse(app.alerts.firstMatch.exists,
                           "\(seed) must present no alert")
            XCTAssertFalse(app.sheets.firstMatch.exists,
                           "\(seed) must present no sheet")
        }
    }

    // MARK: - The queue survives a refused push (S7)

    func testQueueSurvivesRefusedPush() {
        let app = launchSettings(seed: "-seedSettingsUpgradeRequired")
        let status = app.staticTexts["settingsSyncStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Waiting to sync · 5 changes",
                       "a refused push leaves the queue dirty - the count is unchanged")
    }

    // MARK: - RU renders the same states (the localization-blind-spot guard)

    func testUpgradeRequiredRendersInRussian() {
        let app = launchSettingsRU(seed: "-seedSettingsUpgradeRequired")
        let element = noticeElement(for: "-seedSettingsUpgradeRequired", in: app)
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        XCTAssertEqual(element.label, "Нужна новая версия Tankbook – обновите приложение")
    }

    func testRateLimitedRendersInRussian() {
        let app = launchSettingsRU(seed: "-seedSettingsRateLimited")
        let element = noticeElement(for: "-seedSettingsRateLimited", in: app)
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        XCTAssertEqual(element.label, "Повторная попытка через 2 минуты")
    }
}
