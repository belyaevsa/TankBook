import Foundation
import Testing
@testable import TankbookCore

/// PU.22: the real pixels through slicer, classifier and law, on the annotated
/// windows, scored exactly as the ship gate scores the rules parser - committed
/// cells, precision, coverage over `expected.csv`. The locator is kept out
/// (annotated quads), so this is the reader-arm number the gate needs.
@Suite("PU.22 pump reader on real cells")
struct PumpReaderPipelineTests {

    private struct ScoredCell {
        let field: PumpField
        let reading: PumpFieldReading
        let want: Double?
    }

    // Measured on the heldout split (decision 9; 64 stills, 175 cells) on
    // 2026-09-20 with the round-6 classifier (synthetic + real glyphs from the
    // train split): committed 44 at 0.955, 12/64 photos every field right;
    // the shipped synthetic-only model read 18 at 0.944, 4/64. The constants
    // move only upward.
    // 52 at 0.962, 14/64 photos, once the slicer preferred the fundamental
    // pitch; 66 at 0.970, 18/64, once it checked the pitch against the glyph
    // body (PU.4 round of 2026-09-20).
    private static let committedFloor = 104
    private static let precisionFloor = 0.96
    // The live path (no annotation): measured on the heldout split on
    // 2026-09-20 after PU.24's verifier round - every candidate verified, a
    // height floor, the frame's edge and a per-cell aspect rule, the margin
    // at 1.0 and duplicate rows suppressed: committed 7, all correct
    // (0 the day before); 4 once the slicer preferred the fundamental pitch,
    // which lifted the annotated path 44 -> 52; 11 with the pitch-to-body
    // check (annotated 66); 22 with the learned row detector as the locator's
    // first source and the verifier keeping detected rows on count and size
    // alone (PU.33); 23 with PU.34's law arbitration, which stops a slack-only
    // operand close from making an exact read abstain. Moves only upward; a run
    // without the detector file (ml/pump-reader/.out/det/DigitRows.mlmodel)
    // falls back to Vision and reads 11 - the floor assumes the detector is
    // present.
    private static let liveCommittedFloor = PumpReaderTestSupport.detectorURL == nil ? 11 : 43
    private static let livePrecisionFloor = 0.99

    /// The make a fixture's file name names, for the per-head read table. The
    /// prefixes are the corpus's own naming; anything else is `other`.
    static func head(_ name: String) -> String {
        for make in ["wayne", "gilbarco", "tokheim", "scheidt", "tatsuno"] where name.contains(make) {
            return make
        }
        return "other"
    }

    /// The shipped classifier, or a candidate under `PUMP_MODEL=<path>` so a
    /// retrain can be scored on the heldout split before it is copied into the bundle.
    private static let modelURL = ProcessInfo.processInfo.environment["PUMP_MODEL"].map { URL(fileURLWithPath: $0) }
        ?? PumpReaderTestSupport.repoRoot.appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")

