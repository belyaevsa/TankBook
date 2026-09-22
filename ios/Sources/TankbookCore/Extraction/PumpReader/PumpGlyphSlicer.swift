import CoreGraphics
import Foundation

// PU.4 - the digit slicer. Turns an already-warped number strip into glyph
// cells on the display's fixed pitch. Deterministic, no model.
//
// The strip is noisy: glare leaves a gradient under the digits, faint digits
// sit near the background, and a glyph can split into two column runs when its
// middle segment is dim. What makes the column profile tractable:
//
// - Local contrast normalisation divides the strip by a column-wide box blur
//   before any projection, so a glare gradient flattens and a faint digit keeps
//   its contrast beside it (PU.8); polarity and background subtraction zero the
//   panel's level and each projection subtracts its own low percentile.
// - The run threshold is Otsu's split on the profile histogram, not a fraction
//   of the max (PU.8); the pitch is the first peak of the profile's
//   autocorrelation, which survives splitting and stray narrow runs.
// - A split glyph (two runs closer than a third of a pitch whose combined width
//   fits one cell) is re-merged before snapping, unless the right run is already
//   a full body - a glyph of its own (PU.8, PU.37).
// - Runs snap to the pitch grid and merge by cell, so a split glyph and a `1`
//   each occupy one cell and a mark attaches to its host cell; when the count
//   falls short of the grid, a second pass at half the threshold is tried and
//   the more uniform wins (PU.8).

/// One glyph cell on the strip, in strip coordinates.
struct GlyphCell: Equatable, Sendable {
    let rect: CGRect
    let hasDecimalPoint: Bool
    let isBlank: Bool
}

enum PumpGlyphSlicer {

    struct Options: Sendable {
        /// The named mutation's seam: `false` returns the raw column runs as
        /// cells (no pitch snap), which over-counts every split and dp-carrying
        /// window. `PumpGlyphSlicerTests` flips this to prove the snap is
        /// load-bearing.
        var pitchSnap: Bool = true
        var smoothRadius: Int = 2
        /// The fixed-fraction fallback (`runThresholdFraction * maxCol`). Only
        /// used when `adaptiveThreshold` is false; kept as the mutation seam for
        /// the faint-display test.
        var runThresholdFraction: Float = 0.2
        var mergeGapFraction: Float = 0.10
        var bandRowThresholdFraction: Float = 0.15
        var decimalPointTopRowFraction: Float = 0.55
        var pixelInkThreshold: Float = 0.12
        /// The mark-specific second look (PU.34b): a dot or comma never clears
        /// the digit-run threshold, so a separate pass finds it in the
        /// inter-cell gaps at `markThresholdFraction` of that threshold.
        var markSearch: Bool = true
        var markThresholdFraction: Float = 0.5
        /// The pass searches from `markTopFraction` of the band height down,
        /// extended `markBandExtensionFraction` below it for a hanging comma.
        var markTopFraction: Float = 0.5
        var markBandExtensionFraction: Float = 0.25
        /// A single column at a stroke's edge is anti-aliasing, not a mark.
        var markMinimumWidth: Int = 2
        var markWidthFraction: Float = 0.4
        var markHeightFraction: Float = 0.35
        var minPitchFraction: Float = 0.35
        var maxPitchFraction: Float = 1.6
        /// Otsu on the column-profile histogram instead of a fixed fraction.
        var adaptiveThreshold: Bool = true
        /// Divide the strip by a column-wide box blur before projection.
        var localContrastNormalization: Bool = true
        /// Box-blur radius down the strip as a fraction of its height.
        var lcnVerticalRadiusFraction: Float = 0.4
        var lcnEpsilon: Float = 0.001
        /// Merge two runs into one glyph when their gap is closer than this
        /// fraction of the pitch.
        var splitMergeGapFraction: Float = 0.35
        /// ... and their combined width fits this fraction of a pitch.
        var splitMergeWidthFraction: Float = 1.1
        /// Re-merge a glyph that a dim middle segment split into two runs.
        var splitMerge: Bool = true
        /// A split-merge needs a fragment on the right, not a full body (PU.37).
        var splitMergeBodyGuard: Bool = true
        /// A second pass at half the threshold when the snapped count is short.
        var shortCountRetry: Bool = true
        /// PU.42: recover a dim glyph (a ghosted zero, a faint `1`) whose
        /// strokes fall under the one global run threshold, by a second look at
        /// `dimGlyphThresholdFraction` of it. A candidate must snap to an empty
        /// grid cell, carry ink from the top of the band (a mark is lower-band
        /// only), and its column-profile peak must stand
        /// `dimGlyphContrastFraction` of the bright cells' median peak.
        var dimGlyphRecovery: Bool = true
        var dimGlyphThresholdFraction: Float = 0.5
        var dimGlyphContrastFraction: Float = 0.25
        var dimGlyphInkThresholdFraction: Float = 0.5
        var dimGlyphTopRowFraction: Float = 0.55
        /// A recovered cell must overlap the strip by this fraction of a pitch:
        /// a sliver at the frame edge is a crop artifact, not a glyph.
        var dimGlyphMinimumCellWidthFraction: Float = 0.35
        /// The recovery is only meaningful on a row whose pitch is a sane
        /// fraction of its band height; on a harmonic (pitch ~1.4 bands) or
        /// subharmonic (~0.34) row the grid itself is wrong, and filling it in
        /// makes the count worse, not better.
        var dimGlyphMinimumPitchFraction: Float = 0.45
        var dimGlyphMaximumPitchFraction: Float = 1.05
        /// The pitch-to-body check: a glyph body (the widest ink run) is at
        /// least this fraction of the band height to count as a body rather
        /// than a `1`, and the pitch must lie within [minimum, maximum) bodies.
        var bodyMinimumFraction: Float = 0.35
        var pitchToBodyMaximum: Float = 2.2
        var pitchToBodyMinimum: Float = 0.9
    }

