import Foundation
import TankbookCore
import XCTest

final class OdometerStalenessTests: XCTestCase {
    func testBoundaryUsesStrictlyOlderThanThreshold() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let threshold = OdometerStaleness.threshold
        XCTAssertFalse(OdometerStaleness.isStale(lastReadingDate: now.addingTimeInterval(-threshold),
                                                 now: now))
        XCTAssertFalse(OdometerStaleness.isStale(lastReadingDate: now.addingTimeInterval(-threshold + 86_400),
                                                 now: now))
        XCTAssertTrue(OdometerStaleness.isStale(lastReadingDate: now.addingTimeInterval(-threshold - 86_400),
                                                now: now))
    }
}
