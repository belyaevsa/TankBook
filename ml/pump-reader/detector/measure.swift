// Scores the digit-row detector on the heldout stills BEFORE it is wired in.
// The gate primaries are printed first - median IoU and recall @ IoU >= 0.7,
// with false rows per photo beside them - because the read stage consumes the
// box's framing, not loose overlap; recall @ IoU >= 0.5 is reported but never
// decides (docs/EXTRACTION.md, decision 10). Photos with any/every row and the
// per-still found/matched counts follow.
//
//   swift ml/pump-reader/detector/measure.swift <model.mlmodel|.mlmodelc> <det-dir>/heldout [confidence]
import CoreML
import Foundation
import Vision

struct Box { let x0: Double, y0: Double, x1: Double, y1: Double; let confidence: Double }
func iou(_ a: Box, _ b: Box) -> Double {
    let ix = max(0, min(a.x1, b.x1) - max(a.x0, b.x0)), iy = max(0, min(a.y1, b.y1) - max(a.y0, b.y0))
    let inter = ix * iy
    let union = (a.x1 - a.x0) * (a.y1 - a.y0) + (b.x1 - b.x0) * (b.y1 - b.y0) - inter
    return union > 0 ? inter / union : 0
}

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: measure.swift <model> <heldout-dir> [confidence]"); exit(2) }
var modelURL = URL(fileURLWithPath: args[1])
if modelURL.pathExtension == "mlmodel" { modelURL = try MLModel.compileModel(at: modelURL) }
let model = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
let dir = URL(fileURLWithPath: args[2])
let threshold = args.count > 3 ? Double(args[3]) ?? 0.3 : 0.3
let records = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("annotations.json"))) as? [[String: Any]] ?? []

var rowsTotal = 0, hit50 = 0, hit70 = 0, falseRows = 0, photosAllRows = 0, photosAnyRow = 0
var ious: [Double] = []
var perPhoto: [String] = []
for record in records {
    let name = record["image"] as? String ?? ""
    guard let source = CGImageSourceCreateWithURL(dir.appendingPathComponent(name) as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
    let w = Double(cg.width), h = Double(cg.height)
    let truth: [Box] = (record["annotations"] as? [[String: Any]] ?? []).compactMap { a in
        guard let c = a["coordinates"] as? [String: Double] else { return nil }
        return Box(x0: c["x"]! - c["width"]! / 2, y0: c["y"]! - c["height"]! / 2, x1: c["x"]! + c["width"]! / 2, y1: c["y"]! + c["height"]! / 2, confidence: 1)
    }
    let request = VNCoreMLRequest(model: model)
    request.imageCropAndScaleOption = .scaleFit
    try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
    let found: [Box] = (request.results as? [VNRecognizedObjectObservation] ?? []).compactMap { o in
        guard o.confidence >= Float(threshold) else { return nil }
        let b = o.boundingBox  // normalised, bottom-left origin
        return Box(x0: b.minX * w, y0: (1 - b.maxY) * h, x1: b.maxX * w, y1: (1 - b.minY) * h, confidence: Double(o.confidence))
    }
    var matched = Set<Int>()
    var photoHits = 0
    for t in truth {
        rowsTotal += 1
        var best = 0.0, bestIndex = -1
        for (i, f) in found.enumerated() where !matched.contains(i) {
            let v = iou(t, f)
            if v > best { best = v; bestIndex = i }
        }
        ious.append(best)
        if best >= 0.5 { hit50 += 1; matched.insert(bestIndex); photoHits += 1 }
        if best >= 0.7 { hit70 += 1 }
    }
    falseRows += found.count - matched.count
    if photoHits > 0 { photosAnyRow += 1 }
    if photoHits == truth.count { photosAllRows += 1 }
    perPhoto.append("\(name.prefix(30)): truth \(truth.count), found \(found.count), matched \(photoHits)")
}
let sorted = ious.sorted()
let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
let recall50 = Double(hit50) / Double(max(rowsTotal, 1))
let recall70 = Double(hit70) / Double(max(rowsTotal, 1))
let falseRowsPerPhoto = Double(falseRows) / Double(max(records.count, 1))
print("DET heldout: median IoU \(String(format: "%.3f", median)) | "
      + "recall@0.7 \(hit70)/\(rowsTotal) = \(String(format: "%.3f", recall70)) | "
      + "false rows/photo \(String(format: "%.3f", falseRowsPerPhoto)) (\(falseRows) over \(records.count) photos) | "
      + "recall@0.5 \(hit50)/\(rowsTotal) = \(String(format: "%.3f", recall50)) (secondary, never decides) | "
      + "rows \(rowsTotal), photos any row \(photosAnyRow), photos all rows \(photosAllRows), confidence >= \(threshold)")
for line in perPhoto { print("  " + line) }
