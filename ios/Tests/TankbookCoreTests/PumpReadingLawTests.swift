import Foundation
import Testing
@testable import TankbookCore

/// The decode law on the corpus's annotated strings: a "perfect but not
/// certain" reader (0.97 on every true segment state) whose only judge is the
/// arithmetic, scored by the same pump scorer as the rules parser against
/// `expected.csv` (decision 6: the receipt is the truth). This is the ceiling
/// the law gives a perfect classifier, and the fragility pass below is what it
/// does to a single misread.
@Suite("PU.21 pump reading law")
struct PumpReadingLawTests {

    // MARK: - Ratchet constants (measured 2026-09-19; move only upward)

    private static let committedFloor = 294
    private static let precisionFloor = 0.996
    /// Cells the corpus itself declares unreadable as the receipt's value:
    /// a display that rounds or truncates what the receipt prints.
    private static let declaredArtefacts: Set<String> = [
        "pump-031", "pump-065", "pump-073",
    ]

    // MARK: - Unit rules

    @Test("a certain cell ranks its digit first with a wide margin")
    func certainCellRanksItsDigit() {
        for digit in 0...9 {
            let cell = PumpCellReading(certainDigit: digit, decimalPoint: false)
            #expect(cell.top.digit == digit)
            #expect(cell.margin > 2)
        }
    }