    struct Run {
        var start: Int
        var end: Int
        var isDecimalPoint: Bool
    }

    struct Pass {
        var cells: [GlyphCell]
        var digitRuns: [Run]
        var count: Int
    }

    /// The strip state a pass needs: the column profile, the ink map, and the
    /// band/pitch geometry the snap lays cells onto.
    struct Context {
        let profile: [Float]
        let ink: [Float]
        let width: Int
        let height: Int
        let bandTop: Int
        let bandBottom: Int
        let bandHeight: Int
        let pitch: Int
    }

    static func slice(_ gray: PumpGrayscale, options: Options = Options()) -> [GlyphCell] {
        guard let (context, threshold) = Self.prepare(gray, options: options) else { return [] }
        let pass = Self.makePass(context, threshold: threshold, options: options)
        return Self.retried(pass, context: context, threshold: threshold, options: options).cells
    }

    /// The geometry a pass needs plus the run threshold, before any run is
    /// taken. Split out so `diagnostics` can report the numbers the pass ran
    /// with without duplicating the preparation.
    static func prepare(_ gray: PumpGrayscale, options: Options) -> (Context, Float)? {
        let width = gray.width
        let height = gray.height
        guard width > 0, height > 0 else { return nil }

        // Polarity is a property of the raw display; decide it before any
        // normalisation so the LCN cannot flip a dark-on-light panel into a
        // light-on-dark one.
        let (p05, p50, p95) = Self.percentiles(gray.pixels)
        let darkOnLight = (p50 - p05) > (p95 - p50)

        // Local contrast normalisation before any projection.
        let lum: [Float] = options.localContrastNormalization
            ? Self.normalizeLocalContrast(gray.pixels, width: width, height: height, options: options)
            : gray.pixels

        // Background subtraction.
        // The LCN'd strip's median is a second full sort only when the LCN ran;
        // without it `lum` is the raw strip and `p50` is already its median.
        let lumMedian = options.localContrastNormalization ? Self.percentile(lum, 0.50) : p50
        let backgroundLevel: Float = darkOnLight ? (1 - lumMedian) : lumMedian
        let ink: [Float] = lum.map { value in
            let flipped: Float = darkOnLight ? (1 - value) : value
            return max(0, flipped - backgroundLevel)
        }

        guard let context = Self.context(ink: ink, width: width, height: height, options: options) else {
            return nil
        }

        // Run threshold: Otsu on the profile histogram, or the fixed fraction.
        let runThreshold: Float = options.adaptiveThreshold
            ? Self.otsuThreshold(context.profile)
            : options.runThresholdFraction * (context.profile.max() ?? 0)
        return (context, runThreshold)
    }

