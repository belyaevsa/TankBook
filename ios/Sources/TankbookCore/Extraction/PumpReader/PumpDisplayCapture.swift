import CoreGraphics
import CoreVideo
import Foundation

/// Which classification path produced a frame's verdict (PU.38): the detector's
/// rows alone (`fast`) or the full verifier, wall-clock capped (`slow`).
public enum ClassificationPath: String, Sendable, Equatable {
    case fast
    case slow
}

/// The app's door into the pump reader: is this frame a pump display, and if
/// so, what does it read. Runs the locator, the verifier, row assignment and
/// the law; the app only decides what to do with the answer
/// (docs/EXTRACTION.md -> "The pump reader"; PU.29).
///
/// Classification is by structure, never by strings: a frame is a display
/// when the reader itself vouches for at least two rows of seven-segment
/// digits, which a receipt, a screenshot or a shop front never shows.
public enum PumpDisplayCapture {
    public struct Detection: Sendable, Equatable {
        /// Rows of digits the deciding path vouched for, large in the frame.
        public let displayRows: Int
        /// Text lines Vision found in the frame; a receipt is dozens. On the
        /// fast path this is `textLinesNotMeasured` - the frame was decided
        /// before the pass ran; the slow path carries the real count.
        public let textLines: Int
        /// The widest vouched row as a fraction of the frame's width, and
        /// the tallest as a fraction of its height - a display's number rows
        /// are big; a receipt's printed digits are small in the paper.
        public var widestRow: CGFloat = 0
        public var tallestRow: CGFloat = 0
        /// The path that decided this frame (PU.38).
        public let path: ClassificationPath
        /// The verdict itself, set by the path that decided: the detector's
        /// stacked rows on the fast path, the verifier's count on the slow one.
        public let isPumpDisplay: Bool

        public init(displayRows: Int, textLines: Int, widestRow: CGFloat = 0, tallestRow: CGFloat = 0,
                    path: ClassificationPath = .slow, isPumpDisplay: Bool? = nil) {
            self.displayRows = displayRows
            self.textLines = textLines
            self.widestRow = widestRow
            self.tallestRow = tallestRow
            self.path = path
            self.isPumpDisplay = isPumpDisplay
                ?? Self.slowVerdict(displayRows: displayRows, textLines: textLines, widestRow: widestRow)
        }

        /// The slow path's rule: at least two verified rows, under the
        /// text-line ceiling, with a wide enough row. The fast path does not
        /// use it - the detector's rows decide there.
        static func slowVerdict(displayRows: Int, textLines: Int, widestRow: CGFloat) -> Bool {
            displayRows >= PumpDisplayCapture.minimumRows && textLines <= PumpDisplayCapture.maximumTextLines
                && widestRow >= PumpDisplayCapture.minimumWidestRowFraction
        }
    }

    public struct Reading: Sendable, Equatable {
        public let detection: Detection
        public let extraction: FuelExtraction
        /// The law's own answer the extraction was built from: per-field
        /// provenance and the reasons a field was refused, which the extraction
        /// drops.
        public let law: PumpDisplayReading
        /// The windows the fields were read from, normalised over the image,
        /// for the Confirm sheet's tap-to-verify crops.
        public let cropRects: [ManualFillUpMath.Field: CGRect]
    }