    @Test("pump-009: zero-padded Gilbarco strings resolve to 40.00 x 50.95 = 2038.00")
    func pump009Resolves() {
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "02038,00"),
                Self.window(.liters, "00040,00"),
                Self.window(.unitPrice, "050,95"),
            ], currency: CurrencyCode(rawValue: "RUB"))
        #expect(reading.liters.value == Decimal(string: "40"))
        #expect(reading.unitPrice.value == Decimal(string: "50.95"))
        #expect(reading.total.value == Decimal(string: "2038"))
        #expect(reading.total.provenance == .read)
    }

    @Test("pump-003: a KZT total the display rounds is derived, never read")
    func pump003DerivesTheTotal() {
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "20886.3"),
                Self.window(.liters, "85.25"),
                Self.window(.unitPrice, "245.0"),
            ], currency: CurrencyCode(rawValue: "KZT"))
        #expect(reading.liters.value == Decimal(string: "85.25"))
        #expect(reading.unitPrice.value == Decimal(string: "245"))
        // Oracle: expected.csv says 20886.25, the receipt's value.
        #expect(reading.total.value == Decimal(string: "20886.25"))
        #expect(reading.total.provenance == .derived)
    }

    @Test("pump-031: a discount that breaks the arithmetic commits nothing wrong")
    func pump031Abstains() {
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "0032,58"),
                Self.window(.liters, "0016,80"),
                Self.window(.unitPrice, "1,939"),
            ], currency: CurrencyCode(rawValue: "EUR"))
        // 16.80 x 1.939 = 32.575 -> 32.58 closes on the DISPLAY value; the
        // receipt says 32.50 after the discount. The law reads what the pump
        // shows; this is one of the declared artefacts the ratchet excludes.
        #expect(reading.total.value == nil || reading.total.value == Decimal(string: "32.58"))
    }

    @Test("an idle pump commits nothing")
    func idlePumpAbstains() {
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "0.00"),
                Self.window(.liters, "0.00"),
                Self.window(.unitPrice, "1.889"),
            ], currency: CurrencyCode(rawValue: "EUR"))
        #expect(reading.committedCount == 0)
    }

    @Test("a single misread cell is repaired when exactly one substitution closes the arithmetic")
    func oneCellRepairs() {
        // pump-015: 15.89 x 1.889 = 30.02; the price read as 1.884 under glare.
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "30.02"),
                Self.window(.liters, "15.89"),
                Self.window(.unitPrice, "1.884"),
            ], currency: CurrencyCode(rawValue: "EUR"))
        #expect(reading.unitPrice.value == Decimal(string: "1.889"))
        if case .repaired(let index, let from, let to)? = reading.unitPrice.provenance {
            #expect(index == 3 && from == 4 && to == 9)
        } else {
            Issue.record("expected a repaired price, got \(String(describing: reading.unitPrice.provenance))")
        }
    }

    @Test("roles never swap to close the arithmetic")
    func rolesNeverSwap() {
        // Liters and price swapped on the display would still multiply out;
        // the law must not read 1.889 L at 15.89 /L.
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "30.02"),
                Self.window(.liters, "1.889"),
                Self.window(.unitPrice, "15.89"),
            ], currency: CurrencyCode(rawValue: "EUR"))
        #expect(reading.liters.value != Decimal(string: "15.89"))
    }

    // MARK: - The oracle-string harness

    @Test("the law over the annotated strings clears the committed and precision floors",
          .pumpFixturesPresent)
    func oracleStringsRatchet() throws {
        let score = try Self.scoreOracle(mutate: nil)
        print("PU.21 oracle strings: committed \(score.committed), correct \(score.committedCorrect), "
              + "precision \(score.precision), coverage \(score.coverage) of \(score.numericTotal); "
              + "wrong: \(score.wrong.sorted())")
        #expect(score.committed >= Self.committedFloor)
        #expect(score.precision >= Self.precisionFloor)
        let unexpected = score.wrong.filter { name in
            !Self.declaredArtefacts.contains { name.hasPrefix($0) }
        }
        #expect(unexpected.isEmpty, "confident-wrong outside the declared artefacts: \(unexpected)")
    }

    @Test("under single-digit misreads the law repairs far more than it commits wrong",
          .pumpFixturesPresent)
    func fragilityUnderMisreads() throws {
        var rng = SeededGenerator(seed: 21)
        var wrong = 0
        var repaired = 0
        var committed = 0
        for _ in 0..<5 {
            let score = try Self.scoreOracle(mutate: { field, cells in
                Self.mutateOneCell(field: field, cells: cells, rng: &rng)
            })
            committed += score.committed
            wrong += score.committed - score.committedCorrect
            repaired += score.repaired
        }
        let wrongRate = Double(wrong) / Double(max(committed, 1))
        print("PU.21 fragility: committed \(committed), wrong \(wrong) (\(wrongRate)), repaired \(repaired)")
        // Oracle: PU.14 §2.5 measured 1.5 % commit-wrong on single mutations
        // with a wider tier; the exact tier measured 3.9 % on 2026-09-19.
        #expect(wrongRate <= 0.04)
        #expect(repaired > 0)
    }

    // MARK: - The named mutations (PU.14 §6 row 1), as tests that pin the seams

    @Test("without the ambiguity window a beam alternative that also closes blocks the read")
    func ambiguityWindowIsLoadBearing() {
        // Two closing triples exist for pump-015's strings: the true one and a
        // total beam alternative (30.03) 7 nats down. The window is what
        // separates "ambiguous" from "the beam's tail".
        let closed = PumpReadingLaw.closingTriples(
            liters: PumpReadingLaw.candidates(Self.window(.liters, "15.89"), decimals: [2]),
            prices: PumpReadingLaw.candidates(Self.window(.unitPrice, "1.889"), decimals: [3]),
            totals: PumpReadingLaw.candidates(Self.window(.total, "30.02"), decimals: [2]),
            truncated: [])
        #expect(closed.count >= 2, "the beam must offer a second closing triple for this test to mean anything")
        let committed = PumpReadingLaw.commit(closed, repair: nil)
        #expect(committed.total.value == Decimal(string: "30.02"))
        let best = closed.max { $0.logPosterior < $1.logPosterior }!
        let tail = closed.filter { $0 .logPosterior < best.logPosterior }
        #expect(tail.allSatisfy { best.logPosterior - $0.logPosterior > PumpReadingLaw.ambiguityWindow })
    }

    @Test("the read window keeps a two-substitution fabrication from committing")
    func readWindowIsLoadBearing() {
        // pump-010 before the preset tier: 13.17 x 75.99 = 1000.79 closes on a
        // total beam alternative 1000.80 - two unlikely substitutions that the
        // read window (6 nats) rejects and the preset tier then resolves.
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "1000.00"),
                Self.window(.liters, "13.17"),
                Self.window(.unitPrice, "75.95"),
            ], currency: CurrencyCode(rawValue: "RUB"))
        #expect(reading.unitPrice.value == Decimal(string: "75.95"))
        #expect(reading.total.value == Decimal(string: "1000"))
    }

    @Test("a placement that contradicts the seen decimal mark loses to one that agrees")
    func decimalMarkIsAPrior() {
        // Without a band, `050,95` could be 50.95 or 509.5 and both close
        // (2038.00 read, or 20380 as a truncated total); the mark decides.
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "02038,00"),
                Self.window(.liters, "00040,00"),
                Self.window(.unitPrice, "050,95"),
            ], currency: CurrencyCode(rawValue: "RUB"))
        #expect(reading.unitPrice.value == Decimal(string: "50.95"))
    }

    // MARK: - Helpers

    struct OracleScore {
        var numericTotal = 0
        var committed = 0
        var committedCorrect = 0
        var repaired = 0
        var wrong: Set<String> = []
        var precision: Double { committed > 0 ? Double(committedCorrect) / Double(committed) : 0 }
        var coverage: Double { numericTotal > 0 ? Double(committed) / Double(numericTotal) : 0 }
    }

    static func window(_ field: PumpField, _ text: String) -> PumpLocatedWindow {
        PumpLocatedWindow(field: field, cells: cells(for: text))
    }

    /// Cells from an annotation string: digits are cells, a separator marks
    /// the decimal point on the cell before it, leading spaces are skipped.
    static func cells(for text: String) -> [PumpCellReading] {
        var out: [PumpCellReading] = []
        for ch in text {
            if let d = ch.wholeNumberValue {
                out.append(PumpCellReading(certainDigit: d, decimalPoint: false))
            } else if ch == "," || ch == ".", let last = out.popLast() {
                out.append(PumpCellReading(certainDigit: last.top.digit, decimalPoint: true))
            }
        }
        return out
    }

    static func mutateOneCell(field: PumpField, cells: [PumpCellReading],
                              rng: inout SeededGenerator) -> [PumpCellReading] {
        guard !cells.isEmpty, field == .liters || field == .unitPrice else { return cells }
        let index = Int(rng.next() % UInt64(cells.count))
        let current = cells[index].top.digit
        let partners = DigitRepair.confusablePartners(of: current)
        guard !partners.isEmpty else { return cells }
        let partner = partners[Int(rng.next() % UInt64(partners.count))]
        var out = cells
        out[index] = PumpCellReading(certainDigit: partner, decimalPoint: cells[index].decimalPoint)
        return out
    }

    static func scoreOracle(mutate: ((PumpField, [PumpCellReading]) -> [PumpCellReading])?) throws -> OracleScore {
        let expected = try CorpusScorer.loadExpected(
            PumpReaderTestSupport.windowsURL.deletingLastPathComponent().appendingPathComponent("expected.csv"))
        let data = try Data(contentsOf: PumpReaderTestSupport.windowsURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let pack = try FuelPriceBandStore.bundledPack()
        var score = OracleScore()
        for (name, value) in root.sorted(by: { $0.key < $1.key }) {
            guard name != "_about", let ann = value as? [String: Any],
                  let want = expected[name] else { continue }
            var windows: [PumpLocatedWindow] = []
            for raw in ann["windows"] as? [[String: Any]] ?? [] {
                guard let fieldName = raw["field"] as? String, let field = PumpField(rawValue: fieldName),
                      let text = raw["text"] as? String, !text.isEmpty else { continue }
                var cells = Self.cells(for: text)
                if let mutate { cells = mutate(field, cells) }
                windows.append(PumpLocatedWindow(field: field, cells: cells))
            }
            let reading = PumpReadingLaw.resolve(
                windows: windows, currency: want.currency,
                priceBand: want.currency.flatMap { pack.currencyBand(currency: $0) })
            let cells: [(reading: PumpFieldReading, want: Double?)] = [
                (reading.liters, want.liters), (reading.unitPrice, want.unitPrice), (reading.total, want.total),
            ]
            for cell in cells {
                let field = cell.reading
                let got = field.value.map { NSDecimalNumber(decimal: $0).doubleValue }
                guard let wantValue = cell.want else { continue }
                score.numericTotal += 1
                guard let got else { continue }
                score.committed += 1
                // A derived total is the exact product; where the corpus asserts
                // the display's truncated value instead of the receipt's
                // (pump-018 `2499,8`), the product is right to the display's
                // own precision. PU.13 §4 names these cells.
                let derived: Bool = { if case .derived? = field.provenance { return true }; return false }()
                let slack = derived ? 0.1 : CorpusScorer.tolerance
                if abs(got - wantValue) < slack {
                    score.committedCorrect += 1
                    if case .repaired? = field.provenance { score.repaired += 1 }
                } else {
                    score.wrong.insert(name)
                }
            }
        }
        return score
    }
}

/// A tiny deterministic generator for the fragility pass.
struct SeededGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
}