    @Test("the live path: locate, verify, assign, read, resolve - no annotation used", .pumpFixturesPresent)
    func livePath() throws {
        let model = try PumpSegmentsModel(contentsOf: Self.modelURL)
        let reader = PumpReader(model: model, detector: PumpReaderTestSupport.makeDetector())
        let expected = try CorpusScorer.loadExpected(
            PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent("expected.csv"))
        let data = try Data(contentsOf: PumpReaderTestSupport.windowsURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let pack = try FuelPriceBandStore.bundledPack()
        var numericTotal = 0, committed = 0, committedCorrect = 0
        var fixturesAllRight = 0, fixturesScored = 0
        var wrong: [String] = []
        var perHead: [String: (committed: Int, correct: Int)] = [:]
        let start = Date()
        for (name, value) in root.sorted(by: { $0.key < $1.key }) {
            guard name != "_about", let ann = value as? [String: Any], let want = expected[name],
                  PumpReaderTestSupport.isHeldout(name) else { continue }
            guard let image = PumpReaderTestSupport.loadRGB(
                url: PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)) else { continue }
            // The only annotation the live path takes is the photo's rotation,
            // which the app's capture gives it for free (the phone is upright).
            let rotation = (ann["rotationCW"] as? NSNumber)?.intValue ?? 0
            let reading = try reader.readPhoto(
                image: image, rotationCW: rotation, currency: want.currency,
                priceBand: want.currency.flatMap { pack.currencyBand(currency: $0) })
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
            var fixtureTotal = 0, fixtureRight = 0
            let head = Self.head(name)
            for cell in cells {
                guard let wantValue = cell.want else { continue }
                numericTotal += 1; fixtureTotal += 1
                guard let got = cell.reading.value.map({ NSDecimalNumber(decimal: $0).doubleValue }) else { continue }
                committed += 1
                perHead[head, default: (0, 0)].committed += 1
                let derived: Bool = { if case .derived? = cell.reading.provenance { return true }; return false }()
                if abs(got - wantValue) < (derived ? 0.1 : CorpusScorer.tolerance) {
                    committedCorrect += 1; fixtureRight += 1
                    perHead[head]!.correct += 1
                } else {
                    wrong.append("\(name.prefix(8)) \(cell.field.rawValue) got \(got) want \(wantValue)")
                }
            }
            if fixtureTotal > 0 { fixturesScored += 1; if fixtureRight == fixtureTotal { fixturesAllRight += 1 } }
        }
        let precision = committed > 0 ? Double(committedCorrect) / Double(committed) : 0
        print("PU.24 live path: committed \(committed), correct \(committedCorrect), "
              + "precision \(String(format: "%.3f", precision)), coverage \(String(format: "%.3f", Double(committed) / Double(max(numericTotal, 1)))) "
              + "of \(numericTotal); photos with every field right \(fixturesAllRight)/\(fixturesScored); "
              + "\(String(format: "%.1f", Date().timeIntervalSince(start)))s")
        for (head, score) in perHead.sorted(by: { $0.key < $1.key }) {
            print("  \(head): \(score.committed) committed, \(score.correct) correct")
        }
        for line in wrong { print("  WRONG \(line)") }
        #expect(committed >= Self.liveCommittedFloor)
        #expect(precision >= Self.livePrecisionFloor)
    }