    public static let minimumRows = 2
    /// The `Detection.textLines` value on the fast path, which decides on the
    /// detector's rows alone and never runs the Vision text-line pass: `-1`,
    /// not `0`, because a pump face can show no text line at all. Diagnostic
    /// only - no verdict reads it.
    public static let textLinesNotMeasured = -1
    /// A display's digits are large in the frame - the corpus's windows are
    /// 3-12 % of the image height; a receipt's printed lines are under 2 %.
    /// Rows below this fraction are text, not a display, however well the
    /// classifier reads their digits.
    public static let minimumRowHeightFraction: CGFloat = PumpReader.minimumRowHeightFraction
    /// The slow path's ceiling on Vision text lines. A receipt's printed
    /// digits pass the verifier too (they are digits), and a receipt carries
    /// dozens of lines; but so does a pump face covered in labels, so the two
    /// ranges overlap (PU.63: pumps 0-58, receipts with two verified rows
    /// 12-67). The ceiling therefore guards only the slow path, whose rows come
    /// from Vision and the classical proposals as readily off a receipt as off
    /// a display; the fast path's rows come from the learned detector, which is
    /// trained on the receipts as negatives, and are not overruled by it.
    public static let maximumTextLines = 30
    /// A display's number rows span a fifth of the frame or more on every
    /// heldout still (0.20-0.39); a receipt's printed amounts that pass the
    /// verifier are narrow (receipt-038: 0.12 with 16 text lines, which the
    /// line count alone let through).
    public static let minimumWidestRowFraction: CGFloat = 0.18
    /// The fast path's second confidence arm: two rows both at
    /// `PumpRowDetector.minimumConfidence` (0.3) decide, or one at this higher
    /// cut with the other a rescued row under it (PU.38). Both arms were the
    /// detector's measured operating points.
    public static let fastConfidenceHigh: Double = 0.5
    /// The wall-clock cap on the slow classification path (PU.38). The reader
    /// has 3 s on the phone in total (docs/EXTRACTION.md -> P4.12) and
    /// classification runs on every photo, receipts included; the verifier
    /// measured 0.8-3.5 s a photo on the Mac and 28 s on the fallback, so a
    /// frame the detector cannot classify gets this long to change the verdict
    /// and no longer. A frame that exhausts it is not a display.
    public static let slowPathBudget: TimeInterval = 1.5

    /// Loads the classifier from a compiled model URL (the app bundle's
    /// `PumpSegments.mlmodelc`) once; nil when the resource is missing, in
    /// which case every frame classifies as not-a-display and the receipt path
    /// runs as before.
    public static func makeReader(modelURL: URL?, detectorURL: URL? = nil, rowReaderURL: URL? = nil) -> PumpReaderHandle? {
        guard let modelURL, let model = try? PumpSegmentsModel(contentsOf: modelURL) else { return nil }
        let detector = detectorURL.flatMap { try? PumpRowDetector.load(contentsOf: $0) }
        let rowReader = rowReaderURL.flatMap { try? PumpRowReader(contentsOf: $0) }
        return PumpReaderHandle(reader: PumpReader(model: model, detector: detector, rowReader: rowReader))
    }

    /// The classification verdict, read or not: the fast path when the detector
    /// vouches for two stacked rows, the verifier otherwise. The detector-only
    /// decision is a detector pass and a Vision text-line count; it does not
    /// verify, slice or classify (PU.38).
    /// `rotationCW` is the capture's own orientation where the app knows it;
    /// the frame is already upright on the app's path (RV.49 bakes the
    /// interface orientation in), so the search starts at 0 and is the
    /// fallback for a display sideways in that upright frame (PU.53).
    public static func detect(image: CGImage, reader: PumpReaderHandle, rotationCW: Int? = nil) -> Detection {
        decide(rgb: PumpQuadWarp.rgbImage(from: image), reader: reader.reader, budget: slowPathBudget,
               seed: rotationCW).detection
    }

    /// The fast path's verdict (PU.38): the detector's rescued rows alone, no
    /// warping, slicing or classifier. Two rows that pass the size rules and
    /// stack, at the detector's own confidence, make the frame a display
    /// however many text lines surround them (`maximumTextLines` explains why
    /// the ceiling is the slow path's only); `textLines` no longer decides and
    /// stays in the signature its callers share. The reading runs afterwards
    /// only to fill the display in.
    ///
    /// Public because the live preview's guidance (PU.40b) must decide "display
    /// in view" with the same rules the capture path uses, never a second copy.
    public static func fastVerdict(rows: [PumpRowDetector.Row], textLines: Int) -> Bool {
        let sized = rows.filter { passesSize($0) }
        for i in sized.indices {
            for j in sized.indices where j > i {
                let a = sized[i], b = sized[j]
                // A transaction row stacks on one column on every head; a
                // keypad row sits beside the display and shares no x-span.
                guard PumpReader.sharesSpan(a.quad, b.quad), PumpReader.stacks(a.quad, b.quad) else { continue }
                let hi = max(a.confidence, b.confidence), lo = min(a.confidence, b.confidence)
                if lo >= PumpRowDetector.minimumConfidence || hi >= fastConfidenceHigh { return true }
            }
        }
        return false
    }

