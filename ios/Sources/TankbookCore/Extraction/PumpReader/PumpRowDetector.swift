import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import Vision

/// The learned digit-row locator: the rows it sees in a frame, each a quad with
/// a confidence. Two backends answer the same contract - the oriented segmenter
/// the app bundles (`PumpRowSegmenter`, quads that follow a turned display) and
/// the Create ML object detector (upright boxes), which the tools can load.
/// It is the locator's first source; the Vision text boxes and the classical
/// projection remain the fallback for a frame it finds fewer than two rows in
/// (docs/EXTRACTION.md -> "The pump reader").
public final class PumpRowDetector: @unchecked Sendable {
    public struct Row: Sendable, Equatable {
        /// TL, TR, BR, BL, normalised [0, 1] over the image, top-left origin.
        public let quad: [CGPoint]
        public let confidence: Double

        public init(quad: [CGPoint], confidence: Double) {
            self.quad = quad
            self.confidence = confidence
        }

        /// The row's axis-aligned bounds in the same normalised space as `quad`.
        /// The size and stacking rules read this; the preview overlay maps it.
        public var bounds: CGRect { PumpRowAssignment.bounds(quad, rotationCW: 0) }
    }

    private enum Backend {
        case vision(VNCoreMLModel)
        case segmenter(PumpRowSegmenter)
    }

    private let backend: Backend
    /// The confidence a detected row needs on its own. Measured on the heldout
    /// stills (ml/pump-reader/detector/measure.swift): 0.3 keeps 86 % of the
    /// annotated rows at 0.7 false rows per photo, 0.5 keeps 81 % at 0.3.
    public static let minimumConfidence: Double = 0.3
    /// Rows down to this are returned so the reader can rescue one stacked under
    /// a passing row (a transaction row the detector saw but was not sure of);
    /// a row below `minimumConfidence` is a candidate only through that rescue
    /// (`PumpReader.rescueStackedRows`), never on its own.
    public static let rescueConfidence: Double = 0.15

    public init(contentsOf url: URL) throws {
        var modelURL = url
        if url.pathExtension == "mlmodel" {
            modelURL = try MLModel.compileModel(at: url)
        }
        backend = .vision(try VNCoreMLModel(for: MLModel(contentsOf: modelURL)))
    }

    /// A row locator from a model file, source or compiled: a model whose
    /// output is the `maps` tensor is the segmenter (`PumpRowSegmenter`),
    /// anything else the object detector.
    public static func load(contentsOf url: URL) throws -> PumpRowDetector {
        let compiled = url.pathExtension == "mlmodelc" ? url : try MLModel.compileModel(at: url)
        let model = try MLModel(contentsOf: compiled)
        if model.modelDescription.outputDescriptionsByName["maps"] != nil {
            return PumpRowDetector(segmenter: try PumpRowSegmenter(contentsOf: compiled))
        }
        return try PumpRowDetector(contentsOf: compiled)
    }

    init(segmenter: PumpRowSegmenter) {
        backend = .segmenter(segmenter)
    }


    public func detect(in image: CGImage) -> [Row] {
        switch backend {
        case .segmenter(let segmenter): return segmenter.rows(in: image).sorted { $0.confidence > $1.confidence }
        case .vision: break
        }
        return detect(handler: VNImageRequestHandler(cgImage: image, options: [:]))
    }

    /// The live preview's entry point: the same locator over a video frame's
    /// pixel buffer - handed to Vision as is for the object detector, decoded
    /// to an image for the segmenter. The caller is responsible for the
    /// buffer's orientation (`CameraController` rotates the video connection
    /// upright before the delegate sees it).
    public func detect(in pixelBuffer: CVPixelBuffer) -> [Row] {
        if case .segmenter(let segmenter) = backend {
            return segmenter.rows(in: pixelBuffer).sorted { $0.confidence > $1.confidence }
        }
        return detect(handler: VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]))
    }

    private func detect(handler: VNImageRequestHandler) -> [Row] {
        guard case .vision(let model) = backend else { return [] }
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFit
        guard (try? handler.perform([request])) != nil else { return [] }
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
