import CoreGraphics
import Foundation

// PU.4 - the digit slicer. Turns an already-warped number strip into a sequence
// of glyph cells on the display's fixed pitch. Deterministic, no model.
//
// The strip is noisy: glare and canopy leave a gradient under the digits, faint
// digits sit close to the background, and a glyph can split into two column runs
// when its middle segment is dim. Three steps are what make the column profile
// tractable:
//
// - Polarity + background subtraction zero the panel's own level, and each
//   projection then subtracts its own low percentile, so a gradient baseline
//   does not read as ink.
// - The pitch is the first peak of the column profile's autocorrelation, which
//   survives splitting and stray narrow runs that would shrink a median of run
//   gaps (the "every pitch comes out short" trap).
// - Runs are snapped to the pitch grid and merged by cell, so a split glyph and
//   a `1` each occupy one full cell and a decimal point is attached to its host
//   cell rather than counted on its own.

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
        var runThresholdFraction: Float = 0.2
        var mergeGapFraction: Float = 0.10
        var bandRowThresholdFraction: Float = 0.15
        var decimalPointTopRowFraction: Float = 0.55
        var pixelInkThreshold: Float = 0.12
        var minPitchFraction: Float = 0.35
        var maxPitchFraction: Float = 1.6
    }

    private struct Run {
        var start: Int
        var end: Int
        var isDecimalPoint: Bool
    }

    static func slice(_ gray: PumpGrayscale, options: Options = Options()) -> [GlyphCell] {
        let width = gray.width
        let height = gray.height
        guard width > 0, height > 0 else { return [] }

        // Polarity + background subtraction.
        let lum = gray.pixels
        let (p05, p50, p95) = Self.percentiles(lum)
        let darkOnLight = (p50 - p05) > (p95 - p50)
        let backgroundLevel: Float = darkOnLight ? (1 - p50) : p50
        let ink: [Float] = lum.map { value in
            let flipped: Float = darkOnLight ? (1 - value) : value
            return max(0, flipped - backgroundLevel)
        }

        // Row projection trims the glyph band, minus its own baseline.
        var rowSum = [Float](repeating: 0, count: height)
        for y in 0..<height {
            var sum: Float = 0
            for x in 0..<width { sum += ink[y * width + x] }
            rowSum[y] = sum
        }
        let rowBase = Self.percentile(rowSum, 0.10)
        let rowCentered = rowSum.map { $0 - rowBase }
        guard let maxRow = rowCentered.max(), maxRow > 0 else { return [] }
        let rowThreshold = options.bandRowThresholdFraction * maxRow
        guard let bandTop = rowCentered.firstIndex(where: { $0 > rowThreshold }),
              let bandBottom = rowCentered.lastIndex(where: { $0 > rowThreshold }),
              bandBottom > bandTop else { return [] }
        let bandHeight = bandBottom - bandTop + 1

        // Column projection over the band, smoothed, minus its own baseline.
        var colSum = [Float](repeating: 0, count: width)
        for x in 0..<width {
            var sum: Float = 0
            for y in bandTop...bandBottom { sum += ink[y * width + x] }
            colSum[x] = sum
        }
        let smoothed = Self.boxFilter(colSum, radius: options.smoothRadius)
        let colBase = Self.percentile(smoothed, 0.10)
        let profile = smoothed.map { $0 - colBase }
        guard let maxCol = profile.max(), maxCol > 0 else { return [] }

        // Pitch: first autocorrelation peak over a plausible advance range.
        let minPitch = Int(options.minPitchFraction * Float(bandHeight))
        let maxPitch = Int(options.maxPitchFraction * Float(bandHeight))
        guard let pitch = Self.autocorrelationPitch(profile, minLag: max(1, minPitch), maxLag: maxPitch),
              pitch > 0 else { return [] }

        // Ink runs from the thresholded profile.
        let runThreshold = options.runThresholdFraction * maxCol
        let mergeGap = max(1, Int(options.mergeGapFraction * Float(bandHeight)))
        var runs = Self.runs(in: profile, threshold: runThreshold, mergeGap: mergeGap)
        guard !runs.isEmpty else { return [] }

        // Classify decimal points (bottom-only runs) and drop noise fragments.
        var digitRuns: [Run] = []
        var decimalRuns: [Run] = []
        for run in runs {
            let top = Self.topInkRow(run, ink: ink, width: width, bandTop: bandTop, bandBottom: bandBottom,
                                     threshold: options.pixelInkThreshold)
            let isDecimalPoint = top != nil
                && Float(top! - bandTop) > options.decimalPointTopRowFraction * Float(bandHeight)
            var classified = run
            classified.isDecimalPoint = isDecimalPoint
            if isDecimalPoint {
                decimalRuns.append(classified)
            } else {
                digitRuns.append(classified)
            }
        }
        if !options.pitchSnap {
            return Self.rawCells(runs, bandTop: bandTop, bandBottom: bandBottom)
        }
        guard !digitRuns.isEmpty else { return [] }

        // Snap digit runs to the pitch grid and merge runs that share a cell.
        digitRuns.sort { $0.start < $1.start }
        let phase = Self.circularMean(digitRuns.map { Double($0.end).truncatingRemainder(dividingBy: Double(pitch)) },
                                      period: Double(pitch))
        let cellIndex: (Int) -> Int = { end in
            Int(((Double(end) - phase) / Double(pitch)).rounded())
        }
        var cellsByIndex: [Int: [Run]] = [:]
        for run in digitRuns {
            let index = cellIndex(run.end)
            cellsByIndex[index, default: []].append(run)
        }
        let occupied = cellsByIndex.keys.sorted()
        guard let first = occupied.first else { return [] }
        let leadingBlanks = max(0, first)

        let decimalCells = Set(decimalRuns.map { cellIndex($0.start) })

        var cells: [GlyphCell] = []
        let total = leadingBlanks + occupied.count
        for k in 0..<total {
            let rect = CGRect(
                x: CGFloat(Double(k) * Double(pitch)),
                y: CGFloat(bandTop),
                width: CGFloat(pitch),
                height: CGFloat(bandHeight))
            let isDigit = k >= leadingBlanks
            cells.append(GlyphCell(
                rect: rect,
                hasDecimalPoint: isDigit && decimalCells.contains(k),
                isBlank: !isDigit))
        }
        return cells
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
        var bestLag: Int?
        var bestValue: Float = -.greatestFiniteMagnitude
        for lag in minLag...min(maxLag, count - 1) {
            var value: Float = 0
            for i in 0..<(count - lag) {
                value += centered[i] * centered[i + lag]
            }
            let normalized = value / energy
            if normalized > bestValue {
                bestValue = normalized
                bestLag = lag
            }
        }
        return bestLag
    }

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
