import CoreGraphics
import Foundation

/// The verifier's geometry verdict: what a sliced display strip must look like
/// to be a number row, judged from the slicer's cells and the strip alone -
/// never from the classifier.
///
/// The classifier's decode margin used to gate Vision's proposals
/// (`PumpReader.minimumMeanMargin`), which tied the live number to every
/// retrain (ml/pump-reader/REPORT.md rounds 8-11: 39 shipped, 19-36 on the
/// same heldout split). These rules replace that gate; the margin is still
/// computed and carried for the diagnostic, but no keep decision reads it.
///
/// Every bound below is measured on the TRAIN split only (decision 9): the
/// positives are its annotated windows through the current slicer, the
/// negatives the Vision proposals that overlap no annotated window at IoU 0.3.
/// The distributions and the true/false-positive rates are in the PU.47
/// section of the report; the heldout split was not looked at while choosing.
enum PumpRowGeometry {

    /// The rule that rejected a candidate, for the diagnostic and the tests.
    enum Reason: String, CaseIterable {
        case cellCount
        case pitch
        case inkBand
        case decimalMark
        case blankLayout
    }

    struct Verdict {
        let kept: Bool
        let reasons: [Reason]
    }

    /// A display row shows the transaction fields' digit counts and no more
    /// (`PumpReadingLaw.maxCells`); fewer than `minimumVerifiedCells` cells is
    /// a fragment. Both bounds already existed in `PumpReader`.
    static let minimumCells = PumpReader.minimumVerifiedCells
    static let maximumCells = PumpReadingLaw.maxCells

    /// The pitch expressed against the glyph body height: a seven-segment
    /// cell is narrower than its band (train positives p5 0.50, p50 0.69,
    /// p95 1.18; a dense display's pitch measured 0.34), while a keypad's key
    /// caps are square or wider (pump-215's keypad rows 0.94-1.38; the same
    /// measurement is what `isKeypadRow` names from the other side). The
    /// literal coefficient of variation of the cell widths is identically zero
    /// here: `PumpGlyphSlicer` snaps every cell to one pitch, so the pitch is
    /// regular by construction and the measured, discriminating pitch property
    /// is its ratio to the band.
    static let minimumPitchToBand: CGFloat = 0.3
    static let maximumPitchToBand: CGFloat = 1.25

    /// The ink band (the slicer's `bandTop...bandBottom`) as a fraction of the
    /// strip height. A display's digits fill most of the strip (train
    /// positives p5 0.70, p50 0.88); a text row's band is a thin line
    /// (pump-263's CLOSED sum window 0.021). The upper bound is the strip
    /// itself, so it only guards a band that left the strip.
    static let minimumInkBandFraction: CGFloat = 0.35
    static let maximumInkBandFraction: CGFloat = 1.0

    /// A decimal mark sits on the digit before it, and the law reads a value
    /// with at most this many fraction digits (`PumpReadingLaw`'s decimal
    /// placements). A mark implying more than three decimals (a count-8 row
    /// with the mark on the first cell implies seven) is a misplaced mark, not
    /// a number. Both a mark on the first cell ("1,789") and one on the last
    /// (an integer the slicer marked) are legitimate, so neither is rejected
    /// on its own.
    static let maximumDecimalPlaces = 3

    /// A display's unlit leading cells are one run of blanks before the first
    /// digit (pump-032's total, three). An interior blank is a gap a keypad or
    /// spaced text leaves between glyphs: one is allowed (a wide gap, a
    /// separator in its own cell), a run of two or more is not.
    static let maximumInteriorBlankRun = 1

    static func verdict(cells: [GlyphCell], stripWidth: Int, stripHeight: Int) -> Verdict {
        var reasons: [Reason] = []
        let nonBlank = cells.filter { !$0.isBlank }
        guard let first = nonBlank.first else {
            return Verdict(kept: false, reasons: [.cellCount])
        }
        if nonBlank.count < minimumCells || nonBlank.count > maximumCells {
            reasons.append(.cellCount)
        }
        let cellWidth = first.rect.width
        let bandHeight = first.rect.height
        let pitchToBand = bandHeight > 0 ? cellWidth / bandHeight : 0
        if pitchToBand < minimumPitchToBand || pitchToBand > maximumPitchToBand {
            reasons.append(.pitch)
        }
        let bandFraction = stripHeight > 0 ? bandHeight / CGFloat(stripHeight) : 0
        if bandFraction < minimumInkBandFraction || bandFraction > maximumInkBandFraction {
            reasons.append(.inkBand)
        }
        if let mark = cells.firstIndex(where: { $0.hasDecimalPoint }),
           cells.count - 1 - mark > maximumDecimalPlaces {
            reasons.append(.decimalMark)
        }
        if maximumInteriorBlankRun(in: cells) > Self.maximumInteriorBlankRun {
            reasons.append(.blankLayout)
        }
        return Verdict(kept: reasons.isEmpty, reasons: reasons)
    }

    /// The longest run of blanks that is neither leading nor trailing - the
    /// interior gaps a keypad or spaced text leaves. The slicer never emits a
    /// trailing blank run, so only leading and interior runs exist.
    static func maximumInteriorBlankRun(in cells: [GlyphCell]) -> Int {
        guard let firstOccupied = cells.firstIndex(where: { !$0.isBlank }),
              let lastOccupied = cells.lastIndex(where: { !$0.isBlank }),
              firstOccupied < lastOccupied else { return 0 }
        var longest = 0
        var run = 0
        for index in firstOccupied...lastOccupied {
            if cells[index].isBlank {
                run += 1
                longest = max(longest, run)
            } else {
                run = 0
            }
        }
        return longest
    }
}
