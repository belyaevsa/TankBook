import CoreGraphics
import Foundation
import ImageIO

// PU.4 - the number-window warp. Loads an EXIF-oriented image (matching the
// Python scorer's `exif_transpose`), solves the strip->image homography from a
// normalised quad, and bilinearly warps the quad to a straight, horizontal
// strip of a fixed height. Strip corners are ordered TL,TR,BR,BL, so a quad
// that is rotated in the image comes out upright without a separate image
// rotation - the homography un-rotates it.
//
// The homography is solved directly (8x8 linear system, h22 = 1) rather than by
// SVD; four exact correspondences make the system full rank unless the quad is
// degenerate, and the direct solve is deterministic and dependency-free.

/// A decoded image as a row-major RGBA byte buffer with the origin at the top-left.
struct PumpRGBImage: @unchecked Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt8] // 4 bytes per pixel, row-major, top-left origin

    /// Luminance in [0, 1], row-major, 0 = dark, 1 = bright.
    func grayscale() -> PumpGrayscale {
        var out = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let r = Float(pixels[i * 4])
            let g = Float(pixels[i * 4 + 1])
            let b = Float(pixels[i * 4 + 2])
            out[i] = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
        }
        return PumpGrayscale(width: width, height: height, pixels: out)
    }

    /// Writes the buffer as an 8-bit RGB PNG, returning nil on failure.
    @discardableResult
    func writePNG(to url: URL) -> Bool {
        guard let image = PumpQuadWarp.makeImage(pixels, width: width, height: height) else {
            return false
        }
        return PumpQuadWarp.writePNG(image: image, to: url)
    }
}

/// A grayscale image: luminance in [0, 1], row-major, 0 = dark, 1 = bright.
struct PumpGrayscale: @unchecked Sendable {
    let width: Int
    let height: Int
    let pixels: [Float]

    subscript(x: Int, y: Int) -> Float {
        pixels[y * width + x]
    }
}

enum PumpQuadWarp {

    // MARK: - Loading (EXIF orientation applied)

    /// Loads an image with its EXIF orientation applied, matching the Python
    /// scorer's `ImageOps.exif_transpose`. `CreateThumbnailAtIndex` with
    /// `CreateThumbnailWithTransform` returns the full-resolution, display-
    /// oriented pixels without a manual orientation matrix.
    static func loadOrientedImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func rgbImage(from image: CGImage) -> PumpRGBImage {
        let (data, width, height) = rgbaBytes(of: image)
        return PumpRGBImage(width: width, height: height, pixels: data)
    }

    // MARK: - Geometry

    /// The quad's aspect (top+bottom length over left+right length), which is
    /// invariant under the EXIF/rotationCW transforms the annotation describes.
    static func aspect(of quad: [CGPoint]) -> CGFloat {
        let (tl, tr, br, bl) = (quad[0], quad[1], quad[2], quad[3])
        let width = (distance(tr, tl) + distance(br, bl)) / 2
        let height = (distance(bl, tl) + distance(br, tr)) / 2
        return height > 0 ? width / height : 1
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - Rotation (matches the scorer's `rotate_points_cw`)

    static func rotatedSize(width: Int, height: Int, rotationCW: Int) -> (width: Int, height: Int) {
        let rot = ((rotationCW % 360) + 360) % 360
        return rot == 90 || rot == 270 ? (height, width) : (width, height)
    }

    /// Rotates pixel-space points clockwise by `rotationCW` degrees around the
    /// old image centre, landing in the expanded image's coordinate frame. The
    /// inverse of the image rotation a caller applies to upright the text, and
    /// numerically identical to the Python scorer's `rotate_points_cw`.
    /// Reorders an annotated quad (TL, TR, BR, BL in image space) into reading
    /// order for a display that reads upright only after the image is rotated
    /// `rotationCW` degrees clockwise. Rotating 90° clockwise makes the image's
    /// left edge the top edge, so the upright top-left is the image's
    /// bottom-left; 270° makes the right edge the top. The warp is a homography
    /// from these corners, so the image itself never needs rotating.
    static func readingOrder(_ quad: [CGPoint], rotationCW: Int) -> [CGPoint] {
        guard quad.count == 4 else { return quad }
        switch ((rotationCW % 360) + 360) % 360 {
        case 90: return [quad[3], quad[0], quad[1], quad[2]]
        case 180: return [quad[2], quad[3], quad[0], quad[1]]
        case 270: return [quad[1], quad[2], quad[3], quad[0]]
        default: return quad
        }
    }

    static func rotatePointsClockwise(
        _ points: [CGPoint], rotationCW: Int, oldSize: (width: Int, height: Int)
    ) -> [CGPoint] {
        let rot = ((rotationCW % 360) + 360) % 360
        guard rot != 0 else { return points }
        let (w, h) = oldSize
        let angle = Double(-rot) * .pi / 180.0
        let ca = cos(angle)
        let sa = sin(angle)
        let cx = Double(w) / 2
        let cy = Double(h) / 2
        let (nw, nh) = rotatedSize(width: w, height: h, rotationCW: rot)
        let ncx = Double(nw) / 2
        let ncy = Double(nh) / 2
        return points.map { point in
            let dx = Double(point.x) - cx
            let dy = Double(point.y) - cy
            return CGPoint(x: ca * dx - sa * dy + ncx, y: sa * dx + ca * dy + ncy)
        }
    }

    // MARK: - Warp

    /// Warps `image` so that `quad` (TL,TR,BR,BL in image pixel coords) becomes
    /// an axis-aligned strip `stripHeight` px tall, proportionally wide.
    static func warpToStrip(image: CGImage, quad: [CGPoint], stripHeight: CGFloat) -> CGImage? {
        warpToStrip(rgb: rgbImage(from: image), quad: quad, stripHeight: stripHeight)
    }

    /// The same warp over an already-decoded RGBA buffer, so a caller that holds
    /// the pixels warps many windows without re-decoding the full image each time.
    static func warpToStrip(rgb: PumpRGBImage, quad: [CGPoint], stripHeight: CGFloat) -> CGImage? {
        let sw = max(1, Int((stripHeight * aspect(of: quad)).rounded()))
        let sh = max(1, Int(stripHeight))
        let dst = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: CGFloat(sw), y: 0),
            CGPoint(x: CGFloat(sw), y: CGFloat(sh)),
            CGPoint(x: 0, y: CGFloat(sh)),
        ]
        let h = homography(src: dst, dst: quad)
        let src = rgb.pixels
        let srcW = rgb.width
        let srcH = rgb.height
        var out = [UInt8](repeating: 0, count: sw * sh * 4)
        for y in 0..<sh {
            let py = Double(y) + 0.5
            for x in 0..<sw {
                let px = Double(x) + 0.5
                let wgt = h[6] * px + h[7] * py + h[8]
                let u = (h[0] * px + h[1] * py + h[2]) / wgt
                let v = (h[3] * px + h[4] * py + h[5]) / wgt
                let rgb = sampleBilinear(src, width: srcW, height: srcH, x: u, y: v)
                let idx = (y * sw + x) * 4
                out[idx] = rgb.0
                out[idx + 1] = rgb.1
                out[idx + 2] = rgb.2
                out[idx + 3] = 255
            }
        }
        return makeImage(out, width: sw, height: sh)
    }

