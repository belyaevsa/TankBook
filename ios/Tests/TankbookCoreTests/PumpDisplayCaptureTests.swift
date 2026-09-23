import Foundation
import Testing
@testable import TankbookCore

/// PU.29: the classification stage. A pump fixture is a display (the reader
/// vouches for rows of seven-segment digits), a receipt fixture is not - so
/// the capture pipeline routes the first as `.pump` and the second as
/// `.receipt` with no string ever consulted. PU.38 adds the fast path: the
/// detector's stacked rows decide under the text-line guard, and the verifier
/// runs only for the read (or, capped, when the detector abstains).
@Suite("PU.29 pump display classification")
struct PumpDisplayCaptureTests {
    private static let modelURL = PumpReaderTestSupport.repoRoot
        .appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")
    private static let receipts = PumpReaderTestSupport.repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures/receipts")

    /// Six heldout stills (decision 9) that the owner shot the way a user
    /// will: frontal, at arm's length. The floor is the measurement; PU.38's
    /// fast path may rescue a frame the verifier's margin missed.
    private static let heldoutPumps = ["pump-032-gilbarco-circlek-ee-clean.jpg",
                                       "pump-035-dresser-wayne-circlek-ee-rain-pump8.jpg",
                                       "pump-042-dresser-wayne-circlek-ee-preset-20eur.jpg",
                                       "pump-038-dresser-wayne-circlek-ee-reflection-95.jpg",
                                       "pump-092-scheidt-bachmann-rn-3000l-6385-ru.jpeg",
                                       "pump-062-wayne-circlek-ee-pump8-1894.jpg"]
    private static let heldoutRecallFloor = 4

    /// The previous classification, kept to measure the "before": full verify
    /// with no cap, then the count-based rule. Not production code.
    private static func legacyDetection(rgb: PumpRGBImage, reader: PumpReader) -> (PumpDisplayCapture.Detection, Int) {
        let started = Date()
        let all = (try? reader.verify(image: rgb, candidates: reader.candidates(for: rgb))) ?? []
        let rows = PumpDisplayCapture.displayRows(all, imageHeight: rgb.height)
        var widest: CGFloat = 0
        for row in rows {
            let xs = row.quad.map(\.x)
            widest = max(widest, (xs.max()! - xs.min()!) / CGFloat(rgb.width))
        }
        let detection = PumpDisplayCapture.Detection(displayRows: rows.count, textLines: PumpDisplayCapture.textLineCount(rgb),
                                  widestRow: widest, path: .slow)
        return (detection, Int(Date().timeIntervalSince(started) * 1000))
    }

