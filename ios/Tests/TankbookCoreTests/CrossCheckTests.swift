import Foundation
import Testing
@testable import TankbookCore

// P2.12 - the cross-check has four outcomes, not two
// (docs/EXTRACTION.md -> "Cross-check: four outcomes, not two"). These are the
// fast, deterministic L1 checks: the pure evaluator over constructed lines, and
// the extractor's fuel-line resolution (the L-vs-Gab. discriminator). The real
// OCR over the five Circle K screenshots and receipt-038 lives in
// `ScreenshotCrossCheckTests`.

private func dec(_ string: String) -> Decimal { Decimal(string: string)! }

private func evaluate(_ liters: Double, _ unitPrice: Double, _ total: Double,
                      _ lines: [String]) -> ExtractionCrossCheck {
    // The evaluator now takes exact Decimals for money (P2.2b); the test
    // convenience converts through the same ConfirmFormat boundary the
    // extraction uses, so these constructed triples exercise the same path.
    ExtractionCrossCheck.evaluate(
        liters: liters,
        unitPrice: ConfirmFormat.decimal(fromExtraction: unitPrice, fractionDigits: 3),
        total: ConfirmFormat.decimal(fromExtraction: total, fractionDigits: 2),
        lines: lines.map { OCRLine(text: $0) })
}

@Suite("Cross-check: four outcomes (P2.12)")
struct CrossCheckTests {

    // MARK: - lock and notApplicable

    @Test("a clean triple locks")
    func cleanTripleLocks() {
        #expect(evaluate(42.30, 1.679, 71.02, []) == .lock)
        // Exactly at the boundary still locks (diff == tolerance).
        #expect(evaluate(0.5, 2.00, 1.02, []) == .lock)
    }

    @Test("a missing number makes the check notApplicable")
    func missingNumberIsNotApplicable() {
        #expect(evaluate(42.30, 1.679, 71.02, []) != .notApplicable)
        #expect(evaluate(10, 2, 20, []) == .lock)
        #expect(ExtractionCrossCheck.evaluate(liters: nil, unitPrice: 2, total: 20, lines: []) == .notApplicable)
        #expect(ExtractionCrossCheck.evaluate(liters: 10, unitPrice: nil, total: 20, lines: []) == .notApplicable)
        #expect(ExtractionCrossCheck.evaluate(liters: 10, unitPrice: 2, total: nil, lines: []) == .notApplicable)
    }

    // MARK: - mismatch

    @Test("an unexplained residual with no discount line is a mismatch that carries its residual")
    func genuineMismatchCarriesResidual() {
        #expect(evaluate(10, 2, 25, []) == .mismatch(residual: dec("-5")))
        // The positive direction too.
        #expect(evaluate(10, 2, 15, []) == .mismatch(residual: dec("5")))
    }

    @Test("a discount line that does not explain the residual stays a mismatch")
    func discountLineThatDoesNotExplainStaysMismatch() {
        // 10 x 2 = 20, total 25: residual -5. A 1.01 discount line exists but
        // 20 - 25 is -5, and 20 != 25 + 1.01, so nothing reconciles. Without
        // this, an implementation that returns reconciled for any document with
        // a discount line passes every fixture.
        let outcome = evaluate(10, 2, 25, ["1.01 EUR", "Discount", "You saved 1.01 EUR"])
        #expect(outcome == .mismatch(residual: dec("-5")))
    }

    // MARK: - lock, not reconciled: receipt-038

    @Test("receipt-038: a printed discount that does not explain the total does not false-reconcile")
    func receipt038DiscountDoesNotExplain() {
        // receipt-038 prints `EXTRA SOODUS -0,23 EUR` beneath the item while
        // KOKKU still reads 79,32 - the discount is printed but NOT subtracted
        // from the total. Ground truth 45,22 L x 1,754 = 79,32 exactly: the
        // total already equals the product, so the outcome is a LOCK. A
        // residual-driven rule must not turn the mere existence of the -0,23
        // line into a reconciled.
        let lines = ["95E0 miles", "45,22L", "1,754 EUR/L",
                     "EXTRA SOODUS", "-0,23 EUR",
                     "KOKKU", "79,32"]
        let outcome = evaluate(45.22, 1.754, 79.32, lines)
        #expect(outcome == .lock, "got \(outcome)")
    }

