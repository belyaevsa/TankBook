import Accelerate
import CoreGraphics
import Foundation

/// Turns an upright row box to the angle of the digits inside it.
///
/// The row detector returns upright rectangles, while a display row in a photo
/// is usually turned a few degrees - and on a long, thin row a small turn moves
/// the digits' top and bottom by a good part of the row height across its
/// width, which the slicer then reads as a different pitch and band.
///
/// The angle comes from the row's horizontal structure. Seven-segment digits
/// share a flat top and bottom (segments a and d), so when the strip is level
/// its row-by-row brightness changes sharply at those edges; a turned strip
/// smears them across more rows. The search keeps the angle whose strip has the
/// sharpest row profile. Vertical strokes are deliberately not used: many
/// pump fonts are italic, and levelling the strokes would shear every digit.
///
/// Each row gets its own angle: rows at different heights of one display
/// photographed at an angle do not share one (perspective).
enum PumpRowDeskew {
    /// The angles searched either side of level, in degrees. The corpus has
    /// rows turned past 15 degrees (a display shot from the side).
    static let maximumAngle = 30.0
    /// Above this turn the upright box is resized to the row it bounds (see
    /// `rowSize`); below it the box keeps its size, which measured safer than
    /// any refit because the verifier's rules were tuned on the detector's own
    /// framing.
    static let largeTurn = 6.0
    static let coarseStep = 1.0
    static let fineStep = 0.2
    /// How much taller than the detector's box the search crop is, as a
    /// fraction of its height, so a turned row's corners stay inside it.
    static let searchPadding: CGFloat = 0.3
    /// The strip height the search warps to: coarse is enough for a profile.
    static let searchStripHeight: CGFloat = 48
    /// A turn is kept only when it sharpens the profile by at least this much
    /// over level; below it the difference is noise and the box stays upright.
    static let minimumGain = 0.05
    /// A row's ink band: pixel rows whose activity is at least this fraction
    /// of the strip's busiest row.
    static let bandFraction: Float = 0.3
    /// Margin kept above and below the ink band, as a fraction of its height.
    static let bandMargin: CGFloat = 0.12

    struct Result {
        /// TL, TR, BR, BL in image pixels, turned by `degrees`.
        let quad: [CGPoint]
        /// Positive turns the row clockwise in image coordinates (y down).
        let degrees: Double
    }

    /// The row box turned to its digits' angle, or the input unchanged when no
    /// turn beats level by `minimumGain`. With `fitsBand` the height is also
    /// refitted to the ink band at that angle; without it the turned box keeps
    /// the detector's height and centre.
    static func deskew(_ quad: [CGPoint], in image: PumpRGBImage, fitsBand: Bool = false) -> Result {
        let box = PumpRowAssignment.bounds(quad, rotationCW: 0)
        guard box.width > 4, box.height > 4 else { return Result(quad: quad, degrees: 0) }
        let centre = CGPoint(x: box.midX, y: box.midY)
        let searchHeight = box.height * (1 + 2 * searchPadding)
        // Past `largeTurn` the upright box around the row is nearly square, and
        // a crop that size warps to a strip a few dozen pixels wide - the digits
        // alias and a wrong angle can outscore the right one. There each trial
        // crop is sized to the row that angle implies.
        func score(_ degrees: Double) -> Double {
            let row = abs(degrees) > largeTurn
                ? rowSize(boundingWidth: box.width, boundingHeight: box.height, degrees: degrees)
                : CGSize(width: box.width, height: box.height)
            let height = abs(degrees) > largeTurn ? row.height * (1 + 2 * searchPadding) : searchHeight
            let q = inside(centre: centre, width: row.width, height: height, degrees: degrees, image: image)
            guard let strip = PumpQuadWarp.warpToStrip(rgb: image, quad: q, stripHeight: searchStripHeight) else {
                return 0
            }
            return profileSharpness(PumpQuadWarp.rgbImage(from: strip).grayscale())
        }
        let level = score(0)
        var best = (degrees: 0.0, score: level)
        for step in stride(from: -maximumAngle, through: maximumAngle, by: coarseStep) where step != 0 {
            let s = score(step)
            if s > best.score { best = (step, s) }
        }
        for step in stride(from: best.degrees - coarseStep, through: best.degrees + coarseStep, by: fineStep) {
            let s = score(step)
            if s > best.score { best = (step, s) }
        }
        guard best.degrees != 0, level > 0, best.score >= level * (1 + minimumGain) else {
            return Result(quad: quad, degrees: 0)
        }
        if !fitsBand {
            let size = abs(best.degrees) > largeTurn
                ? rowSize(boundingWidth: box.width, boundingHeight: box.height, degrees: best.degrees)
                : CGSize(width: box.width, height: box.height)
            return Result(quad: rotatedRect(centre: centre, width: size.width, height: size.height, degrees: best.degrees),
                          degrees: best.degrees)
        }
        // Fit the height to the ink band at the chosen angle, so the turned box
        // is as tight as the upright one was rather than padded.
        let wide = rotatedRect(centre: centre, width: box.width, height: searchHeight, degrees: best.degrees)
        guard let strip = PumpQuadWarp.warpToStrip(rgb: image, quad: wide, stripHeight: searchStripHeight),
              let band = inkBand(PumpQuadWarp.rgbImage(from: strip).grayscale()) else {
            return Result(quad: rotatedRect(centre: centre, width: box.width, height: box.height, degrees: best.degrees),
                          degrees: best.degrees)
        }
        let rows = CGFloat(strip.height)
        let margin = CGFloat(band.upperBound - band.lowerBound + 1) * bandMargin
        let top = max(0, CGFloat(band.lowerBound) - margin) / rows
        let bottom = min(rows, CGFloat(band.upperBound + 1) + margin) / rows
        // The band's centre, as an offset from the crop's centre along the
        // turned box's own vertical axis.
        let offset = ((top + bottom) / 2 - 0.5) * searchHeight
        let radians = best.degrees * .pi / 180
        let shifted = CGPoint(x: centre.x - offset * CGFloat(sin(radians)), y: centre.y + offset * CGFloat(cos(radians)))
        let height = max((bottom - top) * searchHeight, box.height * 0.5)
        return Result(quad: rotatedRect(centre: shifted, width: box.width, height: height, degrees: best.degrees),
                      degrees: best.degrees)
    }

