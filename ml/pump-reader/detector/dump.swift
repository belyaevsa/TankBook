// Dumps the digit-row detector's boxes on a folder of images as JSON, for scoring
// outside Swift (the PU.76 rotated-IoU gate scores the shipped detector and a
// candidate in one metric). Every observation at or above the rescue confidence
// is kept with its confidence; the scorer applies the thresholds.
//
//   swift ml/pump-reader/detector/dump.swift <model.mlmodel|.mlmodelc> <dir-with-index.json> <out.json>
import CoreML
import Foundation
import Vision

let args = CommandLine.arguments
guard args.count >= 4 else { print("usage: dump.swift <model> <dir> <out.json>"); exit(2) }
var modelURL = URL(fileURLWithPath: args[1])
if modelURL.pathExtension == "mlmodel" { modelURL = try MLModel.compileModel(at: modelURL) }
let model = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
let dir = URL(fileURLWithPath: args[2])
let records = try JSONSerialization.jsonObject(
    with: Data(contentsOf: dir.appendingPathComponent("index.json"))) as? [[String: Any]] ?? []
var out: [String: [[String: Double]]] = [:]
for record in records {
    let name = record["image"] as? String ?? ""
    guard let source = CGImageSourceCreateWithURL(dir.appendingPathComponent(name) as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
    let request = VNCoreMLRequest(model: model)
    request.imageCropAndScaleOption = .scaleFit
    try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
    out[name] = (request.results as? [VNRecognizedObjectObservation] ?? []).compactMap { o in
        guard o.confidence >= 0.15 else { return nil }
        let b = o.boundingBox  // normalised, bottom-left origin
        return ["x0": b.minX, "y0": 1 - b.maxY, "x1": b.maxX, "y1": 1 - b.minY, "confidence": Double(o.confidence)]
    }
}
try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]).write(to: URL(fileURLWithPath: args[3]))
print("dumped \(out.count) images")
