import XCTest
import TankbookCore
@testable import Tankbook

/// How the pump reader's fields and the rules arm's are composed for Confirm.
/// The reader wins where it committed; the rules arm fills a field the reader
/// abstained on - except a cautioned pair's price, which stays for the user.
final class CapturePipelineCompositionTests: XCTestCase {
    private let rules = FuelExtraction(liters: 30.0, unitPrice: Decimal(string: "1.919"),
                                       total: Decimal(string: "57.57"))
    private let pair = FuelExtraction(liters: 30.21, unitPrice: nil, total: Decimal(string: "55.56"))

    func testADiscountedPairKeepsTheBoardPriceOut() {
        let caution = PumpReadingCaution.shownPriceDiffers(shown: Decimal(string: "1.919")!,
                                                           implied: Decimal(string: "1.839")!)
        let out = CapturePipeline.composed(rules: rules, reader: pair, caution: caution)
        XCTAssertEqual(out.liters, 30.21)
        XCTAssertEqual(out.total, Decimal(string: "55.56"))
        XCTAssertNil(out.unitPrice, "the board price the law refused to take as paid must not come back")
    }

    func testAnOrdinaryReadingStillFallsThroughToTheRulesArm() {
        let out = CapturePipeline.composed(rules: rules, reader: pair, caution: nil)
        XCTAssertEqual(out.unitPrice, Decimal(string: "1.919"))
        XCTAssertEqual(out.liters, 30.21, "the reader's committed field wins")
    }
}
