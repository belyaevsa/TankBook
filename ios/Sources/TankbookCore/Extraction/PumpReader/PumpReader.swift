import CoreGraphics
import Foundation

/// The reader end to end for windows already located and assigned: warp each
/// window to a strip, slice it into glyph cells, classify every cell, and let
/// the law decide what to commit. Pure apart from the Core ML call.
///
/// The locator (`PumpPanelLocator`) and row assignment (`PumpRowAssignment`)
/// produce the `windows` argument in production; the harness feeds the
/// annotated quads so the number it prints measures slicer + classifier +
/// law on real pixels, with the locator's error kept out.
struct PumpReader {
    static let stripHeight: CGFloat = 96

    struct Window {
        let field: PumpField
        /// TL, TR, BR, BL in the oriented image's pixels, reading order.
        let quad: [CGPoint]
    }

    struct WindowRead {
        let field: PumpField
        let cells: [PumpCellReading]
        let glyphCount: Int
    }

    let model: PumpSegmentsModel

    /// Classifies every window's cells. Windows the slicer finds nothing in
    /// are dropped, so the law sees only what was read.
    func read(image: PumpRGBImage, windows: [Window]) throws -> [WindowRead] {
        var out: [WindowRead] = []
        for window in windows {
            guard let strip = PumpQuadWarp.warpToStrip(rgb: image, quad: window.quad, stripHeight: Self.stripHeight)
            else { continue }
            let stripRGB = PumpQuadWarp.rgbImage(from: strip)
            let cells = PumpGlyphSlicer.slice(stripRGB.grayscale())
            guard !cells.isEmpty else { continue }
            // Fewer cells than the field can show is a slicer miscount; the
            // law must not be handed it as a reading.
            guard PumpRowAssignment.plausibleCount(cells.filter { !$0.isBlank }.count, for: window.field)
                    || window.field == .board else { continue }
            var readings: [PumpCellReading] = []
            for cell in cells where !cell.isBlank {
                let crop = Self.cropCell(stripRGB, rect: cell.rect)
                var probabilities = try Self.averaged(model: model, crops: crop)
                if probabilities.count > 7 { probabilities[7] = cell.hasDecimalPoint ? max(probabilities[7], 0.5) : probabilities[7] }
                readings.append(PumpCellReading(probabilities: probabilities))
            }
            out.append(WindowRead(field: window.field, cells: readings, glyphCount: cells.count))
        }
        return out
    }

    /// A located candidate the reader vouches for: the slicer found a row of
    /// glyph cells and the classifier is confident they are digits. Printed
    /// labels (SUMMA, LIITRIT, a brand) fail the second test - the decoder's
    /// margin on a letter is low.
    struct VerifiedWindow {
        let quad: [CGPoint]
        let glyphCount: Int
        let meanMargin: Double
    }

    static let minimumVerifiedCells = 3
    /// Mean decode margin (nats) below which a row is not digits. A digit cell
    /// the model is sure of sits well above 2; letters and stickers below 1.
    static let minimumMeanMargin = 1.5

    /// Everything from a photo with no annotation: locate, verify, assign,
    /// read, resolve. `rotationCW` turns the photo so the display reads
    /// upright; the app's capture is upright already.
    func readPhoto(image: PumpRGBImage, rotationCW: Int = 0, currency: CurrencyCode?,
                   priceBand: FuelPriceBand?) throws -> PumpDisplayReading {
        let upright = PumpPanelLocator.rotatedRGB(image, rotationCW: rotationCW)
        let candidates = PumpPanelLocator.locate(upright, rotationCW: 0)
        let verified = try verify(image: upright, candidates: candidates)
        let assignment = PumpRowAssignment.assign(
            windows: verified.map { PumpRowAssignment.Window(quad: $0.quad, glyphCount: $0.glyphCount) },
            rotationCW: 0)
        var windows: [Window] = []
        for (window, role) in zip(verified, assignment.roles) {
            guard let role else { continue }
            windows.append(Window(field: role, quad: window.quad))
        }
        return try resolve(image: upright, windows: windows, currency: currency, priceBand: priceBand)
    }

