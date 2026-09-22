import Foundation

// PU.42 - the dim-glyph recovery. The run threshold is one global Otsu split,
// so a glyph whose strokes are faint (a ghosted leading zero, a dim trailing
// `1`) leaves its grid cell empty and the count comes up short. A second look
// at a fraction of that threshold finds the run, but a run alone is not a
// glyph: the same lower threshold also finds decimal marks, glare edges and a
// bright digit's own anti-aliased spill. A candidate is accepted only where
// the grid cell its run snaps to carries ink from the top of the band (a mark
// lives in the lower band) and its column-profile peak stands a fixed fraction
// of the bright cells' peak above the panel.
extension PumpGlyphSlicer {

    /// The grid indices a dim glyph occupies that the run threshold left empty.
    /// `phase` and `pitch` are the main pass's grid; `occupied` is its set of
    /// bright cells. A returned index can lie outside the bright span (a dim
    /// leading or trailing glyph); `makePass` widens the grid to hold it.
    static func dimGlyphIndices(
        context: Context, threshold: Float, phase: Double, occupied: Set<Int>, options: Options
    ) -> Set<Int> {
        guard options.dimGlyphRecovery, !occupied.isEmpty, threshold > 0 else { return [] }
        let pitchFraction = Float(context.pitch) / Float(context.bandHeight)
        guard pitchFraction >= options.dimGlyphMinimumPitchFraction,
              pitchFraction <= options.dimGlyphMaximumPitchFraction else { return [] }
        let bright = Self.medianCellPeak(occupied, context: context, phase: phase)
        guard bright > 0 else { return [] }

        let lowThreshold = threshold * options.dimGlyphThresholdFraction
        let mergeGap = max(1, Int(options.mergeGapFraction * Float(context.bandHeight)))
        var runs = Self.runs(in: context.profile, threshold: lowThreshold, mergeGap: mergeGap)
        runs.sort { $0.start < $1.start }
        if options.splitMerge {
            runs = Self.splitMerge(runs, pitch: context.pitch, band: context.bandHeight, options: options)
        }

        let pitch = Double(context.pitch)
        let inkThreshold = options.pixelInkThreshold * options.dimGlyphInkThresholdFraction
        var out: Set<Int> = []
        for run in runs {
            let index = Int(((Double(run.end) - phase) / pitch).rounded())
            guard !occupied.contains(index), !out.contains(index) else { continue }
            // The lower threshold widens a bright digit's run, and a slice with
            // a margin can carry the spill past the cell boundary. A run that
            // begins inside an occupied cell is that digit, not a new glyph.
            let startIndex = Int(((Double(run.start) - phase) / pitch).rounded(.down)) + 1
            guard !occupied.contains(startIndex) else { continue }
            guard let columns = Self.cellColumns(index, context: context, phase: phase) else { continue }
            guard Float(columns.count) >= options.dimGlyphMinimumCellWidthFraction * Float(context.pitch)
            else { continue }
            let peak = columns.map { context.profile[$0] }.max() ?? 0
            guard peak >= options.dimGlyphContrastFraction * bright else { continue }
            let cell = Run(start: columns.lowerBound, end: columns.upperBound, isDecimalPoint: false)
            guard let top = Self.topInkRow(cell, ink: context.ink, width: context.width,
                                           bandTop: context.bandTop, bandBottom: context.bandBottom,
                                           threshold: inkThreshold),
                  Float(top - context.bandTop) <= options.dimGlyphTopRowFraction * Float(context.bandHeight)
            else { continue }
            out.insert(index)
        }
        return out
    }

    /// The median of the occupied cells' column-profile peaks: the bright
    /// reference a dim glyph must stand a fixed fraction of.
    static func medianCellPeak(_ occupied: Set<Int>, context: Context, phase: Double) -> Float {
        var peaks: [Float] = []
        for index in occupied {
            guard let columns = Self.cellColumns(index, context: context, phase: phase) else { continue }
            peaks.append(columns.map { context.profile[$0] }.max() ?? 0)
        }
        guard !peaks.isEmpty else { return 0 }
        return Self.percentile(peaks, 0.5)
    }

    /// The columns of grid cell `index`, clipped to the strip; nil when the
    /// cell lies entirely outside it. Cell `i`'s left edge is
    /// `phase + (i - 1) * pitch` (see `makePass`).
    static func cellColumns(_ index: Int, context: Context, phase: Double) -> ClosedRange<Int>? {
        let start = Int((phase + Double(index - 1) * Double(context.pitch)).rounded())
        let end = start + context.pitch - 1
        let lo = max(0, start)
        let hi = min(context.width - 1, end)
        return lo <= hi ? lo...hi : nil
    }
}
