import Foundation
import Testing
@testable import TankbookCore

#if canImport(Vision)
import CoreGraphics
import ImageIO
import Vision

// P6.3 L5 - "compression must not cost accuracy" (docs/API.md -> "The device's
// side of /extract", rule 1; the same paragraph that gates the compression
// settings on the corpus).
//
// Fuel receipts are thermal print: the digits that matter are small, and
// over-compression eats exactly them. So the compression step is re-scored
// here: the receipt fixtures go through `GatewayRendition` (long edge 1600 px,
// quality 0.7 - the exact step the app runs before upload), then OCR + the
// parser, then `CorpusScorer` at the existing tolerance. Hits may not fall
// below the recorded mark (receipts 174/210 - one BETTER than the uncompressed
// 173/210 the ratchet measures, because the resize clears a smear the raw
// image did not). This is what stops "make the upload faster" from quietly
// becoming "read the receipt worse".

@Suite("OCR corpus accuracy through the gateway compression step (P6.3, L5)")
struct CorpusCompressionTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let fixturesRoot = repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures")

    private static let languages = ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"]

    /// The recorded high-water mark for receipts through the compression step.
    /// Measured at 189/220 (RV.56, 2026-09-04): the resize keeps clearing a
    /// smear, so the compressed run stays ahead of the uncompressed ratchet's
    /// 187 (high-water.json) - the resize is not lossy for this parser, and
    /// never below.
    private static let recordedReceipts = (hits: 189, total: 220)

    @Test("receipt hits through the compression step never fall below the recorded mark")
    func compressionDoesNotCostAccuracy() throws {
        let folder = Self.fixturesRoot.appendingPathComponent("receipts")
        let expected = try CorpusScorer.loadExpected(folder.appendingPathComponent("expected.csv"))
        let images = try CorpusScorer.imageFilenames(in: folder)

        // Same injected band as the uncompressed ratchet - the compression step
        // is scored against the parser the app runs, not a bare extractor.
        let pack = try FuelPriceBandStore.bundledPack()
        let extractor = FuelExtractor(bandProvider: DefaultFuelPriceBandProvider(pack: pack))
        var records: [String: ExtractionRecord] = [:]
        var compressed = 0
        for image in images {
            guard expected[image] != nil else { continue }
            let url = folder.appendingPathComponent(image)
            guard let original = Self.loadImage(from: url) else { continue }
            guard let jpeg = GatewayRendition.jpegData(from: original),
                  let rendition = GatewayRendition.image(from: jpeg) else {
                Issue.record("\(image) could not be compressed - the upload step would fail")
                continue
            }
            compressed += 1
            let ocrLines = try VisionTextRecognizer.recognizeText(image: rendition, languages: Self.languages)
            let qrAnchor = CorpusScorer.qrAnchor(forImage: image, in: folder)
            let result = extractor.extract(lines: ocrLines, source: .receipt, qrAnchor: qrAnchor)
            records[image] = ExtractionRecord(filename: image, extraction: result)
        }

        #expect(compressed == images.count,
                "every receipt fixture must survive the compression step")

        let scored = CorpusScorer.score(
            name: "receipts", images: images, records: records, expected: expected)
        #expect(scored.total == Self.recordedReceipts.total,
                "the compression step may not shrink the measured corpus")
        #expect(scored.hits >= Self.recordedReceipts.hits,
                Comment(stringLiteral: "compression cost accuracy: \(scored.hits)/\(scored.total) vs the recorded "
                    + "\(Self.recordedReceipts.hits)/\(Self.recordedReceipts.total)"))
    }

    @Test("the compression step actually compresses the fixtures")
    func compressionShrinksTheFixtures() throws {
        let folder = Self.fixturesRoot.appendingPathComponent("receipts")
        let images = try CorpusScorer.imageFilenames(in: folder)
        var anyShrank = false
        for image in images {
            let url = folder.appendingPathComponent(image)
            guard let original = Self.loadImage(from: url) else { continue }
            let jpeg = try #require(GatewayRendition.jpegData(from: original))
            // The base64 rendition must be under the envelope cap for a
            // full-resolution fixture - the "ceiling, not a target" check.
            #expect(GatewayRendition.base64Length(jpegData: jpeg) < GatewayRendition.envelopeCapBytes)
            anyShrank = true
        }
        #expect(anyShrank, "the fixtures must be loadable")
    }

    private static func loadImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
#endif
