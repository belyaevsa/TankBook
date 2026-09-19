import XCTest

/// RV.119 - the Log's month divider carries the month, not just its spend.
/// The seed pins two complete past months, so last month's divider reads its
/// distance, consumption and cost per km and compares itself with the month
/// before - as whole localised phrases in EN and RU. The values are asserted,
/// not the lines' existence.
@MainActor
final class MonthGlanceUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(russian: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn", "-seedHomeMonthGlance"]
            + (russian ? ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"] : [])
        app.launch()
        return app
    }

    /// The month before last, in the case the delta sentence uses.
    private func monthBeforeLast(locale: Locale) -> String {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .month, value: -2, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter.string(from: date)
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var swipes = 0
        while !element.exists, swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
    }

    func testLastMonthsDividerReadsItsFactsAndItsDelta() {
        let app = launch(russian: false)
        let glance = app.staticTexts["logMonthGlance"].firstMatch
        scrollTo(glance, in: app)
        XCTAssertTrue(glance.waitForExistence(timeout: 10), "last month's divider carries its glance")
        XCTAssertEqual(glance.label, "800 km · 6.7 L/100km · 0.19 €/km")
        let delta = app.staticTexts["logMonthDelta"].firstMatch
        XCTAssertTrue(delta.exists)
        XCTAssertEqual(delta.label, "25% lower than \(monthBeforeLast(locale: Locale(identifier: "en_US")))")
    }

    func testTheDividerPhrasesAreWholeRussianPhrases() {
        let app = launch(russian: true)
        let glance = app.staticTexts["logMonthGlance"].firstMatch
        scrollTo(glance, in: app)
        XCTAssertTrue(glance.waitForExistence(timeout: 10))
        XCTAssertEqual(glance.label, "800 км · 6.7 л/100 км · 0.19 €/км")
        let delta = app.staticTexts["logMonthDelta"].firstMatch
        XCTAssertEqual(delta.label, "на 25% ниже уровня \(monthBeforeLast(locale: Locale(identifier: "ru_RU")))")
    }
}
