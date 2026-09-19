import CoreGraphics
import Foundation

// PU.4 - the panel locator. Classical CV only, best-effort: downscale, local
// contrast normalisation, then a row/column projection that treats a number
// window as a dense horizontal band of high-contrast ink. It is deliberately
// not polished - the digit slicer is the row's deliverable - but it must report
// an honest IoU so PU.6 knows where the corpus stands.

enum PumpPanelLocator {

    /// A candidate number window: an axis-aligned quad, normalised [0,1] over the
    /// image the locator was given (already rotated so the text reads upright).
    struct Candidate: Sendable, Equatable {
        let quad: [CGPoint]
        let glyphCount: Int
    }

    /// Vision's text rectangles first (a display row is a row of same-height
    /// character boxes; PU.24), the classical projection as the second source,
    /// merged by IoU so a window found twice is one candidate. Ranked by how
    /// many glyph boxes a row has and how large they are - a display's digits
    /// are the biggest text on a pump.
    static func locate(_ rgb: PumpRGBImage, rotationCW: Int = 0) -> [Candidate] {
        let rotated = rotatedRGB(rgb, rotationCW: rotationCW)
        var candidates: [(Candidate, CGFloat)] = []
        // Vision proposes on a downscaled frame: a display's digits are tens
        // of pixels tall at 1600 px wide, and the quads are normalised anyway.
        let small = downscaleRGB(rotated, targetWidth: 1600)
        if let cg = PumpQuadWarp.makeImage(small.pixels, width: small.width, height: small.height) {
            for row in PumpVisionProposer.rows(in: cg) {
                candidates.append((Candidate(quad: row.quad, glyphCount: row.boxCount),
                                   CGFloat(row.boxCount) * row.height))
            }
        }
        for classical in locate(downscaleGray(rotated, targetWidth: 1024)) {
            let duplicate = candidates.contains { PumpQuadWarp.iou($0.0.quad, classical.quad) > 0.5 }
            if !duplicate {
                candidates.append((classical, 0))
            }
        }
        return candidates.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// The image turned so the display reads upright, in the reader's frame.
    static func rotatedRGB(_ rgb: PumpRGBImage, rotationCW: Int) -> PumpRGBImage {
        let turns = ((rotationCW % 360) + 360) % 360 / 90
        var image = rgb
        for _ in 0..<turns {
            var out = [UInt8](repeating: 0, count: image.pixels.count)
            let w = image.width, h = image.height
            for y in 0..<h {
                for x in 0..<w {
                    let src = (y * w + x) * 4
                    // (x, y) in the old image lands at (h - 1 - y, x) in the new.
                    let dst = (x * h + (h - 1 - y)) * 4
                    out[dst] = image.pixels[src]; out[dst + 1] = image.pixels[src + 1]
                    out[dst + 2] = image.pixels[src + 2]; out[dst + 3] = image.pixels[src + 3]
                }
            }
            image = PumpRGBImage(width: h, height: w, pixels: out)
        }
        return image
    }

    static func locate(_ gray: PumpGrayscale) -> [Candidate] {
        let width = gray.width
        let height = gray.height
        guard width > 0, height > 0 else { return [] }

        // Local contrast, then a mask of high-contrast pixels.
        let blurRadius = max(4, width / 70)
        let blurred = boxBlur(gray.pixels, width: width, height: height, radius: blurRadius)
        var mask = [Bool](repeating: false, count: width * height)
        for i in 0..<(width * height) {
            mask[i] = abs(gray.pixels[i] - blurred[i]) > 0.15
        }

        // Row projection: a number window is a dense band of contrast.
        var rowSum = [Int](repeating: 0, count: height)
        for y in 0..<height {
            for x in 0..<width where mask[y * width + x] { rowSum[y] += 1 }
        }
        guard let maxRow = rowSum.max(), maxRow > 0 else { return [] }
        let rowThreshold = max(2, Int(Double(maxRow) * 0.30))

        // Merge contiguous rows above the threshold into bands.
        var bands: [(top: Int, bottom: Int)] = []
        var bandStart: Int?
        for y in 0..<height {
            if rowSum[y] > rowThreshold {
                if bandStart == nil { bandStart = y }
            } else if let start = bandStart {
                bands.append((start, y - 1))
                bandStart = nil
            }
        }
        if let start = bandStart { bands.append((start, height - 1)) }

        // Each band becomes a candidate whose horizontal extent is the dense
        // column range within it.
        var candidates: [Candidate] = []
        for band in bands {
            let bandHeight = band.bottom - band.top + 1
            guard bandHeight >= 10 else { continue }
            var colSum = [Int](repeating: 0, count: width)
            for y in band.top...band.bottom {
                for x in 0..<width where mask[y * width + x] { colSum[x] += 1 }
            }
            guard let maxCol = colSum.max(), maxCol > 0 else { continue }
            let colThreshold = max(1, Int(Double(maxCol) * 0.15))
            var left = width
            var right = 0
            for x in 0..<width where colSum[x] > colThreshold {
                left = min(left, x)
                right = max(right, x)
            }
            guard right - left >= 20 else { continue }

            let quad = [
                CGPoint(x: CGFloat(left) / CGFloat(width), y: CGFloat(band.top) / CGFloat(height)),
                CGPoint(x: CGFloat(right + 1) / CGFloat(width), y: CGFloat(band.top) / CGFloat(height)),
                CGPoint(x: CGFloat(right + 1) / CGFloat(width), y: CGFloat(band.bottom + 1) / CGFloat(height)),
                CGPoint(x: CGFloat(left) / CGFloat(width), y: CGFloat(band.bottom + 1) / CGFloat(height)),
            ]
            let glyphCount = (right - left) / max(1, bandHeight * 2 / 3)
            candidates.append(Candidate(quad: quad, glyphCount: glyphCount))
        }

        return candidates.sorted { area($0.quad) > area($1.quad) }
    }

    private static func area(_ quad: [CGPoint]) -> CGFloat {
        let x0 = min(quad[0].x, quad[1].x)
        let x1 = max(quad[0].x, quad[1].x)
        let y0 = min(quad[0].y, quad[2].y)
        let y1 = max(quad[0].y, quad[2].y)
        return (x1 - x0) * (y1 - y0)
    }

    // MARK: - Image primitives

    static func downscaleRGB(_ rgb: PumpRGBImage, targetWidth: Int) -> PumpRGBImage {
        guard rgb.width > targetWidth else { return rgb }
        let scale = Double(rgb.width) / Double(targetWidth)
        let height = max(1, Int((Double(rgb.height) / scale).rounded()))
        var out = [UInt8](repeating: 255, count: targetWidth * height * 4)
        for y in 0..<height {
            let sy = min(rgb.height - 1, Int(Double(y) * scale))
            for x in 0..<targetWidth {
                let sx = min(rgb.width - 1, Int(Double(x) * scale))
                let i = (sy * rgb.width + sx) * 4
                let o = (y * targetWidth + x) * 4
                out[o] = rgb.pixels[i]; out[o + 1] = rgb.pixels[i + 1]; out[o + 2] = rgb.pixels[i + 2]
            }
        }
        return PumpRGBImage(width: targetWidth, height: height, pixels: out)
    }

    static func downscaleGray(_ rgb: PumpRGBImage, targetWidth: Int) -> PumpGrayscale {
        let width = min(targetWidth, rgb.width)
        let scale = Double(rgb.width) / Double(width)
        let height = max(1, Int((Double(rgb.height) / scale).rounded()))
        var out = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let sy = min(rgb.height - 1, Int(Double(y) * scale))
            for x in 0..<width {
                let sx = min(rgb.width - 1, Int(Double(x) * scale))
                let i = (sy * rgb.width + sx) * 4
                out[y * width + x] = (0.299 * Float(rgb.pixels[i])
                    + 0.587 * Float(rgb.pixels[i + 1])
                    + 0.114 * Float(rgb.pixels[i + 2])) / 255.0
            }
        }
        return PumpGrayscale(width: width, height: height, pixels: out)
    }

