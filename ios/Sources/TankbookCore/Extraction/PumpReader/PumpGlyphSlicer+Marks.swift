import CoreGraphics
import Foundation

extension PumpGlyphSlicer {

    /// The slicer's geometry for one strip, for `PumpMarkDiagnosticTests`.
    struct Diagnostics: Sendable {
        let width: Int
        let height: Int
        let bandTop: Int
        let bandBottom: Int
        let bandHeight: Int
        let pitch: Int
        let threshold: Float
        let profile: [Float]
        let ink: [Float]
        let cells: [GlyphCell]
    }

    static func diagnostics(_ gray: PumpGrayscale, options: Options = Options()) -> Diagnostics? {
        guard let (context, threshold) = Self.prepare(gray, options: options) else { return nil }
        let pass = Self.retried(Self.makePass(context, threshold: threshold, options: options),
                                context: context, threshold: threshold, options: options)
        return Diagnostics(width: context.width, height: context.height,
                           bandTop: context.bandTop, bandBottom: context.bandBottom,
                           bandHeight: context.bandHeight, pitch: context.pitch,
                           threshold: threshold, profile: context.profile,
                           ink: context.ink, cells: pass.cells)
    }

    /// Splits the thresholded runs into digits and bottom-only decimal marks.
    static func classify(
        _ runs: [Run], context: Context, options: Options
    ) -> (digit: [Run], decimal: [Run]) {
        var digit: [Run] = []
        var decimal: [Run] = []
        for run in runs {
            let top = Self.topInkRow(run, ink: context.ink, width: context.width,
                                     bandTop: context.bandTop, bandBottom: context.bandBottom,
                                     threshold: options.pixelInkThreshold)
            let isDecimalPoint = top != nil
                && Float(top! - context.bandTop) > options.decimalPointTopRowFraction * Float(context.bandHeight)
            var classified = run
            classified.isDecimalPoint = isDecimalPoint
            if isDecimalPoint {
                decimal.append(classified)
            } else {
                digit.append(classified)
            }
        }
        return (digit, decimal)
    }

    /// An ink blob in an inter-cell gap: the columns that carry ink and their
    /// row extent.
    private struct Blob {
        let start: Int
        let end: Int
        let top: Int
        let bottom: Int
    }

    /// Runs that can only be a decimal mark: a small blob in the gap between
    /// two digit runs, in the lower band, found at a fraction of the run
    /// threshold. The lower threshold and the gap restriction are what keep a
    /// speck in the digits from reading as one.
    static func markRuns(
        in context: Context, threshold: Float, digitRuns: [Run], options: Options
    ) -> [Run] {
        guard digitRuns.count >= 2 else { return [] }
        // The search is the lower half of the band, extended below it for a
        // comma that hangs under the baseline. A digit's upper strokes are
        // outside it, so only a mark's own pixels contribute.
        let markTop = context.bandTop + Int(options.markTopFraction * Float(context.bandHeight))
        let markBottom = min(context.height - 1,
                             context.bandBottom + Int(options.markBandExtensionFraction * Float(context.bandHeight)))
        guard markBottom > markTop else { return [] }
        var colSum = [Float](repeating: 0, count: context.width)
        for x in 0..<context.width {
            var sum: Float = 0
            for y in markTop...markBottom { sum += context.ink[y * context.width + x] }
            colSum[x] = sum
        }
        let smoothed = Self.boxFilter(colSum, radius: options.smoothRadius)
        let profile = smoothed.map { $0 - Self.percentile(smoothed, 0.10) }
        let markThreshold = threshold * options.markThresholdFraction
        let rows = markTop...markBottom
        var out: [Run] = []
        // Only the columns strictly between two adjacent digit runs are
        // searched, so the mark pass never re-reads a digit stroke as a blob
        // even where the lower threshold keeps the stroke connected to the dot.
        for (left, right) in zip(digitRuns, digitRuns.dropFirst()) {
            let gapStart = left.end + 1
            let gapEnd = right.start - 1
            guard gapEnd > gapStart else { continue }
            var x = gapStart
            while x <= gapEnd {
                guard profile[x] > markThreshold else { x += 1; continue }
                let start = x
                var end = x
                while end <= gapEnd, profile[end] > markThreshold { end += 1 }
                x = end
                // The low threshold can bridge the dot to a digit stroke
                // through the gap's blur; keep only the columns that actually
                // carry ink, so a mark is measured where its pixels are.
                guard let blob = Self.inkBlob(start, end - 1, in: context, rows: rows,
                                              threshold: options.pixelInkThreshold),
                      Self.isMarkBlob(blob, between: left, and: right, context: context, options: options)
                else { continue }
                out.append(Run(start: blob.start, end: blob.end, isDecimalPoint: true))
            }
        }
        return out
    }

    /// Whether an ink blob between two digit runs is a mark: small, apart from
    /// both strokes, and no wider or taller than a dot or comma.
    private static func isMarkBlob(
        _ blob: Blob, between left: Run, and right: Run, context: Context, options: Options
    ) -> Bool {
        // A mark stands apart from both digits: a blob touching a stroke is
        // that stroke's anti-aliased edge, not a mark.
        guard blob.start > left.end + 1, blob.end < right.start - 1 else { return false }
        let width = blob.end - blob.start + 1
        guard width >= options.markMinimumWidth,
              Float(width) <= options.markWidthFraction * Float(context.pitch) else { return false }
        let height = blob.bottom - blob.top + 1
        return Float(height) <= options.markHeightFraction * Float(context.bandHeight)
    }

    /// The columns of `start...end` that carry ink, with their row extent. The
    /// mark rule measures a blob on the columns where its pixels are, so a
    /// threshold bridge through the gap's blur does not widen it, and uses the
    /// row extent to reject a blob taller than a mark.
    private static func inkBlob(
        _ start: Int, _ end: Int, in context: Context, rows: ClosedRange<Int>, threshold: Float
    ) -> Blob? {
        var firstColumn: Int?
        var lastColumn: Int?
        var firstRow: Int?
        var lastRow: Int?
        for x in start...end {
            for y in rows where context.ink[y * context.width + x] > threshold {
                if firstColumn == nil { firstColumn = x }
                lastColumn = x
                if firstRow == nil || y < firstRow! { firstRow = y }
                if lastRow == nil || y > lastRow! { lastRow = y }
            }
        }
        guard let firstColumn, let lastColumn, let firstRow, let lastRow else { return nil }
        return Blob(start: firstColumn, end: lastColumn, top: firstRow, bottom: lastRow)
    }
}
