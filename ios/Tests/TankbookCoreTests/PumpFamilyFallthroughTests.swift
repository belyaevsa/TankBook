import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// The capture path `CapturePipeline.process` runs, over the display families
/// the reader does not read - dark LCDs with light segments and TFT screens
/// (`docs/EXTRACTION.md` -> "Display families the reader does not read yet").
/// On these the law refuses, and what the user meets is decided by what runs
/// behind it: a reading with no committed field keeps the photo a pump and the
/// rules arm fills every field the reader left empty; no reading at all makes
/// the photo a receipt, parsed as one. Neither route checks the display
/// family, so this lists every value either route commits, with its verdict.
///
/// Opt-in (`PUMP_FAMILIES=1`, `PUMP_FAMILY_STRIDE=<n>` samples every n-th
/// frame, `PUMP_FAMILY_FRAMES=video-050/337.jpg,...` runs only those frames): it OCRs every still and tracked frame of these families, and the
/// rules arm's numbers are those of the Vision runtime it runs on.
@Suite("Pump family fallthrough", .pumpFixturesPresent,
       .enabled(if: ProcessInfo.processInfo.environment["PUMP_FAMILIES"] == "1", "PUMP_FAMILIES=1"))
struct PumpFamilyFallthroughTests {
    private static let languages = ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"]

    /// The truth an item is judged against. A running display's litres and
    /// total change frame by frame, so only its unit price is fixed; a pair it
    /// commits is judged by whether it closes at that price.
    private struct Truth {
        let liters: Double?
        let unitPrice: Double?
        let total: Double?
        let running: Bool
    }

    private struct Item {
        let family: String
        let label: String
        let url: URL
        let truth: Truth
    }

    @Test("what the capture path commits on dark-LCD and TFT displays")
    func familyOutcomes() async throws {
        let items = try Self.items()
        let pack = try FuelPriceBandStore.bundledPack()
        let bands = DefaultFuelPriceBandProvider(pack: pack)
        let extractor = FuelExtractor(bandProvider: bands)
        let modelURL = PumpReaderTestSupport.repoRoot
            .appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")
        let handle = PumpReaderHandle(reader: PumpReader(model: try PumpSegmentsModel(contentsOf: modelURL),
                                                         detector: PumpReaderTestSupport.makeDetector(),
                                                         rowReader: PumpReaderTestSupport.makeRowReader()))
        var tally: [String: [String: Int]] = [:]
        for item in items {
            guard let rgb = PumpReaderTestSupport.loadRGB(url: item.url),
                  let cg = PumpQuadWarp.makeImage(rgb.pixels, width: rgb.width, height: rgb.height) else { continue }
            // No wall-clock cap, as the gate measures: a Debug build in the
            // simulator runs the verifier several times slower than the app.
            let classified = PumpDisplayCapture.classify(image: cg, reader: handle, currency: .eur,
                                                         priceBand: bands.currencyBand(currency: .eur),
                                                         budget: .infinity, rotationCW: 0)
            let lines = try await TestOCR.recognizeText(in: item.url, languages: Self.languages)
            let route: String
            var final: FuelExtraction
            var reader = FuelExtraction()
            if let reading = classified.reading {
                route = "pump"
                reader = reading.extraction
                let rules = extractor.extract(lines: lines, source: .pump, qrAnchor: nil)
                // `CapturePipeline.composed`, line for line.
                final = rules
                final.liters = reader.liters ?? rules.liters
                final.unitPrice = reader.unitPrice ?? (reading.law.caution == nil ? rules.unitPrice : nil)
                final.total = reader.total ?? rules.total
            } else {
                route = classified.detection.isPumpDisplay ? "receipt(display,no reading)" : "receipt"
                final = extractor.extract(lines: lines, source: .receipt, qrAnchor: nil)
            }
            let verdict = Self.verdict(final, truth: item.truth)
            tally[item.family, default: [:]][verdict, default: 0] += 1
            let cells: [(String, Double?, Double?)] = [
                ("L", final.liters, reader.liters), ("P", Self.double(final.unitPrice), Self.double(reader.unitPrice)),
                ("T", Self.double(final.total), Self.double(reader.total))]
            var fields: [String] = []
            for (name, value, fromReader) in cells {
                guard let value else { continue }
                fields.append("\(name)=\(value)" + (fromReader == nil ? "(rules)" : "(reader)"))
            }
            if verdict == "WRONG" || verdict == "unjudged" {
                for line in lines { print("PU93 OCR \(item.label)\t\(line.text)") }
            }
            print("PU93\t\(item.family)\t\(item.label)\t\(route)\t\(verdict)\t\(fields.joined(separator: " "))")
        }
        for (family, counts) in tally.sorted(by: { $0.key < $1.key }) {
            let summary = counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
            print("PU93 SUMMARY \(family): \(summary.joined(separator: ", "))")
        }
        #expect(!items.isEmpty)
    }

