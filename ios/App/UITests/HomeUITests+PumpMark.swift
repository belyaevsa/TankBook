import XCTest

/// The Log marks an entry read from a pump display.
extension HomeUITests {
    /// An entry read from a pump display carries the pump mark, with
    /// its spoken label, and a typed one does not.
    func testPumpReadEntryCarriesThePumpMark() {
        let app = launch(args: ["-seedHomePumpRead"])
        let marks = app.images.matching(identifier: "logEntryPumpReading")
        XCTAssertTrue(marks.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(marks.count, 1, "only the pump-read fill carries the mark")
        XCTAssertEqual(marks.firstMatch.label, "Read from the pump display")
    }
}
