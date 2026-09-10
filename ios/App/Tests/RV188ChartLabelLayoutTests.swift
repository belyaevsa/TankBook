import TankbookCore
import XCTest
@testable import Tankbook

/// RV.188 chart labels: three points, three readable labels.
///
/// The first version placed a label above or below its point by the point's
/// **index**, which put the offending point's label on top of its neighbour's
/// mark and the neighbour's label on top of that - two labels printed over each
/// other at one corner, and one of three points effectively unlabelled. Nothing
/// caught it: a UI test can find `neighbourhoodChartOdometerLabel` while it sits
/// underneath another one, and only opening the screenshot showed it. These
/// tests are the check that was missing.
final class RV188ChartLabelLayoutTests: XCTestCase {

    private let size = CGSize(width: 300, height: 160)

    /// The owner's own shape: a long gap, then two entries a day apart, so the
    /// last two points nearly share an x. This is the geometry that collided.
    private func layout(offendingIndex: Int = 1) -> TimelineNeighbourhoodChartLayout {
        let start = Date(timeIntervalSince1970: 1_785_000_000)
        let odometers = [100_000, 100_900, 101_500]
        let days: [TimeInterval] = [0, 20, 21]
        let points = (0..<3).map { index in
            TimelineNeighbourhood.Point(
                id: UUID(),
                date: start.addingTimeInterval(days[index] * 86_400),
                odometer: odometers[index],
                isOffending: index == offendingIndex)
        }
        return TimelineNeighbourhoodChartLayout(points: points, size: size)
    }

    /// The headline: no two labels overlap.
    func testNoTwoLabelsOverlap() {
        let frames = Array(layout().labelFrames(in: size).values)
        XCTAssertEqual(frames.count, 3, "every point must be labelled")
        for (i, a) in frames.enumerated() {
            for b in frames[(i + 1)...] {
                XCTAssertFalse(a.intersects(b),
                               "labels must not print on top of each other: \(a) vs \(b)")
            }
        }
    }

    /// Every label stays inside the chart, so none is clipped at an edge - the
    /// rightmost point is the one that used to run off.
    func testEveryLabelStaysInsideTheChart() {
        for frame in layout().labelFrames(in: size).values {
            XCTAssertGreaterThanOrEqual(frame.minX, -0.01, "label runs off the left edge")
            XCTAssertLessThanOrEqual(frame.maxX, size.width + 0.01, "label runs off the right edge")
            XCTAssertGreaterThanOrEqual(frame.minY, -0.01, "label runs off the top")
            XCTAssertLessThanOrEqual(frame.maxY, size.height + 0.01, "label runs off the bottom")
        }
    }

    /// A label never covers ANOTHER point's mark: that is the specific failure
    /// the screenshots showed, and it is not the same assertion as "labels do
    /// not overlap each other".
    func testNoLabelCoversAnotherPointsMark() {
        let chart = layout()
        let frames = chart.labelFrames(in: size)
        for mark in chart.allPoints {
            let markBox = CGRect(x: mark.position.x - 5, y: mark.position.y - 5,
                                 width: 10, height: 10)
            for other in chart.allPoints where other.id != mark.id {
                guard let frame = frames[other.id] else { return XCTFail("unplaced label") }
                XCTAssertFalse(frame.intersects(markBox),
                               "a label must not sit on another point's mark")
            }
        }
    }

    /// Which point is offending changes its colour, never its geometry - the
    /// placement must not depend on it.
    func testPlacementDoesNotDependOnWhichPointIsOffending() {
        let byPosition = { (chart: TimelineNeighbourhoodChartLayout) -> [CGRect] in
            let frames = chart.labelFrames(in: self.size)
            return chart.allPoints.compactMap { frames[$0.id] }
        }
        XCTAssertEqual(byPosition(layout(offendingIndex: 0)), byPosition(layout(offendingIndex: 2)))
    }
}
