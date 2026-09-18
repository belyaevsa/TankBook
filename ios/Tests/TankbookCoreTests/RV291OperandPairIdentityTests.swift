import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

// RV.291 - a fuel-only slip declared mixed by its own fuel line. On
// receipt-069 (an RN-Tver PetrolPlus order slip, Telegram-routed and shot
// sideways) Vision read the operand pair as `63.30 X 30.000` for a printed
// `68.30`, and `OperandPair.fuelOperandIndex` could not place the pair (no
// volume marker, the product line not directly above it). The ladder still
// read litres 30 and price 63.30 from that line - and `nonFuelListSum` then
// counted the SAME line as a shop item, so `resolveTotal` took the
// mixed-receipt branch and returned the pair's product, 1899, over a
// `2 049.00` the paper prints twice. A misread digit multiplied through and
// committed as the total is exactly the confident-wrong value hard rule 13
// forbids. The lines below are quoted as Vision read them.

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

private func line(_ text: String, midX: CGFloat, midY: CGFloat) -> OCRLine {
    OCRLine(text: text, boundingBox: CGRect(x: midX - 0.05, y: midY - 0.01,
                                            width: 0.1, height: 0.02))
}

/// A line as Vision emitted it: text, its bounding box as `[x, y, width, height]` and confidence.
private func box(_ text: String, _ rect: [CGFloat], confidence: Float) -> OCRLine {
    OCRLine(text: text, confidence: confidence,
            boundingBox: CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3]))
}

@Suite("RV.291: the resolved operand pair is never counted as a non-fuel item")
struct RV291OperandPairIdentityTests {

    /// Vision's read of the fixture, every line and its box, quoted verbatim
    /// (the slip lies sideways in a landscape frame, so the boxes are tall and
    /// narrow). A trimmed subset passed on the mutant: `fuelOperandIndex` places
    /// the pair once the card line between it and the product line is gone.
    private static let receipt069: [OCRLine] = [
        box("6905035353", [0.5255, 0.8255, 0.0325, 0.1387], confidence: 1.00),
        box("00106307487478", [0.5769, 0.7738, 0.0310, 0.1918], confidence: 1.00),
        box("16.09.26 21:27", [0.5003, 0.7693, 0.0375, 0.1950], confidence: 1.00),
        box("2 049.00", [0.3406, 0.8021, 0.0250, 0.1104], confidence: 1.00),
        box("7380440902649583", [0.6004, 0.7468, 0.0362, 0.2192], confidence: 1.00),
        box("0000131898015309", [0.5515, 0.7466, 0.0330, 0.2190], confidence: 1.00),
        box("\"РН-ТВЕРЬ\" АЗК 15", [0.2375, 0.4250, 0.0188, 0.2083], confidence: 1.00),
        box("AO", [0.2422, 0.3917, 0.0141, 0.0312], confidence: 1.00),
        box("нефискальный отчет жики", [0.2893, 0.2137, 0.0288, 0.2913], confidence: 1.00),
        box("ЗАКАЗА N: 10065845", [0.3100, 0.2388, 0.0270, 0.2349], confidence: 1.00),
        box("кБО топливная карта РН-Кар 2 049.00", [0.4424, 0.1074, 0.0384, 0.4665], confidence: 1.00),
        box("нЖжиЖЖ НеФИСКаЛЬНЫЙ ОтЧЕт миВка", [0.4927, 0.1095, 0.0402, 0.4293], confidence: 0.30),
        box("2 049.00", [0.4260, 0.2489, 0.0297, 0.1149], confidence: 1.00),
        box("63.30 X 30.000", [0.3966, 0.2070, 0.0367, 0.1947], confidence: 1.00),
        box("1 карти: 7013330012055589222", [0.4685, 0.1010, 0.0393, 0.3838], confidence: 1.00),
        box("NИ-95-K5 N 1:00000", [0.3326, 0.1032, 0.0310, 0.2435], confidence: 1.00),
        box("Іата ВРеМЯ", [0.5324, 0.1121, 0.0233, 0.1343], confidence: 1.00),
        box("KKT", [0.6062, 0.1542, 0.0250, 0.0438], confidence: 1.00),
        box("КВИТАНЦИЯ", [0.3182, 0.1098, 0.0216, 0.1279], confidence: 1.00),
        box("КKT", [0.5812, 0.1500, 0.0234, 0.0458], confidence: 1.00),
        box(":*8*****", [0.2984, 0.1146, 0.0141, 0.1042], confidence: 1.00),
        box("14-95-K5", [0.3806, 0.1007, 0.0301, 0.1174], confidence: 0.30),
        box("МТОГ", [0.4328, 0.1042, 0.0234, 0.0604], confidence: 1.00),
        box("14HH", [0.5562, 0.1063, 0.0250, 0.0479], confidence: 0.30),
        box("ІУБ", [0.4109, 0.1063, 0.0219, 0.0438], confidence: 1.00)
    ]

    @Test("receipt-069: the printed, repeated total outranks a misread pair's product")
    func receipt069PrintedTotalOutranksTheMisreadProduct() throws {
        let pack = try FuelPriceBandStore.bundledPack()
        let extractor = FuelExtractor(bandProvider: DefaultFuelPriceBandProvider(pack: pack))
        let result = extractor.extract(lines: Self.receipt069, source: .receipt)
        // Either the printed `2 049.00` or an abstention is acceptable under
        // hard rule 13; the product of a misread operand never is.
        #expect(result.total == nil || result.total == decimal("2049.00"),
                "total must not be the misread product: \(String(describing: result.total))")
        #expect(result.total != decimal("1899.00"))
    }

    @Test("the resolved pair is excluded from the non-fuel sum in either operand order")
    func resolvedPairIsExcludedInEitherOrder() {
        let lines = [
            line("63.30 X 30.000", midX: 0.415, midY: 0.304),
            line("2 049.00", midX: 0.441, midY: 0.306)
        ]
        #expect(ExtractionCrossCheck.nonFuelListSum(in: lines) > 0,
                "without the identity the unplaced pair counts as a shop item - the bug's precondition")
        #expect(ExtractionCrossCheck.nonFuelListSum(
            in: lines, resolvedOperands: (liters: 30.0, unitPrice: 63.3)) == 0)
        #expect(ExtractionCrossCheck.nonFuelListSum(
            in: lines, resolvedOperands: (liters: 63.3, unitPrice: 30.0)) == 0)
    }

    @Test("a genuine shop item beside the fuel pair still counts")
    func aRealShopItemStillCounts() {
        let lines = [
            line("63.30 X 30.000", midX: 0.415, midY: 0.304),
            line("2 т. X 129.00", midX: 0.415, midY: 0.280)
        ]
        let sum = ExtractionCrossCheck.nonFuelListSum(
            in: lines, resolvedOperands: (liters: 30.0, unitPrice: 63.3))
        #expect(sum == decimal("258.00"))
    }
}
