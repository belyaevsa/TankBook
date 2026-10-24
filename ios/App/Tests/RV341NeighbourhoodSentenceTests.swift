import TankbookCore
import XCTest
@testable import Tankbook

/// RV.341 - the neighbourhood card's date sentence names a single day when the
/// valid window lies inside one, and ends with one full stop when the date
/// already ends in one (Russian "21 окт.").
@MainActor
final class RV341NeighbourhoodSentenceTests: XCTestCase {

    /// A window of hours inside one day reads as that day, not "between 21 Oct
    /// and 21 Oct".
    func testAWindowInsideOneDayNamesTheDay() throws {
        let morning = Date()
        let lower = Calendar.current.startOfDay(for: morning).addingTimeInterval(8 * 3_600)
        let upper = lower.addingTimeInterval(6 * 3_600)
        let text = try XCTUnwrap(TimelineNeighbourhoodSentences.dates(
            .bounded(lower: lower, upper: upper), odometerText: "62 230", unit: .km))
        let day = EntryDateText.dayMonth(lower)
        XCTAssertFalse(text.contains("between"), text)
        XCTAssertTrue(text.contains(day), text)
    }

    /// The sentence keeps exactly one closing full stop.
    func testADoubledFullStopCollapses() {
        XCTAssertEqual(TimelineNeighbourhoodSentences.sentence("дата должна быть 21 окт.."),
                       "дата должна быть 21 окт.")
        XCTAssertEqual(TimelineNeighbourhoodSentences.sentence("the date must be Oct 21."),
                       "the date must be Oct 21.")
        XCTAssertEqual(TimelineNeighbourhoodSentences.sentence("wait..."), "wait...")
    }
}
