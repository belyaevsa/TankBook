import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

// RV.282 - receipt-066 (Circle K Jarvevana) committed the `EXTRA SOODUS -0,96
// EUR` discount as the unit price. Vision splits the fuel block into one-token
// lines; the bare `EUR/L` label's pump form took the subtraction line below it,
// and `NumberScanner.value` drops the sign by design. The real price `2,024`
// sits ABOVE the label, which the pump form excludes by construction.
//
// Oracle: the paper prints `Hind 2,024 EUR/L` and the paired pump-100 shows
// `2.024`; `64.04 x 2.024 = 129.62` closes exactly, while `64.04 x 0.96` does
// not. The geometry below is the real `--dump-text` geometry of the fixture.

private func line(_ text: String, midX: CGFloat, midY: CGFloat) -> OCRLine {
    OCRLine(text: text, boundingBox: CGRect(x: midX - 0.05, y: midY - 0.01,
                                            width: 0.1, height: 0.02))
}

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

@Suite("RV.282: a discount line is never the unit price (receipt-066)")
struct RV282DiscountLineUnitPriceTests {

    /// The six-line fuel block exactly as Vision splits it, with the receipt's
    /// real geometry: `2,024` is above the `EUR/L` label, `-0,96 EUR` below it.
    private var fuelBlock: [OCRLine] {
        [
            line("4 Hind", midX: 0.3711, midY: 0.6395),
            line("2,024", midX: 0.4826, midY: 0.6315),
            line("EXTRA SOODUS", midX: 0.2676, midY: 0.6304),
            line("EUR/L", midX: 0.5610, midY: 0.6286),
            line("-0,96 EUR", midX: 0.5465, midY: 0.6148),
            line("KOKKU", midX: 0.2548, midY: 0.6055)
        ]
    }

    @Test("the pump form skips the discount line below the label")
    func pumpFormSkipsTheDiscountLine() throws {
        let extractor = FuelExtractor()
        let lines = fuelBlock
        let labelIndex = try #require(lines.firstIndex { $0.text == "EUR/L" })
        // Fails today: `-0,96 EUR` sits below the label and its sign is dropped,
        // so this returned 0.96.
        #expect(extractor.pricePerUnitValue(forLabelAt: labelIndex, in: lines) == nil)
    }

    @Test("the printed 2,024 the arithmetic confirms becomes the unit price")
    func derivedPrintedPriceIsTheUnitPrice() {
        var lines = fuelBlock
        lines.insert(line("64,04L", midX: 0.4380, midY: 0.6504), at: 0)
        lines.append(line("129,62", midX: 0.6095, midY: 0.5821))
        lines.append(line("129,62 EUR", midX: 0.6269, midY: 0.5582))
        let result = FuelExtractor().extract(lines: lines)
        #expect(result.liters == 64.04)
        #expect(result.total == decimal("129.62"))
        #expect(result.unitPrice == decimal("2.024"))
    }

    @Test("a receipt-038-shaped inline line still returns 1.754")
    func inlinePriceStillResolves() throws {
        let extractor = FuelExtractor()
        let lines = [
            line("1,754 EUR/L", midX: 0.312, midY: 0.627),
            line("45,22L", midX: 0.291, midY: 0.540)
        ]
        let labelIndex = try #require(lines.firstIndex { $0.text.contains("/L") })
        #expect(extractor.pricePerUnitValue(forLabelAt: labelIndex, in: lines) == 1.754)
    }

    @Test("a receipt-001-shaped pump form still returns the value below")
    func pumpFormStillResolves() throws {
        let extractor = FuelExtractor()
        let lines = [
            line("EUR/L", midX: 0.559, midY: 0.695),
            line("1,869", midX: 0.496, midY: 0.690)
        ]
        let labelIndex = try #require(lines.firstIndex { $0.text == "EUR/L" })
        #expect(extractor.pricePerUnitValue(forLabelAt: labelIndex, in: lines) == 1.869)
    }
}
