import CoreGraphics
import Foundation

/// A record of one `PumpDisplayCapture.classify` run - what every stage took
/// and produced - for the annotator's pipeline view (tools/pump-annotate).
///
/// The run is the app's own: the trace is an optional observer passed through
/// the same calls, nil on the app's path, and nothing reads it back to decide.
/// `PumpTraceParityTests` pins that a traced run returns exactly what an
/// untraced one does, and that the attempt the trace marks as chosen carries
/// the reading `classify` returned.
final class PumpTrace {
    /// One candidate as the verifier judged it: the verdict, and the strip it
    /// sliced with every cell of that slice, blanks included. `strip` is nil
    /// when the candidate was dropped before a strip was cut.
    struct VerdictRecord {
        let verdict: PumpReader.Verdict
        let strip: PumpRGBImage?
        let cells: [GlyphCell]
    }

    /// One assigned window as the reader read it. `readings` has one entry per
    /// non-blank cell, after the slicer's mark and the single-mark rule - what
    /// the law received. `skipped` names why the window never reached the law.
    struct ReadRecord {
        let field: PumpField
        let quad: [CGPoint]
        let strip: PumpRGBImage?
        let cells: [GlyphCell]
        let readings: [PumpCellReading]
        let skipped: String?
    }

    /// One pass of decide-then-read at one orientation. `classify` makes up to
    /// three: at the capture's seed, at the orientation the search prefers,
    /// and with the detector rows turned to their digits' angle.
    final class Attempt {
        var kind: String
        let rotationCW: Int
        /// The upright image every quad below is in, in pixels.
        let width: Int
        let height: Int
        var textLines: Int?
        var detectedRows: [PumpRowDetector.Row] = []
        var fastVerdict: Bool?
        var budgetHit = false
        var detection: PumpDisplayCapture.Detection?
        var candidates: [PumpPanelLocator.Candidate] = []
        var verdicts: [VerdictRecord] = []
        var verified: [PumpReader.VerifiedWindow] = []
        var roles: [PumpField?] = []
        var reads: [ReadRecord] = []
        var law: PumpDisplayReading?

        init(kind: String, rotationCW: Int, width: Int, height: Int) {
            self.kind = kind
            self.rotationCW = rotationCW
            self.width = width
            self.height = height
        }
    }

    var orientationScores: [PumpReader.OrientationScore] = []
    private(set) var attempts: [Attempt] = []
    /// The attempt whose reading `classify` returned; nil when it returned none.
    var chosen: Int?

    var current: Attempt? { attempts.last }

    /// One window as the reader left it, into the current attempt.
    func read(_ window: PumpReader.Window, strip: PumpRGBImage? = nil, cells: [GlyphCell] = [],
              readings: [PumpCellReading] = [], skipped: String? = nil) {
        current?.reads.append(ReadRecord(field: window.field, quad: window.quad, strip: strip, cells: cells,
                                         readings: readings, skipped: skipped))
    }

    /// One verdict, with the strip it judged, into the current attempt.
    func judged(_ verdict: PumpReader.Verdict, strip: PumpRGBImage? = nil, cells: [GlyphCell] = []) {
        current?.verdicts.append(VerdictRecord(verdict: verdict, strip: strip, cells: cells))
    }

    /// Starts an attempt; returns its index.
    @discardableResult
    func begin(_ kind: String, rotationCW: Int, upright: PumpRGBImage) -> Int {
        attempts.append(Attempt(kind: kind, rotationCW: rotationCW, width: upright.width, height: upright.height))
        return attempts.count - 1
    }
}
