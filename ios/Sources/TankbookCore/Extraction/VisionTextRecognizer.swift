import Foundation

#if canImport(Vision)
import ImageIO
import Vision

/// The Vision OCR entry point, kept out of the pure extraction core so the core
/// stays testable from plain `[OCRLine]` with no image and no Vision import.
/// `usesLanguageCorrection = false` is deliberate: receipts are full of codes
/// and correction hurts (docs/VISION.md).
///
/// Every entry point funnels its `perform` through the shared `VisionRequestGate`,
/// which runs it on a background dispatch thread and bounds how many are in flight
/// at once. That is not a nicety - Vision deadlocks when its text recognizer is
/// driven from too many Swift-concurrency threads at once (RV.52,
/// docs/TESTING.md), and a blocking gate alone does not help. The gate is the
/// single choke point every OCR request in the process passes through, so a
/// caller (test or app) cannot hit the ceiling by accident; there is nothing to
/// opt into.
public enum VisionTextRecognizer {

    private static let gate = VisionRequestGate(limit: VisionOCRConcurrency.limit)

    public static func recognizeText(in url: URL, languages: [String]) throws -> [OCRLine] {
        try gate.withSlot {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = languages

            let handler = VNImageRequestHandler(url: url)
            try handler.perform([request])

            let observations = request.results ?? []
            let lines: [OCRLine] = observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return OCRLine(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    boundingBox: observation.boundingBox
                )
            }
            // Vision's boundingBox origin is bottom-left; higher y = higher on the
            // page, so descending midY reads top-to-bottom.
            return lines.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        }
    }

    /// OCR from an in-memory image (the document camera returns `UIImage`s, not
    /// files - P3.1b multi-page invoices). Same request configuration as the
    /// URL entry point, so a scanned page and a saved page OCR identically.
    /// Defaults to `.up` - the orientation of a `CGImage` decoded from a file,
    /// where EXIF has already been applied.
    public static func recognizeText(image: CGImage, languages: [String]) throws -> [OCRLine] {
        try recognizeText(image: image, orientation: .up, languages: languages)
    }

    /// OCR from an in-memory image with an explicit orientation. A `CGImage`
    /// carries no orientation of its own (unlike a file, whose EXIF the URL
    /// entry point honours), so a caller that holds a buffer straight off the
    /// camera sensor - or any pixels that are not already `.up` - MUST pass the
    /// orientation here, or Vision will read the text sideways (RV.49). The
    /// `UIImage` that wraps the buffer knows its `imageOrientation`; map it to
    /// `CGImagePropertyOrientation` and pass it through, never drop it.
    public static func recognizeText(
        image: CGImage,
        orientation: CGImagePropertyOrientation,
        languages: [String]
    ) throws -> [OCRLine] {
        try gate.withSlot {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = languages

            let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            let lines: [OCRLine] = observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return OCRLine(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    boundingBox: observation.boundingBox
                )
            }
            return lines.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        }
    }
}
#endif