    /// Row band, column profile and pitch - the pieces every pass shares.
    private static func context(ink: [Float], width: Int, height: Int, options: Options) -> Context? {
        var rowSum = [Float](repeating: 0, count: height)
        for y in 0..<height {
            var sum: Float = 0
            for x in 0..<width { sum += ink[y * width + x] }
            rowSum[y] = sum
        }
        let rowCentered = rowSum.map { $0 - Self.percentile(rowSum, 0.10) }
        guard let maxRow = rowCentered.max(), maxRow > 0 else { return nil }
        let rowThreshold = options.bandRowThresholdFraction * maxRow
        guard let bandTop = rowCentered.firstIndex(where: { $0 > rowThreshold }),
              let bandBottom = rowCentered.lastIndex(where: { $0 > rowThreshold }),
              bandBottom > bandTop else { return nil }
        let bandHeight = bandBottom - bandTop + 1

        var colSum = [Float](repeating: 0, count: width)
        for x in 0..<width {
            var sum: Float = 0
            for y in bandTop...bandBottom { sum += ink[y * width + x] }
            colSum[x] = sum
        }
        let smoothed = Self.boxFilter(colSum, radius: options.smoothRadius)
        let profile = smoothed.map { $0 - Self.percentile(smoothed, 0.10) }
        guard let maxCol = profile.max(), maxCol > 0 else { return nil }

        let minPitch = Int(options.minPitchFraction * Float(bandHeight))
        let maxPitch = Int(options.maxPitchFraction * Float(bandHeight))
        guard var pitch = Self.autocorrelationPitch(profile, minLag: max(1, minPitch), maxLag: maxPitch),
              pitch > 0 else { return nil }

        // The autocorrelation can still land on a harmonic when the row is
        // half `1`s (a thin glyph every other cell leaves the fundamental no
        // peak). The widest ink run is one glyph's body - an 8 or a 0 - and a
        // glyph is never narrower than half its pitch nor wider than it: a
        // pitch of two bodies or more is doubled, a pitch under a body is
        // halved. Guarded by the run being a real body, not a `1`.
        let threshold = options.adaptiveThreshold ? Self.otsuThreshold(profile) : options.runThresholdFraction * maxCol
        let mergeGap = max(1, Int(options.mergeGapFraction * Float(bandHeight)))
        let widest = Self.runs(in: profile, threshold: threshold, mergeGap: mergeGap)
            .map { $0.end - $0.start + 1 }.max() ?? 0
        if Float(widest) >= options.bodyMinimumFraction * Float(bandHeight) {
            while pitch >= Int(options.pitchToBodyMaximum * Float(widest)), pitch / 2 >= max(1, minPitch) {
                pitch /= 2
            }
            while Float(pitch) < options.pitchToBodyMinimum * Float(widest), pitch * 2 <= maxPitch {
                pitch *= 2
            }
        }

        return Context(profile: profile, ink: ink, width: width, height: height,
                       bandTop: bandTop, bandBottom: bandBottom, bandHeight: bandHeight, pitch: pitch)
    }

    /// The short-count retry: a second pass at half the threshold wins only when
    /// its cells carry a more uniform ink mass.
    static func retried(_ pass: Pass, context: Context, threshold: Float, options: Options) -> Pass {
        guard options.shortCountRetry else { return pass }
        let grid = Int((Double(context.width) / Double(context.pitch)).rounded())
        guard pass.count < grid else { return pass }
        // The retry already runs at half the threshold; its own dim-glyph look
        // would go a quarter of the way down and pull in noise the main pass
        // has not sanctioned.
        var retryOptions = options
        retryOptions.dimGlyphRecovery = false
        let retry = Self.makePass(context, threshold: threshold * 0.5, options: retryOptions)
        guard !retry.cells.isEmpty else { return pass }
        if Self.inkMassUniformity(retry.digitRuns, profile: context.profile)
            > Self.inkMassUniformity(pass.digitRuns, profile: context.profile) {
            // The retry recovers a short count, not the mark: when both passes
            // agree on the count, a pass that saw a decimal mark is not
            // displaced by one that did not. The half threshold can fragment a
            // digit into runs that hide the gap the mark sits in. A differing
            // count is the retry doing its job, so it wins.
            if retry.count == pass.count,
               pass.cells.contains(where: \.hasDecimalPoint),
               !retry.cells.contains(where: \.hasDecimalPoint) {
                return pass
            }
            return retry
        }
        return pass
    }

