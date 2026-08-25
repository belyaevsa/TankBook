import Foundation
import Testing
@testable import TankbookCore

/// P3.1b invoice line splitter tests (docs/JOURNEYS.md J7). The load-bearing
/// invariant - the split is accepted only when its items sum to the invoice
/// total within the CHECK 3 tolerance, and discarded for the lump sum otherwise
/// - is tested in BOTH directions, because a one-sided test stays green straight
/// through the "split loses a line" bug. Fixtures are OCR lines transcribed
/// verbatim from a realistic workshop invoice (the design artboard's Bosch
/// Service RECHNUNG - the repo's fixture corpus holds no invoice images, and no
/// OCR can run from these tests), not text written to flatter the parser.
@Suite struct InvoiceSplitterTests {

    private let splitter = InvoiceSplitter()

    private func decimal(_ string: String) -> Decimal { Decimal(string: string)! }

    // MARK: - The sum invariant, both directions

    @Test("items that sum to the total split; items that do not fall back to the lump sum")
    func sumInvariantBothDirections() {
        // Just inside: 1.00 + 0.99 = 1.99 vs total 2.00, gap 0.01 <= 0.02.
        let inside = splitter.split(textLines: [
            "ACME GARAGE",
            "Widget 1.00",
            "Sprocket 0.99",
            "TOTAL 2.00"
        ])
        #expect(inside.lumpSum == false)
        #expect(inside.items.count == 2)
        #expect(inside.total == decimal("2.00"))

        // Just outside: 1.00 + 0.97 = 1.97 vs total 2.00, gap 0.03 > 0.02.
        let outside = splitter.split(textLines: [
            "ACME GARAGE",
            "Widget 1.00",
            "Sprocket 0.97",
            "TOTAL 2.00"
        ])
        #expect(outside.lumpSum == true)
        #expect(outside.items.count == 1)
        #expect(outside.items[0].amount == decimal("2.00"))
        #expect(outside.items[0].category == .other(""))
    }