    /// Solves the 3x3 homography (h22 = 1) mapping `src[i]` -> `dst[i]`.
    /// Returns the 9 entries row-major; applying H to a strip point yields the
    /// corresponding image point.
    static func homography(src: [CGPoint], dst: [CGPoint]) -> [Double] {
        var m = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for i in 0..<4 {
            let x = Double(src[i].x)
            let y = Double(src[i].y)
            let u = Double(dst[i].x)
            let v = Double(dst[i].y)
            m[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u]
            m[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v]
        }
        for col in 0..<8 {
            var pivot = col
            for row in (col + 1)..<8 where abs(m[row][col]) > abs(m[pivot][col]) {
                pivot = row
            }
            if pivot != col { m.swapAt(pivot, col) }
            let pv = m[col][col]
            guard abs(pv) > 1e-12 else { continue }
            for row in 0..<8 where row != col {
                let factor = m[row][col] / pv
                for c in col..<9 {
                    m[row][c] -= factor * m[col][c]
                }
            }
        }
        var h = [Double](repeating: 0, count: 9)
        for i in 0..<8 {
            h[i] = m[i][8] / m[i][i]
        }
        h[8] = 1.0
        return h
    }

    // MARK: - Pixel plumbing

    private static func rgbaBytes(of image: CGImage) -> ([UInt8], Int, Int) {
        let w = image.width
        let h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &data, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (data, w, h)
        }
        // A CGBitmapContext's buffer is top-row-first; drawing the image with no
        // transform already lands row 0 at the top, matching the normalized
        // quad's y-down convention.
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (data, w, h)
    }

    private static func sampleBilinear(
        _ data: [UInt8], width w: Int, height h: Int, x: Double, y: Double
    ) -> (UInt8, UInt8, UInt8) {
        if x < 0 || y < 0 || x > Double(w - 1) || y > Double(h - 1) {
            return (0, 0, 0)
        }
        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let x1 = min(x0 + 1, w - 1)
        let y1 = min(y0 + 1, h - 1)
        let fx = x - Double(x0)
        let fy = y - Double(y0)
        func channel(_ c: Int) -> UInt8 {
            let i00 = Double(data[y0 * w * 4 + x0 * 4 + c])
            let i10 = Double(data[y0 * w * 4 + x1 * 4 + c])
            let i01 = Double(data[y1 * w * 4 + x0 * 4 + c])
            let i11 = Double(data[y1 * w * 4 + x1 * 4 + c])
            let top = i00 * (1 - fx) + i10 * fx
            let bot = i01 * (1 - fx) + i11 * fx
            let value = top * (1 - fy) + bot * fy
            return UInt8(clamping: Int(value.rounded()))
        }
        return (channel(0), channel(1), channel(2))
    }

    static func makeImage(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        // `pixels` is top-left origin; a CGBitmapContext's buffer is also
        // top-row-first, so a straight copy lands the pixels without a flip.
        pixels.withUnsafeBufferPointer { buffer in
            ctx.data?.copyMemory(from: buffer.baseAddress!, byteCount: width * height * 4)
        }
        return ctx.makeImage()
    }

    static func writePNG(image: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }
}
