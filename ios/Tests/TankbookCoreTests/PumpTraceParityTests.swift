import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// The annotator's pipeline view shows a `PumpTrace` of the app's own
/// `PumpDisplayCapture.classify`; these pin that observing the run never
/// changes it, and that the attempt the trace marks as chosen is the one whose
/// reading `classify` returned - so the view cannot show a different run from
/// the one the app would make.
@Suite("pump trace parity")
struct PumpTraceParityTests {
    private static let modelURL = PumpReaderTestSupport.repoRoot
        .appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")
    private static let detectorURL = PumpReaderTestSupport.repoRoot
        .appendingPathComponent("ml/pump-reader/detector/DigitRows.mlmodel")
    private static let fixtures = PumpReaderTestSupport.repoRoot.appendingPathComponent("Spike/ReceiptSpike/fixtures")

    /// One of each path: a fast-path read, a slow-path read that commits a
    /// wrong pair (rain), a sideways display the search turns, and a receipt
    /// that is not a display.
    private static let images = [
        "pump/pump-326-gilbarco-circlek-2117-1011l-2094-rain-ee.jpg",
        "pump/pump-323-wayne-neste-6503-3389l-board-rain-second-angle-ee.jpg",
        "pump/pump-019-gilbarco-circlek-sikupilli-pump8-ee.jpg",
        "receipts/receipt-038-circlek-sikupilli-95e0-pump8-ee.jpg"
    ]

    private static var modelsPresent: Bool {
        FileManager.default.fileExists(atPath: modelURL.path)
            && FileManager.default.fileExists(atPath: detectorURL.path)
    }

    /// A budget no Mac run reaches, so the slow path's deadline cannot make two
    /// runs of one image differ.
    private static let budget: TimeInterval = 60

    @Test("a traced classify returns exactly what an untraced one does, and the chosen attempt carries its law",
          .enabled(if: modelsPresent, "the bundled pump models"))
    func parity() throws {
        // `.onRefusal` runs every attempt kind the app's path has (seed,
        // searched, turned); `.off` runs a subset of the same calls.
        let deskew = PumpReader.DeskewMode.onRefusal
        let model = try PumpSegmentsModel(contentsOf: Self.modelURL)
        let detector = try PumpRowDetector(contentsOf: Self.detectorURL)
        let handle = PumpReaderHandle(reader: PumpReader(model: model, detector: detector, deskew: deskew))
        var checked = 0
        for name in Self.images {
            let url = Self.fixtures.appendingPathComponent(name)
            guard let image = PumpQuadWarp.loadOrientedImage(from: url) else { continue }
            let plain = PumpDisplayCapture.classify(image: image, reader: handle, currency: .eur, priceBand: nil,
                                                    budget: Self.budget, rotationCW: 0)
            let trace = PumpTrace()
            let traced = PumpDisplayCapture.classify(image: image, reader: handle, currency: .eur, priceBand: nil,
                                                     budget: Self.budget, rotationCW: 0, trace: trace)
            #expect(traced.detection == plain.detection, "\(name): detection changed under the trace")
            #expect(traced.reading == plain.reading, "\(name): reading changed under the trace")
            #expect(!trace.attempts.isEmpty, "\(name): nothing recorded")
            if let reading = traced.reading {
                let chosen = try #require(trace.chosen, "\(name): a reading with no chosen attempt")
                #expect(trace.attempts[chosen].law == reading.law, "\(name): the chosen attempt is not the one read")
            } else {
                #expect(trace.chosen == nil, "\(name): an attempt chosen for a frame that was not read")
            }
            checked += 1
        }
        #expect(checked == Self.images.count, "a fixture failed to load: \(checked) of \(Self.images.count)")
    }
}
