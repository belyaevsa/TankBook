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
    /// When to turn each detector row to its digits' angle (`PumpRowDeskew`).
    /// Off by default while it is measured.
    var deskew: DeskewMode = .off
    /// The row-level sequence reader: when present it reads each located
    /// window's strip whole, in place of the slicer and the cell classifier.
    /// Verification and orientation still use the slicer and the classifier.
    var rowReader: PumpRowReader?

    init(model: PumpSegmentsModel, detector: PumpRowDetector? = nil, deskew: DeskewMode = .off,
         rowReader: PumpRowReader? = nil) {
        self.model = model
        self.detector = detector
        self.deskew = deskew
        self.rowReader = rowReader
    }

    /// Fewer detector rows than this and the frame falls back to the Vision +
    /// classical proposals: a display has at least total and volume.
    static let detectorMinimumRows = 2

    /// The locator's candidates for an upright frame: the detector's rows
    /// first (ranked by confidence, each flagged as detected so the verifier
    /// keeps it on count and size alone), then the Vision + classical
    /// proposals when the detector found fewer than two rows.
    func candidates(for upright: PumpRGBImage) -> [PumpPanelLocator.Candidate] {
        candidates(for: upright, deskewRows: deskew == .always)
    }

    /// The candidates with the detector rows turned to their digits' angle, or not.
    func candidates(for upright: PumpRGBImage, deskewRows: Bool) -> [PumpPanelLocator.Candidate] {
        var out = detectedRows(for: upright).map {
            PumpPanelLocator.Candidate(quad: deskewRows ? Self.deskewed($0.quad, in: upright) : $0.quad,
                                       glyphCount: 0, detected: true)
        }
        if out.count < Self.detectorMinimumRows {
            out += PumpPanelLocator.locate(upright, rotationCW: 0)
        }
        return out
    }

    /// The detector's rows after the stacked-row rescue, with their confidences -
    /// the fast classification path's only input (PU.38). Empty when no detector
    /// is loaded, which makes the fast path abstain and the verifier decide.
    func detectedRows(for upright: PumpRGBImage) -> [PumpRowDetector.Row] {
        guard let detector,
              let cg = PumpQuadWarp.makeImage(upright.pixels, width: upright.width, height: upright.height)
        else { return [] }
        return Self.rescueStackedRows(detector.detect(in: cg))
    }

    /// The detector's rows the reader will use: every row above the confidence
    /// cut, plus a low-confidence row rescued from beside a passing row when it
    /// shares that row's x-span. Transaction rows stack on one column on every
    /// head; a keypad row sits off the display's span, so it is never rescued.
    static func rescueStackedRows(_ rows: [PumpRowDetector.Row]) -> [PumpRowDetector.Row] {
        let passing = rows.filter { $0.confidence >= PumpRowDetector.minimumConfidence }
        var kept = passing
        for row in rows where row.confidence < PumpRowDetector.minimumConfidence {
            if passing.contains(where: { sharesSpan(row.quad, $0.quad) && stacks(row.quad, $0.quad) }) {
                kept.append(row)
            }
        }
        return kept.sorted { $0.confidence > $1.confidence }
    }

    /// Whether two rows share an x-span: one contains the other, or both edges
    /// line up within a quarter of the passing row's width.
    static func sharesSpan(_ a: [CGPoint], _ b: [CGPoint]) -> Bool {
        let ra = PumpRowAssignment.bounds(a, rotationCW: 0)
        let rb = PumpRowAssignment.bounds(b, rotationCW: 0)
        if (ra.minX >= rb.minX && ra.maxX <= rb.maxX) || (rb.minX >= ra.minX && rb.maxX <= ra.maxX) {
            return true
        }
        let tolerance = 0.25 * rb.width
        return abs(ra.minX - rb.minX) <= tolerance && abs(ra.maxX - rb.maxX) <= tolerance
    }

    /// Whether two rows sit above or below each other within three row heights.
    static func stacks(_ a: [CGPoint], _ b: [CGPoint]) -> Bool {
        let ra = PumpRowAssignment.bounds(a, rotationCW: 0)
        let rb = PumpRowAssignment.bounds(b, rotationCW: 0)
        let gap: CGFloat
        if ra.maxY <= rb.minY { gap = rb.minY - ra.maxY }
        else if rb.maxY <= ra.minY { gap = ra.minY - rb.maxY }
        else { return true }
        return gap <= 3 * max(ra.height, rb.height)
    }

    /// A detected box hugs or clips the digits (median IoU 0.80 on the heldout
    /// stills; video-003 loses a thin leading `1` and a trailing `2`), so a
    /// detected quad is widened sideways before slicing. The margin is small
    /// and horizontal only, by measurement on the heldout live path: 0.1 row
    /// heights each side keeps 29 cells and adds a photo, 0.2 keeps 29, 0.5
    /// drops to 3 - the slicer's pitch and band come from what is inside the
    /// box, and panel, bezel and the neighbouring row's ink poison both. Any
    /// vertical margin (0.15) does the same (29 -> 3 to 15 cells). Clamped to
    /// the frame.
    static let detectedMarginHorizontal: CGFloat = 0.1
    static let detectedMarginVertical: CGFloat = 0

    /// The strip and cells a candidate is judged on. A detected box is sliced
    /// widened and as it came, and the widened slice stands only when it found
    /// at least as many cells: the margin exists to recover a clipped edge
    /// digit, and a margin that brings in bezel or a neighbour's ink loses
    /// cells instead (pump-209: 6 -> 1), so the margin may never cost a digit.
    struct SlicedCandidate {
        let quad: [CGPoint]
        let strip: CGImage
        let rgb: PumpRGBImage
        /// The cells a reading uses: the slicer's occupied cells only.
        let cells: [GlyphCell]
        /// The full slice, blanks included - what the geometry verdict reads
        /// (a leading blank run is a display's unlit cells; an interior run is
        /// a keypad or spaced text).
        let fullCells: [GlyphCell]
    }

    static func sliceDetectedOrOriginal(_ original: [CGPoint], detected: Bool, in image: PumpRGBImage) -> SlicedCandidate? {
        func slice(_ quad: [CGPoint]) -> SlicedCandidate? {
            guard let strip = PumpQuadWarp.warpToStrip(rgb: image, quad: quad, stripHeight: Self.stripHeight) else { return nil }
            let rgb = PumpQuadWarp.rgbImage(from: strip)
            let cells = PumpGlyphSlicer.slice(rgb.grayscale())
            return SlicedCandidate(quad: quad, strip: strip, rgb: rgb,
                                   cells: cells.filter { !$0.isBlank }, fullCells: cells)
        }
        guard let plain = slice(original) else { return nil }
        guard detected, let wide = slice(widened(original, in: image)), wide.cells.count >= plain.cells.count else {
            return plain
        }
        return wide
    }

    static func widened(_ quad: [CGPoint], in image: PumpRGBImage) -> [CGPoint] {
        // A turned box widens along its own axes; rebuilding it from its upright
        // bounds would undo the turn.
        if quad.count == 4, abs(quad[1].y - quad[0].y) > 0.5 {
            let u = CGPoint(x: quad[1].x - quad[0].x, y: quad[1].y - quad[0].y)
            let v = CGPoint(x: quad[3].x - quad[0].x, y: quad[3].y - quad[0].y)
            let lu = max(hypot(u.x, u.y), 1), lv = max(hypot(v.x, v.y), 1)
            let ux = u.x / lu, uy = u.y / lu, vx = v.x / lv, vy = v.y / lv
            let dx = detectedMarginHorizontal * lv, dy = detectedMarginVertical * lv
            let signs: [(CGFloat, CGFloat)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
            return zip(quad, signs).map { p, sign in
                CGPoint(x: min(max(p.x + sign.0 * dx * ux + sign.1 * dy * vx, 0), CGFloat(image.width)),
                        y: min(max(p.y + sign.0 * dx * uy + sign.1 * dy * vy, 0), CGFloat(image.height)))
            }
        }
        let b = PumpRowAssignment.bounds(quad, rotationCW: 0)
        let dx = detectedMarginHorizontal * b.height
        let dy = detectedMarginVertical * b.height
        let minX = max(0, b.minX - dx), maxX = min(CGFloat(image.width), b.maxX + dx)
        let minY = max(0, b.minY - dy), maxY = min(CGFloat(image.height), b.maxY + dy)
        return [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY),
                CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY)]
    }

    /// A keypad row is printed digits in a grid of keys, and the detector's
    /// shape check cannot tell it from a display row. Two things single it out,
    /// both structural (decision 10: a detected row is never judged by the
    /// classifier): it shares its x-span with no other detected row and lies
    /// outside the widest one's span (a transaction row stacks with the
    /// column), and its cells are the tall ones of a key grid - a printed key
    /// row's band spans more than one key, so its pitch is under three quarters
    /// of the band, where a seven-segment row's pitch is around the band's
    /// height. Measured: pump-224's keypad 0.57, a true ladder price cell 0.94
    /// (pump-056); see `verdicts`.
    static let keypadMaximumCellAspect: CGFloat = 0.75

    static func isKeypadRow(_ box: CGRect, widest: CGRect, siblings: [CGRect], cellAspect: CGFloat) -> Bool {
        guard cellAspect < Self.keypadMaximumCellAspect else { return false }
        guard box.maxX <= widest.minX || box.minX >= widest.maxX else { return false }
        return !siblings.contains { $0.minX < box.maxX && $0.maxX > box.minX }
    }

    /// Classifies every window's cells. Windows the slicer finds nothing in
    /// are dropped, so the law sees only what was read.
    func read(image: PumpRGBImage, windows: [Window], trace: PumpTrace? = nil) throws -> [WindowRead] {
        var out: [WindowRead] = []
        for window in windows {
            guard let strip = PumpQuadWarp.warpToStrip(rgb: image, quad: window.quad, stripHeight: Self.stripHeight)
            else { trace?.read(window, skipped: "unwarpable"); continue }
            let stripRGB = PumpQuadWarp.rgbImage(from: strip)
            if let rowReader {
                guard let readings = try rowReader.read(strip: stripRGB) else {
                    trace?.read(window, strip: stripRGB, skipped: "noCells"); continue
                }
                guard PumpRowAssignment.plausibleCount(readings.count, for: window.field) || window.field == .board
                else { trace?.read(window, strip: stripRGB, readings: readings, skipped: "implausibleCount"); continue }
                trace?.read(window, strip: stripRGB, readings: readings)
                out.append(WindowRead(field: window.field, cells: readings, glyphCount: readings.count))
                continue
            }
            let cells = PumpGlyphSlicer.slice(stripRGB.grayscale())
            guard !cells.isEmpty else { trace?.read(window, strip: stripRGB, skipped: "noCells"); continue }
            // Fewer cells than the field can show is a slicer miscount; the
            // law must not be handed it as a reading.
            guard PumpRowAssignment.plausibleCount(cells.filter { !$0.isBlank }.count, for: window.field)
                    || window.field == .board
            else { trace?.read(window, strip: stripRGB, cells: cells, skipped: "implausibleCount"); continue }
            // The slicer's mark, where it found one, outranks the classifier's
            // bit: the slicer's mark precision measured 1.00 on the running
            // displays where the classifier's bit fired on the wrong cell
            // (`PumpMarkDiagnosticTests`), so a slicer mark sets its cell to
            // certain and silences the bit on every other cell of the row.
            let slicerMarked = cells.contains { !$0.isBlank && $0.hasDecimalPoint }
            var readings: [PumpCellReading] = []
            for cell in cells where !cell.isBlank {
                let crop = Self.cropCell(stripRGB, rect: cell.rect)
                var probabilities = try Self.averaged(model: model, crops: crop)
                if probabilities.count > 7 {
                    probabilities[7] = Self.markProbability(classifier: probabilities[7], cellMarked: cell.hasDecimalPoint,
                                                            rowMarked: slicerMarked)
                }
                readings.append(PumpCellReading(probabilities: probabilities))
            }
            let marked = Self.singleDecimalMark(readings)
            trace?.read(window, strip: stripRGB, cells: cells, readings: marked)
            out.append(WindowRead(field: window.field, cells: marked, glyphCount: cells.count))
        }
        return out
    }

    /// The mark probability a slicer-found mark is raised to: above any
    /// classifier bit, so `singleDecimalMark` keeps it when both fire.
    static let slicerMarkConfidence = 0.95

    /// The mark probability a cell carries into the reading: the slicer's
    /// mark when it found one on this cell, silence when it found one
    /// elsewhere on the row, the classifier's own bit when it found none.
    static func markProbability(classifier: Double, cellMarked: Bool, rowMarked: Bool) -> Double {
        if cellMarked { return max(classifier, slicerMarkConfidence) }
        if rowMarked { return min(classifier, 0.49) }
        return classifier
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
    /// Mean decode margin (nats) a digit cell carries. The verifier no longer
    /// gates on it - the keep decision is `PumpRowGeometry`, so a retrain
    /// cannot move the live number through this constant - but it is still
    /// computed and reported for the live-path diagnostic.
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
    /// upright; the app's capture is upright already. A nil `rotationCW` means
    /// the caller does not know the display's orientation - the phone never
    /// does, because a display can be sideways in an upright frame - so
    /// `bestOrientation` searches for it.
    func readPhoto(image: PumpRGBImage, rotationCW: Int? = nil, currency: CurrencyCode?,
                   priceBand: FuelPriceBand?) throws -> PumpDisplayReading {
        try readPhotoDetailed(image: image, rotationCW: rotationCW, currency: currency, priceBand: priceBand).reading
    }

    func readUpright(_ upright: PumpRGBImage, deskewRows: Bool, currency: CurrencyCode?,
                             priceBand: FuelPriceBand?) throws -> PumpDisplayReading {
        let verified = try verify(image: upright, candidates: candidates(for: upright, deskewRows: deskewRows))
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
        /// Why a candidate was not kept, for the annotator and the diagnostics.
        /// Nothing reads it back to decide: `kept` is the verdict.
        var dropReasons: [String] = []
    }

    /// Two verified windows are one row when they overlap this much - the
    /// locator offers a row several times (Vision's line, its character
    /// boxes merged, the classical band), and without suppression the
    /// assigner reads the duplicates as a board.
    static let duplicateIoU: CGFloat = 0.3
    static let duplicateContainment: CGFloat = 0.6

    func verify(image: PumpRGBImage, candidates: [PumpPanelLocator.Candidate],
                deadline: Date? = nil, trace: PumpTrace? = nil) throws -> [VerifiedWindow] {
        let judged = try verdicts(image: image, candidates: candidates, deadline: deadline, trace: trace)
        let verified = Self.verified(from: judged)
        trace?.current?.verified = verified
        return verified
    }

    /// The kept verdicts, one per row: `verify` without the judging, for a
    /// caller that already holds the verdicts.
    static func verified(from verdicts: [Verdict]) -> [VerifiedWindow] {
        let kept = verdicts.filter(\.kept)
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

    /// How the best version of a row is picked when the locator offered it
    /// twice: more cells read on a taller strip is the fuller window. The
    /// classifier's margin is deliberately not a term - reading it here would
    /// let a retrain choose a different duplicate and move the live path.
    private static func strength(_ v: Verdict) -> Double {
        Double(v.cells) * Double(v.heightFraction)
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

    /// `deadline` caps the wall clock the verifier may spend: checked before
    /// each candidate, it lets the classification's slow path stop a frame the
    /// detector never saw from running the full 48-candidate sweep (PU.38).
    /// The read path passes none and is unchanged.
    func verdicts(image: PumpRGBImage, candidates: [PumpPanelLocator.Candidate],
                  deadline: Date? = nil, trace: PumpTrace? = nil) throws -> [Verdict] {
        let considered = Array(candidates.prefix(Self.maximumCandidates))
        // The detected rows' boxes before the margin, for the keypad test.
        let detectedBoxes: [(index: Int, box: CGRect)] = considered.enumerated().compactMap { index, candidate in
            guard candidate.detected else { return nil }
            let pixels = candidate.quad.map { CGPoint(x: $0.x * CGFloat(image.width), y: $0.y * CGFloat(image.height)) }
            return (index, PumpRowAssignment.bounds(pixels, rotationCW: 0))
        }
        let widestDetected = detectedBoxes.max { $0.box.width < $1.box.width }?.box
        var out: [Verdict] = []
        for (index, candidate) in considered.enumerated() {
            if let deadline, Date() >= deadline { break }
            let original = candidate.quad.map { CGPoint(x: $0.x * CGFloat(image.width), y: $0.y * CGFloat(image.height)) }
            let originalYs = original.map(\.y)
            let heightFraction = (originalYs.max()! - originalYs.min()!) / CGFloat(image.height)
            // A row against the frame's top or bottom edge is a banner or a
            // sign the photo cut, never a display row the user framed. Judged
            // on the detected box, before the margin, so a margin that reaches
            // the edge does not reject a row the detector placed inside it.
            let edge = Self.frameEdgeFraction * CGFloat(image.height)
            let touchesEdge = originalYs.min()! <= edge || originalYs.max()! >= CGFloat(image.height) - edge
            let sliced = heightFraction >= Self.minimumRowHeightFraction && !touchesEdge
                ? Self.sliceDetectedOrOriginal(original, detected: candidate.detected, in: image) : nil
            guard let sliced else {
                let reasons = heightFraction < Self.minimumRowHeightFraction ? ["tooShort"]
                    : touchesEdge ? ["atFrameEdge"] : ["unsliceable"]
                out.append(Verdict(quad: original, heightFraction: heightFraction, cells: 0, meanMargin: 0, kept: false,
                                   detected: candidate.detected, dropReasons: reasons))
                trace?.judged(out[out.count - 1])
                continue
            }
            let quad = sliced.quad, strip = sliced.strip, stripRGB = sliced.rgb, cells = sliced.cells
            // The classifier's margin is computed for the diagnostic only; the
            // keep decision is the strip's geometry, for a detected row and a
            // Vision proposal alike, so a retrain cannot move it (decision 10).
            var mean = 0.0
            if !cells.isEmpty, cells.count <= PumpReadingLaw.maxCells {
                // One batched prediction for the candidate's cells; each
                // receives the same single crop it did before.
                let probabilities = try model.probabilities(cells: cells.map { Self.resample(
                    stripRGB, rect: $0.rect, width: PumpSegmentsModel.inputWidth,
                    height: PumpSegmentsModel.inputHeight)! })
                let margins = probabilities.map { PumpCellReading(probabilities: $0).margin }
                mean = margins.reduce(0, +) / Double(margins.count)
            }
            let geometry = PumpRowGeometry.verdict(cells: sliced.fullCells, stripWidth: strip.width,
                                                   stripHeight: strip.height)
            let aspect = CGFloat(strip.width) / CGFloat(strip.height)
            let shaped = aspect <= Self.maximumAspectPerCell * CGFloat(max(cells.count, 1)) + 1
            // A keypad row is the one thing the per-strip geometry cannot see:
            // its cells can look like a display row, and what singles it out is
            // its place off the display's span (PU.35), so it stays a separate
            // check on the detector's rows.
            var keypad = false
            if candidate.detected, let widestDetected,
               let box = detectedBoxes.first(where: { $0.index == index })?.box {
                let cellAspect = cells.first.map { $0.rect.width / max($0.rect.height, 1) } ?? 1
                keypad = Self.isKeypadRow(box, widest: widestDetected,
                                          siblings: detectedBoxes.filter { $0.index != index }.map(\.box),
                                          cellAspect: cellAspect)
            }
            let kept = geometry.kept && shaped && !keypad
            let reasons = geometry.reasons.map(\.rawValue) + (shaped ? [] : ["tooWide"]) + (keypad ? ["keypad"] : [])
            out.append(Verdict(quad: quad, heightFraction: heightFraction, cells: cells.count, meanMargin: mean, kept: kept,
                               detected: candidate.detected, dropReasons: reasons))
            trace?.judged(out[out.count - 1], strip: stripRGB, cells: sliced.fullCells)
        }
        return out
    }

    /// The whole answer for one photo.
    func resolve(image: PumpRGBImage, windows: [Window], currency: CurrencyCode?,
                 priceBand: FuelPriceBand?, trace: PumpTrace? = nil) throws -> PumpDisplayReading {
        let reads = try read(image: image, windows: windows, trace: trace)
        let law = PumpReadingLaw.resolve(windows: reads.map { PumpLocatedWindow(field: $0.field, cells: $0.cells) },
                                         currency: currency, priceBand: priceBand)
        trace?.current?.law = law
        return law
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
        // One batched prediction for all crops; the sum order is the crops'
        // own, so the average matches the per-crop loop exactly.
        let probabilities = try model.probabilities(cells: crops)
        var sum = [Double](repeating: 0, count: 8)
        for p in probabilities {
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
