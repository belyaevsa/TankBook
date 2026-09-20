import CoreGraphics
import Foundation

/// Tightens a detected row box to its digits before the slicer sees it. The
/// detector's boxes are axis-aligned and carry a margin of panel around the
/// glyphs; the classifier was measured on human quads that hug the ink
/// (ml/pump-reader/REPORT.md round 4: framing alone moved digit accuracy by
/// a third), and the slicer's pitch estimate suffers most from dark panel
/// above and below the band. The refinement is the slicer's own first step
/// run on the warped box: the ink band by row projection and the ink extent
/// by column projection, mapped back to a quad inside the original box.
/// Nothing here reads a digit; a box the projection finds no band in is
/// returned unchanged.
enum PumpBoxRefiner {
    /// Fraction of the band's height kept as a margin around the ink on every side.
    static let margin: CGFloat = 0.12
    /// The band must be at least this fraction of the box height to trust it;
    /// below, the projection found noise, not a row.
    static let minimumBandFraction: CGFloat = 0.25
    /// The strip height the projection runs at.
    static let stripHeight: CGFloat = 64

    static func refine(quad: [CGPoint], in image: PumpRGBImage) -> [CGPoint] {
        guard quad.count == 4,
              let strip = PumpQuadWarp.warpToStrip(rgb: image, quad: quad, stripHeight: stripHeight) else { return quad }
        let gray = PumpQuadWarp.rgbImage(from: strip).grayscale()
        let w = gray.width, h = gray.height
        guard w > 8, h > 8 else { return quad }
        // Ink relative to the panel: the panel level is the median, the polarity
        // whichever side has the longer tail (a dark-on-light LCD's ink is the
        // low tail).
        let sorted = gray.pixels.sorted()
        let p05 = sorted[sorted.count / 20], p50 = sorted[sorted.count / 2], p95 = sorted[sorted.count * 19 / 20]
        let darkOnLight = (p50 - p05) > (p95 - p50)
        var ink = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let v = darkOnLight ? (p50 - gray.pixels[i]) : (gray.pixels[i] - p50)
            ink[i] = max(0, v)
        }
        // Row band.
        var rows = [Float](repeating: 0, count: h)
        for y in 0..<h { for x in 0..<w { rows[y] += ink[y * w + x] } }
        guard let rowMax = rows.max(), rowMax > 0 else { return quad }
        let rowThreshold = 0.2 * rowMax
        guard let top = rows.firstIndex(where: { $0 > rowThreshold }),
              let bottom = rows.lastIndex(where: { $0 > rowThreshold }), bottom > top,
              CGFloat(bottom - top + 1) >= minimumBandFraction * CGFloat(h) else { return quad }
        // Column extent within the band.
        var cols = [Float](repeating: 0, count: w)
        for x in 0..<w { for y in top...bottom { cols[x] += ink[y * w + x] } }
        guard let colMax = cols.max(), colMax > 0 else { return quad }
        let colThreshold = 0.15 * colMax
        guard let left = cols.firstIndex(where: { $0 > colThreshold }),
              let right = cols.lastIndex(where: { $0 > colThreshold }), right > left else { return quad }
        // The band and extent, with a margin, as fractions of the strip - then
        // bilinearly onto the original quad (TL, TR, BR, BL).
        let bandH = CGFloat(bottom - top + 1)
        let fy0 = max(0, (CGFloat(top) - margin * bandH) / CGFloat(h))
        let fy1 = min(1, (CGFloat(bottom + 1) + margin * bandH) / CGFloat(h))
        let fx0 = max(0, (CGFloat(left) - margin * bandH) / CGFloat(w))
        let fx1 = min(1, (CGFloat(right + 1) + margin * bandH) / CGFloat(w))
        func at(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
            let top = CGPoint(x: quad[0].x + (quad[1].x - quad[0].x) * fx, y: quad[0].y + (quad[1].y - quad[0].y) * fx)
            let bottom = CGPoint(x: quad[3].x + (quad[2].x - quad[3].x) * fx, y: quad[3].y + (quad[2].y - quad[3].y) * fx)
            return CGPoint(x: top.x + (bottom.x - top.x) * fy, y: top.y + (bottom.y - top.y) * fy)
        }
        return [at(fx0, fy0), at(fx1, fy0), at(fx1, fy1), at(fx0, fy1)]
    }
}
