import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// The two arms `CapturePipeline` composes for a pump photo, measured apart
/// and together over the frozen heldout split: the reader alone, the rules
/// parser alone, and the reader with the rules arm filling every field the
/// reader abstained on. The composite is what the user meets; the reader alone
/// is what the law guarantees. Every cell the rules arm adds is listed, so a
/// fill that turns a refusal into a wrong value is visible by name.
///
/// Opt-in (`PUMP_ARMS=1`): it OCRs every heldout still, and the rules arm's
/// numbers are those of the Vision runtime it runs on - a comparison between
/// the arms on one machine, not a gate.
@Suite("Pump composite arms", .pumpFixturesPresent,
       .enabled(if: ProcessInfo.processInfo.environment["PUMP_ARMS"] == "1", "PUMP_ARMS=1"))
struct PumpCompositeArmsTests {
    private static let languages = ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"]

    @Test("reader alone, rules alone, and the composite, over heldout")
    func arms() async throws {
        let folder = PumpReaderTestSupport.pumpFixturesRoot
        let expected = try CorpusScorer.loadExpected(folder.appendingPathComponent("expected.csv"))
        let images = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { CorpusScorer.imageExtensions.contains($0.pathExtension.lowercased()) }
            .filter { PumpReaderTestSupport.isHeldout($0.lastPathComponent) && expected[$0.lastPathComponent] != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let modelURL = PumpReaderTestSupport.repoRoot
            .appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")
        let handle = PumpReaderHandle(reader: PumpReader(model: try PumpSegmentsModel(contentsOf: modelURL),
                                                         detector: PumpReaderTestSupport.makeDetector(),
                                                         rowReader: PumpReaderTestSupport.makeRowReader()))
        let pack = try FuelPriceBandStore.bundledPack()
        let bands = DefaultFuelPriceBandProvider(pack: pack)
        let extractor = FuelExtractor(bandProvider: bands)

        var readerOnly: [String: ExtractionRecord] = [:]
        var rulesOnly: [String: ExtractionRecord] = [:]
        var composite: [String: ExtractionRecord] = [:]
        var noBudget: [String: ExtractionRecord] = [:]
        var floor: [String: ExtractionRecord] = [:]
        var fills: [String] = []
        for image in images {
            let name = image.lastPathComponent
            let want = expected[name]!
            let lines = try await TestOCR.recognizeText(in: image, languages: Self.languages)
            let rules = extractor.extract(lines: lines, source: .pump,
                                          qrAnchor: CorpusScorer.qrAnchor(forImage: name, in: folder))
            var reader = FuelExtraction()
            var unbudgeted = FuelExtraction()
            if let rgb = PumpReaderTestSupport.loadRGB(url: image),
               let cg = PumpQuadWarp.makeImage(rgb.pixels, width: rgb.width, height: rgb.height) {
                let band = bands.currencyBand(currency: want.currency)
                if let reading = PumpDisplayCapture.classify(image: cg, reader: handle, currency: want.currency,
                                                             priceBand: band, rotationCW: 0).reading {
                    reader = reading.extraction
                }
                // The same call with the slow path's wall-clock cap lifted: what
                // the budget costs on THIS build. A Debug build runs the
                // verifier several times slower than the Release app, so the
                // cap trips here where it would not on a phone.
                if let reading = PumpDisplayCapture.classify(image: cg, reader: handle, currency: want.currency,
                                                             priceBand: band, budget: .infinity,
                                                             rotationCW: 0).reading {
                    unbudgeted = reading.extraction
                }
            }
            noBudget[name] = ExtractionRecord(filename: name, extraction: unbudgeted)
            // The live floor's own call (`PumpReaderPipelineTests.measureLive`):
            // the reader with no display decision in front of it.
            var floorRead = FuelExtraction()
            if let rgb = PumpReaderTestSupport.loadRGB(url: image),
               let reading = try? handle.reader.readPhoto(
                   image: rgb, rotationCW: nil, currency: want.currency,
                   priceBand: want.currency.flatMap { pack.currencyBand(currency: $0) }) {
                floorRead.liters = reading.liters.value.map { NSDecimalNumber(decimal: $0).doubleValue }
                floorRead.unitPrice = reading.unitPrice.value
                floorRead.total = reading.total.value
            }
            floor[name] = ExtractionRecord(filename: name, extraction: floorRead)
            var both = rules
            both.liters = reader.liters ?? rules.liters
            both.unitPrice = reader.unitPrice ?? rules.unitPrice
            both.total = reader.total ?? rules.total
            readerOnly[name] = ExtractionRecord(filename: name, extraction: reader)
            rulesOnly[name] = ExtractionRecord(filename: name, extraction: rules)
            composite[name] = ExtractionRecord(filename: name, extraction: both)

            // Every cell the fallthrough supplies, and whether it is right.
            let r = readerOnly[name]!, c = composite[name]!
            // A cell's value is the composite's; it is a fill when the reader had none.
            let cells = [Cell(field: "liters", value: r.liters == nil ? c.liters : nil, truth: want.liters),
                         Cell(field: "unitPrice", value: r.unitPrice == nil ? c.unitPrice : nil,
                              truth: want.unitPrice),
                         Cell(field: "total", value: r.total == nil ? c.total : nil, truth: want.total)]
            let readerCommitted = [r.liters, r.unitPrice, r.total].contains { $0 != nil }
            for cell in cells {
                guard let filled = cell.value else { continue }
                let verdict: String
                if let truth = cell.truth { verdict = abs(filled - truth) < 0.011 ? "right" : "WRONG want \(truth)" }
                else { verdict = "unasserted" }
                fills.append("\(name.prefix(8)) \(readerCommitted ? "beside reader" : "reader silent") "
                    + "\(cell.field)=\(filled) \(verdict)")
            }
        }
        let names = images.map(\.lastPathComponent)
        for (label, records) in [("reader alone", readerOnly), ("reader, no budget", noBudget), ("floor's call", floor),
                                 ("rules alone", rulesOnly), ("composite", composite)] {
            let s = CorpusScorer.scorePump(name: label, images: names, records: records, expected: expected)
            let precision = s.committed > 0 ? Double(s.committedCorrect) / Double(s.committed) : 0
            print("PU.62 \(label): committed \(s.committed), correct \(s.committedCorrect), "
                + "precision \(String(format: "%.3f", precision)), of \(s.numericTotal) cells, \(names.count) stills")
        }
        reportReader(names: names, readerOnly: readerOnly, noBudget: noBudget, floor: floor,
                     expected: expected)
        print("PU.62 fallthrough fills: \(fills.count)")
        for f in fills { print("  FILL \(f)") }
        #expect(!names.isEmpty)
    }

    private struct Cell {
        let field: String
        let value: Double?
        let truth: Double?
    }

    /// Every still the reader alone commits on and every committed cell the
    /// corpus contradicts, then where the app's entry point and the live
    /// floor's call part company.
    private func reportReader(names: [String], readerOnly: [String: ExtractionRecord],
                              noBudget: [String: ExtractionRecord], floor: [String: ExtractionRecord],
                              expected: [String: ExpectedRow]) {
        for name in names {
            guard let r = readerOnly[name], let want = expected[name] else { continue }
            let cells = [Cell(field: "liters", value: r.liters, truth: want.liters),
                         Cell(field: "unitPrice", value: r.unitPrice, truth: want.unitPrice),
                         Cell(field: "total", value: r.total, truth: want.total)]
            let committed = cells.compactMap { c in c.value.map { "\(c.field)=\($0)" } }
            if !committed.isEmpty { print("  READER \(name.prefix(8)) \(committed.joined(separator: " "))") }
            for c in cells {
                if let value = c.value, let truth = c.truth, abs(value - truth) >= 0.011 {
                    print("  WRONG reader \(name.prefix(8)) \(c.field) got \(value) want \(truth)")
                }
            }
        }
        for name in names {
            guard let a = noBudget[name], let f = floor[name] else { continue }
            let app = [a.liters, a.unitPrice, a.total].compactMap { $0 }.count
            let bare = [f.liters, f.unitPrice, f.total].compactMap { $0 }.count
            if app != bare { print("  DIFF \(name.prefix(8)) app \(app) cells, floor's call \(bare) cells") }
        }
    }
}
