import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// The row-level sequence reader's offline harness (`ml/pump-reader/src/pump_reader/rowreader.py`).
/// Two opt-in modes:
/// - `PUMP_ROWREADER=export` writes every heldout window with text as the 96 px strip the reader
///   warps (`PumpQuadWarp.warpToStrip`, the hand quad in reading order) plus the CURRENT arm's
///   string for it - `PumpReader.read` on that window alone, top digit per cell and its mark - so
///   both readers are scored on the same pixels.
/// - `PUMP_ROWREADER=law` with `PUMP_ROWREADER_POSTERIORS=<json>` builds each window's cells from
///   the sequence reader's per-position posteriors and scores `PumpReadingLaw` exactly as
///   `PumpReaderPipelineTests.gateMirror` scores the shipped reader.
@Suite("PU.77 spike: the row reader's heldout harness")
struct PumpRowReaderSpikeTests {
    private static let mode = ProcessInfo.processInfo.environment["PUMP_ROWREADER"] ?? ""
    /// `PUMP_ROWREADER_SPLIT=heldout2` scores the second frozen draw, once, at the go/no-go.
    private static let split = ProcessInfo.processInfo.environment["PUMP_ROWREADER_SPLIT"] ?? "heldout"
    private static let outDir = PumpReaderTestSupport.outRoot.appendingPathComponent("rowreader/\(split)")
    private static let modelURL = PumpReaderTestSupport.repoRoot
        .appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")

    private struct Held {
        let name: String
        let ann: [String: Any]
        let want: ExpectedRow
        let image: PumpRGBImage
        let windows: [(index: Int, window: PumpReader.Window, text: String)]
    }

