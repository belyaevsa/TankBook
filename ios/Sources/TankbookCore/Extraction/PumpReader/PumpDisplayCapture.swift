import CoreGraphics
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
        /// Text lines Vision found in the frame; a receipt is dozens.
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
        /// The windows the fields were read from, normalised over the image,
        /// for the Confirm sheet's tap-to-verify crops.
        public let cropRects: [ManualFillUpMath.Field: CGRect]
    }

    public static let minimumRows = 2
    /// A display's digits are large in the frame - the corpus's windows are
    /// 3-12 % of the image height; a receipt's printed lines are under 2 %.
    /// Rows below this fraction are text, not a display, however well the
    /// classifier reads their digits.
    public static let minimumRowHeightFraction: CGFloat = PumpReader.minimumRowHeightFraction
    /// A receipt's printed digits pass the verifier too (they are digits),
    /// but a receipt is dozens of text lines where a display is a handful:
    /// measured 6-27 on pump fixtures, 31-49 on receipts that had two or more
    /// verified rows.
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
    public static func makeReader(modelURL: URL?, detectorURL: URL? = nil) -> PumpReaderHandle? {
        guard let modelURL, let model = try? PumpSegmentsModel(contentsOf: modelURL) else { return nil }
        let detector = detectorURL.flatMap { try? PumpRowDetector(contentsOf: $0) }
        return PumpReaderHandle(reader: PumpReader(model: model, detector: detector))
    }

    /// The classification verdict, read or not: the fast path when the detector
    /// vouches for two stacked rows, the verifier otherwise. The detector-only
    /// decision is a detector pass and a Vision text-line count; it does not
    /// verify, slice or classify (PU.38).
    public static func detect(image: CGImage, reader: PumpReaderHandle) -> Detection {
        decide(rgb: PumpQuadWarp.rgbImage(from: image), reader: reader.reader, budget: slowPathBudget).detection
    }

    /// The fast path's verdict (PU.38): the detector's rescued rows alone, no
    /// warping, slicing or classifier. Two rows that pass the size rules and
    /// stack, at the detector's own confidence, under the text-line ceiling.
    /// The frame is a display; the reading runs afterwards only to fill it.
    static func fastVerdict(rows: [PumpRowDetector.Row], textLines: Int) -> Bool {
        guard textLines <= maximumTextLines else { return false }
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

    private static func passesSize(_ row: PumpRowDetector.Row) -> Bool {
        let bounds = PumpRowAssignment.bounds(row.quad, rotationCW: 0)
        return bounds.height >= minimumRowHeightFraction && bounds.width >= minimumWidestRowFraction
    }

    /// The decision and, when the read should run, how to get its windows. Fast
    /// when the detector's rows decide (no verify yet - the read runs later);
    /// slow (the verifier, capped at `slowPathBudget`) when they abstain, so a
    /// head the detector never saw still gets its Vision and classical chance.
    private struct Decision {
        let detection: Detection
        /// Windows the verifier already returned for the read (slow path).
        let verified: [PumpReader.VerifiedWindow]?
        /// The detector's candidates the fast path's read will verify.
        let candidates: [PumpPanelLocator.Candidate]?
    }

    private static func decide(rgb: PumpRGBImage, reader: PumpReader, budget: TimeInterval) -> Decision {
        let textLines = textLineCount(rgb)
        let detected = reader.detectedRows(for: rgb)
        if fastVerdict(rows: detected, textLines: textLines) {
            let detection = detectorDetection(rows: detected, textLines: textLines)
            let candidates = detected.map { PumpPanelLocator.Candidate(quad: $0.quad, glyphCount: 0, detected: true) }
            return Decision(detection: detection, verified: nil, candidates: candidates)
        }
        let deadline = Date().addingTimeInterval(budget)
        let verified = (try? reader.verify(image: rgb, candidates: reader.candidates(for: rgb), deadline: deadline)) ?? []
        let budgetHit = Date() >= deadline
        let rows = displayRows(verified, imageHeight: rgb.height)
        let detection = makeDetection(rows: rows, textLines: textLines, imageWidth: rgb.width,
                                      imageHeight: rgb.height, path: .slow, isPumpDisplay: nil)
        guard !budgetHit, detection.isPumpDisplay else {
            return Decision(detection: makeDetection(isDisplay: false, from: detection), verified: nil, candidates: nil)
        }
        return Decision(detection: detection, verified: verified, candidates: nil)
    }

    /// The fast path's Detection, counted from the detector's rows alone: every
    /// rescued row that passes the size rules is a display row.
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
                            priceBand: FuelPriceBand?) -> Reading? {
        classify(image: image, reader: reader, currency: currency, priceBand: priceBand).reading
    }

    /// `read` with the detection kept when the frame is NOT a display, so the
    /// caller can log what the classifier counted and why it declined.
    public static func classify(image: CGImage, reader: PumpReaderHandle, currency: CurrencyCode?,
                                priceBand: FuelPriceBand?) -> (detection: Detection, reading: Reading?) {
        classify(image: image, reader: reader, currency: currency, priceBand: priceBand, budget: slowPathBudget)
    }

    /// The classification with the slow-path cap supplied, so a test can pin it
    /// without depending on wall clock (PU.38).
    static func classify(image: CGImage, reader: PumpReaderHandle, currency: CurrencyCode?,
                         priceBand: FuelPriceBand?, budget: TimeInterval) -> (detection: Detection, reading: Reading?) {
        let rgb = PumpQuadWarp.rgbImage(from: image)
        let decision = decide(rgb: rgb, reader: reader.reader, budget: budget)
        guard decision.detection.isPumpDisplay else { return (decision.detection, nil) }
        // The decision is made; the read's verify runs only on an accepted
        // frame. The slow path already has its windows; the fast path verifies
        // the detector's rows now.
        let verified = decision.verified
            ?? ((try? reader.reader.verify(image: rgb, candidates: decision.candidates ?? [])) ?? [])
        return (decision.detection, reading(from: verified, rgb: rgb, detection: decision.detection,
                                            reader: reader.reader, currency: currency, priceBand: priceBand))
    }

    /// Assigns roles to the verified windows and resolves the law on them. The
    /// classification already accepted the frame; a window the assigner leaves
    /// without a role is simply not read.
    private static func reading(from verified: [PumpReader.VerifiedWindow], rgb: PumpRGBImage,
                                detection: Detection, reader: PumpReader, currency: CurrencyCode?,
                                priceBand: FuelPriceBand?) -> Reading? {
        let assignment = PumpRowAssignment.assign(
            windows: verified.map { PumpRowAssignment.Window(quad: $0.quad, glyphCount: $0.glyphCount) },
            rotationCW: 0)
        var windows: [PumpReader.Window] = []
        var rects: [ManualFillUpMath.Field: CGRect] = [:]
        for (window, role) in zip(verified, assignment.roles) {
            guard let role else { continue }
            windows.append(PumpReader.Window(field: role, quad: window.quad))
            let xs = window.quad.map { $0.x / CGFloat(rgb.width) }, ys = window.quad.map { $0.y / CGFloat(rgb.height) }
            let rect = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            switch role {
            case .total: rects[.total] = rect
            case .liters: rects[.volume] = rect
            case .unitPrice: rects[.unitPrice] = rect
            case .board: break
            }
        }
        guard let reading = try? reader.resolve(image: rgb, windows: windows, currency: currency,
                                                priceBand: priceBand) else { return nil }
        var extraction = FuelExtraction(
            liters: reading.liters.value.map { NSDecimalNumber(decimal: $0).doubleValue },
            unitPrice: reading.unitPrice.value,
            total: reading.total.value,
            currency: currency)
        extraction.crossCheck = reading.committedCount == 3 ? .lock : .notApplicable
        return Reading(detection: detection, extraction: extraction, cropRects: rects)
    }
}

/// An opaque handle around the reader so the app never sees the internal
/// types; one per process, since the Core ML model loads once.
public final class PumpReaderHandle: @unchecked Sendable {
    let reader: PumpReader
    init(reader: PumpReader) { self.reader = reader }
}
