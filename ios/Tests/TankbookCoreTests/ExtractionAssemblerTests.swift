import Foundation
import Testing
@testable import TankbookCore

#if canImport(Vision)
import Vision

// PJ.1 - the capture assembler: OCR lines + an optional fiscal-QR payload in,
// one extraction + anchor + crop-rect-per-resolved-field out. This is the L1
// gate for the capture pipeline - the decision-making must live in core (never
// the app target) so a crop rect that is dropped or an extraction that stops
// resolving fails HERE, in a 30-second `swift test`, not on a device.

@Suite("PJ.1 extraction assembler (capture pipeline core)")
struct ExtractionAssemblerTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let fixturesRoot = repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures")
    private static let languages = ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"]

    // MARK: - A corpus fixture resolves the extraction it expects + a crop rect per field

    @Test("receipt-011 resolves its expected fields and a crop rect per resolved field")
    func receiptFixtureResolvesExtractionAndCropRects() throws {
        let image = Self.fixturesRoot
            .appendingPathComponent("receipts/receipt-011-samara-diesel-ru.png")
        let ocr = try VisionTextRecognizer.recognizeText(in: image, languages: Self.languages)
        let assembly = ExtractionAssembler.assemble(lines: ocr, qrPayload: nil, source: .receipt)

        // The extraction the fixture's expected.csv promises.
        #expect(assembly.extraction.liters == 66.81)
        #expect(assembly.extraction.unitPrice == Decimal(string: "62.89"))
        #expect(assembly.extraction.total == Decimal(string: "4201.68"))
        #expect(assembly.extraction.fuelKind == .diesel)

        // A crop rect per resolved field - not merely present, but a real region
        // of the page. Dropping the crop rects while keeping the values must
        // fail here (mutation check 2).
        for field in [ManualFillUpMath.Field.volume, .unitPrice, .total] {
            let rect = try #require(assembly.cropRects[field],
                                    "a resolved field must carry a crop rect: \(field)")
            #expect(rect.width > 0 && rect.height > 0,
                    "\(field) crop must be a real region, got \(rect)")
        }
        // No other field sneaks a crop in.
        #expect(Set(assembly.cropRects.keys) == [.volume, .unitPrice, .total])
    }

    // MARK: - A QR-only payload yields an anchor with no OCR total

    @Test("a QR payload alone yields an anchor and no OCR total")
    func qrOnlyPayloadYieldsAnAnchorWithNoOcrTotal() throws {
        let payload = try String(
            contentsOf: Self.fixturesRoot
                .appendingPathComponent("receipts/receipt-011-samara-diesel-ru.qr.txt"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        // No OCR lines: the QR is the whole story.
        let assembly = ExtractionAssembler.assemble(lines: [], qrPayload: payload, source: .receipt)

        let anchor = try #require(assembly.qrAnchor)
        #expect(anchor.total == Decimal(string: "4201.68"))
        #expect(assembly.extraction.total == nil)
        #expect(assembly.cropRects.isEmpty)
    }

    // MARK: - Nothing resolved is the ordinary empty form, never an error

    @Test("garbage OCR lines produce an all-nil extraction, not a throw")
    func garbageLinesProduceAnEmptyExtraction() {
        let lines = ["Cafe", "Receipt for a coffee", "Have a nice day"].map { OCRLine(text: $0) }
        let assembly = ExtractionAssembler.assemble(lines: lines, qrPayload: nil, source: .receipt)
        #expect(assembly.extraction.liters == nil)
        #expect(assembly.extraction.unitPrice == nil)
        #expect(assembly.extraction.total == nil)
        #expect(assembly.extraction.fuelKind == nil)
        #expect(assembly.qrAnchor == nil)
        #expect(assembly.cropRects.isEmpty)
    }
}
#endif