    static func rotateClockwise90(_ gray: PumpGrayscale) -> PumpGrayscale {
        let w = gray.width
        let h = gray.height
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let nx = h - 1 - y
                let ny = x
                out[ny * h + nx] = gray.pixels[y * w + x]
            }
        }
        return PumpGrayscale(width: h, height: w, pixels: out)
    }

    static func boxBlur(_ values: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        var out = [Float](repeating: 0, count: width * height)
        let r = max(1, radius)
        var tmp = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = y * width
            var prefix = [Float](repeating: 0, count: width + 1)
            for x in 0..<width { prefix[x + 1] = prefix[x] + values[row + x] }
            for x in 0..<width {
                let left = max(0, x - r)
                let right = min(width - 1, x + r)
                tmp[row + x] = (prefix[right + 1] - prefix[left]) / Float(right - left + 1)
            }
        }
        for x in 0..<width {
            var prefix = [Float](repeating: 0, count: height + 1)
            for y in 0..<height { prefix[y + 1] = prefix[y] + tmp[y * width + x] }
            for y in 0..<height {
                let top = max(0, y - r)
                let bottom = min(height - 1, y + r)
                out[y * width + x] = (prefix[bottom + 1] - prefix[top]) / Float(bottom - top + 1)
            }
        }
        return out
    }
}