    /// The length and height of a row turned by `degrees` whose upright bounding
    /// box is `boundingWidth` x `boundingHeight` - what the detector returns for
    /// a turned row. Keeping the box's own size is wrong at a large turn: the
    /// box is taller than the row by its length times the sine and shorter
    /// along it, so a turned copy overhangs the row above and misses the row's
    /// ends. Solves w = L cos + H sin, h = L sin + H cos; a box that is not a
    /// tight bound can give a height near zero, so both are floored.
    static func rowSize(boundingWidth w: CGFloat, boundingHeight h: CGFloat, degrees: Double) -> CGSize {
        let r = abs(degrees) * .pi / 180
        let c = CGFloat(cos(r)), s = CGFloat(sin(r))
        let det = c * c - s * s
        guard det > 0.1 else { return CGSize(width: w, height: h) }
        let length = (w * c - h * s) / det, height = (h * c - w * s) / det
        return CGSize(width: max(length, 0.5 * w), height: max(height, 0.3 * h))
    }

    /// A search crop kept inside the photo: its height is shrunk until every
    /// corner lies in the frame. Samples from outside the photo come back black,
    /// and the jump from a display to black scores as a sharp edge, so a crop
    /// leaving the frame would win for the wrong reason.
    static func inside(centre: CGPoint, width: CGFloat, height: CGFloat, degrees: Double,
                       image: PumpRGBImage) -> [CGPoint] {
        var h = height
        for _ in 0..<12 {
            let q = rotatedRect(centre: centre, width: width, height: h, degrees: degrees)
            if q.allSatisfy({ $0.x >= 0 && $0.y >= 0 && $0.x <= CGFloat(image.width) && $0.y <= CGFloat(image.height) }) {
                return q
            }
            h *= 0.85
        }
        return rotatedRect(centre: centre, width: width, height: h, degrees: degrees)
    }

