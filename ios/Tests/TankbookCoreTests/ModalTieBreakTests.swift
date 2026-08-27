import Foundation
import Testing
@testable import TankbookCore

// P2.14 - the total-finder's tie-break is now deterministic and, when the tie
// is unbreakable, it abstains rather than guessing. `Dictionary(grouping:)`
// iteration order is not guaranteed in Swift, so the old `modes.max(by:)` over
// equal `primaryCounts` (with `?? modes.first` behind it) returned whichever
// value the per-process hash seed had left last. P4.13 caught it: three sweeps
// per image, receipt-021/-026/-029 flipping 29/96 <-> 30/96 across identical
// runs. The named rule below is **nil on an unbreakable tie** - the parser
// already refuses rather than guessing everywhere else (a printed `0.00` becomes
// nil, an unmarked operand pair returns nil; `SCHEMA.md` -> Fuel price bands,
// step 5), and hard rule 13 says a confident wrong total is worse than an empty
// field the user fills.
//
// These tests drive the rule through `receiptGrandTotal`, the public path to
// `modal`. The determinism-across-processes half is NOT a same-process loop:
// Swift's hash seed is fixed within one process, so calling the function twice
// in one test agrees even while the bug is live. See
// `P2.14` in docs/TASKS.md and the cross-process probe below.

@Suite("Fuel extractor: deterministic total tie-break (P2.14)")
struct ModalTieBreakTests {

    private func total(_ lines: [String]) -> Double? {
        FuelExtractor().receiptGrandTotal(lines.map { OCRLine(text: $0) })
    }

    // MARK: - The named rule

    @Test("an unbreakable tie between two totals abstains (nil), never guesses")
    func unbreakableTieReturnsNil() {
        // Two totals (100.00 and 200.00), each named exactly once by a primary
        // label - a tie on count AND on primary-label count. The parser does not
        // know which is the receipt's total, so it abstains.
        #expect(total(["ИТОГ", "100.00", "----", "ИТОГО", "200.00"]) == nil)
    }

    // MARK: - The common path must not change

    @Test("a single clear mode is still returned")
    func singleClearModeStillResolves() {
        // 100.00 is the only candidate, named by three primary labels.
        #expect(total(["ИТОГ", "100.00", "ИТОГО", "100.00", "ИТОГ", "100.00"]) == 100.00)
    }

    @Test("a tie broken by the primary label still resolves to that value")
    func primaryLabelStillBreaksTheTie() {
        // 100.00 and 200.00 each appear twice, but only 100.00 is ever named by
        // a primary label - so the tie is breakable and resolves to 100.00.
        let lines = ["ИТОГ", "100.00", "----", "НАЛИЧНЫМИ", "100.00",
                     "----", "НАЛИЧНЫМИ", "200.00", "----", "НАЛИЧНЫМИ", "200.00"]
        #expect(total(lines) == 100.00)
    }

    // MARK: - The three receipts P4.13 caught flipping

    /// receipt-021: `ИТОГ` misread as `НТОГ` drops the only primary label,
    /// leaving the two payment totals 2519.81 and 5050.00 tied - the pair the
    /// three PaddleOCR sweeps flipped between.
    @Test("receipt-021: the tied totals 2519.81 vs 5050.00 abstain")
    func receipt021UnbreakableTieAbstains() {
        #expect(total(["НАЛИЧНЫМИ", "2519.81", "----", "НАЛИЧНЫМИ", "5050.00"]) == nil)
    }

    /// receipt-026: same misread - `ИТОГ` dropped, the payment totals 5380.00
    /// and 970.16 tied.
    @Test("receipt-026: the tied totals 5380.00 vs 970.16 abstain")
    func receipt026UnbreakableTieAbstains() {
        #expect(total(["НАЛИЧНЫМИ", "5380.00", "----", "НАЛИЧНЫМИ", "970.16"]) == nil)
    }

    /// receipt-029: same misread - `ИТОГ` dropped, the payment totals 2529.97
    /// and 421.66 tied.
    @Test("receipt-029: the tied totals 2529.97 vs 421.66 abstain")
    func receipt029UnbreakableTieAbstains() {
        #expect(total(["НАЛИЧНЫМИ", "2529.97", "----", "НАЛИЧНЫМИ", "421.66"]) == nil)
    }

    // MARK: - Cross-process determinism probe

    /// Prints the tie result so a shell loop can run it in 100 separate
    /// processes and assert the output is identical. A same-process loop would
    /// share the hash seed and agree even while the bug is live. The `#expect`
    /// is the named-rule assertion; the `print` is the cross-process evidence.
    @Test("P2.14 determinism probe: one unbreakable tie, one answer every process")
    func crossProcessProbe() {
        let result = total(["НАЛИЧНЫМИ", "2519.81", "----", "НАЛИЧНЫМИ", "5050.00"])
        print("MODAL_TIE_RESULT \(String(describing: result))")
        #expect(result == nil)
    }
}
