import Foundation
import Testing
@testable import TankbookCore

// P2.13 - cross-multiplication as seven-segment digit repair
// (docs/EXTRACTION.md -> "Cross-multiplication as digit repair"). The engine
// substitutes the confusable seven-segment pairs (4/9, 8/9, 8/6, 8/0, 3/9, 5/6,
// 1/7) one digit at a time and accepts a repair only when EXACTLY ONE
// substitution reproduces the total at the display's money precision. These are
// the fast, deterministic L1 checks over fixture ground truth.
//
// The two-candidate refusal (test 3) is the half that keeps the feature from
// inventing digits, and the pump-only gate (test 4) keeps it from fabricating
// receipt numbers that have no segment story.

private func dec(_ string: String) -> Decimal { Decimal(string: string)! }

private func pumpBox(x: CGFloat, y: CGFloat) -> CGRect {
    CGRect(x: x, y: y, width: 0.1, height: 0.5)
}

/// The OCR geometry of a Dresser Wayne pump with a `/L` price label
/// (pump-013/015 family): SUMMA value right of its label, LIITRIT value right
/// of its label, and the unit price directly below its `/L` label.
private func pumpLines(volume: String, price: String, total: String) -> [OCRLine] {
    [
        OCRLine(text: "SUMMA", boundingBox: pumpBox(x: 0.3, y: 3)),
        OCRLine(text: total, boundingBox: pumpBox(x: 0.7, y: 3)),
        OCRLine(text: "LIITRIT", boundingBox: pumpBox(x: 0.3, y: 2)),
        OCRLine(text: volume, boundingBox: pumpBox(x: 0.7, y: 2)),
        OCRLine(text: "HIND/1L", boundingBox: pumpBox(x: 0.3, y: 1)),
        OCRLine(text: price, boundingBox: pumpBox(x: 0.7, y: 0.985))
    ]
}

@Suite("Seven-segment digit repair (P2.13)")
struct DigitRepairTests {

    // MARK: - The two corpus fixtures repair to ground truth

    @Test("pump-015 repairs the glare-read 1.884 price to 1.889")
    func pump015RepairsItsPrice() {
        // pump-015 shows SUMMA 30.02, LIITRIT 15.89, price read 1.884. But
        // 15.89 x 1.884 = 29.94, not 30.02, and 15.89 x 1.889 = 30.02 exactly
        // (fixtures/pump/README.md). A glare fills the segment that turns a
        // seven-segment 9 into a 4, so the terminal digit is the repair target.
        let repair = DigitRepair.apply(liters: 15.89, unitPrice: 1.884, total: 30.02, source: .pump)
        guard let repair else {
            Issue.record("pump-015 did not repair")
            return
        }
        #expect(repair.operand == .unitPrice)
        #expect(repair.original == 1.884)
        #expect(abs(repair.repaired - 1.889) < 0.005)
    }

    @Test("pump-013 repairs the glare-read 1.774 price to 1.779")
    func pump013RepairsItsPrice() {
        // pump-013: 7.34 x 1.774 = 13.02, where 7.34 x 1.779 = 13.06 reproduces
        // the displayed SUMMA. The 9-as-4 is at the price's last digit.
        let repair = DigitRepair.apply(liters: 7.34, unitPrice: 1.774, total: 13.06, source: .pump)
        guard let repair else {
            Issue.record("pump-013 did not repair")
            return
        }
        #expect(repair.operand == .unitPrice)
        #expect(repair.original == 1.774)
        #expect(abs(repair.repaired - 1.779) < 0.005)
    }

    @Test("pump-015 repairs end-to-end through the extractor with real geometry")
    func pump015RepairsEndToEnd() {
        let lines = pumpLines(volume: "15.89 L", price: "1.884", total: "30.02")
        let result = FuelExtractor().extract(lines: lines, source: .pump)
        #expect(result.liters == 15.89)
        #expect(abs((result.unitPrice ?? 0) - 1.889) < 0.005)
        #expect(result.total == 30.02)
        #expect(result.digitRepair != nil)
    }

    @Test("pump-013 repairs end-to-end through the extractor with real geometry")
    func pump013RepairsEndToEnd() {
        let lines = pumpLines(volume: "7.34 L", price: "1.774", total: "13.06")
        let result = FuelExtractor().extract(lines: lines, source: .pump)
        #expect(result.liters == 7.34)
        #expect(abs((result.unitPrice ?? 0) - 1.779) < 0.005)
        #expect(result.total == 13.06)
        #expect(result.digitRepair != nil)
    }

    // MARK: - The refusal: exactly one substitution may close

    @Test("two different closing substitutions mean nil, never a pick")
    func twoClosingSubstitutionsRefuse() {
        // Constructed: liters 1.70, price 1.70, total 1.87. The naive product
        // 2.89 does not reproduce 1.87, but TWO single-digit repairs both do:
        //   1.10 x 1.70 = 1.87   (liters 7->1, a 1/7 confusion)
        //   1.70 x 1.10 = 1.87   (price 7->1, the same confusion on the price)
        // Each alone is a consistent triple - which is exactly why the document
        // does not determine the answer. The engine must return nil, not pick.
        #expect(DigitRepair.apply(liters: 1.70, unitPrice: 1.70, total: 1.87, source: .pump) == nil)

        // The proof that each candidate really does close: the engine repairs
        // nothing on the already-consistent results, because there is nothing
        // left to fix - yet it will not choose between them on the original.
        #expect(DigitRepair.apply(liters: 1.10, unitPrice: 1.70, total: 1.87, source: .pump) == nil)
        #expect(DigitRepair.apply(liters: 1.70, unitPrice: 1.10, total: 1.87, source: .pump) == nil)
    }