    @Test("the reader over the annotated windows: committed cells, precision, coverage", .pumpFixturesPresent)
    func gateMirror() throws {
        let model = try PumpSegmentsModel(contentsOf: Self.modelURL)
        let reader = PumpReader(model: model, detector: PumpReaderTestSupport.makeDetector())
        let expected = try CorpusScorer.loadExpected(
            PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent("expected.csv"))
        let data = try Data(contentsOf: PumpReaderTestSupport.windowsURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let pack = try FuelPriceBandStore.bundledPack()

        var numericTotal = 0
        var committed = 0
        var committedCorrect = 0
        var wrong: [String] = []
        var perField: [PumpField: (ok: Int, committed: Int, total: Int)] = [:]
        var fixturesAllRight = 0
        var fixturesScored = 0
        let start = Date()

        for (name, value) in root.sorted(by: { $0.key < $1.key }) {
            guard name != "_about", let ann = value as? [String: Any], let want = expected[name],
                  PumpReaderTestSupport.isHeldout(name) else { continue }
            let url = PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)
            guard let image = PumpReaderTestSupport.loadRGB(url: url) else {
                Issue.record("cannot load \(name)")
                continue
            }
            let rotation = (ann["rotationCW"] as? NSNumber)?.intValue ?? 0
            var windows: [PumpReader.Window] = []
            for raw in ann["windows"] as? [[String: Any]] ?? [] {
                guard let fieldName = raw["field"] as? String, let field = PumpField(rawValue: fieldName),
                      let text = raw["text"] as? String, !text.isEmpty,
                      let quad = raw["quad"] as? [[Double]] else { continue }
                let pixels = PumpQuadWarp.readingOrder(
                    PumpReaderTestSupport.quadPixels(quad, width: image.width, height: image.height),
                    rotationCW: rotation)
                windows.append(PumpReader.Window(field: field, quad: pixels))
            }
            let reading = try reader.resolve(
                image: image, windows: windows, currency: want.currency,
                priceBand: want.currency.flatMap { pack.currencyBand(currency: $0) })

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
            var fixtureTotal = 0
            var fixtureRight = 0
            for cell in cells {
                let field = cell.field
                let got = cell.reading.value.map { NSDecimalNumber(decimal: $0).doubleValue }
                let provenance = cell.reading.provenance
                guard let wantValue = cell.want else { continue }
                numericTotal += 1
                fixtureTotal += 1
                perField[field, default: (0, 0, 0)].total += 1
                guard let got else { continue }
                committed += 1
                perField[field]!.committed += 1
                let derived: Bool = { if case .derived? = provenance { return true }; return false }()
                if abs(got - wantValue) < (derived ? 0.1 : CorpusScorer.tolerance) {
                    committedCorrect += 1
                    fixtureRight += 1
                    perField[field]!.ok += 1
                } else {
                    wrong.append("\(name.prefix(8)) \(field.rawValue) got \(got) want \(wantValue)")
                }
            }
            if fixtureTotal > 0 {
                fixturesScored += 1
                if fixtureRight == fixtureTotal { fixturesAllRight += 1 }
            }
        }
        let precision = committed > 0 ? Double(committedCorrect) / Double(committed) : 0
        let coverage = Double(committed) / Double(max(numericTotal, 1))
        print("PU.22 reader on real cells: committed \(committed), correct \(committedCorrect), "
              + "precision \(String(format: "%.3f", precision)), coverage \(String(format: "%.3f", coverage)) "
              + "of \(numericTotal); photos with every field right \(fixturesAllRight)/\(fixturesScored); "
              + "\(String(format: "%.1f", Date().timeIntervalSince(start)))s")
        for (field, s) in perField.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("  \(field.rawValue): \(s.ok)/\(s.committed) committed right, \(s.total) asserted")
        }
        for line in wrong { print("  WRONG \(line)") }
        // The heldout cells asserted (liters, price, total over the 64 stills);
        // a corpus fact, read off the split and the CSV, not pinned here.
        #expect(numericTotal > 100)
        #expect(committed >= Self.committedFloor)
        #expect(precision >= Self.precisionFloor)
    }

    // MARK: - Fusion over a record's frames

    private struct FusionScore {
        var committed = 0
        var correct = 0
        var asserted = 0
        var photosRight = 0
        var photosScored = 0
        var seconds = 0.0

        var precision: Double { committed > 0 ? Double(correct) / Double(committed) : 0 }

        mutating func add(_ other: FusionScore) {
            committed += other.committed
            correct += other.correct
            asserted += other.asserted
            photosRight += other.photosRight
            photosScored += other.photosScored
            seconds += other.seconds
        }
    }

    private func score(_ reading: PumpDisplayReading, want: ExpectedRow) -> FusionScore {
        var result = FusionScore()
        func count(_ cell: PumpFieldReading, _ wantValue: Double?) {
            guard let wantValue else { return }
            result.asserted += 1
            guard let got = cell.value.map({ NSDecimalNumber(decimal: $0).doubleValue }) else { return }
            result.committed += 1
            let derived: Bool = { if case .derived? = cell.provenance { return true }; return false }()
            if abs(got - wantValue) < (derived ? 0.1 : CorpusScorer.tolerance) { result.correct += 1 }
        }
        count(reading.liters, want.liters)
        count(reading.unitPrice, want.unitPrice)
        count(reading.total, want.total)
        if result.asserted > 0 {
            result.photosScored = 1
            if result.correct == result.asserted { result.photosRight = 1 }
        }
        return result
    }

    /// The value a field committed, for the per-photo flip log.
    private func value(_ reading: PumpFieldReading) -> Double? {
        reading.value.map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    private struct FusionMeasurement {
        var still = FusionScore()
        var allFrames = FusionScore()
        var fifthFrame = FusionScore()
        var pixels = FusionScore()
        var flips: [String] = []
    }

    private func measureFusion(reader: PumpReader, records: [PumpReaderTestSupport.PumpLiveRecord],
                               root: [String: Any], expected: [String: ExpectedRow],
                               pack: FuelPriceBandPack) throws -> FusionMeasurement {
        func band(_ currency: CurrencyCode?) -> FuelPriceBand? {
            currency.flatMap { pack.currencyBand(currency: $0) }
        }
        var measurement = FusionMeasurement()
        for record in records {
            guard let ann = root[record.still] as? [String: Any], let want = expected[record.still] else { continue }
            let url = PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(record.still)
            guard let image = PumpReaderTestSupport.loadRGB(url: url) else {
                Issue.record("cannot load \(record.still)")
                continue
            }
            let windows = PumpReaderTestSupport.annotatedWindows(ann, image: image)

            var start = Date()
            let stillReading = try reader.resolve(image: image, windows: windows,
                currency: want.currency, priceBand: band(want.currency))
            measurement.still.seconds += Date().timeIntervalSince(start)

            start = Date()
            let allReading = try reader.resolveFused(still: image, windows: windows,
                frames: PumpReaderTestSupport.trackedFrames(for: record), stride: 1,
                mode: .probabilities, currency: want.currency, priceBand: band(want.currency))
            measurement.allFrames.seconds += Date().timeIntervalSince(start)

            start = Date()
            let fifthReading = try reader.resolveFused(still: image, windows: windows,
                frames: PumpReaderTestSupport.trackedFrames(for: record, step: 5), stride: 1,
                mode: .probabilities, currency: want.currency, priceBand: band(want.currency))
            measurement.fifthFrame.seconds += Date().timeIntervalSince(start)

            start = Date()
            let pixelReading = try reader.resolveFused(still: image, windows: windows,
                frames: PumpReaderTestSupport.trackedFrames(for: record, step: 5), stride: 1,
                mode: .pixels, currency: want.currency, priceBand: band(want.currency))
            measurement.pixels.seconds += Date().timeIntervalSince(start)

            measurement.still.add(score(stillReading, want: want))
            measurement.allFrames.add(score(allReading, want: want))
            measurement.fifthFrame.add(score(fifthReading, want: want))
            measurement.pixels.add(score(pixelReading, want: want))

            let stillCells = [stillReading.liters, stillReading.unitPrice, stillReading.total]
            let fusedCells = [allReading.liters, allReading.unitPrice, allReading.total]
            let fields: [PumpField] = [.liters, .unitPrice, .total]
            for index in fields.indices where value(stillCells[index]) != value(fusedCells[index]) {
                let sv = value(stillCells[index]).map { String($0) } ?? "nil"
                let fv = value(fusedCells[index]).map { String($0) } ?? "nil"
                measurement.flips.append("\(record.id) \(record.still.prefix(8)) \(fields[index].rawValue): "
                                          + "still \(sv) -> fused \(fv)")
            }
        }
        return measurement
    }

    /// The still alone, the same read fused over the record's tracked frames,
    /// and fused over every fifth frame, on the 17 heldout stills with a
    /// tracked record. A frame whose slicer finds a different cell count than
    /// the still is skipped whole, so a fusion that never agrees with the
    /// still returns the still's own reading.
    /// Opt-in (`PUMP_FUSION=1`): the all-frames pass reads 860 frames and takes
    /// 17 minutes; it is a measurement, not a floor.
    @Test("PU.19 fusion: still alone, all tracked frames, every fifth frame", .pumpFixturesPresent,
          .enabled(if: ProcessInfo.processInfo.environment["PUMP_FUSION"] == "1", "PUMP_FUSION=1"))
    func liveFusion() throws {
        let model = try PumpSegmentsModel(contentsOf: Self.modelURL)
        let reader = PumpReader(model: model)
        let expected = try CorpusScorer.loadExpected(
            PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent("expected.csv"))
        let data = try Data(contentsOf: PumpReaderTestSupport.windowsURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let pack = try FuelPriceBandStore.bundledPack()
        let records = PumpReaderTestSupport.heldoutLiveRecords()
        print("PU.19 heldout records with a tracked Live record: \(records.count)")

        let measurement = try measureFusion(reader: reader, records: records, root: root,
                                            expected: expected, pack: pack)
        func report(_ label: String, _ totals: FusionScore) {
            print("PU.19 \(label): committed \(totals.committed), correct \(totals.correct), "
                  + "precision \(String(format: "%.3f", totals.precision)), "
                  + "photos with every field right \(totals.photosRight)/\(totals.photosScored); "
                  + "\(String(format: "%.1f", totals.seconds))s")
        }
        report("still only", measurement.still)
        report("fused, all frames (probabilities)", measurement.allFrames)
        report("fused, every 5th frame (probabilities)", measurement.fifthFrame)
        report("fused, every 5th frame (pixels)", measurement.pixels)
        for line in measurement.flips { print("  FLIP \(line)") }
    }
}