    // MARK: - Local contrast normalisation

    private static func normalizeLocalContrast(
        _ pixels: [Float], width: Int, height: Int, options: Options
    ) -> [Float] {
        let verticalRadius = max(1, Int(options.lcnVerticalRadiusFraction * Float(height)))
        let blurred = Self.verticalBoxBlur(pixels, width: width, height: height, radius: verticalRadius)
        var normalized = [Float](repeating: 0, count: pixels.count)
        for i in 0..<pixels.count {
            normalized[i] = pixels[i] / (blurred[i] + options.lcnEpsilon)
        }
        if let lo = normalized.min(), let hi = normalized.max(), hi > lo {
            for i in 0..<normalized.count {
                normalized[i] = (normalized[i] - lo) / (hi - lo)
            }
        }
        return normalized
    }

    /// A vertical box blur: each pixel is averaged with the pixels above and
    /// below it in the same column. Dividing by this column mean flattens a
    /// glare gradient that runs along the strip without smearing one digit
    /// into its neighbour.
    private static func verticalBoxBlur(_ values: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        var out = [Float](repeating: 0, count: values.count)
        for x in 0..<width {
            for y in 0..<height {
                let top = max(0, y - radius)
                let bottom = min(height - 1, y + radius)
                var sum: Float = 0
                for j in top...bottom { sum += values[j * width + x] }
                out[y * width + x] = sum / Float(bottom - top + 1)
            }
        }
        return out
    }

    // MARK: - One pass: runs -> classify -> split-merge -> snap

