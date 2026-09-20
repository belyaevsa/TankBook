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
    /// The learned row detector (PU.33); nil runs the Vision + classical
    /// locator alone, which is the fallback either way.
    let detector: PumpRowDetector?

    init(model: PumpSegmentsModel, detector: PumpRowDetector? = nil) {
        self.model = model
        self.detector = detector
    }

    /// Fewer detector rows than this and the frame falls back to the Vision +
    /// classical proposals: a display has at least total and volume.
    static let detectorMinimumRows = 2
    static let refineDetectedBoxes = false

    /// The locator's candidates for an upright frame: the detector's rows
    /// first (ranked by confidence, each flagged as detected so the verifier
    /// keeps it on count and size alone), then the Vision + classical
    /// proposals when the detector found fewer than two rows.
    func candidates(for upright: PumpRGBImage) -> [PumpPanelLocator.Candidate] {
        var out: [PumpPanelLocator.Candidate] = []
        if let detector, let cg = PumpQuadWarp.makeImage(upright.pixels, width: upright.width, height: upright.height) {
            out = detector.detect(in: cg).map { PumpPanelLocator.Candidate(quad: $0.quad, glyphCount: 0, detected: true) }
        }
        if out.count < Self.detectorMinimumRows {
            out += PumpPanelLocator.locate(upright, rotationCW: 0)
        }
        return out
    }

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
            out.append(WindowRead(field: window.field, cells: Self.singleDecimalMark(readings), glyphCount: cells.count))
        }
        return out
    }

    /// A number row shows one decimal mark. When the classifier (or the slicer's
    /// mark detection) fires on two cells - a segment gap, a bezel speck or a
    /// comma-shaped digit tail reads as a second mark - only the strongest mark
    /// stands; the others are cleared so the law's placement hint and the
    /// displayed string ("1.9.09") do not carry the false one.
    static func singleDecimalMark(_ readings: [PumpCellReading]) -> [PumpCellReading] {
        let marked = readings.indices.filter { readings[$0].decimalPoint }
        guard marked.count > 1 else { return readings }
        let keep = marked.max { readings[$0].probabilities[7] < readings[$1].probabilities[7] }!
        return readings.enumerated().map { index, reading in
            guard index != keep, reading.decimalPoint else { return reading }
            var probabilities = reading.probabilities
            probabilities[7] = min(probabilities[7], 0.49)
            return PumpCellReading(probabilities: probabilities)
        }
    }

    /// A located candidate the reader vouches for: the slicer found a row of
    /// glyph cells and the classifier is confident they are digits. Printed
    /// labels (SUMMA, LIITRIT, a brand) fail the second test - the decoder's
    /// margin on a letter is low.
    struct VerifiedWindow {
        let quad: [CGPoint]
        let glyphCount: Int
        let meanMargin: Double
        /// From the row detector (PU.33) rather than the Vision proposals.
        var detected: Bool = false
    }

    static let minimumVerifiedCells = 3
    /// Mean decode margin (nats) below which a row is not digits. A digit cell
    /// the model is sure of sits well above 2; letters and stickers below 1.
    static let minimumMeanMargin = 1.0
    /// A digit row is about 0.6 heights wide per cell (seven-segment glyphs
    /// are taller than wide, plus the gaps and a decimal mark). A candidate
    /// far wider than its cells account for is a text line or a bezel band
    /// the slicer found a few marks in, not a number window.
    static let maximumAspectPerCell: CGFloat = 1.3
    static let frameEdgeFraction: CGFloat = 0.01
    /// How many locator candidates the verifier looks at, in the locator's
    /// rank order. A photo yields 30-45 (Vision lines, character rows and the
    /// classical bands); the annotated rows of the heldout stills sat at
    /// ranks beyond twelve often enough that twelve lost whole displays.
    static let maximumCandidates = 48

    /// Everything from a photo with no annotation: locate, verify, assign,
    /// read, resolve. `rotationCW` turns the photo so the display reads
    /// upright; the app's capture is upright already.
    func readPhoto(image: PumpRGBImage, rotationCW: Int = 0, currency: CurrencyCode?,
                   priceBand: FuelPriceBand?) throws -> PumpDisplayReading {
        let upright = PumpPanelLocator.rotatedRGB(image, rotationCW: rotationCW)
        let verified = try verify(image: upright, candidates: candidates(for: upright))
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

    /// A display's digit rows are large in the frame: the corpus's windows are
    /// 3-12 % of the image height, a receipt's or a label's lines under 2 %.
    /// Shared with the classification stage (`PumpDisplayCapture`).
    static let minimumRowHeightFraction: CGFloat = 0.025

    /// What the verifier saw for one candidate, for the diagnostic and the
    /// verifier itself: nil cells means the strip could not be cut.
    struct Verdict {
        let quad: [CGPoint]
        let heightFraction: CGFloat
        let cells: Int
        let meanMargin: Double
        let kept: Bool
        var detected: Bool = false
    }

    /// Two verified windows are one row when they overlap this much - the
    /// locator offers a row several times (Vision's line, its character
    /// boxes merged, the classical band), and without suppression the
    /// assigner reads the duplicates as a board.
    static let duplicateIoU: CGFloat = 0.3
    static let duplicateContainment: CGFloat = 0.6

    func verify(image: PumpRGBImage, candidates: [PumpPanelLocator.Candidate]) throws -> [VerifiedWindow] {
        let kept = try verdicts(image: image, candidates: candidates).filter(\.kept)
        // Best version of each row first: more cells read with a wider margin
        // on a taller strip is the fuller window, not a fragment of it.
        let ranked = kept.sorted { Self.strength($0) > Self.strength($1) }
        var out: [VerifiedWindow] = []
        for verdict in ranked {
            let duplicate = out.contains { existing in
                PumpQuadWarp.iou(existing.quad, verdict.quad) >= Self.duplicateIoU
                    || Self.containment(existing.quad, verdict.quad) >= Self.duplicateContainment
            }
            if !duplicate {
                out.append(VerifiedWindow(quad: verdict.quad, glyphCount: verdict.cells, meanMargin: verdict.meanMargin,
                                          detected: verdict.detected))
            }
        }
        return out
    }

    private static func strength(_ v: Verdict) -> Double {
        Double(v.cells) * v.meanMargin * Double(v.heightFraction)
    }

    /// Intersection over the smaller box: a fragment inside a row scores
    /// high here while its IoU with the row stays low.
    private static func containment(_ a: [CGPoint], _ b: [CGPoint]) -> CGFloat {
        let ra = PumpRowAssignment.bounds(a, rotationCW: 0), rb = PumpRowAssignment.bounds(b, rotationCW: 0)
        let inter = ra.intersection(rb)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return 0 }
        let smaller = min(ra.width * ra.height, rb.width * rb.height)
        return smaller > 0 ? (inter.width * inter.height) / smaller : 0
    }

    func verdicts(image: PumpRGBImage, candidates: [PumpPanelLocator.Candidate]) throws -> [Verdict] {
        var out: [Verdict] = []
        for candidate in candidates.prefix(Self.maximumCandidates) {
            var quad = candidate.quad.map { CGPoint(x: $0.x * CGFloat(image.width), y: $0.y * CGFloat(image.height)) }
            // A detected box carries panel around the digits; PumpBoxRefiner
            // tightens it to the ink, measured on the heldout split as no
            // gain (22 -> 21 committed), so it stays off until the read
            // stage's losses are understood (PumpLivePathDiagnosticTests).
            if candidate.detected && Self.refineDetectedBoxes {
                quad = PumpBoxRefiner.refine(quad: quad, in: image)
            }
            let ys = quad.map(\.y)
            let heightFraction = (ys.max()! - ys.min()!) / CGFloat(image.height)
            // A row against the frame's top or bottom edge is a banner or a
            // sign the photo cut, never a display row the user framed.
            let edge = Self.frameEdgeFraction * CGFloat(image.height)
            let touchesEdge = ys.min()! <= edge || ys.max()! >= CGFloat(image.height) - edge
            guard heightFraction >= Self.minimumRowHeightFraction, !touchesEdge,
                  let strip = PumpQuadWarp.warpToStrip(rgb: image, quad: quad, stripHeight: Self.stripHeight) else {
                out.append(Verdict(quad: quad, heightFraction: heightFraction, cells: 0, meanMargin: 0, kept: false))
                continue
            }
            let stripRGB = PumpQuadWarp.rgbImage(from: strip)
            let cells = PumpGlyphSlicer.slice(stripRGB.grayscale()).filter { !$0.isBlank }
            guard cells.count >= Self.minimumVerifiedCells, cells.count <= PumpReadingLaw.maxCells else {
                out.append(Verdict(quad: quad, heightFraction: heightFraction, cells: cells.count, meanMargin: 0, kept: false))
                continue
            }
            var margins: [Double] = []
            for cell in cells {
                let probabilities = try Self.averaged(model: model, crops: [Self.resample(
                    stripRGB, rect: cell.rect, width: PumpSegmentsModel.inputWidth,
                    height: PumpSegmentsModel.inputHeight)!])
                margins.append(PumpCellReading(probabilities: probabilities).margin)
            }
            let mean = margins.reduce(0, +) / Double(margins.count)
            let aspect = CGFloat(strip.width) / CGFloat(strip.height)
            let shaped = aspect <= Self.maximumAspectPerCell * CGFloat(cells.count) + 1
            // A detected row is kept on count and size alone: the detector's
            // confidence already vouched for it, and gating it on the
            // classifier's margin coupled the live number to every retrain.
            let kept = candidate.detected ? shaped : (shaped && mean >= Self.minimumMeanMargin)
            out.append(Verdict(quad: quad, heightFraction: heightFraction, cells: cells.count, meanMargin: mean, kept: kept,
                               detected: candidate.detected))
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
