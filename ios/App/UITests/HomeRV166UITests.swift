import XCTest

// MARK: - RV.166 a purchase group with a rate-pending member never prints a bare total

/// Kept as an extension of `HomeUITests` (its own file, so the base file stays
/// under the lint ceiling) - the tests run as part of the Home suite.
@MainActor
extension HomeUITests {

    /// The group header's partial state (RV.166): a receipt whose known members
    /// total 30.00 EUR beside one rate-pending line must show the known sum
    /// marked with the pending phrase - never `30.00 €` alone, which reads as
    /// the whole receipt while a line still waits (the defect: the header
    /// summed the pending member as zero and printed the bare total).
    func testRV166PartialGroupHeaderPrintsKnownSumMarkedPending() {
        let app = launch(args: ["-seedHomeRV166PartialGroup"])

        let toggle = app.buttons["logGroupToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10),
                      "the seeded receipt must render its group card")

        // The known sum is still printed - partial is printable (RV.106).
        let figure = app.staticTexts["logGroupGrandTotal"].firstMatch
        XCTAssertTrue(figure.exists, "the group must keep showing its known sum")
        XCTAssertTrue(figure.label.contains("30.00"),
                      "the header must state the two known members' sum, got \(figure.label)")

        // And it is marked partial: the pending phrase rides beneath it. A bare
        // figure with no mark is the defect this row fixes.
        let note = app.staticTexts["logGroupPendingRates"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5),
                      "a receipt with a rate-pending member must mark its figure partial")
        XCTAssertTrue(note.label.contains("pending rates"),
                      "the partial mark must carry the pending phrase, got \(note.label)")
    }
}