    // MARK: - reconciled, residual-driven

    @Test("a residual equal to a printed discount line is reconciled, carrying both numbers")
    func residualEqualToDiscountIsReconciled() {
        // screenshot-004 shape: 67 x 1.884 = 126.23, total 125.22, printed
        // discount 1.01. The residual (1.01) is explained by the discount line.
        let outcome = evaluate(67, 1.884, 125.22,
                               ["125.22 EUR", "1.884 EUR x 67 L",
                                "1.01 EUR", "Discount", "You saved 1.01 EUR"])
        guard case .reconciled(let residual, let discountLine) = outcome else {
            Issue.record("expected reconciled, got \(outcome)")
            return
        }
        #expect(abs(residual - dec("1.01")) < dec("0.005"))
        #expect(abs(discountLine - dec("1.01")) < dec("0.005"))
    }

    @Test("a mixed receipt reconciles as a whole document: product + shop list == grand total + discount")
    func mixedReceiptReconcilesAsAWhole() {
        // screenshot-008: the fuel line 1.924 x 59.78 L is the third of eight
        // operand lines (Latvian `Gab.` items before and after it), charged
        // 112.63 against a 122.99 grand total and a 3.17 printed discount.
        // product 115.02 + shop list 11.14 == 122.99 + 3.17. The residual 2.39
        // is the fuel's share of the discount.
        let outcome = evaluate(59.78, 1.924, 112.63, Self.screenshot008Lines)
        guard case .reconciled(let residual, let discountLine) = outcome else {
            Issue.record("expected reconciled, got \(outcome)")
            return
        }
        #expect(abs(residual - dec("2.39")) < dec("0.005"))
        #expect(abs(discountLine - dec("3.17")) < dec("0.005"))
    }

    // MARK: - mixed (hard rule 4)

    @Test("product below a grand total with the gap explained by other lines is mixed: use the fuel line")
    func grandTotalGapIsMixed() {
        // receipt-009 shape: 47.56 x 129 = 6135.24 fuel, water 1 x 129.00,
        // ВСЕГО 6264.00. A caller passing the GRAND total as `total` learns the
        // fill-up amount is the fuel line, never the grand total (hard rule 4).
        let lines = ["47.56 л Х 129,00", "Вода Святой Источник 0.5л", "1 т. X 129.00",
                     "ВСЕГО", "6264.00"]
        let outcome = evaluate(47.56, 129.0, 6264.00, lines)
        guard case .mixed(let grandTotal, let fuelLine) = outcome else {
            Issue.record("expected mixed, got \(outcome)")
            return
        }
        #expect(abs(grandTotal - dec("6264")) < dec("0.005"))
        #expect(abs(fuelLine - dec("6135.24")) < dec("0.005"))
    }

    // MARK: - the two things the cross-check must stay blind to

    @Test("a swapped volume/price pair still locks - a x b == b x a")
    func swappedPairStillLocks() {
        // receipt-035 as the cloud model read it: 70.44 L at 39.00 instead of
        // 39.000 L at 70.44. The cross-check cannot see the swap.
        #expect(evaluate(70.44, 39.0, 2747.16, []) == .lock)
    }

    @Test("a lost decimal separator still locks - the check is scale-invariant")
    func lostDecimalSeparatorStillLocks() {
        // pump-009 as the model read it: 400.0 x 50.95 = 20380 instead of
        // 40.00 x 50.95 = 2038.00. Same self-consistency.
        #expect(evaluate(400.0, 50.95, 20380.0, []) == .lock)
    }

