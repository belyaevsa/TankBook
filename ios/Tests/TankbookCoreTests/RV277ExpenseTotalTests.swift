import Foundation
import Testing
@testable import TankbookCore

// RV.277 - the expense read must resolve the AMOUNT, not only the kind. The
// corpus's first parking ticket (RV.200) taught `ExpenseCategoryInference` the
// KIND; the second showed the money vocabulary stopped at fuel-receipt words -
// `TASU` (fee) and `MAKSTUD` (paid) are not total markers, so the shared
// `FuelExtractor` abstained and the expense form opened empty.
//
// These are L1 tests over the extractor's INPUT: each fixture is the OCR text a
// receipt of that kind prints, and the ground truth is `expected.csv` written by
// hand from the paper, never from the extractor's output (the oracle rule in
// Spike/ReceiptSpike/fixtures/README.md). The expense read runs through the SAME
// `FuelExtractor` the fill-up path uses - there is no expense-only finder - so
// these assertions pin the one finder the brief requires. The class's ratchet
// lives in `AccuracyRatchetTests`, beside the fuel classes'.
@Suite("RV.277 expense total / currency / date read")
struct RV277ExpenseTotalTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent()  // TankbookCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // ios
        .deletingLastPathComponent()  // repo
    private static let fixturesRoot = repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures/expenses")

    static func rows() throws -> [ExpenseExpectedRow] {
        try CorpusScorer.loadExpenseExpected(
            fixturesRoot.appendingPathComponent("expected.csv"))
    }

    private static func lines(_ filename: String) throws -> [OCRLine] {
        let text = try String(contentsOf: fixturesRoot.appendingPathComponent(filename),
                              encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { OCRLine(text: String($0)) }
    }

    /// The extraction the expense read produces for a fixture: the same
    /// `FuelExtractor` call the app's `CapturePipeline` makes on OCR lines.
    private static func extraction(_ filename: String) throws -> FuelExtraction {
        FuelExtractor().extract(lines: try lines(filename))
    }

    /// The named acceptance case, and the one that FAILS before the vocabulary
    /// lands: the second Tallinn Airport ticket reads total 4.00, currency EUR,
    /// date 2026-09-13 and kind parking. The value is the paper's `TASU: 4.00
    /// EUR` (which `MAKSTUD` agrees with); `NETO` (3.23) is never the total.
    @Test("the second Tallinn Airport ticket reads 4.00 EUR, 2026-09-13, parking")
    func secondTallinnTicketResolvesMoneyAndKind() throws {
        let extraction = try Self.extraction("parking-tallinn-airport-et-2.txt")
        #expect(extraction.total == Decimal(string: "4.00"))
        #expect(extraction.currency == .eur)
        #expect(extraction.date.flatMap { ConfirmDate.parse($0) } == ConfirmDate.parse("13.09.26"))
        #expect(ExpenseCategoryInference.infer(from: try Self.lines(
            "parking-tallinn-airport-et-2.txt")) == .parking)
    }

    /// The first Tallinn ticket (RV.200's photograph) must not regress: 2.00 EUR
    /// and parking.
    @Test("the first Tallinn Airport ticket still reads 2.00 EUR and parking")
    func firstTallinnTicketStillResolves() throws {
        let extraction = try Self.extraction("parking-tallinn-airport-et.txt")
        #expect(extraction.total == Decimal(string: "2.00"))
        #expect(extraction.currency == .eur)
        #expect(ExpenseCategoryInference.infer(from: try Self.lines(
            "parking-tallinn-airport-et.txt")) == .parking)
    }

    /// Every hand-authored fixture that prints an amount must resolve it through
    /// the shared finder. `ИТОГО`/`ИТОГ` are read on the label's own line or the
    /// line beside it; `ШТРАФ` is the fine's amount.
    @Test("the hand-authored fixtures resolve the totals their lines carry")
    func handAuthoredFixturesResolveTheirTotals() throws {
        for filename in ["parking-ru.txt", "parking-en.txt", "wash-ru.txt", "toll-ru.txt",
                         "fine-ru.txt", "insurance-ru.txt", "tax-ru.txt", "parts-ru.txt",
                         "accessory-ru.txt", "ambiguous-fuel-ru.txt"] {
            let expected = try #require(Self.rows().first { $0.filename == filename })
            #expect(expected.total != nil, "\(filename): the fixture carries no expected total")
            let got = try Self.extraction(filename).total
            #expect(got == expected.total,
                    "\(filename): expected total \(String(describing: expected.total)), got \(String(describing: got))")
        }
    }

    /// The whole-class guard the ratchet cannot see: a committed value that
    /// contradicts `expected.csv` is a confident wrong value (hard rule 13),
    /// while an abstention (nil) is an honest miss. Mirrors
    /// `noReceiptCommitsAFuelKindItsExpectedContradicts` for the expense folder.
    @Test("no expense fixture commits a value its expected.csv contradicts")
    func noExpenseFixtureCommitsAContradictedValue() throws {
        var contradictions: [String] = []
        for row in try Self.rows() {
            let got = try Self.extraction(row.filename)
            if let want = row.total, let gotTotal = got.total, gotTotal != want {
                contradictions.append("\(row.filename): committed total \(gotTotal), expected \(want)")
            }
            if let want = row.currency, let gotCurrency = got.currency, gotCurrency != want {
                contradictions.append("\(row.filename): committed currency \(gotCurrency.rawValue), "
                    + "expected \(want.rawValue)")
            }
            if let want = row.date, let raw = got.date, let gotDate = ConfirmDate.parse(raw),
               gotDate != want {
                contradictions.append("\(row.filename): committed date \(gotDate), expected \(want)")
            }
            if row.categoryAsserted,
               let gotCategory = ExpenseCategoryInference.infer(from: try Self.lines(row.filename)),
               gotCategory != row.category {
                contradictions.append("\(row.filename): committed category \(gotCategory), "
                    + "expected \(String(describing: row.category))")
            }
        }
        #expect(contradictions.isEmpty, Comment(stringLiteral: contradictions.joined(separator: "\n")))
    }
}
