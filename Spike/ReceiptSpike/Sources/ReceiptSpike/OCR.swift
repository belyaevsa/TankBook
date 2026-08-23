import Foundation
import Vision

/// One recognized text line with its position (normalized, origin bottom-left).
struct OCRLine: Sendable {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}

enum OCRError: Error, CustomStringConvertible {
    case unreadableImage(URL)

    var description: String {
        switch self {
        case .unreadableImage(let url): return "Cannot read image: \(url.path)"
        }
    }
}

/// Runs Vision text recognition on an image file and returns lines sorted top-to-bottom.
func recognizeText(in url: URL, languages: [String]) throws -> [OCRLine] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false // receipts are full of codes/numbers; correction hurts
    request.recognitionLanguages = languages

    let handler = VNImageRequestHandler(url: url)
    try handler.perform([request])

    let observations = request.results ?? []
    let lines: [OCRLine] = observations.compactMap { obs in
        guard let candidate = obs.topCandidates(1).first else { return nil }
        return OCRLine(text: candidate.string, confidence: candidate.confidence, boundingBox: obs.boundingBox)
    }
    // Vision's boundingBox origin is bottom-left; higher y = higher on the page.
    return lines.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
}