    /// Whether one detected row is big enough in the frame to be a display row
    /// rather than a receipt's printed line. Shared with the preview guidance.
    public static func passesSize(_ row: PumpRowDetector.Row) -> Bool {
        let bounds = row.bounds
        return bounds.height >= minimumRowHeightFraction && bounds.width >= minimumWidestRowFraction
    }

    /// The detector's rows after the stacked-row rescue (`PumpReader`): every
    /// row above the confidence cut plus a low-confidence row rescued from
    /// beside a passing one. Public so the preview guidance's state machine can
    /// be tested on synthetic rows with the production rescue, and used by
    /// `PumpReaderHandle` so the two can never diverge.
    public static func rescuedRows(_ rows: [PumpRowDetector.Row]) -> [PumpRowDetector.Row] {
        PumpReader.rescueStackedRows(rows)
    }

    /// The decision and, when the read should run, how to get its windows. Fast
    /// when the detector's rows decide (no verify yet - the read runs later);
    /// slow (the verifier, capped at `slowPathBudget`) when they abstain, so a
    /// head the detector never saw still gets its Vision and classical chance.
    private struct Decision {
        let detection: Detection
        /// The image the decision's windows are normalised over: the original
        /// frame turned by `rotationCW`.
        let upright: PumpRGBImage
        let rotationCW: Int
        /// Windows the verifier already returned for the read (slow path).
        let verified: [PumpReader.VerifiedWindow]?
        /// The detector's candidates the fast path's read will verify.
        let candidates: [PumpPanelLocator.Candidate]?
    }

    /// The decision at the capture's seed orientation. Classification stays at
    /// the frame the user composed; the orientation search is the read's, run
    /// by `classify` only when the seed read commits nothing (PU.53). Searching
    /// here would run the slow verifier a second time on every receipt, which
    /// decides nothing.
    private static func decide(rgb: PumpRGBImage, reader: PumpReader, budget: TimeInterval,
                               seed: Int?, trace: PumpTrace? = nil) -> Decision {
        decideAt(rgb: rgb, rotationCW: normalizedRotation(seed ?? 0), reader: reader, budget: budget, trace: trace)
    }

    private static func decideAt(rgb: PumpRGBImage, rotationCW: Int, reader: PumpReader,
                                 budget: TimeInterval, trace: PumpTrace? = nil) -> Decision {
        let upright = PumpPanelLocator.rotatedRGB(rgb, rotationCW: rotationCW)
        trace?.begin("seed", rotationCW: rotationCW, upright: upright)
        let detected = reader.detectedRows(for: upright)
        trace?.current?.detectedRows = detected
        // The text-line pass is measured only when the fast path abstains: the
        // detector's rows decide the frame and never read the count.
        if fastVerdict(rows: detected, textLines: textLinesNotMeasured) {
            let detection = detectorDetection(rows: detected, textLines: textLinesNotMeasured)
            let candidates = detected.map { PumpPanelLocator.Candidate(quad: $0.quad, glyphCount: 0, detected: true) }
            trace?.current?.textLines = textLinesNotMeasured
            trace?.current?.fastVerdict = true
            trace?.current?.detection = detection
            trace?.current?.candidates = candidates
            return Decision(detection: detection, upright: upright, rotationCW: rotationCW,
                            verified: nil, candidates: candidates)
        }
        trace?.current?.fastVerdict = false
        let textLines = textLineCount(upright)
        trace?.current?.textLines = textLines
        let deadline = Date().addingTimeInterval(budget)
        let candidates = reader.candidates(for: upright)
        trace?.current?.candidates = candidates
        let verified = (try? reader.verify(image: upright, candidates: candidates,
                                           deadline: deadline, trace: trace)) ?? []
        let budgetHit = Date() >= deadline
        trace?.current?.budgetHit = budgetHit
        let rows = displayRows(verified, imageHeight: upright.height)
        let detection = makeDetection(rows: rows, textLines: textLines, imageWidth: upright.width,
                                      imageHeight: upright.height, path: .slow, isPumpDisplay: nil)
        guard !budgetHit, detection.isPumpDisplay else {
            let refused = makeDetection(isDisplay: false, from: detection)
            trace?.current?.detection = refused
            return Decision(detection: refused, upright: upright,
                            rotationCW: rotationCW, verified: nil, candidates: nil)
        }
        trace?.current?.detection = detection
        return Decision(detection: detection, upright: upright, rotationCW: rotationCW,
                        verified: verified, candidates: nil)
    }