    /// A rectangle of the given size about `centre`, turned by `degrees`:
    /// TL, TR, BR, BL in reading order.
    static func rotatedRect(centre: CGPoint, width: CGFloat, height: CGFloat, degrees: Double) -> [CGPoint] {
        let r = degrees * .pi / 180
        let c = CGFloat(cos(r)), s = CGFloat(sin(r))
        let hw = width / 2, hh = height / 2
        return [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)].map { dx, dy in
            CGPoint(x: centre.x + dx * c - dy * s, y: centre.y + dx * s + dy * c)
        }
    }

    /// How sharply the strip's brightness changes from one pixel row to the
    /// next, summed over the strip and normalised by its size. Polarity-free:
    /// an LCD's dark digits and an LED's bright ones both score.
    static func profileSharpness(_ gray: PumpGrayscale) -> Double {
        guard gray.height > 2, gray.width > 0 else { return 0 }
        var means = [Double](repeating: 0, count: gray.height)
        for y in 0..<gray.height {
            var sum: Float = 0
            for x in 0..<gray.width { sum += gray[x, y] }
            means[y] = Double(sum / Float(gray.width))
        }
        var total = 0.0
        for y in 1..<gray.height { let d = means[y] - means[y - 1]; total += d * d }
        return total / Double(gray.height)
    }

    /// The pixel rows holding the digits: the longest run of rows whose
    /// horizontal activity (the digits' vertical strokes crossing the row)
    /// reaches `bandFraction` of the busiest row.
    static func inkBand(_ gray: PumpGrayscale) -> ClosedRange<Int>? {
        guard gray.width > 1, gray.height > 0 else { return nil }
        var activity = [Float](repeating: 0, count: gray.height)
        for y in 0..<gray.height {
            var sum: Float = 0
            for x in 1..<gray.width { sum += abs(gray[x, y] - gray[x - 1, y]) }
            activity[y] = sum
        }
        guard let peak = activity.max(), peak > 0 else { return nil }
        let threshold = peak * bandFraction
        var best: ClosedRange<Int>?
        var start: Int?
        for y in 0...gray.height {
            let on = y < gray.height && activity[y] >= threshold
            if on, start == nil { start = y }
            if !on, let s = start {
                if best.map({ $0.count }) ?? 0 < y - s { best = s...(y - 1) }
                start = nil
            }
        }
        return best
    }
}

extension PumpReader {
    /// When the reader turns detector rows to their digits' angle.
    enum DeskewMode: String, Sendable {
        /// Detector rows are read as the detector placed them.
        case off
        /// The rows are read upright first and turned only when that read
        /// commits nothing, so a photo the upright read handles never changes.
        case onRefusal
        /// Every detector row is turned before it is judged - the diagnostic
        /// arm; measured, it gains on some photos and loses on others.
        case always
        /// The whole photo is levelled by the rows' median angle and read,
        /// whatever that read commits - the diagnostic arm for levelling.
        case level
    }

    /// The display's turn in an upright photo, from the detector's own rows.
    func levelAngle(_ upright: PumpRGBImage) -> Double? {
        let w = CGFloat(upright.width), h = CGFloat(upright.height)
        let rows = detectedRows(for: upright).map { $0.quad.map { CGPoint(x: $0.x * w, y: $0.y * h) } }
        return PumpRowDeskew.levelAngle(rows: rows, in: upright)
    }

    /// A normalised detector quad turned to its digits' angle, normalised back.
    static func deskewed(_ quad: [CGPoint], in image: PumpRGBImage) -> [CGPoint] {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let pixels = quad.map { CGPoint(x: $0.x * w, y: $0.y * h) }
        return PumpRowDeskew.deskew(pixels, in: image).quad.map { CGPoint(x: $0.x / w, y: $0.y / h) }
    }

    /// What `readPhotoDetailed` read and how: the orientation, whether the rows
    /// were turned, and the turn applied to the whole photo (0 when it was not
    /// levelled). A reading from a levelled photo has its windows in that
    /// photo's frame; `PumpRowDeskew.unlevelled` maps them back.
    struct DetailedReading {
        let reading: PumpDisplayReading
        let deskewed: Bool
        let rotationCW: Int
        let levelDegrees: Double
    }

