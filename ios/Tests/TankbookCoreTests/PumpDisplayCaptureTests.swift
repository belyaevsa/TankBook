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

    @Test("a pump display classifies as one and a receipt does not", .pumpFixturesPresent)
    func classifies() throws {
        let reader = try #require(PumpDisplayCapture.makeReader(modelURL: Self.modelURL))
        let pumps = ["pump-078-gilbarco-circlek-peetri-pump7-3143l-ee.jpg",
                     "pump-036-dresser-wayne-circlek-ee-pump4-95.jpg",
                     "pump-101-gilbarco-circlek-ee-1765l-2034-closeup.jpg",
                     "pump-092-scheidt-bachmann-rn-3000l-6385-ru.jpeg",
                     "pump-062-wayne-circlek-ee-pump8-1894.jpg"]
        let receiptFiles = (try? FileManager.default.contentsOfDirectory(atPath: Self.receipts.path)) ?? []
        let receipts = receiptFiles.filter { $0.hasSuffix(".jpg") }.sorted().prefix(8)
        var pumpHits = 0
        for name in pumps {
            let url = PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)
            let image = try #require(PumpQuadWarp.loadOrientedImage(from: url))
            let detection = PumpDisplayCapture.detect(image: image, reader: reader)
            print("PU.29 \(name.prefix(8)): \(detection.displayRows) display rows, \(detection.textLines) text lines")
            if detection.isPumpDisplay { pumpHits += 1 }
        }
        var receiptMisses = 0
        for name in receipts {
            let image = try #require(PumpQuadWarp.loadOrientedImage(from: Self.receipts.appendingPathComponent(name)))
            let detection = PumpDisplayCapture.detect(image: image, reader: reader)
            print("PU.29 \(name.prefix(11)): \(detection.displayRows) display rows, \(detection.textLines) text lines")
            if detection.isPumpDisplay { receiptMisses += 1 }
        }
        #expect(pumpHits == pumps.count, "\(pumpHits)/\(pumps.count) pump fixtures classified as displays")
        #expect(receiptMisses == 0, "\(receiptMisses) receipts classified as pump displays")
    }
}
