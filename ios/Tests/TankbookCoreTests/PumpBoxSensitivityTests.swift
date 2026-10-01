import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// How the reader and the law answer when the hand windows are moved or
/// resized a few percent (PU.91): the oracle boxes, then the same boxes wider,
/// narrower, taller, shorter, shifted and jittered, read through `resolve` with
/// no locator. A reader that only reads well on exact boxes reads the app's
/// located boxes badly; this is the curve a reader change reports. Opt-in
/// (`PUMP_BOX_SENSITIVITY=1`), with `PUMP_ROWREADER_MODEL` to score a candidate.
@Suite("Reader sensitivity to the box (PU.91)")
struct PumpBoxSensitivityTests {
    private static var enabled: Bool { ProcessInfo.processInfo.environment["PUMP_BOX_SENSITIVITY"] == "1" }

    typealias Perturb = ([CGPoint]) -> [CGPoint]

    static func scaled(_ q: [CGPoint], sx: CGFloat, sy: CGFloat, dx: CGFloat = 0, dy: CGFloat = 0) -> [CGPoint] {
        let cx = q.map(\.x).reduce(0, +) / 4, cy = q.map(\.y).reduce(0, +) / 4
        let w = (PumpQuadWarp.distance(q[0], q[1]) + PumpQuadWarp.distance(q[3], q[2])) / 2
        let h = (PumpQuadWarp.distance(q[0], q[3]) + PumpQuadWarp.distance(q[1], q[2])) / 2
        return q.map { CGPoint(x: cx + ($0.x - cx) * sx + dx * w, y: cy + ($0.y - cy) * sy + dy * h) }
    }

    @Test("committed and correct cells as the hand boxes move", .enabled(if: enabled, "PUMP_BOX_SENSITIVITY=1"))
    func sensitivity() throws {
        let model = try PumpSegmentsModel(contentsOf: PumpReaderTestSupport.repoRoot.appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage"))
        let reader = PumpReader(model: model, detector: nil, rowReader: PumpReaderTestSupport.makeRowReader())
        let expected = try CorpusScorer.loadExpected(PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent("expected.csv"))
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: PumpReaderTestSupport.windowsURL)) as? [String: Any] ?? [:]
        let pack = try FuelPriceBandStore.bundledPack()
        var seed: UInt64 = 42
        func rand() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(Double(seed >> 11) / Double(1 << 53)) * 2 - 1 }
        let variants: [(String, Perturb)] = [
            ("hand", { $0 }),
            ("wider 6%", { Self.scaled($0, sx: 1.06, sy: 1.0) }),
            ("narrower 6%", { Self.scaled($0, sx: 0.94, sy: 1.0) }),
            ("taller 10%", { Self.scaled($0, sx: 1.0, sy: 1.10) }),
            ("shorter 10%", { Self.scaled($0, sx: 1.0, sy: 0.90) }),
            ("down 8% of h", { Self.scaled($0, sx: 1, sy: 1, dy: 0.08) }),
            ("right 3% of w", { Self.scaled($0, sx: 1, sy: 1, dx: 0.03) }),
            ("corner jitter 2%", { q in
                let w = PumpQuadWarp.distance(q[0], q[1]), h = PumpQuadWarp.distance(q[0], q[3])
                return q.map { CGPoint(x: $0.x + rand() * 0.02 * w, y: $0.y + rand() * 0.06 * h) } })
        ]
        var base: [String: [Double?]] = [:]
        for (label, perturb) in variants {
            var committed = 0, correct = 0, flipped = 0, total = 0
            for (name, value) in root.sorted(by: { $0.key < $1.key }) {
                guard name != "_about", let ann = value as? [String: Any], let want = expected[name],
                      PumpReaderTestSupport.isHeldout(name),
                      let image = PumpReaderTestSupport.loadRGB(url: PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)) else { continue }
                let rotation = (ann["rotationCW"] as? NSNumber)?.intValue ?? 0
                var windows: [PumpReader.Window] = []
                for raw in ann["windows"] as? [[String: Any]] ?? [] {
                    guard let f = raw["field"] as? String, let field = PumpField(rawValue: f),
                          let text = raw["text"] as? String, !text.isEmpty, let quad = raw["quad"] as? [[Double]] else { continue }
                    let px = PumpQuadWarp.readingOrder(PumpReaderTestSupport.quadPixels(quad, width: image.width, height: image.height), rotationCW: rotation)
                    windows.append(PumpReader.Window(field: field, quad: perturb(px)))
                }
                let r = try reader.resolve(image: image, windows: windows, currency: want.currency,
                                           priceBand: want.currency.flatMap { pack.currencyBand(currency: $0) })
                let got = [r.liters, r.unitPrice, r.total].map { $0.value.map { NSDecimalNumber(decimal: $0).doubleValue } }
                let wants = [want.liters, want.unitPrice, want.total]
                for (g, w) in zip(got, wants) where w != nil {
                    total += 1
                    if let g { committed += 1; if abs(g - w!) < 0.1 { correct += 1 } }
                }
                if label == "hand" { base[name] = got } else if base[name].map({ $0 != got }) ?? false { flipped += 1 }
            }
            print("SENS \(label): committed \(committed), correct \(correct) of \(total); photos changed vs hand \(flipped)")
        }
    }
}