    // MARK: - the extractor side: the L-vs-Gab. discriminator

    @Test("the operand ladder tolerates a currency word between operands")
    func currencyWordBetweenOperandsParses() {
        // The Circle K screenshots print `1.884 EUR x 67 L`; the thermal
        // receipts omit the currency. Both must parse as one operand pair.
        let withCurrency = OperandPair(line: "1.884 EUR x 67 L")
        #expect(withCurrency?.left == 1.884)
        #expect(withCurrency?.right == 67.0)
        #expect(withCurrency?.rightText == "67L")
        #expect(withCurrency?.rightText.hasVolumeMarker == true)
        let plain = OperandPair(line: "43.61 Х 99.40")
        #expect(plain?.left == 43.61)
        #expect(plain?.right == 99.40)
    }

    @Test("the volume marker finds the fuel line among Latvian Gab. items")
    func volumeMarkerFindsTheFuelLine() {
        // screenshot-008: eight operand lines, the fuel line (with `L`) is the
        // third. "First priced line" and "line nearest the total" both fetch a
        // chocolate bar; the unit token separates them.
        let lines = Self.screenshot008Lines.map { OCRLine(text: $0) }
        let fuel = OperandPair.fuelLine(in: lines)
        #expect(fuel != nil)
        #expect(fuel?.index == 8)
        #expect(fuel?.pair.left == 1.924)
        #expect(fuel?.pair.right == 59.78)
    }

    @Test("screenshot-008 extracts the fuel line and returns 112.63, never the grand total 122.99")
    func screenshot008ReturnsTheFuelLine() {
        let result = FuelExtractor().extract(textLines: Self.screenshot008Lines)
        #expect(result.liters == 59.78)
        #expect(result.unitPrice == dec("1.924"))
        #expect(result.total == dec("112.63"))
        #expect(result.total != dec("122.99"), "hard rule 4: the fuel amount is the fuel line")
        guard case .reconciled(let residual, let discountLine) = result.crossCheck else {
            Issue.record("expected reconciled, got \(result.crossCheck)")
            return
        }
        #expect(abs(residual - dec("2.39")) < dec("0.005"))
        #expect(abs(discountLine - dec("3.17")) < dec("0.005"))
    }

    @Test("screenshot-004 extracts all three fields over a currency-bearing operand line")
    func screenshot004ExtractsOverCurrencyOperand() {
        let lines = ["D BO miles", "125.22 EUR", "1.884 EUR x 67 L",
                     "Total", "125.22 EUR", "24.24 EUR", "Tax",
                     "1.01 EUR", "Discount", "You saved 1.01 EUR"]
        let result = FuelExtractor().extract(textLines: lines)
        #expect(result.liters == 67.0)
        #expect(result.unitPrice == dec("1.884"))
        #expect(result.total == dec("125.22"))
    }

    // The screenshot-008 OCR lines in reading order (from the real Vision run).
    static let screenshot008Lines = [
        "ŠOK.BAT.KNOPPE", "1.00 EUR", "1.39 EUR x 1 Gab.",
        "ŠOK.BAT.KNOPPE", "1.00 EUR", "1.39 EUR x 1 Gab.",
        "Dizeld. Miles", "112.63 EUR", "1.924 EUR × 59.78 L",
        "LIMO.COCA COLA", "1.69 EUR", "1.69 EUR × 1 Gab.",
        "DEPOZITA MAKSA", "0.10 EUR", "0.1 EUR × 1 Gab.",
        "PIENA BAT.KIND", "0.99 EUR", "0.99 EUR x 1 Gab.",
        "M KAFIJA", "2.79 EUR", "2.79 EUR × 1 Gab.",
        "M KAFIJA", "2.79 EUR", "2.79 EUR × 1 Gab.",
        "Total", "122.99 EUR",
        "3.17 EUR", "Discount"
    ]
}
