import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// A speed change moves no reading (PU.75): the direct-pixels warp returns the
/// bytes the original per-pixel sampler produced, and the bytes a caller used
/// to get by building the strip's `CGImage` and drawing it back into a buffer.
@Suite("The strip warp's pixels are the original warp's pixels")
struct PumpQuadWarpIdentityTests {
    /// The sampler as it was before the pointer rewrite, kept as the oracle.
    private static func referenceWarp(_ rgb: PumpRGBImage, quad: [CGPoint], stripHeight: CGFloat) -> [UInt8] {
        let sw = max(1, Int((stripHeight * PumpQuadWarp.aspect(of: quad)).rounded()))
        let sh = max(1, Int(stripHeight))
        let dst = [CGPoint(x: 0, y: 0), CGPoint(x: CGFloat(sw), y: 0),
                   CGPoint(x: CGFloat(sw), y: CGFloat(sh)), CGPoint(x: 0, y: CGFloat(sh))]
        let hom = PumpQuadWarp.homography(src: dst, dst: quad)
        let data = rgb.pixels, width = rgb.width, height = rgb.height
        var out = [UInt8](repeating: 0, count: sw * sh * 4)
        for row in 0..<sh {
            let py = Double(row) + 0.5
            for col in 0..<sw {
                let px = Double(col) + 0.5
                let wgt = hom[6] * px + hom[7] * py + hom[8]
                let x = (hom[0] * px + hom[1] * py + hom[2]) / wgt
                let y = (hom[3] * px + hom[4] * py + hom[5]) / wgt
                let idx = (row * sw + col) * 4
                out[idx + 3] = 255
                guard x >= 0, y >= 0, x <= Double(width - 1), y <= Double(height - 1) else { continue }
                let x0 = Int(floor(x)), y0 = Int(floor(y))
                let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
                let fx = x - Double(x0), fy = y - Double(y0)
                for chan in 0..<3 {
                    let i00 = Double(data[y0 * width * 4 + x0 * 4 + chan])
                    let i10 = Double(data[y0 * width * 4 + x1 * 4 + chan])
                    let i01 = Double(data[y1 * width * 4 + x0 * 4 + chan])
                    let i11 = Double(data[y1 * width * 4 + x1 * 4 + chan])
                    let value = (i00 * (1 - fx) + i10 * fx) * (1 - fy) + (i01 * (1 - fx) + i11 * fx) * fy
                    out[idx + chan] = UInt8(clamping: Int(value.rounded()))
                }
            }
        }
        return out
    }

    @Test("every heldout window warps to the same bytes, with and without the CGImage round trip",
          .pumpFixturesPresent)
    func warpIsBitIdentical() throws {
        let data = try Data(contentsOf: PumpReaderTestSupport.windowsURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var windows = 0, mismatches: [String] = []
        for (name, value) in root.sorted(by: { $0.key < $1.key }) where PumpReaderTestSupport.isHeldout(name) {
            guard let ann = value as? [String: Any],
                  let image = PumpReaderTestSupport.loadRGB(
                      url: PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)) else { continue }
            for raw in ann["windows"] as? [[String: Any]] ?? [] {
                guard let norm = raw["quad"] as? [[Double]], norm.count == 4 else { continue }
                let quad = norm.map { CGPoint(x: $0[0] * Double(image.width), y: $0[1] * Double(image.height)) }
                let direct = PumpQuadWarp.warpToStripPixels(rgb: image, quad: quad, stripHeight: 32)
                let reference = Self.referenceWarp(image, quad: quad, stripHeight: 32)
                let roundTrip = PumpQuadWarp.warpToStrip(rgb: image, quad: quad, stripHeight: 32)
                    .map { PumpQuadWarp.rgbImage(from: $0).pixels }
                windows += 1
                if direct.pixels != reference || direct.pixels != roundTrip {
                    mismatches.append("\(name.prefix(8)) \(raw["field"] ?? "")")
                }
            }
        }
        #expect(windows > 200, "only \(windows) windows compared")
        #expect(mismatches.isEmpty, "differ: \(mismatches.prefix(10))")
    }
}