    static func makePass(_ context: Context, threshold: Float, options: Options) -> Pass {
        let mergeGap = max(1, Int(options.mergeGapFraction * Float(context.bandHeight)))
        let runs = Self.runs(in: context.profile, threshold: threshold, mergeGap: mergeGap)
        guard !runs.isEmpty else { return Pass(cells: [], digitRuns: [], count: 0) }

        // Classify decimal points (bottom-only runs) and drop noise fragments.
        var (digitRuns, decimalRuns) = Self.classify(runs, context: context, options: options)
        if !options.pitchSnap {
            let raw = Self.rawCells(runs, bandTop: context.bandTop, bandBottom: context.bandBottom)
            return Pass(cells: raw, digitRuns: digitRuns, count: raw.count)
        }
        guard !digitRuns.isEmpty else { return Pass(cells: [], digitRuns: [], count: 0) }

        // Re-merge a glyph that a dim middle segment split into two runs.
        digitRuns.sort { $0.start < $1.start }
        if options.splitMerge {
            digitRuns = Self.splitMerge(digitRuns, pitch: context.pitch, band: context.bandHeight, options: options)
        }

        // The mark-specific second look (PU.34b); it attaches to its left run.
        let markRuns = options.markSearch
            ? Self.markRuns(in: context, threshold: threshold, digitRuns: digitRuns, options: options)
            : []

        // Snap digit runs to the pitch grid and merge runs that share a cell.
        let pitch = Double(context.pitch)
        let phase = Self.circularMean(digitRuns.map { Double($0.end).truncatingRemainder(dividingBy: pitch) },
                                      period: pitch)
        let cellIndex: (Int) -> Int = { end in
            Int(((Double(end) - phase) / pitch).rounded())
        }
        var cellsByIndex: [Int: [Run]] = [:]
        for run in digitRuns {
            let index = cellIndex(run.end)
            cellsByIndex[index, default: []].append(run)
        }
        var occupied = Set(cellsByIndex.keys)
        guard let first = occupied.min() else { return Pass(cells: [], digitRuns: [], count: 0) }
        // The grid is anchored on the first occupied cell, whose left edge is
        // one pitch before its phase-aligned right edge. A leading blank cell
        // exists only where a whole cell (within a quarter pitch) fits between
        // the strip's left edge and that anchor - a strip margin narrower than
        // that is a margin, not a blank glyph.
        let firstCellStart = phase + Double(first) * pitch - pitch
        let leadingBlanks = max(0, Int((firstCellStart / pitch + 0.25).rounded(.down)))
        let gridFirst = first - leadingBlanks
        let last = occupied.max()!

        // PU.42: a dim glyph the run threshold missed sits on an empty grid
        // position; recover it and widen the grid to hold a leading or
        // trailing one. A recovered cell is a digit, never a mark, so its
        // index is struck from the decimal set the main pass may have put it in.
        let recovered = Self.dimGlyphIndices(context: context, threshold: threshold,
                                             phase: phase, occupied: occupied, options: options)
        let decimalCells = Set((decimalRuns + markRuns).map { cellIndex($0.start) })
            .subtracting(recovered)
        occupied.formUnion(recovered)
        let cellFirst = min(gridFirst, recovered.min() ?? gridFirst)
        let cellLast = max(last, recovered.max() ?? last)

        // Every grid position from the first leading blank to the last occupied
        // cell is a cell: an empty position between two digits (a wide gap, a
        // separator drawn in its own narrow cell) is a blank cell, never a
        // collapsed one - collapsing it would shift every later cell's rect
        // onto the wrong glyph.
        var cells: [GlyphCell] = []
        for index in cellFirst...cellLast {
            let rect = CGRect(
                x: CGFloat(phase + Double(index - 1) * pitch),
                y: CGFloat(context.bandTop),
                width: CGFloat(context.pitch),
                height: CGFloat(context.bandHeight))
            let isDigit = occupied.contains(index)
            cells.append(GlyphCell(
                rect: rect,
                hasDecimalPoint: isDigit && decimalCells.contains(index),
                isBlank: !isDigit))
        }
        return Pass(cells: cells, digitRuns: digitRuns, count: cells.count)
    }

    /// The ink mass of each digit run; a good slice has them all alike.
    private static func inkMassUniformity(_ digitRuns: [Run], profile: [Float]) -> Float {
        guard !digitRuns.isEmpty else { return 0 }
        var masses = [Float](repeating: 0, count: digitRuns.count)
        for (index, run) in digitRuns.enumerated() {
            var sum: Float = 0
            for x in run.start...run.end { sum += profile[x] }
            masses[index] = sum
        }
        let mean = masses.reduce(0, +) / Float(masses.count)
        let variance = masses.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(masses.count)
        let std = variance.squareRoot()
        return mean / (mean + std)
    }

    static func splitMerge(_ runs: [Run], pitch: Int, band: Int, options: Options) -> [Run] {
        var result: [Run] = []
        for run in runs {
            if let last = result.last,
               Float(run.start - last.end) <= options.splitMergeGapFraction * Float(pitch) {
                let combinedWidth = run.end - last.start + 1
                let rightIsBody = options.splitMergeBodyGuard
                    && Float(run.end - run.start + 1) >= options.bodyMinimumFraction * Float(band)
                if !rightIsBody, Float(combinedWidth) <= options.splitMergeWidthFraction * Float(pitch) {
                    result[result.count - 1].end = run.end
                    continue
                }
            }
            result.append(run)
        }
        return result
    }

    // MARK: - The mutation's raw form

    private static func rawCells(_ runs: [Run], bandTop: Int, bandBottom: Int) -> [GlyphCell] {
        return runs.map { run in
            GlyphCell(
                rect: CGRect(
                    x: CGFloat(run.start), y: CGFloat(bandTop),
                    width: CGFloat(run.end - run.start + 1), height: CGFloat(bandBottom - bandTop + 1)),
                hasDecimalPoint: run.isDecimalPoint,
                isBlank: false)
        }
    }
}

// PU.34b - the mark-specific second look: find a dot or comma in the gaps.
