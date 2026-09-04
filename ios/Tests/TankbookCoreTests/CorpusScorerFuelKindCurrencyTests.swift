import Foundation
import Testing
@testable import TankbookCore

// P6.14 - the scorer must see `fuelKind` and `currency`, the two extracted
// fields `CorpusABScorer.score` did not measure. Neither can move the number
// that guards extraction (P2.11 fixed fuel-kind resolution on receipt-034 and
// the receipts score stayed flat - correctly), so this suite pins the new
// semantics before the extractor improves: hit on a match, miss on a
// difference, empty expected cell skipped, nil extracted value against a
// non-empty expectation a miss. The tolerance is untouched and the extractor
// is untouched - these tests assert the *comparison*, not the score.

@Suite("P6.14 scorer semantics: fuelKind and currency")
struct CorpusScorerFuelKindCurrencyTests {

    @Test("fuelKind and currency: a match is a hit and a difference is a miss")
    func fuelKindAndCurrencyScoreBothDirections() {
        let want = ExpectedRow(liters: nil, unitPrice: nil, total: nil, fuelKind: .diesel, currency: .kzt)
        func scored(fuelKind: FuelKind?, currency: CurrencyCode?) -> ScoredClass {
            let record = ExtractionRecord(
                filename: "x.jpg", liters: nil, unitPrice: nil, total: nil,
                fuelKind: fuelKind, currency: currency
            )
            return CorpusScorer.score(
                name: "x", images: ["x.jpg"], records: ["x.jpg": record], expected: ["x.jpg": want]
            )
        }
        // Both directions must be asserted: proving only the hit half would not
        // prove the fields are scored at all (a scorer could count everything).
        #expect(scored(fuelKind: .diesel, currency: .kzt) == ScoredClass(name: "x", hits: 2, total: 2),
                "both fields match")
        #expect(scored(fuelKind: .petrol95, currency: .kzt) == ScoredClass(name: "x", hits: 1, total: 2),
                "fuelKind differs, currency matches")
        #expect(scored(fuelKind: .diesel, currency: .rub) == ScoredClass(name: "x", hits: 1, total: 2),
                "fuelKind matches, currency differs")
        #expect(scored(fuelKind: .lpg, currency: .eur) == ScoredClass(name: "x", hits: 0, total: 2),
                "both differ")
    }

    @Test("an empty expected fuelKind or currency field is skipped, never a miss")
    func emptyNewFieldsAreSkipped() {
        // Both new columns empty: however confident the record, neither is scored.
        let wantEmpty = ExpectedRow(liters: 10.0, unitPrice: nil, total: nil, fuelKind: nil, currency: nil)
        let confident = ExtractionRecord(
            filename: "x.jpg", liters: 10.0, unitPrice: 5.0, total: nil,
            fuelKind: .petrol98, currency: .eur
        )
        let scoredEmpty = CorpusScorer.score(
            name: "x", images: ["x.jpg"], records: ["x.jpg": confident], expected: ["x.jpg": wantEmpty]
        )
        #expect(scoredEmpty.total == 1, "only the asserted liters is scored")
        #expect(scoredEmpty.hits == 1)

        // One new column empty: only the asserted one is scored.
        let wantPartial = ExpectedRow(liters: nil, unitPrice: nil, total: nil, fuelKind: .diesel, currency: nil)
        let recordPartial = ExtractionRecord(
            filename: "x.jpg", liters: nil, unitPrice: nil, total: nil,
            fuelKind: .diesel, currency: .eur
        )
        let scoredPartial = CorpusScorer.score(
            name: "x", images: ["x.jpg"], records: ["x.jpg": recordPartial],
            expected: ["x.jpg": wantPartial]
        )
        #expect(scoredPartial.total == 1, "only fuelKind is scored")
        #expect(scoredPartial.hits == 1)
    }

    @Test("a nil extracted value against a non-empty expectation is a miss, not a skip")
    func nilExtractionAgainstNonEmptyExpectationIsAMiss() {
        let want = ExpectedRow(liters: nil, unitPrice: nil, total: nil, fuelKind: .diesel, currency: .rub)
        let abstained = ExtractionRecord(
            filename: "x.jpg", liters: nil, unitPrice: nil, total: nil, fuelKind: nil, currency: nil
        )
        let scored = CorpusScorer.score(
            name: "x", images: ["x.jpg"], records: ["x.jpg": abstained], expected: ["x.jpg": want]
        )
        #expect(scored.total == 2)
        #expect(scored.hits == 0)
    }

    @Test("the ratchet still fires on a fuelKind/currency regression and tolerates corpus growth")
    func ratchetWithTheNewFields() {
        // Adding fixtures that assert the new columns but resolve nothing must
        // not fire - that is corpus growth, and a gate that fires on growth is
        // a gate that gets deleted.
        #expect(AccuracyRatchet.violation(
            name: "receipts", currentHits: 48, currentTotal: 111, recordedHits: 48, recordedTotal: 106
        ) == nil)
        // A real regression - one fuelKind hit lost - fires even while the
        // corpus (and its total) grew.
        #expect(AccuracyRatchet.violation(
            name: "receipts", currentHits: 47, currentTotal: 111, recordedHits: 48, recordedTotal: 106
        ) != nil)
    }

    // MARK: - The committed corpus actually asserts the columns

    private static let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let fixturesRoot = repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures")

    @Test("every expected.csv parses with the six-column header and no silent holes")
    func expectedParsesWithTheNewColumns() throws {
        var assertedFuelKind = 0
        var assertedCurrency = 0
        var rows = 0
        for name in ["receipts", "pump", "fiscal", "screenshots"] {
            let url = Self.fixturesRoot.appendingPathComponent(name).appendingPathComponent("expected.csv")
            let header = try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n").first.map(String.init) ?? ""
            #expect(
                header == "filename,liters,unitPrice,total,fuelKind,currency",
                "\(name) header must be the documented six-column header; got '\(header)'"
            )
            let expected = try CorpusScorer.loadExpected(url)
            #expect(!expected.isEmpty, "\(name) parsed no rows")
            for row in expected.values {                rows += 1
                if row.fuelKind != nil { assertedFuelKind += 1 }
                if row.currency != nil { assertedCurrency += 1 }
            }
        }
        #expect(rows == 48 + 66 + 3 + 8, "corpus row count drifted: \(rows)")
        // The vacuous-assertion guard: a scored field nobody asserts is not
        // scored at all. The new columns must carry real cells, or this whole
        // task would measure nothing.
        #expect(assertedFuelKind > 0, "no fuelKind cell is asserted anywhere in the corpus")
        #expect(assertedCurrency > 0, "no currency cell is asserted anywhere in the corpus")
    }
}
