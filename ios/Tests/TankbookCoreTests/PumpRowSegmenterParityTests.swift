import CoreGraphics
import ImageIO
import Foundation
@testable import TankbookCore

import Testing

/// Parity: the Swift decode reproduces `segeval`'s Python quads on the heldout
/// stills it wrote (`<run>/heldout-quads.json`), so the Swift arms measure the
/// model the rotated gate scored. Opt-in: `PUMP_SEGMENTER=<.mlpackage>` and
/// `PUMP_SEGMENTER_QUADS=<heldout-quads.json>`.
@Suite("PU.76 spike: the Swift segmenter decode matches Python")
struct PumpRowSegmenterParityTests {
    @Test("the same rows, within a hundredth of the image, on the heldout stills")
    func swiftMatchesPython() throws {
        let env = ProcessInfo.processInfo.environment
        guard let modelPath = env["PUMP_SEGMENTER"], let quadsPath = env["PUMP_SEGMENTER_QUADS"] else { return }
        let segmenter = try PumpRowSegmenter(contentsOf: URL(fileURLWithPath: modelPath))
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: quadsPath))) as? [String: Any]
        let images = root?["images"] as? [String: [[String: Any]]] ?? [:]
        let dir = URL(fileURLWithPath: quadsPath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("seg/heldout")
        var rows = 0, matched = 0, countMismatch: [String] = [], worst = 0.0
        for (name, python) in images.sorted(by: { $0.key < $1.key }) {
            guard let src = CGImageSourceCreateWithURL(dir.appendingPathComponent(name) as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            let swift = segmenter.rows(in: cg)
            if swift.count != python.count { countMismatch.append("\(name): swift \(swift.count) python \(python.count)") }
            for p in python {
                rows += 1
                let pq = (p["quad"] as? [[Double]] ?? []).map { CGPoint(x: $0[0], y: $0[1]) }
                let best = swift.map { s in zip(s.quad, pq).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 1 }.min() ?? 1
                worst = max(worst, best)
                if best < 0.01 { matched += 1 }
            }
        }
        print("PU.76 parity: \(matched)/\(rows) python rows within 0.01 of a swift row; worst corner \(worst); "
              + "count mismatches \(countMismatch.count): \(countMismatch.prefix(8))")
        #expect(rows > 200)
        #expect(Double(matched) >= 0.97 * Double(rows))
    }
}
