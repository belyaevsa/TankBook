// Trains the digit-row detector with Create ML on the set `pump_reader.detdata`
// builds, and exports it as a Core ML model.
//
//   swift ml/pump-reader/detector/train.swift <det-dir> <out.mlmodel> [iterations]
//
// Create ML's object detector is a YOLOv2-class network with transfer learning
// from Apple's feature extractor; ~700 images with ~2 500 boxes is a small set
// for it, which is why the frames and negatives are in the set at all.
import CreateML
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: train.swift <det-dir> <out.mlmodel> [iterations]"); exit(2) }
let det = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2])
let iterations = args.count > 3 ? Int(args[3]) ?? 3000 : 3000

let train = try MLObjectDetector.DataSource.directoryWithImagesAndJsonAnnotation(at: det.appendingPathComponent("train"))
var params = MLObjectDetector.ModelParameters()
params.maxIterations = iterations
params.batchSize = 16
params.validation = .split(strategy: .automatic)
let start = Date()
let detector = try MLObjectDetector(trainingData: train, parameters: params, annotationType: .boundingBox(units: .pixel, origin: .topLeft, anchor: .center))
print(String(format: "trained in %.0f s", Date().timeIntervalSince(start)))
print("training metrics:", detector.trainingMetrics)
print("validation metrics:", detector.validationMetrics)
try detector.write(to: out, metadata: MLModelMetadata(author: "tankbook", shortDescription: "pump display digit-row detector (PU.33)", version: "1"))
print("wrote \(out.path)")
