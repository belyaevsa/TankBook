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
/// which runs it on a background dispatch thread, bounds how many are in flight
/// at once, and suspends - never blocks - the caller. That is not a nicety:
/// Vision deadlocks when the cooperative thread pool is exhausted around a
/// request (docs/TESTING.md -> "Vision OCR concurrency ceiling"), which is why
/// the API is `async` and has no synchronous form. The gate is the single choke
/// point every OCR request in the process passes through, so a caller (test or
/// app) cannot hit the ceiling by accident; there is nothing to opt into.
public enum VisionTextRecognizer {

    private static let gate = VisionRequestGate(limit: VisionOCRConcurrency.limit)

    /// OCR from a file. EXIF orientation is honoured by Vision itself.
    public static func recognizeText(in url: URL, languages: [String]) async throws -> [OCRLine] {
        try await gate.withSlot {
            try perform(VNImageRequestHandler(url: url), languages: languages)
        }
    }

    /// OCR from an in-memory image (the document camera returns `UIImage`s, not
    /// files). Same request configuration as the URL entry point, so a scanned
    /// page and a saved page OCR identically. Defaults to `.up` - the
    /// orientation of a `CGImage` decoded from a file, where EXIF has already
    /// been applied.
    public static func recognizeText(image: CGImage, languages: [String]) async throws -> [OCRLine] {
        try await recognizeText(image: image, orientation: .up, languages: languages)
    }

    /// OCR from an in-memory image with an explicit orientation. A `CGImage`
    /// carries no orientation of its own (unlike a file, whose EXIF the URL
    /// entry point honours), so a caller that holds a buffer straight off the
    /// camera sensor - or any pixels that are not already `.up` - MUST pass the
    /// orientation here, or Vision will read the text sideways. The `UIImage`
    /// that wraps the buffer knows its `imageOrientation`; map it to
    /// `CGImagePropertyOrientation` and pass it through, never drop it.
    public static func recognizeText(
        image: CGImage,
        orientation: CGImagePropertyOrientation,
        languages: [String]
    ) async throws -> [OCRLine] {
        let box = CGImageBox(image)
        return try await gate.withSlot {
            try perform(VNImageRequestHandler(cgImage: box.image, orientation: orientation, options: [:]),
                        languages: languages)
        }
    }

    /// Runs inside the gate's slot, on a dispatch thread.
    private static func perform(_ handler: VNImageRequestHandler, languages: [String]) throws -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = languages
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

    /// `CGImage` is immutable but not `Sendable`; the box carries it into the
    /// gate's `@Sendable` body.
    private struct CGImageBox: @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }
}
#endif