    private static func normalizedRotation(_ rotationCW: Int) -> Int {
        ((rotationCW % 360) + 360) % 360
    }

    /// The fast path's Detection, counted from the detector's rows alone: every
    /// rescued row that passes the size rules is a display row. `textLines` is
    /// the `textLinesNotMeasured` sentinel - the pass never ran.
    private static func detectorDetection(rows: [PumpRowDetector.Row], textLines: Int) -> Detection {
        let sized = rows.filter { passesSize($0) }
        var widest: CGFloat = 0, tallest: CGFloat = 0
        for row in sized {
            // The detector's quads are normalised, so their bounds already are
            // fractions of the frame.
            let bounds = PumpRowAssignment.bounds(row.quad, rotationCW: 0)
            widest = max(widest, bounds.width)
            tallest = max(tallest, bounds.height)
        }
        return Detection(displayRows: sized.count, textLines: textLines, widestRow: widest,
                         tallestRow: tallest, path: .fast, isPumpDisplay: true)
    }

    private static func makeDetection(rows: [PumpReader.VerifiedWindow], textLines: Int, imageWidth: Int,
                                      imageHeight: Int, path: ClassificationPath, isPumpDisplay: Bool?) -> Detection {
        var widest: CGFloat = 0, tallest: CGFloat = 0
        for row in rows {
            let xs = row.quad.map(\.x), ys = row.quad.map(\.y)
            widest = max(widest, (xs.max()! - xs.min()!) / CGFloat(imageWidth))
            tallest = max(tallest, (ys.max()! - ys.min()!) / CGFloat(imageHeight))
        }
        return Detection(displayRows: rows.count, textLines: textLines, widestRow: widest,
                         tallestRow: tallest, path: path, isPumpDisplay: isPumpDisplay)
    }

    private static func makeDetection(isDisplay: Bool, from detection: Detection) -> Detection {
        Detection(displayRows: detection.displayRows, textLines: detection.textLines,
                  widestRow: detection.widestRow, tallestRow: detection.tallestRow,
                  path: detection.path, isPumpDisplay: isDisplay)
    }

    static func textLineCount(_ rgb: PumpRGBImage) -> Int {
        let small = PumpPanelLocator.downscaleRGB(rgb, targetWidth: 1600)
        guard let cg = PumpQuadWarp.makeImage(small.pixels, width: small.width, height: small.height) else { return 0 }
        return PumpVisionProposer.textLineCount(in: cg)
    }

    /// The reader keeps a row from a margin of 1.0 (`PumpReader.minimumMeanMargin`)
    /// because the law can still refuse it; the classifier decides whether a
    /// photo is a display at all and asks for the wider margin a real digit
    /// row carries - at 1.0 a receipt's printed totals classified as one.
    public static let classificationMinimumMargin = 1.5

    static func displayRows(_ verified: [PumpReader.VerifiedWindow], imageHeight: Int) -> [PumpReader.VerifiedWindow] {
        verified.filter { window in
            let ys = window.quad.map(\.y)
            // A row the detector vouched for counts on size alone; a Vision
            // row still needs the classifier's wider margin (a receipt's
            // printed totals passed the verifier at 1.0).
            return (ys.max()! - ys.min()!) >= minimumRowHeightFraction * CGFloat(imageHeight)
                && (window.detected || window.meanMargin >= classificationMinimumMargin)
        }
    }