    /// `readPhoto`, saying how it read. On a refusal, `.onRefusal` tries two
    /// more reads in order: the detector rows turned to their digits' angle,
    /// then the whole photo levelled by the rows' median angle - the detector
    /// places boxes badly on a display turned far past what it was trained on.
    func readPhotoDetailed(image: PumpRGBImage, rotationCW: Int? = nil, currency: CurrencyCode?,
                           priceBand: FuelPriceBand?) throws -> DetailedReading {
        let rotation = rotationCW ?? bestOrientation(for: image)
        let upright = PumpPanelLocator.rotatedRGB(image, rotationCW: rotation)
        if deskew == .level, let angle = levelAngle(upright), abs(angle) >= PumpRowDeskew.minimumLevelAngle {
            let reading = try readUpright(PumpRowDeskew.levelled(upright, degrees: -angle), deskewRows: false,
                                          currency: currency, priceBand: priceBand)
            return DetailedReading(reading: reading, deskewed: false, rotationCW: rotation, levelDegrees: -angle)
        }
        let first = try readUpright(upright, deskewRows: deskew == .always, currency: currency, priceBand: priceBand)
        if deskew == .onRefusal, first.committedCount == 0 {
            let turned = try readUpright(upright, deskewRows: true, currency: currency, priceBand: priceBand)
            if turned.committedCount > 0 {
                return DetailedReading(reading: turned, deskewed: true, rotationCW: rotation, levelDegrees: 0)
            }
            if let angle = levelAngle(upright), abs(angle) >= PumpRowDeskew.minimumLevelAngle {
                let level = PumpRowDeskew.levelled(upright, degrees: -angle)
                let reading = try readUpright(level, deskewRows: false, currency: currency, priceBand: priceBand)
                if reading.committedCount > 0 {
                    return DetailedReading(reading: reading, deskewed: false, rotationCW: rotation, levelDegrees: -angle)
                }
            }
        }
        return DetailedReading(reading: first, deskewed: deskew == .always, rotationCW: rotation, levelDegrees: 0)
    }
}

// MARK: - Levelling the whole photo

extension PumpRowDeskew {
    /// Below this the photo is not levelled: the rows are read as found.
    static let minimumLevelAngle = 3.0

    /// The display's turn in the photo: the median of the detector rows' own
    /// angles. Rows on one display disagree by a few degrees (perspective), so
    /// the median levels every row closely rather than one row exactly.
    static func levelAngle(rows: [[CGPoint]], in image: PumpRGBImage) -> Double? {
        let angles = rows.map { deskew($0, in: image).degrees }.sorted()
        guard !angles.isEmpty else { return nil }
        let mid = angles.count / 2
        return angles.count % 2 == 1 ? angles[mid] : (angles[mid - 1] + angles[mid]) / 2
    }

    /// The photo turned by `degrees` about its centre (positive clockwise, y
    /// down), the same size; what the turn brings in from outside is black.
    /// The detector was trained on nearly level rows, so a display shot from
    /// the side is levelled for it rather than read where it misplaces boxes.
    static func levelled(_ image: PumpRGBImage, degrees: Double) -> PumpRGBImage {
        let w = image.width, h = image.height
        var source = image.pixels
        var out = [UInt8](repeating: 0, count: source.count)
        // vImage applies the transform from the output back to the input, so
        // the matrix is the inverse turn; `levelledTurnsClockwise` pins the
        // direction.
        let r = -degrees * .pi / 180
        let c = cos(r), s = sin(r), cx = Double(w) / 2, cy = Double(h) / 2
        var transform = vImage_AffineTransform(
            a: Float(c), b: Float(s), c: Float(-s), d: Float(c),
            tx: Float(cx - c * cx + s * cy), ty: Float(cy - s * cx - c * cy))
        var background: [UInt8] = [0, 0, 0, 255]
        source.withUnsafeMutableBytes { src in
            out.withUnsafeMutableBytes { dst in
                var from = vImage_Buffer(data: src.baseAddress, height: vImagePixelCount(h),
                                         width: vImagePixelCount(w), rowBytes: w * 4)
                var into = vImage_Buffer(data: dst.baseAddress, height: vImagePixelCount(h),
                                         width: vImagePixelCount(w), rowBytes: w * 4)
                _ = vImageAffineWarp_ARGB8888(&from, &into, nil, &transform, &background,
                                              vImage_Flags(kvImageBackgroundColorFill))
            }
        }
        return PumpRGBImage(width: w, height: h, pixels: out)
    }

    /// A pixel point of the levelled photo, back in the photo before levelling.
    static func unlevelled(_ point: CGPoint, degrees: Double, width: Int, height: Int) -> CGPoint {
        let r = -degrees * .pi / 180
        let c = CGFloat(cos(r)), s = CGFloat(sin(r))
        let cx = CGFloat(width) / 2, cy = CGFloat(height) / 2
        let dx = point.x - cx, dy = point.y - cy
        return CGPoint(x: cx + dx * c - dy * s, y: cy + dx * s + dy * c)
    }
}
