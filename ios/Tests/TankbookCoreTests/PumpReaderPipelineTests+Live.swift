import Foundation
import Testing
@testable import TankbookCore

// MARK: - PU.53 live measurement

extension PumpReaderPipelineTests {

    struct LiveMeasurement {
        var numericTotal = 0
        var committed = 0
        var committedCorrect = 0
        var fixturesAllRight = 0
        var fixturesScored = 0
        var abstainedStills = 0
        var stillReasons: [PumpAbstentionReason: Int] = [:]
        var fieldReasons: [PumpAbstentionReason: Int] = [:]
        var wrong: [String] = []
        /// Wrong committed cells that reached the reading WITHOUT a caution -
        /// the silent kind. A cautioned wrong cell (`shownPriceDiffers`, the
        /// pair tier's shown-price band) arrives on Confirm flagged.
        var wrongUncautioned = 0
        /// Cells nothing closed on whose unclosed top read went to the form
        /// under the don't-multiply-up warning, and how many of those were right.
        var warned = 0
        var warnedCorrect = 0
        var perHead: [String: (committed: Int, correct: Int)] = [:]
        var seconds = 0.0
        /// Photos that committed at least one scored cell, and of those the
        /// ones with any wrong cell - the per-photo loss the certificate uses
        /// (the law commits a photo's cells together, so the photo is the
        /// exchangeable unit, `agents/research/PU.68.md` §5.3).
        var photosCommitting = 0
        var photosWrong = 0
        /// The sum over committing photos of wrong / committed cells.
        var fractionalLoss = 0.0
        /// One row per scored still, for `PumpLiveLedger`.
        var ledgerStills: [PumpLiveLedger.Still] = []

        var precision: Double { committed > 0 ? Double(committedCorrect) / Double(committed) : 0 }
    }