    func verify(image: PumpRGBImage, candidates: [PumpPanelLocator.Candidate]) throws -> [VerifiedWindow] {
        var out: [VerifiedWindow] = []
        for candidate in candidates.prefix(12) {
            let quad = candidate.quad.map { CGPoint(x: $0.x * CGFloat(image.width), y: $0.y * CGFloat(image.height)) }
            guard let strip = PumpQuadWarp.warpToStrip(rgb: image, quad: quad, stripHeight: Self.stripHeight) else { continue }
            let stripRGB = PumpQuadWarp.rgbImage(from: strip)
            let cells = PumpGlyphSlicer.slice(stripRGB.grayscale()).filter { !$0.isBlank }
            guard cells.count >= Self.minimumVerifiedCells, cells.count <= PumpReadingLaw.maxCells else { continue }
            var margins: [Double] = []
            for cell in cells {
                let probabilities = try Self.averaged(model: model, crops: [Self.resample(
                    stripRGB, rect: cell.rect, width: PumpSegmentsModel.inputWidth,
                    height: PumpSegmentsModel.inputHeight)!])
                margins.append(PumpCellReading(probabilities: probabilities).margin)
            }
            let mean = margins.reduce(0, +) / Double(margins.count)
            guard mean >= Self.minimumMeanMargin else { continue }
            out.append(VerifiedWindow(quad: quad, glyphCount: cells.count, meanMargin: mean))
        }
        return out
    }

    /// The whole answer for one photo.
    func resolve(image: PumpRGBImage, windows: [Window], currency: CurrencyCode?,
                 priceBand: FuelPriceBand?) throws -> PumpDisplayReading {
        let reads = try read(image: image, windows: windows)
        return PumpReadingLaw.resolve(
            windows: reads.map { PumpLocatedWindow(field: $0.field, cells: $0.cells) },
            currency: currency, priceBand: priceBand)
    }

    // MARK: - Cells

    /// Test-time augmentation: the cell and four crops shifted by 6 % of its
    /// size, averaged - the slicer's own placement uncertainty, measured to
    /// lift digit accuracy and to make the margin rank (ml/pump-reader/REPORT.md).
    static let augmentationOffsets: [(dx: CGFloat, dy: CGFloat)] = [
        (0, 0), (-0.06, 0), (0.06, 0), (0, -0.06), (0, 0.06),
    ]

    static func cropCell(_ strip: PumpRGBImage, rect: CGRect) -> [PumpRGBImage] {
        augmentationOffsets.compactMap { offset in
            let shifted = rect.offsetBy(dx: offset.dx * rect.width, dy: offset.dy * rect.height)
            return resample(strip, rect: shifted, width: PumpSegmentsModel.inputWidth,
                            height: PumpSegmentsModel.inputHeight)
        }
    }

    static func averaged(model: PumpSegmentsModel, crops: [PumpRGBImage]) throws -> [Double] {
        var sum = [Double](repeating: 0, count: 8)
        for crop in crops {
            let p = try model.probabilities(cell: crop)
            for i in 0..<8 { sum[i] += p[i] }
        }
        return sum.map { $0 / Double(max(crops.count, 1)) }
    }

    /// Bilinear resample of `rect` (clamped to the strip) into `width x height`.
    static func resample(_ image: PumpRGBImage, rect: CGRect, width: Int, height: Int) -> PumpRGBImage? {
        let x0 = max(0, min(CGFloat(image.width - 1), rect.minX))
        let y0 = max(0, min(CGFloat(image.height - 1), rect.minY))
        let x1 = max(x0 + 1, min(CGFloat(image.width), rect.maxX))
        let y1 = max(y0 + 1, min(CGFloat(image.height), rect.maxY))
        var out = [UInt8](repeating: 255, count: width * height * 4)
        let sx = (x1 - x0) / CGFloat(width)
        let sy = (y1 - y0) / CGFloat(height)
        for y in 0..<height {
            let fy = y0 + (CGFloat(y) + 0.5) * sy - 0.5
            let iy = Int(floor(fy))
            let ty = fy - CGFloat(iy)
            for x in 0..<width {
                let fx = x0 + (CGFloat(x) + 0.5) * sx - 0.5
                let ix = Int(floor(fx))
                let tx = fx - CGFloat(ix)
                for c in 0..<3 {
                    let v00 = sample(image, ix, iy, c)
                    let v10 = sample(image, ix + 1, iy, c)
                    let v01 = sample(image, ix, iy + 1, c)
                    let v11 = sample(image, ix + 1, iy + 1, c)
                    let top = v00 * (1 - tx) + v10 * tx
                    let bottom = v01 * (1 - tx) + v11 * tx
                    out[(y * width + x) * 4 + c] = UInt8(max(0, min(255, (top * (1 - ty) + bottom * ty).rounded())))
                }
            }
        }
        return PumpRGBImage(width: width, height: height, pixels: out)
    }

    private static func sample(_ image: PumpRGBImage, _ x: Int, _ y: Int, _ c: Int) -> CGFloat {
        let cx = max(0, min(image.width - 1, x))
        let cy = max(0, min(image.height - 1, y))
        return CGFloat(image.pixels[(cy * image.width + cx) * 4 + c])
    }
}
