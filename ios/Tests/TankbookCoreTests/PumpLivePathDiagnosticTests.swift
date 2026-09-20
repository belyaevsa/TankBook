import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// Where the live path loses each heldout still: the locator's candidates
/// against the annotated windows (IoU), what the verifier keeps, what the
/// assigner calls it, and what the law commits. Prints only; opt-in
/// (`PUMP_LIVE_DIAG=1`, optional `PUMP_LIVE_DIAG_ONLY=pump-032`) because it
/// is a reading aid for the locator rounds (PU.24), not a check.
@Suite("PU.24 live path diagnostic")
struct PumpLivePathDiagnosticTests {
    private static var enabled: Bool { ProcessInfo.processInfo.environment["PUMP_LIVE_DIAG"] == "1" }
    private static let modelURL = PumpReaderTestSupport.repoRoot
        .appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")

    @Test("per heldout still: candidates, verified, assigned, committed",
          .enabled(if: enabled && PumpReaderTestSupport.fixturesPresent, "PUMP_LIVE_DIAG=1 with the corpus"))
    func diagnose() throws {
        let only = ProcessInfo.processInfo.environment["PUMP_LIVE_DIAG_ONLY"]
        let model = try PumpSegmentsModel(contentsOf: Self.modelURL)
        let reader = PumpReader(model: model, detector: PumpReaderTestSupport.makeDetector())
        let data = try Data(contentsOf: PumpReaderTestSupport.windowsURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let expected = try CorpusScorer.loadExpected(
            PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent("expected.csv"))
        let pack = try FuelPriceBandStore.bundledPack()
        var stage = (photos: 0, anyCandidateHit: 0, anyVerifiedHit: 0, threeVerifiedHit: 0, assignedRight: 0, committed: 0)
        for (name, value) in root.sorted(by: { $0.key < $1.key }) {
            guard name != "_about", let ann = value as? [String: Any], PumpReaderTestSupport.isHeldout(name),
                  only == nil || name.hasPrefix(only!) else { continue }
            guard let image = PumpReaderTestSupport.loadRGB(
                url: PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)) else { continue }
            let rotation = (ann["rotationCW"] as? NSNumber)?.intValue ?? 0
            let upright = PumpPanelLocator.rotatedRGB(image, rotationCW: rotation)
            // Annotated windows in the upright frame.
            var truth: [(field: String, quad: [CGPoint])] = []
            for w in ann["windows"] as? [[String: Any]] ?? [] {
                guard let field = w["field"] as? String, let q = (w["quad"] as? [[NSNumber]])?.map({ $0.map(\.doubleValue) }) else { continue }
                let px = PumpQuadWarp.readingOrder(PumpReaderTestSupport.quadPixels(q, width: image.width, height: image.height),
                                                   rotationCW: rotation)
                truth.append((field, px))
            }
            let candidates = reader.candidates(for: upright)
            let verified = try reader.verify(image: upright, candidates: candidates)
            let assignment = PumpRowAssignment.assign(
                windows: verified.map { PumpRowAssignment.Window(quad: $0.quad, glyphCount: $0.glyphCount) }, rotationCW: 0)
            func bestTruth(_ quad: [CGPoint]) -> (String, Double) {
                var best = ("-", 0.0)
                for t in truth {
                    let iou = Double(PumpQuadWarp.iou(quad, t.quad))
                    if iou > best.1 { best = (t.field, iou) }
                }
                return best
            }
            let candPx = candidates.map { c in c.quad.map { CGPoint(x: $0.x * CGFloat(upright.width), y: $0.y * CGFloat(upright.height)) } }
            let candHits = candPx.map { bestTruth($0) }.filter { $0.1 >= 0.5 }
            // Why a true row failed the verifier.
            let verdicts = try reader.verdicts(image: upright, candidates: candidates)
            var missLines: [String] = []
            for v in verdicts where !v.kept {
                let (field, iou) = bestTruth(v.quad)
                if iou >= 0.5 {
                    missLines.append(String(format: "      LOST %@ iou %.2f  h %.3f cells %d margin %.1f", field, iou, v.heightFraction, v.cells, v.meanMargin))
                }
            }
            let candHitFields = Set(candHits.map(\.0))
            let candRank = candPx.enumerated().filter { bestTruth($0.element).1 >= 0.5 }.map(\.offset)
            let verHits = verified.map { bestTruth($0.quad) }
            let transactionHits = Set(verHits.filter { $0.1 >= 0.5 && $0.0 != "board" }.map(\.0))
            stage.photos += 1
            if !candHits.isEmpty { stage.anyCandidateHit += 1 }
            if verHits.contains(where: { $0.1 >= 0.5 }) { stage.anyVerifiedHit += 1 }
            if transactionHits.count >= 2 { stage.threeVerifiedHit += 1 }
            var rolesRight = 0
            var roleLines: [String] = []
            for (v, role) in zip(verified, assignment.roles) {
                let (field, iou) = bestTruth(v.quad)
                let got = role?.rawValue ?? "nil"
                if iou >= 0.5 && got == field { rolesRight += 1 }
                let b = PumpRowAssignment.bounds(v.quad, rotationCW: 0)
                roleLines.append(String(format: "      %@ -> %@ iou %.2f  cells %d margin %.1f  x %.2f-%.2f y %.2f-%.2f h %.3f",
                                        field, got, iou, v.glyphCount, v.meanMargin,
                                        b.minX / CGFloat(upright.width), b.maxX / CGFloat(upright.width),
                                        b.minY / CGFloat(upright.height), b.maxY / CGFloat(upright.height),
                                        b.height / CGFloat(upright.height)))
            }
            if rolesRight >= 2 { stage.assignedRight += 1 }
            let want = expected[name]
            let reading = try reader.readPhoto(image: image, rotationCW: rotation, currency: want?.currency,
                                               priceBand: want?.currency.flatMap { pack.currencyBand(currency: $0) })
            if reading.committedCount > 0 { stage.committed += 1 }
            print("DIAG \(name.prefix(40)): candidates \(candidates.count) (hits \(candHits.count) \(candHitFields.sorted()) "
                  + "at ranks \(candRank)), verified \(verified.count), "
                  + "committed \(reading.committedCount) [\(reading.liters.value.map { "\($0)" } ?? "-") / "
                  + "\(reading.unitPrice.value.map { "\($0)" } ?? "-") / \(reading.total.value.map { "\($0)" } ?? "-")]")
            for line in roleLines { print(line) }
            for line in missLines { print(line) }
        }
        print("DIAG stages over \(stage.photos) photos: candidate hit \(stage.anyCandidateHit), verified hit \(stage.anyVerifiedHit), "
              + "two transaction rows verified \(stage.threeVerifiedHit), assigned right \(stage.assignedRight), committed \(stage.committed)")
    }
}
