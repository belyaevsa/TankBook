import XCTest

/// RV.131: the S2 combined duplicate card shows the pair it asks the user to
/// decide on. The old card rendered one sentence derived from the counted
/// member only, so the excluded entry was invisible and unreachable while the
/// card stood; these tests pin the two halves of the fix - both entries are
/// named with the fields that DIFFER, and each member opens its own editor.
///
/// The seed (`-seedHomeDuplicateFields`) deliberately produces a pair whose
/// members differ in odometer and total (122 800 / 71.02 € vs 122 950 /
/// 72.05 €), because a pair whose members were identical could not show the
/// defect this row exists to fix. The newer fill carries the receipt, so it is
/// the Merge survivor and the paperclip's meaning (docs/SYNC.md) is on screen.
@MainActor
final class HomeDuplicateCardUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Every launch sets the language explicitly (EN by default): `-AppleLanguages`
    /// writes to the app's UserDefaults and survives across launches, so a test
    /// that launches RU would otherwise leave the whole suite running in Russian.
    func launch(args: [String],
                language: [String] = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsSignedIn"] + language + args
        app.launch()
        return app
    }

    /// The card names BOTH entries and shows the fields that DIFFER - a pair
    /// whose members were identical could not see this defect (the card once
    /// rendered one sentence derived from the counted member only).
    func testDuplicateCardNamesBothEntriesWithTheirDifferences() {
        let app = launch(args: ["-seedHomeDuplicateFields"])

        let card = anyElement(app, "homeDuplicateCard")
        XCTAssertTrue(card.waitForExistence(timeout: 10))

        // Both members render as their own reachable rows.
        XCTAssertEqual(app.buttons.matching(identifier: "homeDuplicateMemberButton").count, 2,
                       "both members of the pair must be present as rows")

        // Both totals are present (the amounts differ: 71.02 vs 72.05).
        let amounts = app.staticTexts.matching(identifier: "homeDuplicateAmount")
        XCTAssertEqual(amounts.count, 2, "each member row must carry its own total")
        let labels = amounts.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(labels.contains { $0.contains("71.02") },
                      "the first member's total must render, got \(labels)")
        XCTAssertTrue(labels.contains { $0.contains("72.05") },
                      "the second member's total must render, got \(labels)")

        // Both odometers are present (122 800 vs 122 950), via the rows' own
        // exposed elements rather than the garage card's odometer.
        let odometers = app.staticTexts.matching(identifier: "homeDuplicateOdometer")
        XCTAssertEqual(odometers.count, 2, "each member row must carry its own odometer")
        let odometerLabels = odometers.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(odometerLabels.contains { $0.hasPrefix("122\u{00A0}800") },
                      "the first member's odometer must render, got \(odometerLabels)")
        XCTAssertTrue(odometerLabels.contains { $0.hasPrefix("122\u{00A0}950") },
                      "the second member's odometer must render, got \(odometerLabels)")
    }

    /// Each member opens its OWN editor from the card - the pair must never be
    /// less reachable than the two ordinary rows it replaced. The distinguishing
    /// field is the total: one editor reads 71.02, the other 72.05.
    func testEachDuplicateMemberOpensItsOwnEditor() {
        let app = launch(args: ["-seedHomeDuplicateFields"])

        XCTAssertTrue(anyElement(app, "homeDuplicateCard").waitForExistence(timeout: 10))

        var seen: Set<String> = []
        for index in 0..<2 {
            let rows = app.buttons.matching(identifier: "homeDuplicateMemberButton")
            XCTAssertEqual(rows.count, 2,
                           "both member rows must be present before opening row \(index)")
            let row = rows.element(boundBy: index)
            XCTAssertTrue(row.isHittable, "member row \(index) must be reachable")
            row.tap()

            let total = app.textFields["manualFillUpTotalField"]
            XCTAssertTrue(total.waitForExistence(timeout: 5),
                          "member row \(index) must open its editor")
            seen.insert((total.value as? String) ?? "")

            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(anyElement(app, "homeDuplicateCard").waitForExistence(timeout: 5),
                          "back must return to the card so the other member is reachable")
        }
        XCTAssertEqual(seen, ["71.02", "72.05"],
                       "each member must open ITS OWN editor, got \(seen)")
    }

    /// Russian is 20-30% longer and short strings expand worst; both entries
    /// and both actions must still be on screen. Geometry, not text: the two
    /// member rows must each be hittable and fully inside the window, or the RU
    /// pass has pushed the pair below the fold.
    func testDuplicateCardShowsBothEntriesInRussian() {
        let app = launch(args: ["-seedHomeDuplicateFields"],
                         language: ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"])

        let card = anyElement(app, "homeDuplicateCard")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(textContaining(app, "внесены дважды").exists,
                      "the RU duplicate header must render")

        let rows = app.buttons.matching(identifier: "homeDuplicateMemberButton")
        XCTAssertEqual(rows.count, 2, "both members must be present in RU")
        let window = app.windows.firstMatch.frame
        for (index, row) in rows.allElementsBoundByIndex.enumerated() {
            XCTAssertTrue(row.isHittable,
                          "member row \(index) must be on screen in RU")
            XCTAssertGreaterThanOrEqual(row.frame.minY, window.minY - 1,
                                        "member row \(index) must start inside the window")
            XCTAssertLessThanOrEqual(row.frame.maxY, window.maxY + 1,
                                     "member row \(index) must end inside the window")
        }

        let amounts = app.staticTexts.matching(identifier: "homeDuplicateAmount")
        XCTAssertEqual(amounts.count, 2, "both totals must render in RU")
        let labels = amounts.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(labels.contains { $0.contains("71.02") },
                      "the first member's total must render in RU, got \(labels)")
        XCTAssertTrue(labels.contains { $0.contains("72.05") },
                      "the second member's total must render in RU, got \(labels)")

        // Restore the app's persisted language: `-AppleLanguages` writes to
        // UserDefaults, which survives launches, so the tests running after
        // this RU launch must not inherit Russian.
        app.terminate()
        let reset = XCUIApplication()
        reset.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        reset.launch()
        reset.terminate()
    }

    private func textContaining(_ app: XCUIApplication, _ substring: String) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", substring)).firstMatch
    }

    private func anyElement(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