    @Test("heldout pump displays classify at the measured recall and no receipt does", .pumpFixturesPresent)
    func classifies() throws {
        let reader = try #require(PumpDisplayCapture.makeReader(modelURL: Self.modelURL, detectorURL: PumpReaderTestSupport.detectorURL))
        let pumps = Self.heldoutPumps
        let receiptFiles = (try? FileManager.default.contentsOfDirectory(atPath: Self.receipts.path)) ?? []
        let receipts = receiptFiles.filter { $0.hasSuffix(".jpg") }.sorted().prefix(8)
        var pumpHits = 0
        var pumpFast = 0
        var afterMs: [Int] = []
        var decisionMs: [Int] = []
        var beforeMs: [Int] = []
        for name in pumps {
            let url = PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)
            let image = try #require(PumpQuadWarp.loadOrientedImage(from: url))
            let rgb = PumpQuadWarp.rgbImage(from: image)
            let decisionStarted = Date()
            let decision = PumpDisplayCapture.detect(image: image, reader: reader)
            let decisionMillis = Int(Date().timeIntervalSince(decisionStarted) * 1000)
            decisionMs.append(decisionMillis)
            let started = Date()
            let classified = PumpDisplayCapture.classify(image: image, reader: reader, currency: nil, priceBand: nil)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            afterMs.append(ms)
            let (before, beforeM) = Self.legacyDetection(rgb: rgb, reader: reader.reader)
            beforeMs.append(beforeM)
            print("PU.38 \(name.prefix(8)): path=\(classified.detection.path.rawValue) decision=\(decisionMillis)ms classify=\(ms)ms "
                  + "display=\(classified.detection.isPumpDisplay) (before slow \(beforeM)ms display=\(before.isPumpDisplay)) "
                  + "rows=\(classified.detection.displayRows) textLines=\(classified.detection.textLines) "
                  + "widest=\(String(format: "%.2f", classified.detection.widestRow))")
            if classified.detection.isPumpDisplay { pumpHits += 1 }
            if classified.detection.path == .fast { pumpFast += 1 }
        }
        var receiptMisses = 0
        var receiptAfterMs: [Int] = []
        for name in receipts {
            let url = Self.receipts.appendingPathComponent(name)
            let image = try #require(PumpQuadWarp.loadOrientedImage(from: url))
            let started = Date()
            let classified = PumpDisplayCapture.classify(image: image, reader: reader, currency: nil, priceBand: nil)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            receiptAfterMs.append(ms)
            print("PU.38 \(name.prefix(11)): path=\(classified.detection.path.rawValue) classify=\(ms)ms "
                  + "display=\(classified.detection.isPumpDisplay) rows=\(classified.detection.displayRows) "
                  + "textLines=\(classified.detection.textLines)")
            if classified.detection.isPumpDisplay { receiptMisses += 1 }
        }
        let sortedAfter = afterMs.sorted()
        let sortedDecision = decisionMs.sorted()
        let sortedBefore = beforeMs.sorted()
        print("PU.38 heldout classification: \(pumpHits)/\(pumps.count) pumps (\(pumpFast) fast), \(receiptMisses)/\(receipts.count) receipts leaked")
        print("PU.38 pump decision ms: median \(sortedDecision[sortedDecision.count / 2]) max \(sortedDecision.last ?? 0); "
              + "classify+read ms: median \(sortedAfter[sortedAfter.count / 2]) max \(sortedAfter.last ?? 0); "
              + "before: median \(sortedBefore[sortedBefore.count / 2]) max \(sortedBefore.last ?? 0)")
        print("PU.38 receipt classify ms after: median \(receiptAfterMs.sorted()[receiptAfterMs.count / 2]) max \(receiptAfterMs.max() ?? 0)")
        #expect(pumpHits >= Self.heldoutRecallFloor, "\(pumpHits)/\(pumps.count) heldout pump fixtures classified as displays")
        #expect(receiptMisses == 0, "\(receiptMisses) receipts classified as pump displays")
    }

    // MARK: - PU.38 synthetic fast path (no corpus)

    /// A row as the detector returns it: normalised quad + confidence. The
    /// quads are axis-aligned, which is what the size and stacking rules read.
    private static func row(x0: CGFloat, x1: CGFloat, y0: CGFloat, y1: CGFloat, confidence: Double) -> PumpRowDetector.Row {
        PumpRowDetector.Row(quad: [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0),
                                   CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)],
                            confidence: confidence)
    }

    @Test("two stacked rows at the detector's confidence classify fast")
    func fastTwoStackedRows() {
        let rows = [Self.row(x0: 0.1, x1: 0.6, y0: 0.10, y1: 0.15, confidence: 0.4),
                    Self.row(x0: 0.1, x1: 0.6, y0: 0.20, y1: 0.25, confidence: 0.4)]
        #expect(PumpDisplayCapture.fastVerdict(rows: rows, textLines: 8))
    }

    @Test("two rows side by side (a keypad beside a display) do not classify fast")
    func fastSideBySideRowsAbstain() {
        let rows = [Self.row(x0: 0.10, x1: 0.40, y0: 0.10, y1: 0.15, confidence: 0.6),
                    Self.row(x0: 0.55, x1: 0.85, y0: 0.10, y1: 0.15, confidence: 0.6)]
        #expect(!PumpDisplayCapture.fastVerdict(rows: rows, textLines: 8))
    }

    @Test("one high-confidence row plus a rescued row under it classify fast")
    func fastHighPlusRescued() {
        let rows = [Self.row(x0: 0.1, x1: 0.6, y0: 0.10, y1: 0.15, confidence: 0.6),
                    Self.row(x0: 0.1, x1: 0.6, y0: 0.20, y1: 0.25, confidence: 0.2)]
        #expect(PumpDisplayCapture.fastVerdict(rows: rows, textLines: 8))
    }

    @Test("one row alone abstains to the slow path")
    func fastOneRowAbstains() {
        let rows = [Self.row(x0: 0.1, x1: 0.6, y0: 0.10, y1: 0.15, confidence: 0.9)]
        #expect(!PumpDisplayCapture.fastVerdict(rows: rows, textLines: 8))
    }

    @Test("the detector's own stacked rows make a display however much text surrounds them")
    func fastIgnoresTextLines() {
        // PU.63: 21 pump faces covered in labels (31-58 Vision lines) were
        // refused on the line count alone although the detector - trained on
        // the receipts as negatives - vouched for their rows.
        let rows = [Self.row(x0: 0.1, x1: 0.6, y0: 0.10, y1: 0.15, confidence: 0.9),
                    Self.row(x0: 0.1, x1: 0.6, y0: 0.20, y1: 0.25, confidence: 0.9)]
        #expect(PumpDisplayCapture.fastVerdict(rows: rows, textLines: 58))
    }

    @Test("the slow path still refuses a frame over the text-line ceiling")
    func slowKeepsTheCeiling() {
        // The slow path's rows come from Vision and the classical proposals,
        // which a receipt offers as readily as a display.
        let heavy = PumpDisplayCapture.Detection(displayRows: 3, textLines: PumpDisplayCapture.maximumTextLines + 1,
                                                 widestRow: 0.5, path: .slow)
        let light = PumpDisplayCapture.Detection(displayRows: 3, textLines: PumpDisplayCapture.maximumTextLines,
                                                 widestRow: 0.5, path: .slow)
        #expect(!heavy.isPumpDisplay)
        #expect(light.isPumpDisplay)
    }

    @Test("two small rows below the size rules abstain")
    func fastSmallRowsAbstain() {
        let rows = [Self.row(x0: 0.1, x1: 0.2, y0: 0.10, y1: 0.12, confidence: 0.9),
                    Self.row(x0: 0.1, x1: 0.2, y0: 0.14, y1: 0.16, confidence: 0.9)]
        #expect(!PumpDisplayCapture.fastVerdict(rows: rows, textLines: 8))
    }

    /// The slow path exists for a head the detector never saw (a Tatsuno, a
    /// Topaz). pump-019's detector rows do not stack, so the fast path
    /// abstains; the verifier finds two and classifies. The budgets are
    /// injected so the test never asserts wall clock: one that outlasts the
    /// verifier accepts the frame, an expired one refuses it before the
    /// verifier's first row. The production cap's own guard is what a zeroed
    /// `slowPathBudget` trips.
    @Test("the slow-path budget refuses a frame when it expires", .pumpFixturesPresent)
    func slowPathBudgetRefuses() throws {
        let reader = try #require(PumpDisplayCapture.makeReader(modelURL: Self.modelURL, detectorURL: PumpReaderTestSupport.detectorURL))
        let name = "pump-019-gilbarco-circlek-sikupilli-pump8-ee.jpg"
        let image = try #require(PumpQuadWarp.loadOrientedImage(
            from: PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)))
        let rgb = PumpQuadWarp.rgbImage(from: image)
        let detected = reader.reader.detectedRows(for: rgb)
        #expect(!PumpDisplayCapture.fastVerdict(rows: detected, textLines: PumpDisplayCapture.textLineCount(rgb)),
                "the fast path must abstain for this frame to exercise the slow path")
        let accepted = PumpDisplayCapture.classify(image: image, reader: reader, currency: nil, priceBand: nil, budget: 30)
        #expect(accepted.detection.path == .slow)
        #expect(accepted.detection.isPumpDisplay)
        let refused = PumpDisplayCapture.classify(image: image, reader: reader, currency: nil, priceBand: nil, budget: 0)
        #expect(refused.detection.path == .slow)
        #expect(!refused.detection.isPumpDisplay)
        #expect(PumpDisplayCapture.slowPathBudget > 0, "the production cap must be a positive wall clock")
    }
}
