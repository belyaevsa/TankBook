import Foundation
import Testing
@testable import TankbookCore

/// PU.29: the classification stage. A pump fixture is a display (the reader
/// vouches for rows of seven-segment digits), a receipt fixture is not - so
/// the capture pipeline routes the first as `.pump` and the second as
/// `.receipt` with no string ever consulted.
@Suite("PU.29 pump display classification")
struct PumpDisplayCaptureTests {
    private static let modelURL = PumpReaderTestSupport.repoRoot
        .appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")
    private static let receipts = PumpReaderTestSupport.repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures/receipts")

    /// Six heldout stills (decision 9) that the owner shot the way a user
    /// will: frontal, at arm's length. Measured 2026-09-20 after PU.24's
    /// verifier round: four of the six classify - pump-032 yields no verified
    /// row at the classification margin, pump-035 sits at 31 Vision text
    /// lines against the 30-line receipt ceiling. The floor is the
    /// measurement; the text-line ceiling is the next thing to replace.
    private static let heldoutPumps = ["pump-032-gilbarco-circlek-ee-clean.jpg",
                                       "pump-035-dresser-wayne-circlek-ee-rain-pump8.jpg",
                                       "pump-042-dresser-wayne-circlek-ee-preset-20eur.jpg",
                                       "pump-038-dresser-wayne-circlek-ee-reflection-95.jpg",
                                       "pump-092-scheidt-bachmann-rn-3000l-6385-ru.jpeg",
                                       "pump-062-wayne-circlek-ee-pump8-1894.jpg"]
    private static let heldoutRecallFloor = 4

    @Test("heldout pump displays classify at the measured recall and no receipt does", .pumpFixturesPresent)
    func classifies() throws {
        let reader = try #require(PumpDisplayCapture.makeReader(modelURL: Self.modelURL, detectorURL: PumpReaderTestSupport.detectorURL))
        let pumps = Self.heldoutPumps
        let receiptFiles = (try? FileManager.default.contentsOfDirectory(atPath: Self.receipts.path)) ?? []
        let receipts = receiptFiles.filter { $0.hasSuffix(".jpg") }.sorted().prefix(8)
        var pumpHits = 0
        for name in pumps {
            let url = PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)
            let image = try #require(PumpQuadWarp.loadOrientedImage(from: url))
            let detection = PumpDisplayCapture.detect(image: image, reader: reader)
            print("PU.29 \(name.prefix(8)): \(detection.displayRows) display rows, \(detection.textLines) text lines, "
                  + "widest \(String(format: "%.2f", detection.widestRow)) tallest \(String(format: "%.3f", detection.tallestRow))")
            if detection.isPumpDisplay { pumpHits += 1 }
        }
        var receiptMisses = 0
        for name in receipts {
            let image = try #require(PumpQuadWarp.loadOrientedImage(from: Self.receipts.appendingPathComponent(name)))
            let detection = PumpDisplayCapture.detect(image: image, reader: reader)
            print("PU.29 \(name.prefix(11)): \(detection.displayRows) display rows, \(detection.textLines) text lines, "
                  + "widest \(String(format: "%.2f", detection.widestRow)) tallest \(String(format: "%.3f", detection.tallestRow))")
            if detection.isPumpDisplay { receiptMisses += 1 }
        }
        print("PU.29 heldout classification: \(pumpHits)/\(pumps.count)")
        #expect(pumpHits >= Self.heldoutRecallFloor, "\(pumpHits)/\(pumps.count) heldout pump fixtures classified as displays")
        #expect(receiptMisses == 0, "\(receiptMisses) receipts classified as pump displays")
    }
}
