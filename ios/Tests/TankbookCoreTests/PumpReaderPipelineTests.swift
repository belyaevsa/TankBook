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
    private static let committedFloor = 66
    private static let precisionFloor = 0.96
    // The live path (no annotation): measured on the heldout split on
    // 2026-09-20 after PU.24's verifier round - every candidate verified, a
    // height floor, the frame's edge and a per-cell aspect rule, the margin
    // at 1.0 and duplicate rows suppressed: committed 7, all correct
    // (0 the day before); 4 once the slicer preferred the fundamental pitch,
    // which lifted the annotated path 44 -> 52; 11 with the pitch-to-body
    // check (annotated 66); 22 with the learned row detector as the locator's
    // first source and the verifier keeping detected rows on count and size
    // alone (PU.33). Moves only upward; a run without the detector file
    // (ml/pump-reader/.out/det/DigitRows.mlmodel) falls back to Vision and
    // reads 11 - the floor assumes the detector is present.
    private static let liveCommittedFloor = PumpReaderTestSupport.detectorURL == nil ? 11 : 22
    private static let livePrecisionFloor = 0.99

    private static let modelURL = PumpReaderTestSupport.repoRoot
        .appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")

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
            let cells: [ScoredCell] = [
                ScoredCell(field: .liters, reading: reading.liters, want: want.liters),
                ScoredCell(field: .unitPrice, reading: reading.unitPrice, want: want.unitPrice),
                ScoredCell(field: .total, reading: reading.total, want: want.total),
            ]
            var fixtureTotal = 0, fixtureRight = 0
            for cell in cells {
                guard let wantValue = cell.want else { continue }
                numericTotal += 1; fixtureTotal += 1
                guard let got = cell.reading.value.map({ NSDecimalNumber(decimal: $0).doubleValue }) else { continue }
                committed += 1
                let derived: Bool = { if case .derived? = cell.reading.provenance { return true }; return false }()
                if abs(got - wantValue) < (derived ? 0.1 : CorpusScorer.tolerance) {
                    committedCorrect += 1; fixtureRight += 1
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

            let cells: [ScoredCell] = [
                ScoredCell(field: .liters, reading: reading.liters, want: want.liters),
                ScoredCell(field: .unitPrice, reading: reading.unitPrice, want: want.unitPrice),
                ScoredCell(field: .total, reading: reading.total, want: want.total),
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
}
