import CoreGraphics
import Foundation
@testable import TankbookCore  // the trace and the reader's stages are package-internal

// `--trace-serve`: the annotator's pipeline view. One JSON request per stdin
// line - {"image", "classifier", "detector", "deskew", "currency", "budget",
// "outDir"} - runs the APP's entry point, `PumpDisplayCapture.classify`, with a
// `PumpTrace` observing it, and replies with every stage: the orientation
// scores, each attempt's decision, candidates, verdicts, verified rows, roles,
// reads and law. Strips are written as PNGs into `outDir` and named in the
// reply. Every quad is normalised over the photo as it was taken. Models are
// loaded once per path and kept. `budget` is the slow path's cap in seconds;
// absent or <= 0 means the app's `slowPathBudget`, as the phone runs it.

private struct TraceRequest: Decodable {
    var image: String?
    var classifier: String?
    var detector: String?
    /// A row reader's path, or `none` for the slicer and cell classifier.
    var rowReader: String?
    var deskew: String?
    var currency: String?
    var budget: Double?
    var outDir: String?
}

/// Models loaded once per path for the life of the process.
private final class ModelCache {
    var classifiers: [String: PumpSegmentsModel] = [:]
    var detectors: [String: PumpRowDetector] = [:]
    var rowReaders: [String: PumpRowReader] = [:]

    func classifier(_ path: String) -> PumpSegmentsModel? {
        if classifiers[path] == nil {
            classifiers[path] = try? PumpSegmentsModel(contentsOf: URL(fileURLWithPath: path))
        }
        return classifiers[path]
    }

    func detector(_ path: String?) -> PumpRowDetector? {
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        if detectors[path] == nil {
            detectors[path] = try? PumpRowDetector.load(contentsOf: URL(fileURLWithPath: path))
        }
        return detectors[path]
    }

    func rowReader(_ path: String?) -> PumpRowReader? {
        guard let path, path != "none", FileManager.default.fileExists(atPath: path) else { return nil }
        if rowReaders[path] == nil {
            rowReaders[path] = try? PumpRowReader(contentsOf: URL(fileURLWithPath: path))
        }
        return rowReaders[path]
    }
}

func runTraceServe(defaultClassifier: String, defaultDetector: String?, defaultRowReader: String?) -> Never {
    let cache = ModelCache()
    setvbuf(stdout, nil, _IOLBF, 0)
    while let line = readLine(strippingNewline: true) {
        let started = Date()
        var reply = traceReply(line: line, cache: cache, defaultClassifier: defaultClassifier,
                               defaultDetector: defaultDetector, defaultRowReader: defaultRowReader)
        reply["ms"] = Int(Date().timeIntervalSince(started) * 1000)
        if let data = try? JSONSerialization.data(withJSONObject: reply),
           let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }
    exit(0)
}

private func traceReply(line: String, cache: ModelCache, defaultClassifier: String,
                        defaultDetector: String?, defaultRowReader: String?) -> [String: Any] {
    guard let data = line.data(using: .utf8), let request = try? JSONDecoder().decode(TraceRequest.self, from: data),
          let path = request.image, let outDir = request.outDir else { return ["error": "bad request"] }
    guard let image = PumpQuadWarp.loadOrientedImage(from: URL(fileURLWithPath: path)) else {
        return ["error": "cannot load image"]
    }
    guard let model = cache.classifier(request.classifier ?? defaultClassifier) else {
        return ["error": "cannot load classifier"]
    }
    let deskew = request.deskew.flatMap(PumpReader.DeskewMode.init(rawValue:)) ?? .off
    let reader = PumpReader(model: model, detector: cache.detector(request.detector ?? defaultDetector), deskew: deskew,
                            rowReader: cache.rowReader(request.rowReader ?? defaultRowReader))
    let currency = request.currency.flatMap { CurrencyCode(rawValue: $0) }
    let band = currency.flatMap { code in (try? FuelPriceBandStore.bundledPack())?.currencyBand(currency: code) }
    let budget = (request.budget ?? 0) > 0 ? request.budget! : PumpDisplayCapture.slowPathBudget
    let trace = PumpTrace()
    let result = PumpDisplayCapture.classify(image: image, reader: PumpReaderHandle(reader: reader),
                                             currency: currency, priceBand: band, budget: budget,
                                             rotationCW: 0, trace: trace)
    let folder = URL(fileURLWithPath: outDir)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let reply = PumpTraceJSON.reply(trace: trace, result: result, photoWidth: image.width, photoHeight: image.height,
                                    budget: budget, currency: currency, extra: ["deskew": deskew.rawValue]) { strip, name in
        writeStrip(strip, named: name, in: folder)
    }
    return reply
}

private func writeStrip(_ rgb: PumpRGBImage?, named name: String, in folder: URL) -> Any {
    guard let rgb, let image = PumpQuadWarp.makeImage(rgb.pixels, width: rgb.width, height: rgb.height),
          PumpQuadWarp.writePNG(image: image, to: folder.appendingPathComponent(name)) else { return NSNull() }
    return ["file": name, "w": rgb.width, "h": rgb.height]
}