    /// `nothing` (no field committed), `right`, `WRONG`, or `unjudged` (a
    /// running display's lone litres or total, which no fixed truth pins).
    private static func verdict(_ e: FuelExtraction, truth: Truth) -> String {
        let cells: [(Double?, Double?)] = [(e.liters, truth.liters), (double(e.unitPrice), truth.unitPrice),
                                           (double(e.total), truth.total)]
        if cells.allSatisfy({ $0.0 == nil }) { return "nothing" }
        if truth.running {
            if let price = double(e.unitPrice), abs(price - (truth.unitPrice ?? 0)) >= 0.0005 { return "WRONG" }
            if let liters = e.liters, let total = double(e.total), let price = truth.unitPrice {
                return abs(liters * price - total) <= 0.011 ? "right" : "WRONG"
            }
            return e.liters == nil && e.total == nil ? "right" : "unjudged"
        }
        for (value, want) in cells {
            guard let value else { continue }
            guard let want else { return "WRONG" }
            if abs(value - want) >= 0.0051 { return "WRONG" }
        }
        return "right"
    }

    private static func double(_ value: Decimal?) -> Double? {
        value.map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    private static func items() throws -> [Item] {
        let root = PumpReaderTestSupport.pumpFixturesRoot
        let expected = try CorpusScorer.loadExpected(root.appendingPathComponent("expected.csv"))
        func truth(_ still: String) -> Truth {
            let row = expected[still]
            return Truth(liters: row?.liters, unitPrice: row?.unitPrice, total: row?.total, running: false)
        }
        let stills: [(String, String)] = [
            ("dark", "pump-117-wayne-alexela-98-press-err-third-party-ee.jpg"),
            ("dark", "pump-144-wayne-alexela-98-same-fill-as-117-wider-third-party-ee.jpg"),
            ("dark", "pump-332-unknown-alexela-black-lcd-idle-board-reflection-ee.jpg"),
            ("dark", "pump-334-unknown-alexela-black-lcd-idle-board-self-reflection-ee.jpg"),
            ("dark", "pump-335-unknown-alexela-black-lcd-idle-board-ee.jpg"),
            ("dark", "pump-339-unknown-neste-black-lcd-pump3-2999-1531l-board-ee.jpg"),
            ("dark", "pump-340-unknown-neste-black-lcd-pump4-1961-1001l-board-ee.jpg"),
            ("tft", "pump-337-tokheim-terminal-tft-screen-7280-3500l-2080-ee.jpg"),
        ]
        var items = stills.map { family, name in
            Item(family: family, label: String(name.prefix(8)), url: root.appendingPathComponent(name),
                 truth: truth(name))
        }
        let frames = PumpReaderTestSupport.pumpLiveFramesRoot
        let stride = Int(ProcessInfo.processInfo.environment["PUMP_FAMILY_STRIDE"] ?? "") ?? 1
        let records: [(String, String, Truth)] = [
            ("dark", "live-6402", truth(stills[2].1)), ("dark", "live-6404", truth(stills[3].1)),
            ("dark", "live-6405", truth(stills[4].1)), ("dark", "live-6424", truth(stills[5].1)),
            ("dark", "live-6425", truth(stills[6].1)), ("tft", "live-6420", truth(stills[7].1)),
            ("dark", "video-050-unknown-alexela-black-lcd-running-display-2079-ee",
             Truth(liters: nil, unitPrice: 2.079, total: nil, running: true)),
            ("tft", "video-051-tokheim-terminal-tft-static-display-2080-ee",
             Truth(liters: 35.00, unitPrice: 2.080, total: 72.80, running: false)),
        ]
        for (family, record, want) in records {
            let dir = frames.appendingPathComponent(record)
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
                // Numbered frames only: `sheet.jpg` is the tracker's contact sheet.
                .filter { $0.wholeMatch(of: /\d+\.jpg/) != nil }.sorted()
            let only = Set((ProcessInfo.processInfo.environment["PUMP_FAMILY_FRAMES"] ?? "")
                .split(separator: ",").map(String.init))
            for (index, name) in names.enumerated()
            where only.isEmpty ? index % stride == 0 : only.contains("\(record.prefix(9))/\(name)") {
                items.append(Item(family: family, label: "\(record.prefix(9))/\(name)",
                                  url: dir.appendingPathComponent(name), truth: want))
            }
        }
        return items
    }
}
