import Foundation

#if canImport(Vision)
import Vision

/// The Vision OCR entry point, kept out of the pure extraction core so the core
/// stays testable from plain `[OCRLine]` with no image and no Vision import.
/// `usesLanguageCorrection = false` is deliberate: receipts are full of codes
/// and correction hurts (docs/VISION.md).
public enum VisionTextRecognizer {
    public static func recognizeText(in url: URL, languages: [String]) throws -> [OCRLine] {
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

    /// OCR from an in-memory image (the document camera returns `UIImage`s, not
    /// files - P3.1b multi-page invoices). Same request configuration as the
    /// URL entry point, so a scanned page and a saved page OCR identically.
    public static func recognizeText(image: CGImage, languages: [String]) throws -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = languages

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
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
#endif