    /// One live arm over the heldout split: locate, verify, assign, read,
    /// resolve, scored exactly as the ship gate scores the rules parser. The
    /// only difference between arms is the rotation `rotation` resolves for
    /// each still; the shipped arm returns nil, which makes the reader search.
    func measureLive(reader: PumpReader, root: [String: Any], expected: [String: ExpectedRow],
                     pack: FuelPriceBandPack, appPath: Bool = false,
                     includes: (String) -> Bool = PumpReaderTestSupport.isHeldout,
                     rotation: ([String: Any]) -> Int?) throws -> LiveMeasurement {
        var m = LiveMeasurement()
        let start = Date()
        for (name, value) in root.sorted(by: { $0.key < $1.key }) {
            guard name != "_about", let ann = value as? [String: Any], let want = expected[name],
                  includes(name) else { continue }
            guard let image = PumpReaderTestSupport.loadRGB(
                url: PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)) else { continue }
            let band = want.currency.flatMap { pack.currencyBand(currency: $0) }
            // The app's path is `classify`: the display decision first, then the
            // read (PU.63). A frame it refuses as a display reads as nothing.
            // The no-budget overload keeps a Debug run deterministic: the
            // Release verifier finishes inside the 1.5 s cap on a phone.
            let reading: PumpDisplayReading
            var notADisplay = false
            if appPath {
                guard let cg = PumpQuadWarp.makeImage(image.pixels, width: image.width, height: image.height) else {
                    continue
                }
                let decided = PumpDisplayCapture.classify(image: cg, reader: PumpReaderHandle(reader: reader),
                                                          currency: want.currency, priceBand: band, budget: .infinity,
                                                          rotationCW: 0).reading
                notADisplay = decided == nil
                reading = decided?.law ?? .abstained
            } else {
                reading = try reader.readPhoto(image: image, rotationCW: rotation(ann),
                                               currency: want.currency, priceBand: band)
            }
            // A field the annotation marks `csvDisagrees` is unscored: the CSV
            // carries the receipt's value where the display showed another
            // (pump-031's discounted total), and a reader that reads the
            // display is right, not wrong.
            let disagrees = Set((ann["csvDisagrees"] as? [String: Any])?.keys.map { $0 } ?? [])
            let cells: [ScoredCell] = [
                ScoredCell(field: .liters, reading: reading.liters, want: disagrees.contains("liters") ? nil : want.liters),
                ScoredCell(field: .unitPrice, reading: reading.unitPrice, want: disagrees.contains("unitPrice") ? nil : want.unitPrice),
                ScoredCell(field: .total, reading: reading.total, want: disagrees.contains("total") ? nil : want.total),
            ]
            for field in [reading.liters, reading.unitPrice, reading.total] where field.value == nil {
                if let reason = field.reason { m.fieldReasons[reason, default: 0] += 1 }
            }
            if reading.committedCount == 0 {
                m.abstainedStills += 1
                if let reason = reading.reason { m.stillReasons[reason, default: 0] += 1 }
            }
            var fixtureTotal = 0, fixtureRight = 0, fixtureCommitted = 0, fixtureWrong = 0
            let head = Self.head(name)
            var ledgerFields: [String: PumpLiveLedger.Field] = [:]
            for cell in cells {
                let gotValue = cell.reading.value.map { NSDecimalNumber(decimal: $0).doubleValue }
                var entry = PumpLiveLedger.Field(outcome: "unscored", got: gotValue, want: cell.want,
                                                 reason: cell.reading.reason?.rawValue,
                                                 warned: Self.warnedValue(reading.unclosed, cell.field))
                defer { ledgerFields[cell.field.rawValue] = entry }
                guard let wantValue = cell.want else { continue }
                m.numericTotal += 1; fixtureTotal += 1
                guard let got = gotValue else {
                    entry.outcome = "abstained"
                    Self.scoreWarned(&m, reading.unclosed, cell.field, want: wantValue)
                    continue
                }
                m.committed += 1; fixtureCommitted += 1
                m.perHead[head, default: (0, 0)].committed += 1
                let derived: Bool = { if case .derived? = cell.reading.provenance { return true }; return false }()
                if abs(got - wantValue) < (derived ? 0.1 : CorpusScorer.tolerance) {
                    entry.outcome = "right"
                    m.committedCorrect += 1; fixtureRight += 1
                    m.perHead[head]!.correct += 1
                } else {
                    entry.outcome = "wrong"
                    fixtureWrong += 1
                    if reading.caution == nil { m.wrongUncautioned += 1 }
                    m.wrong.append("\(name.prefix(8)) \(cell.field.rawValue) got \(got) want \(wantValue)"
                                   + (reading.caution == nil ? "" : " (cautioned)"))
                }
            }
            m.ledgerStills.append(PumpLiveLedger.Still(
                name: name, head: head, split: PumpReaderTestSupport.splitOf(name),
                reason: notADisplay ? "notADisplay" : (reading.committedCount == 0 ? reading.reason?.rawValue : nil),
                caution: PumpLiveLedger.cautionName(reading.caution), fields: ledgerFields))
            if fixtureTotal > 0 { m.fixturesScored += 1; if fixtureRight == fixtureTotal { m.fixturesAllRight += 1 } }
            if fixtureCommitted > 0 {
                m.photosCommitting += 1
                if fixtureWrong > 0 { m.photosWrong += 1 }
                m.fractionalLoss += Double(fixtureWrong) / Double(fixtureCommitted)
            }
        }
        m.seconds = Date().timeIntervalSince(start)
        return m
    }

    /// The unclosed top read of one field, the value the form gets under the warning.
    static func warnedValue(_ top: PumpUnclosedRead?, _ field: PumpField) -> Double? {
        let value: Decimal?
        switch field {
        case .liters: value = top?.liters
        case .unitPrice: value = top?.unitPrice
        case .total: value = top?.total
        case .board: value = nil
        }
        return value.map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    /// Scores an abstained cell's unclosed top read, the value the form got under the warning.
    static func scoreWarned(_ measurement: inout LiveMeasurement, _ top: PumpUnclosedRead?,
                            _ field: PumpField, want: Double) {
        guard let value = warnedValue(top, field) else { return }
        measurement.warned += 1
        if abs(value - want) < CorpusScorer.tolerance {
            measurement.warnedCorrect += 1
        }
    }

    func report(_ label: String, _ m: LiveMeasurement) {
        print("\(label): committed \(m.committed), correct \(m.committedCorrect), "
              + "precision \(String(format: "%.3f", m.precision)), "
              + "coverage \(String(format: "%.3f", Double(m.committed) / Double(max(m.numericTotal, 1)))) "
              + "of \(m.numericTotal); photos with every field right \(m.fixturesAllRight)/\(m.fixturesScored); "
              + "\(String(format: "%.1f", m.seconds))s")
        print("  " + PumpPrecisionBounds.precisionLine(correct: m.committedCorrect, committed: m.committed))
        print("  warned (unclosed top read, not committed): \(m.warnedCorrect)/\(m.warned) right")
        let photoLower = PumpPrecisionBounds.wilson(m.photosCommitting - m.photosWrong, m.photosCommitting,
                                                    z: PumpPrecisionBounds.z95OneSided).lower
        print("  photos: \(m.photosCommitting) committing, \(m.photosWrong) with a wrong cell; "
              + "one-sided 95% Wilson lower on photo precision \(String(format: "%.4f", photoLower))")
        for (head, score) in m.perHead.sorted(by: { $0.key < $1.key }) {
            print("  \(head): \(score.committed) committed, \(score.correct) correct")
        }
        print("\(label) reason histogram over \(m.abstainedStills) stills that commit nothing:")
        for (reason, count) in Self.histogram(m.stillReasons) { print("  \(reason.rawValue): \(count)") }
        print("\(label) field reason histogram over fields that abstained in a partial read:")
        for (reason, count) in Self.histogram(m.fieldReasons) { print("  \(reason.rawValue): \(count)") }
        for line in m.wrong { print("  WRONG \(line)") }
    }

    /// The per-photo ledger a model or reader change reports beside the
    /// scalar floor (`scripts/pump-live-diff.py`); its rows must add up to the
    /// numbers the run printed, or it describes another run.
    func writeLedger(_ measurement: LiveMeasurement) throws {
        let ledger = PumpLiveLedger(
            detector: PumpReaderTestSupport.detectorURL?.lastPathComponent,
            totals: .init(numericTotal: measurement.numericTotal, committed: measurement.committed,
                          committedCorrect: measurement.committedCorrect),
            stills: measurement.ledgerStills)
        #expect(ledger.recount == ledger.totals,
                "the ledger's rows add up to \(ledger.recount), the run to \(ledger.totals)")
        try ledger.write()
        print("live ledger: \(PumpLiveLedger.outputURL.path)")
    }
}