    private static func heldout() throws -> [Held] {
        let expected = try CorpusScorer.loadExpected(
            PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent("expected.csv"))
        let root = try JSONSerialization.jsonObject(
            with: Data(contentsOf: PumpReaderTestSupport.windowsURL)) as? [String: Any] ?? [:]
        var out: [Held] = []
        for (name, value) in root.sorted(by: { $0.key < $1.key }) {
            guard name != "_about", let ann = value as? [String: Any], let want = expected[name],
                  split == "heldout" ? PumpReaderTestSupport.isHeldout(name)
                      : PumpReaderTestSupport.splitOf(name) == split,
                  let image = PumpReaderTestSupport.loadRGB(
                    url: PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)) else { continue }
            let rotation = (ann["rotationCW"] as? NSNumber)?.intValue ?? 0
            var windows: [(Int, PumpReader.Window, String)] = []
            for (index, raw) in (ann["windows"] as? [[String: Any]] ?? []).enumerated() {
                guard let fieldName = raw["field"] as? String, let field = PumpField(rawValue: fieldName),
                      let text = raw["text"] as? String, !text.isEmpty,
                      let quad = raw["quad"] as? [[Double]] else { continue }
                let pixels = PumpQuadWarp.readingOrder(
                    PumpReaderTestSupport.quadPixels(quad, width: image.width, height: image.height),
                    rotationCW: rotation)
                windows.append((index, PumpReader.Window(field: field, quad: pixels), text))
            }
            out.append(Held(name: name, ann: ann, want: want, image: image, windows: windows))
        }
        return out
    }

    private static func string(_ cells: [PumpCellReading]) -> String {
        cells.map { "\($0.top.digit)" + ($0.decimalPoint ? "." : "") }.joined()
    }

    @Test("export: heldout strips and the current reader's string for each",
          .enabled(if: mode == "export" && PumpReaderTestSupport.fixturesPresent, "PUMP_ROWREADER=export"))
    func export() throws {
        let reader = PumpReader(model: try PumpSegmentsModel(contentsOf: Self.modelURL))
        let strips = Self.outDir.appendingPathComponent("strips")
        try FileManager.default.createDirectory(at: strips, withIntermediateDirectories: true)
        var index: [[String: Any]] = []
        for held in try Self.heldout() {
            for (windowIndex, window, text) in held.windows {
                guard let strip = PumpQuadWarp.warpToStrip(rgb: held.image, quad: window.quad,
                                                           stripHeight: PumpReader.stripHeight) else { continue }
                let file = "\(held.name.split(separator: ".").first ?? "x")-\(windowIndex).png"
                _ = PumpQuadWarp.writePNG(image: strip, to: strips.appendingPathComponent(file))
                let current = try reader.read(image: held.image, windows: [window]).first
                index.append(["fixture": held.name, "window": windowIndex, "field": window.field.rawValue,
                              "text": text, "strip": "strips/\(file)",
                              "current": current.map { Self.string($0.cells) } ?? NSNull()])
            }
        }
        try JSONSerialization.data(withJSONObject: index, options: [.prettyPrinted, .sortedKeys])
            .write(to: Self.outDir.appendingPathComponent("index.json"))
        print("PU.77 heldout strips: \(index.count) windows written to \(Self.outDir.path)")
        #expect(index.count > (Self.split == "heldout" ? 200 : 0))
    }

    @Test("law: the sequence reader's posteriors through the law, scored as gateMirror scores",
          .enabled(if: mode == "law" && PumpReaderTestSupport.fixturesPresent, "PUMP_ROWREADER=law"))
    func law() throws {
        let path = try #require(ProcessInfo.processInfo.environment["PUMP_ROWREADER_POSTERIORS"])
        let posteriors = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: path))) as? [[String: Any]] ?? []
        var byWindow: [String: [PumpCellReading]] = [:]
        for entry in posteriors {
            guard let fixture = entry["fixture"] as? String, let window = entry["window"] as? Int,
                  let positions = entry["positions"] as? [[[String: Any]]],
                  let sep = entry["sep"] as? [Double] else { continue }
            byWindow["\(fixture)#\(window)"] = positions.enumerated().map { i, ranked in
                PumpCellReading(probabilities: [], ranked: ranked.compactMap { c in
                    guard let d = c["digit"] as? Int, let lp = c["logp"] as? Double else { return nil }
                    return PumpGlyphCandidate(digit: d, logPosterior: lp)
                }, decimalPoint: i < sep.count && sep[i] >= 0.5)
            }
        }
        let pack = try FuelPriceBandStore.bundledPack()
        var total = 0, committed = 0, correct = 0, photosRight = 0, photos = 0
        var wrong: [String] = []
        for held in try Self.heldout() {
            let windows = held.windows.compactMap { index, window, _ in
                byWindow["\(held.name)#\(index)"].map { PumpLocatedWindow(field: window.field, cells: $0) }
            }
            let reading = PumpReadingLaw.resolve(
                windows: windows, currency: held.want.currency,
                priceBand: held.want.currency.flatMap { pack.currencyBand(currency: $0) })
            let disagrees = Set((held.ann["csvDisagrees"] as? [String: Any])?.keys.map { $0 } ?? [])
            var asserted = 0, right = 0
            for (field, cell, want) in [(PumpField.liters, reading.liters, held.want.liters),
                                        (.unitPrice, reading.unitPrice, held.want.unitPrice),
                                        (.total, reading.total, held.want.total)] {
                guard let wantValue = disagrees.contains(field.rawValue) ? nil : want else { continue }
                total += 1
                asserted += 1
                guard let got = cell.value.map({ NSDecimalNumber(decimal: $0).doubleValue }) else { continue }
                committed += 1
                let derived: Bool = { if case .derived? = cell.provenance { return true }; return false }()
                if abs(got - wantValue) < (derived ? 0.1 : CorpusScorer.tolerance) {
                    correct += 1
                    right += 1
                } else {
                    wrong.append("\(held.name.prefix(8)) \(field.rawValue) got \(got) want \(wantValue)")
                }
            }
            if asserted > 0 {
                photos += 1
                if right == asserted { photosRight += 1 }
            }
        }
        let precision = committed > 0 ? Double(correct) / Double(committed) : 0
        print("PU.77 law over the row reader: committed \(committed), correct \(correct), precision "
              + "\(String(format: "%.3f", precision)) of \(total); photos with every field right \(photosRight)/\(photos)")
        print("  " + PumpPrecisionBounds.precisionLine(correct: correct, committed: committed))
        for line in wrong { print("  WRONG \(line)") }
        #expect(total > 100)
    }
}
