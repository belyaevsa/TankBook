import Foundation
import Testing
@testable import TankbookCore

#if canImport(Vision)
import CoreGraphics
import ImageIO

/// SH.10's question, measured: which stored JPEG - long edge and quality - is
/// the smallest that reads as well as the full-size capture. Each arm encodes
/// every receipt fixture and every heldout pump still the way
/// `AttachmentRendition` does, decodes it again, and reads it: receipts through
/// OCR and `FuelExtractor` scored by the corpus scorer, pumps through the app's
/// `PumpDisplayCapture.classify` scored like the live path. Opt-in
/// (`VISION_STORED_SWEEP=1`) and on the measured runtime:
///
///   VISION_STORED_SWEEP=1 scripts/vision-suites.sh StoredRenditionAccuracyTests
@Suite("Stored rendition accuracy sweep (SH.10)", .visionMeasuredRuntimeOnly,
       .enabled(if: ProcessInfo.processInfo.environment["VISION_STORED_SWEEP"] != nil))
struct StoredRenditionAccuracyTests {
    /// nil long edge = the full-size original, untouched.
    private struct Arm: CustomStringConvertible {
        let longEdge: Int?
        let quality: Double
        var description: String { longEdge.map { "\($0)px q\(Int(quality * 100))" } ?? "full size" }
    }

    private static let arms: [Arm] = [
        Arm(longEdge: nil, quality: 1),
        Arm(longEdge: 2048, quality: 0.8),
        Arm(longEdge: 2048, quality: 0.7),
        Arm(longEdge: 2048, quality: 0.6),
        Arm(longEdge: 1600, quality: 0.8),
        Arm(longEdge: 1600, quality: 0.7),
        Arm(longEdge: 1280, quality: 0.8)
    ]

    private static let fixturesRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Spike/ReceiptSpike/fixtures")
    private static let languages = ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"]

    /// The stored bytes and the image a later read decodes from them.
    private static func stored(_ url: URL, _ arm: Arm) throws -> (bytes: Int, image: CGImage)? {
        let original = try Data(contentsOf: url)
        let data = try arm.longEdge.map {
            try AttachmentRendition.jpeg(data: original, longEdge: $0, quality: arm.quality).data
        } ?? original
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return (data.count, image)
    }

    @Test("receipts and heldout pumps, per stored arm")
    func sweep() async throws {
        let pack = try FuelPriceBandStore.bundledPack()
        let extractor = FuelExtractor(bandProvider: DefaultFuelPriceBandProvider(pack: pack))
        let receipts = Self.fixturesRoot.appendingPathComponent("receipts")
        let receiptExpected = try CorpusScorer.loadExpected(receipts.appendingPathComponent("expected.csv"))
        let receiptImages = try CorpusScorer.imageFilenames(in: receipts).filter { receiptExpected[$0] != nil }
        let pumpExpected = try CorpusScorer.loadExpected(
            PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent("expected.csv"))
        let pumpNames = pumpExpected.keys.filter(PumpReaderTestSupport.isHeldout).sorted()
        let model = try PumpSegmentsModel(contentsOf: PumpReaderTestSupport.repoRoot
            .appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage"))
        let reader = PumpReaderHandle(reader: PumpReader(model: model, detector: PumpReaderTestSupport.makeDetector(),
                                                         rowReader: PumpReaderTestSupport.makeRowReader()))

        for arm in Self.arms {
            var receiptBytes = 0, records: [String: ExtractionRecord] = [:], receiptWrong = 0
            for name in receiptImages {
                guard let (bytes, image) = try Self.stored(receipts.appendingPathComponent(name), arm) else { continue }
                receiptBytes += bytes
                let lines = try await TestOCR.recognizeText(image: image, languages: Self.languages)
                let read = extractor.extract(lines: lines, source: .receipt,
                                             qrAnchor: CorpusScorer.qrAnchor(forImage: name, in: receipts))
                records[name] = ExtractionRecord(filename: name, extraction: read)
                let want = receiptExpected[name]!
                for (got, expected) in [(read.liters, want.liters),
                                        (read.unitPrice.map { NSDecimalNumber(decimal: $0).doubleValue }, want.unitPrice),
                                        (read.total.map { NSDecimalNumber(decimal: $0).doubleValue }, want.total)] {
                    if let got, let expected, abs(got - expected) >= CorpusScorer.tolerance { receiptWrong += 1 }
                }
            }
            let scored = CorpusScorer.score(name: "receipts", images: receiptImages, records: records,
                                            expected: receiptExpected)

            var pumpBytes = 0, committed = 0, right = 0
            for name in pumpNames {
                let url = PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)
                guard let (bytes, image) = try Self.stored(url, arm) else { continue }
                pumpBytes += bytes
                let want = pumpExpected[name]!
                let band = want.currency.flatMap { pack.currencyBand(currency: $0) }
                let law = PumpDisplayCapture.classify(image: image, reader: reader, currency: want.currency,
                                                      priceBand: band, budget: .infinity, rotationCW: 0).reading?.law
                for (field, expected) in [(law?.liters, want.liters), (law?.unitPrice, want.unitPrice),
                                          (law?.total, want.total)] {
                    guard let expected, let value = field?.value else { continue }
                    committed += 1
                    let derived: Bool = { if case .derived? = field?.provenance { return true }; return false }()
                    if abs(NSDecimalNumber(decimal: value).doubleValue - expected)
                        < (derived ? 0.1 : CorpusScorer.tolerance) { right += 1 }
                }
            }
            print(String(format: "STORED %@: receipts %d/%d right, %d wrong, %.2f MB avg | pumps %d committed, "
                         + "%d right, %d wrong, %.2f MB avg",
                         arm.description, scored.hits, scored.total, receiptWrong,
                         Double(receiptBytes) / Double(max(receiptImages.count, 1)) / 1_048_576,
                         committed, right, committed - right,
                         Double(pumpBytes) / Double(max(pumpNames.count, 1)) / 1_048_576))
        }
    }
}
#endif
