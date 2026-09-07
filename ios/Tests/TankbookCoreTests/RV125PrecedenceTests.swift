import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

// RV.125 - the precedence between a printed total and a derived product,
// stated as a rule and asserted directly rather than inferred from one image.
//
// The rule (docs/EXTRACTION.md -> "Printed total vs derived product"): a total
// the receipt PRINTS outranks a product derived from two OCR'd operands. The
// derived product is used in exactly two places - when no total is printed at
// all (the rescue path), and on a mixed receipt where a genuine non-fuel line
// makes the printed total the GRAND total rather than the fuel amount (hard
// rule 4). A product that agrees with itself is not evidence: both factors come
// from one line, so a single misread digit propagates into both and the
// cross-check confirms the wrong number instead of catching it.

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

/// An OCR line centred at the given midX/midY - the two coordinates the total
/// finder's label/value pairing reads.
private func line(_ text: String, midX: CGFloat, midY: CGFloat) -> OCRLine {
    OCRLine(text: text, boundingBox: CGRect(x: midX - 0.05, y: midY - 0.01,
                                            width: 0.1, height: 0.02))
}

@Suite("RV.125: a printed total outranks a derived product")
struct RV125PrecedenceTests {

    // The rule, stated directly: a printed total beats a product built from an
    // operand line that contradicts it, when there is no non-fuel line to make
    // the receipt mixed. `20.31 X 32.000` derives 649.92; the receipt prints
    // `=2249.92` twice. Without the rule the derived product wins (the exact
    // receipt-052 defect); with it the printed total wins.
    @Test("a printed total outranks the derived product when no non-fuel line exists")
    func printedTotalOutranksDerivedProduct() {
        let result = FuelExtractor().extract(textLines: [
            "Бензин G-Drive 95 (АИ-95-К5)",
            "20.31 X 32.000",
            "=2249.92",
            "=2249.92"
        ])
        #expect(result.total == decimal("2249.92"),
                "the printed total, not the derived 649.92, is the amount")
    }

    // The rescue path must survive: with no printed total at all, the amount
    // is the arithmetic fuel line. This is what a "printed always wins" rule
    // would delete.
    @Test("a receipt with no printed total still resolves from the product")
    func absentTotalResolvesFromTheProduct() {
        let result = FuelExtractor().extract(textLines: ["ДТ-Л-К5 ДИЗЕЛЬ", "42.30 л X 1.679"])
        #expect(result.liters == 42.30)
        #expect(result.unitPrice == decimal("1.679"))
        #expect(result.total == decimal("71.02"),
                "42.30 x 1.679 = 71.02 is the amount when no total is printed")
    }

    // Hard rule 4: on a mixed receipt the fuel amount is the fuel line, never
    // the grand total - even though a printed total exists. The fuel line is
    // UNMARKED (`43.38 Х 38.28`, no `л`), which is exactly the shape that used
    // to be miscounted as its own non-fuel item; the genuine service line is
    // what must separate the two, not the fuel line's own product.
    @Test("a mixed receipt keeps the fuel line against the printed grand total")
    func mixedReceiptKeepsTheFuelLine() {
        let result = FuelExtractor().extract(lines: [
            line("ТРК-2 АИ-95-К5", midX: 0.265, midY: 0.631),
            line("43.38 Х 38.28", midX: 0.257, midY: 0.604),
            line("Услуга по регистрации покупки", midX: 0.373, midY: 0.677),
            line("69.28 X 1", midX: 0.229, midY: 0.658),
            line("ИТОГ:", midX: 0.194, midY: 0.553),
            line("=1729.87 РУБ", midX: 0.664, midY: 0.552)
        ])
        #expect(result.total == decimal("1660.59"),
                "the fuel line (43.38 x 38.28) stands, not the grand total 1729.87")
        #expect(result.total != decimal("1729.87"))
    }
}
