import CoreGraphics
import Foundation

// PU.4 - the digit slicer. Turns an already-warped number strip into a sequence
// of glyph cells on the display's fixed pitch. Deterministic, no model.
//
// The strip is noisy: glare and canopy leave a gradient under the digits, faint
// digits sit close to the background, and a glyph can split into two column runs
// when its middle segment is dim. The steps that make the column profile
// tractable:
//
// - Local contrast normalisation divides the strip by a column-wide box blur
//   before any projection, so a glare gradient is flattened and a faint digit
//   keeps its contrast relative to the background beside it (PU.8).
// - Polarity + background subtraction zero the panel's own level, and each
//   projection then subtracts its own low percentile, so a residual gradient
//   baseline does not read as ink.
// - The run threshold is Otsu's split on the profile's own histogram, not a
//   fixed fraction of the max, so a glare-hot column cannot price a faint
//   digit out of the threshold (PU.8).
// - The pitch is the first peak of the column profile's autocorrelation, which
//   survives splitting and stray narrow runs that would shrink a median of run
//   gaps (the "every pitch comes out short" trap).
// - A split glyph (two runs closer than a third of a pitch whose combined width
//   fits one cell) is re-merged before snapping, so a dim middle segment does
//   not become a phantom cell (PU.8).
// - Runs are snapped to the pitch grid and merged by cell, so a split glyph and
//   a `1` each occupy one full cell and a decimal point is attached to its host
//   cell rather than counted on its own.
// - When the snapped count falls short of what the pitch grid allows for the
//   strip width, a second pass at half the threshold is tried and the more
//   uniform of the two wins (PU.8).

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
        /// A second pass at half the threshold when the snapped count is short.
        var shortCountRetry: Bool = true
        /// The pitch-to-body check: a glyph body (the widest ink run) is at
        /// least this fraction of the band height to count as a body rather
        /// than a `1`, and the pitch must lie within [minimum, maximum) bodies.
        var bodyMinimumFraction: Float = 0.35
        var pitchToBodyMaximum: Float = 2.2
        var pitchToBodyMinimum: Float = 0.9
    }

    private struct Run {
        var start: Int
        var end: Int
        var isDecimalPoint: Bool
    }

    private struct Pass {
        var cells: [GlyphCell]
        var digitRuns: [Run]
        var count: Int
    }

    /// The strip state a pass needs: the column profile, the ink map, and the
    /// band/pitch geometry the snap lays cells onto.
    private struct Context {
        let profile: [Float]
        let ink: [Float]
        let width: Int
        let bandTop: Int
        let bandBottom: Int
        let bandHeight: Int
        let pitch: Int
    }

    static func slice(_ gray: PumpGrayscale, options: Options = Options()) -> [GlyphCell] {
        let width = gray.width
        let height = gray.height
        guard width > 0, height > 0 else { return [] }

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
        let backgroundLevel: Float = darkOnLight ? (1 - Self.percentile(lum, 0.50)) : Self.percentile(lum, 0.50)
        let ink: [Float] = lum.map { value in
            let flipped: Float = darkOnLight ? (1 - value) : value
            return max(0, flipped - backgroundLevel)
        }

        guard let context = Self.context(ink: ink, width: width, height: height, options: options) else {
            return []
        }

        // Run threshold: Otsu on the profile histogram, or the fixed fraction.
        let runThreshold: Float = options.adaptiveThreshold
            ? Self.otsuThreshold(context.profile)
            : options.runThresholdFraction * (context.profile.max() ?? 0)

        let pass = Self.makePass(context, threshold: runThreshold, options: options)
        return Self.retried(pass, context: context, threshold: runThreshold, options: options).cells
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

        return Context(profile: profile, ink: ink, width: width,
                       bandTop: bandTop, bandBottom: bandBottom, bandHeight: bandHeight, pitch: pitch)
    }

    /// The short-count retry: a second pass at half the threshold wins only when
    /// its cells carry a more uniform ink mass.
    private static func retried(_ pass: Pass, context: Context, threshold: Float, options: Options) -> Pass {
        guard options.shortCountRetry else { return pass }
        let grid = Int((Double(context.width) / Double(context.pitch)).rounded())
        guard pass.count < grid else { return pass }
        let retry = Self.makePass(context, threshold: threshold * 0.5, options: options)
        if !retry.cells.isEmpty,
           Self.inkMassUniformity(retry.digitRuns, profile: context.profile)
               > Self.inkMassUniformity(pass.digitRuns, profile: context.profile) {
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

    private static func makePass(_ context: Context, threshold: Float, options: Options) -> Pass {
        let mergeGap = max(1, Int(options.mergeGapFraction * Float(context.bandHeight)))
        let runs = Self.runs(in: context.profile, threshold: threshold, mergeGap: mergeGap)
        guard !runs.isEmpty else { return Pass(cells: [], digitRuns: [], count: 0) }

        // Classify decimal points (bottom-only runs) and drop noise fragments.
        var digitRuns: [Run] = []
        var decimalRuns: [Run] = []
        for run in runs {
            let top = Self.topInkRow(run, ink: context.ink, width: context.width,
                                     bandTop: context.bandTop, bandBottom: context.bandBottom,
                                     threshold: options.pixelInkThreshold)
            let isDecimalPoint = top != nil
                && Float(top! - context.bandTop) > options.decimalPointTopRowFraction * Float(context.bandHeight)
            var classified = run
            classified.isDecimalPoint = isDecimalPoint
            if isDecimalPoint {
                decimalRuns.append(classified)
            } else {
                digitRuns.append(classified)
            }
        }
        if !options.pitchSnap {
            let raw = Self.rawCells(runs, bandTop: context.bandTop, bandBottom: context.bandBottom)
            return Pass(cells: raw, digitRuns: digitRuns, count: raw.count)
        }
        guard !digitRuns.isEmpty else { return Pass(cells: [], digitRuns: [], count: 0) }

        // Re-merge a glyph that a dim middle segment split into two runs.
        digitRuns.sort { $0.start < $1.start }
        if options.splitMerge {
            digitRuns = Self.splitMerge(digitRuns, pitch: context.pitch, options: options)
        }

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
        let occupied = cellsByIndex.keys.sorted()
        guard let first = occupied.first else { return Pass(cells: [], digitRuns: [], count: 0) }
        // The grid is anchored on the first occupied cell, whose left edge is
        // one pitch before its phase-aligned right edge. A leading blank cell
        // exists only where a whole cell (within a quarter pitch) fits between
        // the strip's left edge and that anchor - a strip margin narrower than
        // that is a margin, not a blank glyph.
        let firstCellStart = phase + Double(first) * pitch - pitch
        let leadingBlanks = max(0, Int((firstCellStart / pitch + 0.25).rounded(.down)))
        let gridOrigin = firstCellStart - Double(leadingBlanks) * pitch

        let decimalCells = Set(decimalRuns.map { cellIndex($0.start) })

        // Every grid position from the first leading blank to the last occupied
        // cell is a cell: an empty position between two digits (a wide gap, a
        // separator drawn in its own narrow cell) is a blank cell, never a
        // collapsed one - collapsing it would shift every later cell's rect
        // onto the wrong glyph.
        let occupiedSet = Set(occupied)
        let last = occupied.last!
        var cells: [GlyphCell] = []
        for index in (first - leadingBlanks)...last {
            let k = index - (first - leadingBlanks)
            let rect = CGRect(
                x: CGFloat(gridOrigin + Double(k) * pitch),
                y: CGFloat(context.bandTop),
                width: CGFloat(context.pitch),
                height: CGFloat(context.bandHeight))
            let isDigit = occupiedSet.contains(index)
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

    private static func splitMerge(_ runs: [Run], pitch: Int, options: Options) -> [Run] {
        var result: [Run] = []
        for run in runs {
            if let last = result.last,
               Float(run.start - last.end) <= options.splitMergeGapFraction * Float(pitch) {
                let combinedWidth = run.end - last.start + 1
                if Float(combinedWidth) <= options.splitMergeWidthFraction * Float(pitch) {
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

    // MARK: - Pitch via autocorrelation

    private static func autocorrelationPitch(_ profile: [Float], minLag: Int, maxLag: Int) -> Int? {
        let count = profile.count
        guard count > maxLag, maxLag >= minLag else { return nil }
        let mean = profile.reduce(0, +) / Float(count)
        let centered = profile.map { $0 - mean }
        var energy: Float = 0
        for value in centered { energy += value * value }
        guard energy > 0 else { return nil }
        let lags = Array(minLag...min(maxLag, count - 1))
        var values: [Float] = []
        values.reserveCapacity(lags.count)
        for lag in lags {
            var value: Float = 0
            for i in 0..<(count - lag) {
                value += centered[i] * centered[i + lag]
            }
            values.append(value / energy)
        }
        guard let bestValue = values.max() else { return nil }
        // The profile of a digit row repeats at the pitch AND at every multiple
        // of it, and the doubled lag often carries the higher peak (a decimal
        // mark or a dim `1` every other cell weakens the fundamental). Take the
        // shortest local peak that is nearly as strong as the strongest, so the
        // fundamental wins over its harmonic; measured on the train export the
        // harmonic halved the count on 954 of 8 527 windows.
        for (i, lag) in lags.enumerated() where values[i] >= harmonicTolerance * bestValue {
            let before = i == 0 ? -.greatestFiniteMagnitude : values[i - 1]
            let after = i + 1 < values.count ? values[i + 1] : -.greatestFiniteMagnitude
            if values[i] >= before && values[i] >= after { return lag }
        }
        return lags[values.firstIndex(of: bestValue)!]
    }

    /// How close to the strongest autocorrelation peak a shorter peak must be
    /// to be taken as the fundamental pitch.
    static let harmonicTolerance: Float = 0.6

    // MARK: - Primitives

    private static func runs(in profile: [Float], threshold: Float, mergeGap: Int) -> [Run] {
        var result: [Run] = []
        var i = 0
        while i < profile.count {
            guard profile[i] > threshold else { i += 1; continue }
            let start = i
            var end = i
            while end < profile.count && profile[end] > threshold { end += 1 }
            let runEnd = end - 1
            if let last = result.last, start - last.end <= mergeGap {
                result[result.count - 1].end = runEnd
            } else {
                result.append(Run(start: start, end: runEnd, isDecimalPoint: false))
            }
            i = end + 1
        }
        return result
    }

    private static func topInkRow(
        _ run: Run, ink: [Float], width: Int, bandTop: Int, bandBottom: Int, threshold: Float
    ) -> Int? {
        for y in bandTop...bandBottom {
            for x in run.start...run.end where ink[y * width + x] > threshold {
                return y
            }
        }
        return nil
    }

    private static func boxFilter(_ values: [Float], radius: Int) -> [Float] {
        let count = values.count
        guard radius > 0, count > 0 else { return values }
        var prefix = [Float](repeating: 0, count: count + 1)
        for i in 0..<count { prefix[i + 1] = prefix[i] + values[i] }
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let left = max(0, i - radius)
            let right = min(count - 1, i + radius)
            out[i] = (prefix[right + 1] - prefix[left]) / Float(right - left + 1)
        }
        return out
    }

    private static func otsuThreshold(_ values: [Float]) -> Float {
        let count = values.count
        guard count > 1, let lo = values.min(), let hi = values.max(), hi > lo else {
            return values.max() ?? 0
        }
        let bins = 256
        var hist = [Float](repeating: 0, count: bins)
        let scale = Float(bins - 1) / (hi - lo)
        for value in values {
            var index = Int(((value - lo) * scale).rounded())
            index = max(0, min(bins - 1, index))
            hist[index] += 1
        }
        let binCenters = (0..<bins).map { lo + Float($0) * (hi - lo) / Float(bins - 1) }
        var prefixCount = [Float](repeating: 0, count: bins)
        var prefixSum = [Float](repeating: 0, count: bins)
        for i in 0..<bins {
            prefixCount[i] = (i > 0 ? prefixCount[i - 1] : 0) + hist[i]
            prefixSum[i] = (i > 0 ? prefixSum[i - 1] : 0) + hist[i] * binCenters[i]
        }
        let total = Float(count)
        let totalSum = prefixSum[bins - 1]
        var best: Float = -1
        var bestThreshold = lo
        for i in 0..<(bins - 1) {
            let weight1 = prefixCount[i]
            let weight2 = total - weight1
            guard weight1 > 0, weight2 > 0 else { continue }
            let mean1 = prefixSum[i] / weight1
            let mean2 = (totalSum - prefixSum[i]) / weight2
            let between = weight1 * weight2 * (mean1 - mean2) * (mean1 - mean2)
            if between > best {
                best = between
                bestThreshold = binCenters[i]
            }
        }
        return bestThreshold
    }

    private static func percentile(_ values: [Float], _ p: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, Int((Float(sorted.count - 1) * p).rounded()))
        return sorted[index]
    }

    private static func percentiles(_ values: [Float]) -> (p05: Float, p50: Float, p95: Float) {
        (percentile(values, 0.05), percentile(values, 0.50), percentile(values, 0.95))
    }

    private static func circularMean(_ values: [Double], period: Double) -> Double {
        guard !values.isEmpty, period > 0 else { return 0 }
        var sx = 0.0
        var sy = 0.0
        for value in values {
            let angle = 2 * Double.pi * value / period
            sx += cos(angle)
            sy += sin(angle)
        }
        var mean = atan2(sy, sx) * period / (2 * Double.pi)
        if mean < 0 { mean += period }
        return mean
    }
}
