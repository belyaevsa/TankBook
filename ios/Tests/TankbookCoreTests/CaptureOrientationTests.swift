import Foundation
import Testing
@testable import TankbookCore

#if canImport(Vision)
import CoreGraphics
import ImageIO
import Vision

// RV.49 - the in-app shutter handed Vision every photo sideways. The corpus
// harness only ever exercised the URL entry point (`VNImageRequestHandler(url:)`),
// which honours EXIF orientation, so the 38.3% receipt rate was measured on
// correctly-oriented images while the live camera path fed Vision the sensor's
// native landscape buffer with no orientation at all.
//
// This is the L5 that fails today and passes after the fix: OCR a corpus fixture
// ROTATED 90 degrees through the cgImage entry point (NOT the URL one - that
// already works, which is the whole point) and assert the recognised line count
// and key values match the upright run. A rotated fixture that reaches the
// cgImage path with no orientation reads sideways and loses/misreads lines; the
// same pixels with the orientation passed through read identically to upright.
//
// It is the ONLY honest proof of RV.49: every other gate, including the corpus
// accuracy gate, is file-based and stays green whether the orientation bug is
// present or not. It reaches Vision through the shared `VisionRequestGate`
// (RV.52) like every other OCR caller, so it no longer tips the parallel suite
// over Vision's concurrency ceiling.
@Suite("RV.49 camera orientation reaches Vision (L5)")
struct CaptureOrientationTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let fixture = repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures/receipts/receipt-011-samara-diesel-ru.png")

    private static let languages = ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"]

    @Test("a 90-degree-rotated fixture OCRs through the cgImage path the same as upright")
    func rotatedFixtureMatchesUpright() throws {
        let upright = try #require(Self.loadCGImage(from: Self.fixture))
        let rotated = try #require(Self.rotate90Clockwise(upright))

        let uprightLines = try VisionTextRecognizer.recognizeText(image: upright, languages: Self.languages)
        let rotatedLines = try VisionTextRecognizer.recognizeText(
            image: rotated, orientation: .right, languages: Self.languages)

        // The recognised line count must match: sideways pixels lose and misread
        // lines (measured 33 vs 36 on this fixture before the fix).
        #expect(rotatedLines.count == uprightLines.count,
                Comment(stringLiteral: "rotated line count \(rotatedLines.count) != upright \(uprightLines.count)"))

        // The key values - the extracted fields the receipt actually carries -
        // must match the upright run, not merely be present.
        let extractor = FuelExtractor()
        let uprightExtraction = extractor.extract(lines: uprightLines, source: .receipt)
        let rotatedExtraction = extractor.extract(lines: rotatedLines, source: .receipt)

        let mismatch = Comment(
            rawValue: "rotated \(Self.key(rotatedExtraction)) vs upright \(Self.key(uprightExtraction))"
        )
        #expect(rotatedExtraction.total == uprightExtraction.total, mismatch)
        #expect(rotatedExtraction.liters == uprightExtraction.liters, mismatch)
        #expect(rotatedExtraction.unitPrice == uprightExtraction.unitPrice, mismatch)

        // The upright run must actually resolve the receipt - a fixture that
        // resolves nothing on either side would make this test vacuous.
        #expect(uprightExtraction.total != nil && uprightExtraction.liters != nil,
                "the upright fixture must resolve its key fields")
    }

    // MARK: - Image plumbing (CoreGraphics, no UIKit)

    /// A compact `liters/price/total` summary for a failure message.
    private static func key(_ extraction: FuelExtraction) -> String {
        let liters = extraction.liters.map { String($0) } ?? "-"
        let price = extraction.unitPrice.map { String(describing: $0) } ?? "-"
        let total = extraction.total.map { String(describing: $0) } ?? "-"
        return "\(liters)/\(price)/\(total)"
    }

    /// Loads the fixture's raw pixels without applying any EXIF orientation -
    /// the same shape the in-app shutter's `cgImageRepresentation()` returns.
    private static func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Rotates 90 degrees clockwise, simulating the sensor's native landscape
    /// buffer for a portrait-held phone.
    private static func rotate90Clockwise(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil, width: height, height: width,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.translateBy(x: CGFloat(height) / 2, y: CGFloat(width) / 2)
        context.rotate(by: .pi / 2)
        context.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
#endif