    @Test("a triple that already reproduces the total is never repaired")
    func alreadyConsistentTripleIsNotRepaired() {
        // 15.89 x 1.889 = 30.02: the product rounds to the total, so the
        // misread-segment hypothesis is unnecessary.
        #expect(DigitRepair.apply(liters: 15.89, unitPrice: 1.889, total: 30.02, source: .pump) == nil)
    }

    @Test("pump-010's preset-amount rounding is never 'corrected'")
    func presetAmountRoundingIsNotRepaired() {
        // pump-010: 13.17 x 75.95 = 1000.26 against Итого 1000.00. Nothing is
        // misread - the customer preset a round amount and the display rounds
        // the volume (fixtures/pump/README.md). The honest record is the
        // displayed 13.17 and 1000.00, and the cross-check tolerance absorbs
        // the 0.26. Digit repair must NOT invent a correction here: no single
        // substitution reproduces the total exactly, so the engine abstains.
        #expect(DigitRepair.apply(liters: 13.17, unitPrice: 75.95, total: 1000.00, source: .pump) == nil)
    }

    // MARK: - Pump source only

    @Test("a receipt-source triple is never repaired, even when a substitution would close")
    func receiptSourceIsNeverRepaired() {
        // The same numbers that repair under .pump are untouched under .receipt:
        // thermal print has no segment topology, so a repair there would be a
        // fabricated number with no physical story behind it.
        #expect(DigitRepair.apply(liters: 15.89, unitPrice: 1.884, total: 30.02, source: .receipt) == nil)
        #expect(DigitRepair.apply(liters: 15.89, unitPrice: 1.884, total: 30.02, source: .fiscal) == nil)
        #expect(DigitRepair.apply(liters: 15.89, unitPrice: 1.884, total: 30.02, source: .screenshot) == nil)
    }

    @Test("a receipt that would repair under pump keeps its read value through the extractor")
    func receiptKeepsItsReadValueEndToEnd() {
        // The same 15.89 L x 1.884 / 30.02 numbers that repair under .pump are
        // untouched when the source is a receipt: thermal print has no segment
        // topology, so a repair would be a fabricated number with no physical
        // story behind it.
        let lines = ["SUMMA", "30.02", "15.89 L x 1.884"]
        let result = FuelExtractor().extract(textLines: lines) // source defaults to .receipt
        #expect(result.liters == 15.89)
        #expect(result.unitPrice == 1.884, "a receipt is never repaired - the read price stands")
        #expect(result.total == 30.02)
        #expect(result.digitRepair == nil)
    }

    // MARK: - The repair is a suggestion, never a lock

    @Test("a repaired field is returned unconfirmed: cross-check stays a mismatch, never lock")
    func repairIsASuggestionNotALock() {
        let lines = pumpLines(volume: "15.89 L", price: "1.884", total: "30.02")
        let result = FuelExtractor().extract(lines: lines, source: .pump)

        // The read triple would have locked under the shared tolerance, but the
        // repair deliberately keeps the cross-check a mismatch carrying the read
        // residual: the confirm screen never treats the corrected price as a
        // confirmed field (hard rule 13).
        guard case .mismatch(let residual) = result.crossCheck else {
            Issue.record("expected mismatch, got \(result.crossCheck)")
            return
        }
        #expect(abs(residual - dec("-0.08")) < dec("0.005"))
        #expect(result.crossCheck != .lock)

        // The repaired numbers themselves ARE consistent - which is exactly why
        // the mismatch is a deliberate choice, not an accident: the arithmetic
        // alone cannot be trusted to confirm a repaired digit.
        let recomputed = ExtractionCrossCheck.evaluate(
            liters: result.liters, unitPrice: result.unitPrice, total: result.total, lines: []
        )
        #expect(recomputed == .lock)
    }

    // MARK: - Missing numbers and Codable

    @Test("a missing number makes the repair notApplicable")
    func missingNumberIsNotRepaired() {
        #expect(DigitRepair.apply(liters: nil, unitPrice: 1.884, total: 30.02, source: .pump) == nil)
        #expect(DigitRepair.apply(liters: 15.89, unitPrice: nil, total: 30.02, source: .pump) == nil)
        #expect(DigitRepair.apply(liters: 15.89, unitPrice: 1.884, total: nil, source: .pump) == nil)
    }

    @Test("the repair marker survives a Codable round-trip")
    func repairMarkerSurvivesCodable() throws {
        let repair = DigitRepair.Result(operand: .unitPrice, original: 1.884, repaired: 1.889)
        let extraction = FuelExtraction(liters: 15.89, unitPrice: 1.889, total: 30.02, digitRepair: repair)
        let data = try JSONEncoder().encode(extraction)
        let decoded = try JSONDecoder().decode(FuelExtraction.self, from: data)
        #expect(decoded.digitRepair == repair)
    }

    @Test("a payload without the repair key decodes to nil (backward compatible)")
    func decodingWithoutTheRepairKeyYieldsNil() throws {
        // An extraction carrying no repair (an "old" payload, as the encoder
        // omits a nil optional) decodes with digitRepair nil - adding the field
        // must not break decoding of existing FuelExtraction payloads.
        let extraction = FuelExtraction(liters: 15.89, unitPrice: 1.884, total: 30.02)
        let data = try JSONEncoder().encode(extraction)
        let decoded = try JSONDecoder().decode(FuelExtraction.self, from: data)
        #expect(decoded.digitRepair == nil)
        #expect(decoded.liters == 15.89)
    }
}