    @Test("the tolerance boundary itself is exact")
    func toleranceBoundary() {
        // Two candidates whose sum sits exactly at max(0.02, 2.00 x 0.005) = 0.02.
        #expect(InvoiceSplitter.sumsToTotal(
            [InvoiceLineItem(title: "a", amount: decimal("1.00"), category: .other("")),
             InvoiceLineItem(title: "b", amount: decimal("0.98"), category: .other(""))],
            total: decimal("2.00")) == true)
        #expect(InvoiceSplitter.sumsToTotal(
            [InvoiceLineItem(title: "a", amount: decimal("1.00"), category: .other("")),
             InvoiceLineItem(title: "b", amount: decimal("0.97"), category: .other(""))],
            total: decimal("2.00")) == false)
    }

    // MARK: - The realistic split

    @Test("a workshop invoice splits into its line items with guessed categories")
    func workshopInvoiceSplits() {
        let result = splitter.split(textLines: [
            "BOSCH SERVICE",
            "RECHNUNG 2026-4411",
            "Ölservice inkl. Filter 89.00",
            "Bremsbeläge vorn 59.00",
            "GESAMT 148.00 EUR"
        ])
        #expect(result.vendor == "BOSCH SERVICE")
        #expect(result.total == decimal("148.00"))
        #expect(result.lumpSum == false)
        #expect(result.items.count == 2)
        #expect(result.items[0].title == "Ölservice inkl. Filter")
        #expect(result.items[0].amount == decimal("89.00"))
        #expect(result.items[0].category == .oil)
        #expect(result.items[1].title == "Bremsbeläge vorn")
        #expect(result.items[1].amount == decimal("59.00"))
        #expect(result.items[1].category == .brakes)
    }

    // MARK: - A failed split is the lump sum, never an error

    @Test("a split that loses a line is discarded entirely, not silently kept")
    func partialSplitIsDiscarded() {
        // Three items that sum to 160.40 but a 148.00 total: the parser could
        // "succeed" by dropping the Luftfilter, which would store a wrong number
        // that looks right. The result must be the single lump sum instead.
        let result = splitter.split(textLines: [
            "BOSCH SERVICE",
            "Ölservice inkl. Filter 89.00",
            "Bremsbeläge vorn 59.00",
            "Luftfilter 12.40",
            "GESAMT 148.00 EUR"
        ])
        #expect(result.lumpSum == true)
        #expect(result.items.count == 1)
        #expect(result.items[0].amount == decimal("148.00"))
        #expect(result.items[0].category == .other(""))
    }

    @Test("a single candidate line is never presented as a split")
    func singleCandidateIsNotASplit() {
        // One item equals the total, but one item cannot distinguish a split
        // from a lump sum - it IS the lump sum (the vacuous-assertion trap).
        let result = splitter.split(textLines: [
            "ACME GARAGE",
            "Full service 89.00",
            "TOTAL 89.00"
        ])
        #expect(result.lumpSum == true)
        #expect(result.items.count == 1)
    }

    @Test("no total means no confident items - the user types, nothing is fabricated")
    func noTotalYieldsNoItems() {
        let result = splitter.split(textLines: [
            "ACME GARAGE",
            "Widget 1.00",
            "Sprocket 0.99"
        ])
        #expect(result.items.isEmpty)
        #expect(result.total == nil)
        #expect(result.vendor == "ACME GARAGE")
    }

    // MARK: - Vendor and date

    @Test("the header names the vendor and the printed date is parsed")
    func vendorAndDate() {
        let result = splitter.split(textLines: [
            "BOSCH SERVICE",
            "RECHNUNG 2026-4411",
            "Datum: 09.08.2026",
            "Ölservice inkl. Filter 89.00",
            "GESAMT 89.00 EUR"
        ])
        #expect(result.vendor == "BOSCH SERVICE")
        #expect(result.date != nil)
        // "RECHNUNG 2026-4411" must not be mistaken for a date.
        #expect(result.date.map {
            Calendar(identifier: .gregorian).component(.year, from: $0)
        } == 2026)
    }

    @Test("an invoice number is not a date")
    func invoiceNumberIsNotADate() {
        let result = splitter.split(textLines: [
            "BOSCH SERVICE",
            "RECHNUNG 2026-4411",
            "Ölservice 89.00",
            "GESAMT 89.00"
        ])
        #expect(result.date == nil)
    }

    // MARK: - Category vocabulary

    @Test("the vocabulary guesses a category and falls back to .other for unknowns")
    func categoryVocabulary() {
        #expect(InvoiceSplitter.category(for: "Engine oil") == .oil)
        #expect(InvoiceSplitter.category(for: "Bremsbeläge vorn") == .brakes)
        #expect(InvoiceSplitter.category(for: "Тормозные колодки") == .brakes)
        #expect(InvoiceSplitter.category(for: "Winterreifen") == .tires)
        #expect(InvoiceSplitter.category(for: "Battery replacement") == .battery)
        #expect(InvoiceSplitter.category(for: "Luftfilter") == .filters)
        #expect(InvoiceSplitter.category(for: "Inspektion") == .inspection)
        #expect(InvoiceSplitter.category(for: "Reparatur") == .repair)
        #expect(InvoiceSplitter.category(for: "Мойка кузова") == .wash)
        #expect(InvoiceSplitter.category(for: "Miscellaneous work") == .other(""))
    }

    // MARK: - Provenance

    @Test("the result records the pipeline and per-line confidence")
    func provenanceMeta() {
        let result = splitter.split(textLines: [
            "BOSCH SERVICE",
            "Ölservice inkl. Filter 89.00",
            "Bremsbeläge vorn 59.00",
            "GESAMT 148.00 EUR"
        ])
        #expect(result.pipeline == "vision+rules invoice v1")
        #expect(result.extraction.fields[.vendor] != nil)
        #expect(result.extraction.fields[.lineItem(0)] != nil)
        #expect(result.extraction.fields[.lineItem(1)] != nil)
    }
}
