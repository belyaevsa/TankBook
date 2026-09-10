import XCTest

/// RV.188 - the timeline neighbourhood panel must explain itself: it lists the
/// NEXT entry beside Previous and This, labels every chart point with its
/// odometer and date, and names the offending PAIR in the both-`.none` case
/// instead of gesturing at "the entries around this one". Split from
/// `EditEntryUITests` to keep each class inside the linter's body budget.
final class EditEntryNeighbourhoodUITests: XCTestCase {

    /// A flagged MIDDLE fill (both neighbours, two crossing pace bounds), opened
    /// via the `-editEntryFlagged` pose - the state no newest-entry tap can
    /// reach.
    private func launchOnMiddleConflict() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedEditEntryConflictMiddle",
                               "-editEntryFlagged", "-presentScreen", "editEntry"]
        app.launch()
        return app
    }

    /// The existing order-conflict seed: the flagged entry is the NEWEST, so it
    /// has no next neighbour.
    private func launchOnNewestConflict() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedEditEntryConflict",
                               "-presentScreen", "editEntry"]
        app.launch()
        return app
    }

    /// The exact grouped form the app renders (no-break-space thousands
    /// separators, `OdometerFormat`).
    private func grouped(_ value: Int) -> String {
        let digits = String(value)
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0 && (digits.count - index).isMultiple(of: 3) {
                result += "\u{00A0}"
            }
            result.append(character)
        }
        return result
    }

    @discardableResult
    private func revealCard(_ app: XCUIApplication) -> XCUIElement {
        let card = app.descendants(matching: .any)
            .matching(identifier: "timelineNeighbourhoodCard").firstMatch
        var swipes = 0
        while !card.exists && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(card.waitForExistence(timeout: 10),
                      "the neighbourhood card must render (swipes=\(swipes))")
        return card
    }

    /// RV.188 item 1: the next entry is listed with its odometer - the panel no
    /// longer stops at "This entry".
    func testNeighbourhoodListsTheNextEntryWhenOneExists() {
        let app = launchOnMiddleConflict()
        revealCard(app)
        let nextRow = app.staticTexts["Next entry"]
        XCTAssertTrue(nextRow.waitForExistence(timeout: 10),
                      "the next entry row must render when a next neighbour exists")
        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", grouped(101_500))).firstMatch.exists,
            "the next entry's odometer must be on screen")
    }

    /// RV.188 item 2: every chart point carries its odometer and date, so the
    /// anonymous dot that caused the dead end is named.
    func testNeighbourhoodChartPointsCarryOdometerAndDate() {
        let app = launchOnMiddleConflict()
        revealCard(app)
        let labels = app.staticTexts
            .matching(identifier: "neighbourhoodChartOdometerLabel")
        XCTAssertTrue(labels.firstMatch.waitForExistence(timeout: 10),
                      "the chart must label its points with an odometer")
        XCTAssertGreaterThanOrEqual(labels.count, 3,
                                    "all three plotted points must carry an odometer label")
        XCTAssertTrue(labels.containing(
            NSPredicate(format: "label CONTAINS %@", grouped(100_900))).firstMatch.exists,
            "the offending point's reading must be on the chart")
        XCTAssertTrue(app.staticTexts
            .matching(identifier: "neighbourhoodChartDateLabel").firstMatch.exists,
            "the chart points must also carry a date")
    }

    /// The both-`.none` case says nothing in prose: the chart and the three
    /// bracket rows carry the reading and its neighbours, and the row's banner
    /// above carries the next step. Two amber paragraphs restating the same
    /// numbers in words were the panel's bulk and none of its meaning (product
    /// owner, 2026-09-10). Asserted as an ABSENCE so re-adding them is a
    /// deliberate decision, not a drift.
    func testTheInconsistentCaseRendersNoProseParagraph() {
        let app = launchOnMiddleConflict()
        revealCard(app)
        XCTAssertTrue(app.otherElements["neighbourhoodChart"].waitForExistence(timeout: 10),
                      "the chart and its bracket rows are the explanation")
        XCTAssertEqual(app.staticTexts.matching(
            identifier: "neighbourhoodCulpritStatement").count, 0)
        XCTAssertEqual(app.staticTexts.matching(
            identifier: "neighbourhoodInconsistentStatement").count, 0)
        // The numbers are still on screen - in the rows, where they belong.
        XCTAssertTrue(app.staticTexts["This entry"].exists)
        XCTAssertTrue(app.staticTexts["Previous entry"].exists)
    }

    /// RV.188 item 4: a flagged newest entry has no next, and the panel renders
    /// with no blank "Next entry" row.
    func testNeighbourhoodWithNoNextEntryHasNoBlankRow() {
        let app = launchOnNewestConflict()
        revealCard(app)
        XCTAssertFalse(app.staticTexts["Next entry"].exists,
                       "no next neighbour means no next row, not a blank one")
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "neighbourhoodOffendingPoint").firstMatch.exists,
            "the panel still renders")
    }
}
