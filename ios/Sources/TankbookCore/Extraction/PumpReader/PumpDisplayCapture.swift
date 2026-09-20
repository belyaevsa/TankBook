import CoreGraphics
import Foundation

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
        /// Rows of digits the reader vouched for, large in the frame.
        public let displayRows: Int
        /// Text lines Vision found in the frame; a receipt is dozens.
        public let textLines: Int
        /// The widest vouched row as a fraction of the frame's width, and
        /// the tallest as a fraction of its height - a display's number rows
        /// are big; a receipt's printed digits are small in the paper.
        public var widestRow: CGFloat = 0
        public var tallestRow: CGFloat = 0
        public var isPumpDisplay: Bool {
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

    /// Loads the classifier from a compiled model URL (the app bundle's
    /// `PumpSegments.mlmodelc`) once; nil when the resource is missing, in
    /// which case every frame classifies as not-a-display and the receipt path
    /// runs as before.
    public static func makeReader(modelURL: URL?, detectorURL: URL? = nil) -> PumpReaderHandle? {
        guard let modelURL, let model = try? PumpSegmentsModel(contentsOf: modelURL) else { return nil }
        let detector = detectorURL.flatMap { try? PumpRowDetector(contentsOf: $0) }
        return PumpReaderHandle(reader: PumpReader(model: model, detector: detector))
    }

    public static func detect(image: CGImage, reader: PumpReaderHandle) -> Detection {
        let rgb = PumpQuadWarp.rgbImage(from: image)
        let candidates = reader.reader.candidates(for: rgb)
        let verified = (try? reader.reader.verify(image: rgb, candidates: candidates)) ?? []
        let rows = displayRows(verified, imageHeight: rgb.height)
        var detection = Detection(displayRows: rows.count, textLines: textLineCount(rgb))
        for row in rows {
            let xs = row.quad.map(\.x), ys = row.quad.map(\.y)
            detection.widestRow = max(detection.widestRow, (xs.max()! - xs.min()!) / CGFloat(rgb.width))
            detection.tallestRow = max(detection.tallestRow, (ys.max()! - ys.min()!) / CGFloat(rgb.height))
        }
        return detection
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
        let rgb = PumpQuadWarp.rgbImage(from: image)
        guard let all = try? reader.reader.verify(image: rgb, candidates: reader.reader.candidates(for: rgb)) else {
            return (Detection(displayRows: 0, textLines: 0), nil)
        }
        let verified = displayRows(all, imageHeight: rgb.height)
        var detection = Detection(displayRows: verified.count, textLines: textLineCount(rgb))
        for row in verified {
            let xs = row.quad.map(\.x), ys = row.quad.map(\.y)
            detection.widestRow = max(detection.widestRow, (xs.max()! - xs.min()!) / CGFloat(rgb.width))
            detection.tallestRow = max(detection.tallestRow, (ys.max()! - ys.min()!) / CGFloat(rgb.height))
        }
        guard detection.isPumpDisplay else { return (detection, nil) }
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
        guard let reading = try? reader.reader.resolve(image: rgb, windows: windows, currency: currency,
                                                        priceBand: priceBand) else { return (detection, nil) }
        var extraction = FuelExtraction(
            liters: reading.liters.value.map { NSDecimalNumber(decimal: $0).doubleValue },
            unitPrice: reading.unitPrice.value,
            total: reading.total.value,
            currency: currency)
        extraction.crossCheck = reading.committedCount == 3 ? .lock : .notApplicable
        return (detection, Reading(detection: detection, extraction: extraction, cropRects: rects))
    }
}

/// An opaque handle around the reader so the app never sees the internal
/// types; one per process, since the Core ML model loads once.
public final class PumpReaderHandle: @unchecked Sendable {
    let reader: PumpReader
    init(reader: PumpReader) { self.reader = reader }
}
