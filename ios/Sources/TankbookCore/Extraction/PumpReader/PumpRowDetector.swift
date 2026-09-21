import CoreGraphics
import CoreML
import Foundation
import Vision

/// The learned digit-row detector (PU.33): one Core ML object detector trained
/// on the corpus's annotated windows and their tracked frames, returning the
/// rows it sees in a frame with a confidence. It is the locator's first source;
/// the Vision text boxes and the classical projection remain the fallback for
/// a frame it finds fewer than two rows in (docs/EXTRACTION.md -> "The pump
/// reader").
final class PumpRowDetector: @unchecked Sendable {
    struct Row: Sendable, Equatable {
        /// TL, TR, BR, BL, normalised [0, 1] over the image, top-left origin.
        let quad: [CGPoint]
        let confidence: Double
    }

    private let model: VNCoreMLModel
    /// The confidence a detected row needs on its own. Measured on the heldout
    /// stills (ml/pump-reader/detector/measure.swift): 0.3 keeps 86 % of the
    /// annotated rows at 0.7 false rows per photo, 0.5 keeps 81 % at 0.3.
    static let minimumConfidence: Double = 0.3
    /// Rows down to this are returned so the reader can rescue one stacked under
    /// a passing row (a transaction row the detector saw but was not sure of);
    /// a row below `minimumConfidence` is a candidate only through that rescue
    /// (`PumpReader.rescueStackedRows`), never on its own.
    static let rescueConfidence: Double = 0.15

    init(contentsOf url: URL) throws {
        var modelURL = url
        if url.pathExtension == "mlmodel" {
            modelURL = try MLModel.compileModel(at: url)
        }
        model = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
    }

    func detect(in image: CGImage) -> [Row] {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFit
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil else { return [] }
        let observations = request.results as? [VNRecognizedObjectObservation] ?? []
        return observations.compactMap { observation in
            guard Double(observation.confidence) >= Self.rescueConfidence else { return nil }
            let b = observation.boundingBox  // Vision: bottom-left origin
            let top = 1 - b.maxY, bottom = 1 - b.minY
            return Row(quad: [CGPoint(x: b.minX, y: top), CGPoint(x: b.maxX, y: top),
                              CGPoint(x: b.maxX, y: bottom), CGPoint(x: b.minX, y: bottom)],
                       confidence: Double(observation.confidence))
        }.sorted { $0.confidence > $1.confidence }
    }
}
