import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// A discount label pairs with its own signed value, never the unsigned unit
/// price that shares its baseline. Geometry is receipt-066's real
/// `--dump-text` split (the RV.282 block): `EXTRA SOODUS` at midY 0.6304
/// shares a baseline with the price `2,024` (0.6315) while `-0,96 EUR` sits
/// 0.0156 below.
@Suite("RV.283 the discount label pairs with its signed value")
struct RV283DiscountPairingTests {
    private func line(_ text: String, midX: CGFloat, midY: CGFloat) -> OCRLine {
        OCRLine(text: text, boundingBox: CGRect(x: midX - 0.05, y: midY - 0.01, width: 0.1, height: 0.02))
    }

    @Test("receipt-066's split block: the discount is 0.96, not the price 2.02")
    func splitBlockPairsTheSignedValue() {
        let lines = [
            line("4 Hind", midX: 0.3711, midY: 0.6395),
            line("2,024", midX: 0.4826, midY: 0.6315),
            line("EXTRA SOODUS", midX: 0.2676, midY: 0.6304),
            line("EUR/L", midX: 0.5610, midY: 0.6286),
            line("-0,96 EUR", midX: 0.5465, midY: 0.6148),
            line("KOKKU", midX: 0.2548, midY: 0.6055)
        ]
        #expect(ExtractionCrossCheck.discountLines(in: lines) == [Decimal(string: "0.96")!])
    }

    @Test("a receipt-038-shaped line carrying its own value is unchanged")
    func inlineDiscountUnchanged() {
        let lines = [line("EXTRA SOODUS -0,23 EUR", midX: 0.3, midY: 0.6)]
        #expect(ExtractionCrossCheck.discountLines(in: lines) == [Decimal(string: "0.23")!])
    }

    @Test("with no signed value, the unsigned one on the label's baseline is the discount")
    func unsignedBaselineValueIsTheFallback() {
        let lines = [line("Discount", midX: 0.3, midY: 0.6), line("2.39", midX: 0.7, midY: 0.6)]
        #expect(ExtractionCrossCheck.discountLines(in: lines) == [Decimal(string: "2.39")!])
    }
}
