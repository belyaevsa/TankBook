import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// What the row locator costs per image: the object detector the app used to bundle against the
/// oriented segmenter it bundles now (model pass plus the Swift decode), on the same stills.
/// Opt-in (`PUMP_LOCATOR_TIMING=1`) and meaningful only in an optimised build:
/// `swift test -c release -Xswiftc -enable-testing --filter PumpLocatorTimingTests`.
@Suite("Row locator latency")
struct PumpLocatorTimingTests {
    @Test("median milliseconds per image, object detector against segmenter",
          .enabled(if: ProcessInfo.processInfo.environment["PUMP_LOCATOR_TIMING"] == "1"
                   && PumpReaderTestSupport.fixturesPresent))
    func timing() throws {
        let root = PumpReaderTestSupport.repoRoot
        let detector = try PumpRowDetector.load(
            contentsOf: root.appendingPathComponent("ml/pump-reader/detector/DigitRows.mlmodel"))
        let segmenter = try PumpRowDetector.load(
            contentsOf: root.appendingPathComponent("ios/App/Resources/RowSeg.mlpackage"))
        let names = try FileManager.default.contentsOfDirectory(atPath: PumpReaderTestSupport.pumpFixturesRoot.path)
            .filter { $0.hasPrefix("pump-") && PumpReaderTestSupport.isHeldout($0) }.sorted().prefix(12)
        var images: [CGImage] = []
        for name in names {
            if let image = PumpQuadWarp.loadOrientedImage(
                from: PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)) { images.append(image) }
        }
        func median(_ locator: PumpRowDetector) -> Double {
            _ = locator.detect(in: images[0])  // warm-up: the first prediction compiles the plan
            let ms = images.map { image -> Double in
                let start = CFAbsoluteTimeGetCurrent()
                _ = locator.detect(in: image)
                return (CFAbsoluteTimeGetCurrent() - start) * 1000
            }.sorted()
            return ms[ms.count / 2]
        }
        let d = median(detector), s = median(segmenter)
        print("Row locator median over \(images.count) heldout stills: object detector \(String(format: "%.1f", d)) ms, "
              + "segmenter \(String(format: "%.1f", s)) ms")
        #expect(images.count >= 10)
    }
}
