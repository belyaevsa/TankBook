import TankbookCore
import XCTest
@testable import Tankbook

/// RV.276 coincident chart labels: two points at one stop are labelled once.
///
/// The old layout placed a label per point. Two coincident points (same date,
/// same reading) got the same side and, clamped against the same edge, printed
/// their labels over each other - the product owner saw `401 544 km` drawn over
/// itself. The fix groups points by plotted position and draws one block.
final class RV276CoincidentLabelTests: XCTestCase {

    private let size = CGSize(width: 300, height: 160)
    private let start = Date(timeIntervalSince1970: 1_785_000_000)

    /// The reported shape: a same-stop pair at 401 544 km plus the genuinely
    /// falling entry the card is open on. The pair sits at the top edge, where
    /// the old clamp collapsed their two labels onto one another.
    private func layout() -> TimelineNeighbourhoodChartLayout {
        let points = [
            TimelineNeighbourhood.Point(id: UUID(), date: start, odometer: 401_544,
                                        isOffending: false),
            TimelineNeighbourhood.Point(id: UUID(),
                                        date: start.addingTimeInterval(120),
                                        odometer: 401_544, isOffending: false),
            TimelineNeighbourhood.Point(id: UUID(),
                                        date: start.addingTimeInterval(11 * 86_400),
                                        odometer: 401_000, isOffending: true)
        ]
        return TimelineNeighbourhoodChartLayout(points: points, size: size)
    }

    /// The two same-reading points are one group, labelled once.
    func testCoincidentPointsShareOneLabelGroup() {
        let groups = layout().labelGroups()
        XCTAssertEqual(groups.count, 2, "the pair is one group plus the offending point")
        let pair = groups.first { $0.marks.count == 2 }
        XCTAssertNotNil(pair, "the two coincident points must be grouped")
        XCTAssertEqual(pair?.labels.count, 1,
                       "an identical reading must not be repeated in the block")
    }

    /// Both coincident points resolve to the SAME frame - one block, not two.
    func testCoincidentPointsShareOneFrame() {
        let chart = layout()
        let frames = chart.labelFrames(in: size)
        let pair = chart.allPoints.filter { $0.odometer == 401_544 }
        XCTAssertEqual(pair.count, 2, "the fixture must carry the pair")
        XCTAssertEqual(frames[pair[0].id], frames[pair[1].id],
                       "coincident points must share one label frame")
    }

    /// Two readings on one calendar day share an x, so they stack into one
    /// block - the reported `401 778 km` over `401 544 km` shape.
    func testSameDayDifferentReadingsStackIntoOneBlock() {
        let points = [
            TimelineNeighbourhood.Point(id: UUID(), date: start, odometer: 401_544,
                                        isOffending: true),
            TimelineNeighbourhood.Point(id: UUID(),
                                        date: start.addingTimeInterval(3_600),
                                        odometer: 401_778, isOffending: false)
        ]
        let layout = TimelineNeighbourhoodChartLayout(points: points, size: size)
        XCTAssertEqual(layout.labelGroups().count, 1,
                       "points on one day share an x and one block")
        XCTAssertEqual(layout.labelGroups().first?.labels.count, 2,
                       "different readings stack as two labels")
    }

    /// The stacked block does not print over the offending point's label, and
    /// every distinct block stays inside the chart.
    func testCoincidentBlockIsLegible() {
        let frames = Array(layout().labelFrames(in: size).values)
        let distinct = Array(Set(frames))
        for (index, frame) in distinct.enumerated() {
            for other in distinct[(index + 1)...] {
                XCTAssertFalse(frame.intersects(other),
                               "labels must not print on top of each other")
            }
            XCTAssertGreaterThanOrEqual(frame.minX, -0.01)
            XCTAssertLessThanOrEqual(frame.maxX, size.width + 0.01)
            XCTAssertGreaterThanOrEqual(frame.minY, -0.01)
            XCTAssertLessThanOrEqual(frame.maxY, size.height + 0.01)
        }
    }
}
