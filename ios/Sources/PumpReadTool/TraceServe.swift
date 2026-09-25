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
    var reply: [String: Any] = ["photo": ["w": image.width, "h": image.height], "budget": budget,
                                "deskew": deskew.rawValue, "currency": currency?.rawValue ?? NSNull(),
                                "chosen": trace.chosen ?? NSNull()]
    reply["orientationScores"] = trace.orientationScores.map {
        ["rotationCW": $0.rotationCW, "keptRows": $0.keptRows, "inkBandArea": $0.inkBandArea]
    }
    reply["attempts"] = trace.attempts.enumerated().map { index, attempt in
        attemptJSON(attempt, index: index, folder: folder)
    }
    reply["final"] = ["detection": detectionJSON(result.detection), "routedAsPump": result.reading != nil,
                      "law": result.reading.map { lawJSON($0.law) } ?? NSNull()]
    return reply
}

private func attemptJSON(_ attempt: PumpTrace.Attempt, index: Int, folder: URL) -> [String: Any] {
    func quad(_ points: [CGPoint], normalised: Bool) -> [[Double]] {
        quadJSON(points, normalised: normalised, attempt)
    }
    var out: [String: Any] = ["kind": attempt.kind, "rotationCW": attempt.rotationCW,
                              "w": attempt.width, "h": attempt.height,
                              "textLines": attempt.textLines ?? NSNull(),
                              "fastVerdict": attempt.fastVerdict ?? NSNull(), "budgetHit": attempt.budgetHit,
                              "detection": attempt.detection.map(detectionJSON) ?? NSNull(),
                              "law": attempt.law.map(lawJSON) ?? NSNull()]
    out["detectedRows"] = attempt.detectedRows.map { row -> [String: Any] in
        ["quad": quad(row.quad, normalised: true), "confidence": row.confidence,
         "passesSize": PumpDisplayCapture.passesSize(row)]
    }
    out["candidates"] = attempt.candidates.map { ["quad": quad($0.quad, normalised: true), "detected": $0.detected] }
    out["verdicts"] = attempt.verdicts.enumerated().map { number, record -> [String: Any] in
        let verdict = record.verdict
        return ["quad": quad(verdict.quad, normalised: false), "kept": verdict.kept, "detected": verdict.detected,
                "reasons": verdict.dropReasons, "cells": verdict.cells, "heightFraction": verdict.heightFraction,
                "meanMargin": verdict.meanMargin, "cellRects": cellsJSON(record.cells),
                "strip": writeStrip(record.strip, named: "a\(index)-v\(number).png", in: folder)]
    }
    out["verified"] = attempt.verified.enumerated().map { number, window -> [String: Any] in
        let role = number < attempt.roles.count ? attempt.roles[number]?.rawValue : nil
        return ["quad": quad(window.quad, normalised: false), "cells": window.glyphCount, "detected": window.detected,
                "meanMargin": window.meanMargin, "role": role ?? NSNull()]
    }
    out["reads"] = attempt.reads.enumerated().map { number, record -> [String: Any] in
        ["field": record.field.rawValue, "quad": quad(record.quad, normalised: false),
         "skipped": record.skipped ?? NSNull(), "cellRects": cellsJSON(record.cells),
         // A row read has digits and no slicer cells: the strip was read whole.
         "reader": record.cells.isEmpty && !record.readings.isEmpty ? "row" : "cells",
         "readings": record.readings.map(readingJSON),
         "strip": writeStrip(record.strip, named: "a\(index)-r\(number).png", in: folder)]
    }
    return out
}

/// A point of the attempt's upright image, normalised over the photo as taken.
private func unturned(_ point: CGPoint, rotationCW: Int) -> [Double] {
    var turned = point
    for _ in 0..<((4 - ((rotationCW % 360) + 360) % 360 / 90) % 4) {
        turned = CGPoint(x: 1 - turned.y, y: turned.x)
    }
    return [turned.x, turned.y]
}

private func quadJSON(_ quad: [CGPoint], normalised: Bool, _ attempt: PumpTrace.Attempt) -> [[Double]] {
    quad.map { point in
        let unit = normalised ? point
            : CGPoint(x: point.x / Double(attempt.width), y: point.y / Double(attempt.height))
        return unturned(unit, rotationCW: attempt.rotationCW)
    }
}

private func writeStrip(_ rgb: PumpRGBImage?, named name: String, in folder: URL) -> Any {
    guard let rgb, let image = PumpQuadWarp.makeImage(rgb.pixels, width: rgb.width, height: rgb.height),
          PumpQuadWarp.writePNG(image: image, to: folder.appendingPathComponent(name)) else { return NSNull() }
    return ["file": name, "w": rgb.width, "h": rgb.height]
}

private func cellsJSON(_ cells: [GlyphCell]) -> [[String: Any]] {
    cells.map { ["x": $0.rect.minX, "y": $0.rect.minY, "w": $0.rect.width, "h": $0.rect.height,
                 "blank": $0.isBlank, "dp": $0.hasDecimalPoint] }
}

private func readingJSON(_ reading: PumpCellReading) -> [String: Any] {
    ["top": reading.ranked.prefix(3).map { ["d": $0.digit, "lp": $0.logPosterior] },
     "margin": reading.margin, "dp": reading.decimalPoint,
     "dpProb": reading.probabilities.count > 7 ? reading.probabilities[7] : 0]
}

private func fieldJSON(_ field: PumpFieldReading) -> [String: Any] {
    var provenance: Any = NSNull()
    switch field.provenance {
    case .read: provenance = "read"
    case .derived: provenance = "derived"
    case let .repaired(cellIndex, fromDigit, toDigit):
        provenance = ["repaired": ["cell": cellIndex, "from": fromDigit, "to": toDigit]]
    case nil: break
    }
    return ["value": field.value.map { "\($0)" } ?? NSNull(), "reason": field.reason?.rawValue ?? NSNull(),
            "provenance": provenance, "logPosterior": field.logPosterior]
}

private func lawJSON(_ law: PumpDisplayReading) -> [String: Any] {
    ["total": fieldJSON(law.total), "liters": fieldJSON(law.liters), "unitPrice": fieldJSON(law.unitPrice),
     "reason": law.reason?.rawValue ?? NSNull(), "caution": law.caution.map { "\($0)" } ?? NSNull(),
     "committed": law.committedCount]
}

private func detectionJSON(_ detection: PumpDisplayCapture.Detection) -> [String: Any] {
    ["display": detection.isPumpDisplay, "rows": detection.displayRows, "textLines": detection.textLines,
     "widestRow": detection.widestRow, "tallestRow": detection.tallestRow, "path": detection.path.rawValue]
}
