import Foundation
import Testing
@testable import TankbookCore

/// The repair tier's budget (docs/EXTRACTION.md -> "The repair budget"): a
/// substitution pays the reader's own posterior for the partner digit, and no
/// more than `PumpReadingLaw.repairWindow`.
@Suite("PumpReadingLaw repair budget")
struct PumpReadingLawRepairBudgetTests {
    @Test("a digit the reader was sure of is not rewritten to fit a total the arithmetic disputes")
    func certainCellIsNotRepaired() {
        // pump-041's shape: the price 1.784 read with certainty, the total
        // 54.63 read as 54.93 under glare. 30.62 x 1.794 closes to 54.93, so
        // an uncharged repair turns the certain 8 into its partner 9. The
        // 9's cost (5.6 nats) is the row reader's, T-scaled: inside the read
        // window, outside the repair budget.
        var price = PumpReadingLawTests.window(.unitPrice, "1.784").cells
        price[2] = PumpCellReading(probabilities: [], ranked: [
            PumpGlyphCandidate(digit: 8, logPosterior: -0.052),
            PumpGlyphCandidate(digit: 1, logPosterior: -4.2),
            PumpGlyphCandidate(digit: 6, logPosterior: -5.1),
            PumpGlyphCandidate(digit: 9, logPosterior: -5.66),
        ], decimalPoint: false)
        let reading = PumpReadingLaw.resolve(
            windows: [
                PumpReadingLawTests.window(.total, "54.93"),
                PumpReadingLawTests.window(.liters, "30.62"),
                PumpLocatedWindow(field: .unitPrice, cells: price),
            ], currency: CurrencyCode(rawValue: "EUR"))
        #expect(reading.unitPrice.value != Decimal(string: "1.794"))
        for field in [reading.liters, reading.unitPrice, reading.total] {
            if case .repaired? = field.provenance { Issue.record("a certain cell was repaired: \(field)") }
        }
    }
}
