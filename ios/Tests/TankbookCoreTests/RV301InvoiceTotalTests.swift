import Foundation
import Testing
@testable import TankbookCore

// A Russian delivery note / invoice prints its grand total with a
// document-total word (`На сумму :`, `Сумма документа:`), not the receipt
// finder's fuel vocabulary. These are L1 tests over the extractor's INPUT: the
// `.txt` is the OCR text a document of that kind prints, and the ground truth is
// `expected.csv`, hand-written from the paper. The read runs through the same
// `FuelExtractor` the fill-up and expense paths share - there is no
// invoice-only finder - so these assertions pin the one finder and its
// document-total ranking.
@Suite("RV.301 invoice totals")
struct RV301InvoiceTotalTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent()  // TankbookCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // ios
        .deletingLastPathComponent()  // repo
    private static let fixturesRoot = repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures/expenses")

    private static func lines(_ filename: String) throws -> [OCRLine] {
        let text = try String(contentsOf: fixturesRoot.appendingPathComponent(filename),
                              encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { OCRLine(text: String($0)) }
    }

    private static func expectedRow(_ filename: String) throws -> ExpenseExpectedRow {
        try #require(
            try CorpusScorer.loadExpenseExpected(
                fixturesRoot.appendingPathComponent("expected.csv"))
                .first { $0.filename == filename },
            "\(filename): no expected.csv row")
    }

    /// The three documents whose paper grand total the `expected.csv` records:
    /// the Gorunov delivery note (`На сумму : 11 850.00 руб.`), the Akhmadullin
    /// tyre note (`Итого:` then `Всего наименований 7, на сумму 87600 руб`) and
    /// the VAG page-two screenshot (`Итого:` columns, then `Сумма документа:
    /// 159 373,00`). Each must resolve the paper's figure, never a line item.
    @Test("the three invoice fixtures resolve their expected grand total")
    func invoiceFixturesResolveTheirGrandTotals() throws {
        for filename in ["accessory-gorunov-roof-rack-invoice-ru.txt",
                         "parts-akhmadullin-kumho-tires-invoice-ru.txt",
                         "parts-vag-invoice-page-two-screenshot-ru.txt"] {
            let expected = try Self.expectedRow(filename)
            #expect(expected.total != nil, "\(filename): the row asserts no total")
            let got = FuelExtractor().extract(lines: try Self.lines(filename)).total
            #expect(got == expected.total, Comment(stringLiteral:
                    "\(filename): expected \(String(describing: expected.total)), "
                    + "got \(String(describing: got))"))
        }
    }

    /// Two document labels that disagree leave the total empty rather than fall
    /// through to a lower-ranked label's figure.
    @Test("disagreeing document labels abstain instead of reading a column total")
    func disagreeingDocumentLabelsAbstain() {
        let lines = ["На сумму : 100.00 руб.", "Сумма документа: 200.00", "ИТОГО 300.00"]
            .map { OCRLine(text: $0) }
        #expect(FuelExtractor().extract(lines: lines).total == nil)
        let outvoted = ["На сумму : 100.00 руб.", "Сумма документа: 100.00", "Сумма документа: 200.00",
                        "ИТОГО 300.00"].map { OCRLine(text: $0) }
        #expect(FuelExtractor().extract(lines: outvoted).total == nil)
    }

    /// The vocabulary the ranking rests on: a document-total word classifies as
    /// its own kind, distinct from the `СУММА` stem it contains, so the finder
    /// can rank it over a column `Итого`.
    @Test("document-total words classify as the document kind")
    func documentTotalWordsClassifyAsDocument() {
        #expect(TotalLabel.classify("На сумму : 11 850.00 руб.") == .document)
        #expect(TotalLabel.classify("Сумма документа:") == .document)
        #expect(TotalLabel.classify("Итого:") == .primary)
        #expect(TotalLabel.classify("Сумма") == .primary)
    }
}