    /// Detects, and reads when it is a display. The extraction carries the
    /// law's committed fields; an abstained field is nil, never a guess.
    public static func read(image: CGImage, reader: PumpReaderHandle, currency: CurrencyCode?,
                            priceBand: FuelPriceBand?, rotationCW: Int? = nil) -> Reading? {
        classify(image: image, reader: reader, currency: currency, priceBand: priceBand,
                 rotationCW: rotationCW).reading
    }

    /// `read` with the detection kept when the frame is NOT a display, so the
    /// caller can log what the classifier counted and why it declined.
    public static func classify(image: CGImage, reader: PumpReaderHandle, currency: CurrencyCode?,
                                priceBand: FuelPriceBand?,
                                rotationCW: Int? = nil) -> (detection: Detection, reading: Reading?) {
        classify(image: image, reader: reader, currency: currency, priceBand: priceBand,
                 budget: slowPathBudget, rotationCW: rotationCW)
    }

    /// The classification with the slow-path cap supplied, so a test can pin it
    /// without depending on wall clock (PU.38).
    ///
    /// `rotationCW` is the capture's orientation seed (PU.53). The frame is
    /// classified at the seed; when that orientation reads nothing, the search
    /// tries the orientation the detector prefers and keeps its reading if it
    /// commits. A reading that commits at the seed is never replaced, and the
    /// detection is always the seed's.
    static func classify(image: CGImage, reader: PumpReaderHandle, currency: CurrencyCode?,
                         priceBand: FuelPriceBand?, budget: TimeInterval,
                         rotationCW: Int? = nil,
                         trace: PumpTrace? = nil) -> (detection: Detection, reading: Reading?) {
        let rgb = PumpQuadWarp.rgbImage(from: image)
        let decision = decide(rgb: rgb, reader: reader.reader, budget: budget, seed: rotationCW, trace: trace)
        let seedAttempt = trace.map { $0.attempts.count - 1 }
        guard decision.detection.isPumpDisplay else { return (decision.detection, nil) }
        let seedReading = readDecision(decision, reader: reader.reader, currency: currency, priceBand: priceBand,
                                       trace: trace)
        trace?.chosen = seedReading == nil ? nil : seedAttempt
        if commits(seedReading) { return (decision.detection, seedReading) }
        // The seed orientation read nothing: a display sideways in an upright
        // frame is read upright here.
        let orientation = reader.reader.bestOrientation(for: rgb, seed: rotationCW, trace: trace)
        if orientation != decision.rotationCW {
            let searched = decideAt(rgb: rgb, rotationCW: orientation, reader: reader.reader, budget: budget,
                                    trace: trace)
            trace?.current?.kind = "searched"
            if searched.detection.isPumpDisplay,
               let searchedReading = readDecision(searched, reader: reader.reader, currency: currency,
                                                  priceBand: priceBand, trace: trace),
               commits(searchedReading) {
                trace?.chosen = trace.map { $0.attempts.count - 1 }
                return (decision.detection, searchedReading)
            }
        }
        // Still nothing: the detector rows turned to their digits' angle, at the
        // seed orientation, when the reader is set to retry that way.
        if reader.reader.deskew == .onRefusal {
            trace?.begin("turned", rotationCW: decision.rotationCW, upright: decision.upright)
            trace?.current?.detection = decision.detection
            let candidates = reader.reader.candidates(for: decision.upright, deskewRows: true)
            trace?.current?.candidates = candidates
            if let verified = try? reader.reader.verify(image: decision.upright, candidates: candidates, trace: trace),
               let turned = reading(from: verified, rgb: decision.upright, detection: decision.detection,
                                    reader: reader.reader, currency: currency, priceBand: priceBand,
                                    rotationCW: decision.rotationCW, trace: trace),
               commits(turned) {
                trace?.chosen = trace.map { $0.attempts.count - 1 }
                return (decision.detection, turned)
            }
        }
        return (decision.detection, seedReading)
    }

    /// Whether a reading committed any field. A display the law could not close
    /// on reads nothing, which is what sends the search after it.
    private static func commits(_ reading: Reading?) -> Bool {
        guard let extraction = reading?.extraction else { return false }
        return extraction.liters != nil || extraction.unitPrice != nil || extraction.total != nil
    }

    /// The read for an accepted decision: the decision's own verified windows
    /// (slow path) or the detector's rows verified now (fast path).
    private static func readDecision(_ decision: Decision, reader: PumpReader, currency: CurrencyCode?,
                                     priceBand: FuelPriceBand?, trace: PumpTrace? = nil) -> Reading? {
        let verified = decision.verified
            ?? ((try? reader.verify(image: decision.upright, candidates: decision.candidates ?? [],
                                    trace: trace)) ?? [])
        return reading(from: verified, rgb: decision.upright, detection: decision.detection,
                       reader: reader, currency: currency, priceBand: priceBand, rotationCW: decision.rotationCW,
                       trace: trace)
    }

    /// Assigns roles to the verified windows and resolves the law on them. The
    /// classification already accepted the frame; a window the assigner leaves
    /// without a role is simply not read. `rotationCW` maps the crop rects,
    /// normalised over the turned image, back to the original frame's.
    private static func reading(from verified: [PumpReader.VerifiedWindow], rgb: PumpRGBImage,
                                detection: Detection, reader: PumpReader, currency: CurrencyCode?,
                                priceBand: FuelPriceBand?, rotationCW: Int, trace: PumpTrace? = nil) -> Reading? {
        let assignment = PumpRowAssignment.assign(
            windows: verified.map { PumpRowAssignment.Window(quad: $0.quad, glyphCount: $0.glyphCount) },
            rotationCW: 0)
        trace?.current?.roles = assignment.roles
        var windows: [PumpReader.Window] = []
        var rects: [ManualFillUpMath.Field: CGRect] = [:]
        for (window, role) in zip(verified, assignment.roles) {
            guard let role else { continue }
            windows.append(PumpReader.Window(field: role, quad: window.quad))
            let xs = window.quad.map { $0.x / CGFloat(rgb.width) }, ys = window.quad.map { $0.y / CGFloat(rgb.height) }
            let rect = PumpPanelLocator.unrotated(
                CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!),
                rotationCW: rotationCW)
            switch role {
            case .total: rects[.total] = rect
            case .liters: rects[.volume] = rect
            case .unitPrice: rects[.unitPrice] = rect
            case .board: break
            }
        }
        guard let reading = try? reader.resolve(image: rgb, windows: windows, currency: currency,
                                                priceBand: priceBand, trace: trace) else { return nil }
        var extraction = FuelExtraction(
            liters: reading.liters.value.map { NSDecimalNumber(decimal: $0).doubleValue },
            unitPrice: reading.unitPrice.value,
            total: reading.total.value,
            currency: currency)
        extraction.crossCheck = reading.committedCount == 3 ? .lock : .notApplicable
        return Reading(detection: detection, extraction: extraction, law: reading, cropRects: rects)
    }
}

/// An opaque handle around the reader so the app never sees the internal
/// types; one per process, since the Core ML model loads once.
public final class PumpReaderHandle: @unchecked Sendable {
    let reader: PumpReader
    init(reader: PumpReader) { self.reader = reader }

    /// The detector's rows after the stacked-row rescue, with no warping,
    /// slicing or classification - the fast path's input, exposed for the live
    /// preview's guidance (PU.40b). Empty when no detector is loaded.
    public func detectedRows(in pixelBuffer: CVPixelBuffer) -> [PumpRowDetector.Row] {
        guard let detector = reader.detector else { return [] }
        return PumpDisplayCapture.rescuedRows(detector.detect(in: pixelBuffer))
    }

    /// The same rows from a decoded image, so a test frame can drive the
    /// guidance with no camera (PU.40b).
    public func detectedRows(in image: CGImage) -> [PumpRowDetector.Row] {
        guard let detector = reader.detector else { return [] }
        return PumpDisplayCapture.rescuedRows(detector.detect(in: image))
    }
}
