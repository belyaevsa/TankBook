// The pump reader as a command - what the annotator calls to show the model's
// reading of a frame or a still (tools/pump-annotate):
//
//   pump-read <image> [--classifier <PumpSegments.mlpackage>] [--detector <DigitRows.mlmodel or RowSeg.mlpackage>] < request.json
//   pump-read --slice-serve            # resident slicer: one request per stdin line, no model
//   pump-read --read-serve [--classifier p]  # resident video-frame reader, model loaded once
//   pump-read --trace-serve            # resident pipeline tracer: the app's classify, every stage recorded
//
// Request (stdin): {"rotationCW": 0, "currency": "EUR",
//                   "windows": [{"field": "total", "quad": [[x, y] x 4]}, ...]}
// With windows, each is warped, sliced and classified and the reply carries the
// cells (top digit, decimal mark, margin), the joined string per field and what
// the law committed. Without windows the live path runs (detector -> verify ->
// assign -> law) and the reply carries the located rows and the committed fields.
import Foundation
@testable import TankbookCore  // the reader's stages are package-internal; debug builds carry testability

struct Request: Decodable {
    // Every key optional: the synthesised decoder ignores a default value and
    // would reject a request that leaves one out.
    var rotationCW: Int?
    var currency: String?
    /// When to turn detector rows to their digits' angle: "off", "onRefusal"
    /// or "always" (PumpReader.DeskewMode).
    var deskew: String?
    /// Diagnosis: turn the whole photo by this many degrees (clockwise) before
    /// anything reads it - what levelling does, at an angle chosen by hand.
    var level: Double?
    var windows: [Window]?
    struct Window: Decodable {
        let field: String
        let quad: [[Double]]
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: pump-read <image> [--classifier p] [--detector p]\n".utf8))
    exit(2)
}
var classifierPath = "ios/App/Resources/PumpSegments.mlpackage"
var detectorPath: String? = "ios/App/Resources/DigitRows.mlmodel"
var dumpDirectory: String?
var index = 2
while index < arguments.count {
    if arguments[index] == "--dump-strips", index + 1 < arguments.count {
        dumpDirectory = arguments[index + 1]
        index += 2
        continue
    }
    if arguments[index] == "--classifier", index + 1 < arguments.count {
        classifierPath = arguments[index + 1]
        index += 2
    } else if arguments[index] == "--detector", index + 1 < arguments.count {
        detectorPath = arguments[index + 1]
        index += 2
    } else {
        index += 1
    }
}
/// The slicer's cells for one window: the strip is warped, sliced with the
/// diagnosis overrides, and each cell's rect is mapped back onto the quad
/// (normalised over the oriented image) so a caller can draw where each glyph
/// was cut and where a decimal mark was seen. No model runs here.
func slicedCells(image: PumpRGBImage, window: PumpReader.Window, dumpDirectory: String? = nil) -> (cells: [GlyphCell], quads: [[String: Any]]) {
    guard let strip = PumpQuadWarp.warpToStrip(rgb: image, quad: window.quad, stripHeight: PumpReader.stripHeight)
    else { return ([], []) }
    // PUMP_MERGE_GAP / PUMP_DP_TOP override the slicer's run-merge gap and
    // decimal-mark top-row fraction for a diagnosis; a model reading is untouched.
    var options = PumpGlyphSlicer.Options()
    let environment = ProcessInfo.processInfo.environment
    if let value = environment["PUMP_MERGE_GAP"].flatMap(Float.init) { options.mergeGapFraction = value }
    if let value = environment["PUMP_DP_TOP"].flatMap(Float.init) { options.decimalPointTopRowFraction = value }
    let cells = PumpGlyphSlicer.slice(PumpQuadWarp.rgbImage(from: strip).grayscale(), options: options)
    if let dumpDirectory {
        // The warped strip as the slicer sees it, for looking at a miss.
        _ = PumpQuadWarp.writePNG(image: strip, to: URL(fileURLWithPath: dumpDirectory)
            .appendingPathComponent("\(window.field.rawValue).png"))
    }
    let stripWidth = CGFloat(strip.width), stripHeight = CGFloat(strip.height)
    let quad = window.quad
    func at(_ fx: CGFloat, _ fy: CGFloat) -> [Double] {
        let top = CGPoint(x: quad[0].x + (quad[1].x - quad[0].x) * fx, y: quad[0].y + (quad[1].y - quad[0].y) * fx)
        let bottom = CGPoint(x: quad[3].x + (quad[2].x - quad[3].x) * fx, y: quad[3].y + (quad[2].y - quad[3].y) * fx)
        let point = CGPoint(x: top.x + (bottom.x - top.x) * fy, y: top.y + (bottom.y - top.y) * fy)
        return [point.x / Double(image.width), point.y / Double(image.height)]
    }
    let quads = cells.map { cell -> [String: Any] in
        let fx0 = cell.rect.minX / stripWidth, fx1 = cell.rect.maxX / stripWidth
        let fy0 = cell.rect.minY / stripHeight, fy1 = cell.rect.maxY / stripHeight
        return ["quad": [at(fx0, fy0), at(fx1, fy0), at(fx1, fy1), at(fx0, fy1)],
                "blank": cell.isBlank, "dp": cell.hasDecimalPoint]
    }
    return (cells, quads)
}

func locate(_ windows: [Request.Window], in image: PumpRGBImage, rotationCW: Int) -> [PumpReader.Window] {
    windows.compactMap { window -> PumpReader.Window? in
        guard let field = PumpField(rawValue: window.field) else { return nil }
        let pixels = window.quad.map { CGPoint(x: $0[0] * Double(image.width), y: $0[1] * Double(image.height)) }
        return PumpReader.Window(field: field, quad: PumpQuadWarp.readingOrder(pixels, rotationCW: rotationCW))
    }
}

// `--slice-serve`: a resident slicer for the annotator's live overlay. One JSON
// request per stdin line - {"image": path, "rotationCW": n, "windows": [...]} -
// one JSON reply per line with each window's slicer cells and their count. No
// model is loaded and the last decoded image is kept, so a reply costs the
// warp and the column profiles rather than a process launch and a 12 MP decode.
if arguments.contains("--slice-serve") {
    struct ServeRequest: Decodable {
        var image: String?
        var rotationCW: Int?
        var windows: [Request.Window]?
    }
    var cachedPath: String?
    var cachedImage: PumpRGBImage?
    setvbuf(stdout, nil, _IOLBF, 0)
    while let line = readLine(strippingNewline: true) {
        let started = Date()
        var reply: [String: Any] = [:]
        if let data = line.data(using: .utf8), let request = try? JSONDecoder().decode(ServeRequest.self, from: data),
           let path = request.image {
            if path != cachedPath {
                cachedImage = PumpQuadWarp.loadOrientedImage(from: URL(fileURLWithPath: path)).map(PumpQuadWarp.rgbImage(from:))
                cachedPath = path
            }
            if let image = cachedImage {
                let located = locate(request.windows ?? [], in: image, rotationCW: request.rotationCW ?? 0)
                reply["windows"] = located.map { window -> [String: Any] in
                    let sliced = slicedCells(image: image, window: window)
                    return ["field": window.field.rawValue, "sliced": sliced.quads,
                            "cells": sliced.cells.count,
                            "dpCell": sliced.cells.firstIndex(where: { $0.hasDecimalPoint }) ?? NSNull()]
                }
            } else {
                reply["error"] = "cannot load image"
            }
        } else {
            reply["error"] = "bad request"
        }
        reply["ms"] = Int(Date().timeIntervalSince(started) * 1000)
        if let out = try? JSONSerialization.data(withJSONObject: reply), let text = String(data: out, encoding: .utf8) {
            print(text)
        }
    }
    exit(0)
}

// `--read-serve`: a resident video-frame reader for the annotator's re-read
// after a retrack. One JSON request per stdin line - {"image": path,
// "priceText": "2.250", "windows": [...]} with quads normalised over the
// oriented frame - one JSON reply per line with the frame's reading and, when
// total == liters x price closes, its arithmetic label. It reads through
// PumpVideoFrameRead, the same code PumpVideoReadTests labels with, so the
// model is loaded once instead of per `swift test` launch.
if arguments.contains("--read-serve") {
    struct ReadRequest: Decodable {
        var image: String?
        var priceText: String?
        var windows: [Request.Window]?
    }
    let reader = PumpReader(model: try PumpSegmentsModel(contentsOf: URL(fileURLWithPath: classifierPath)))
    setvbuf(stdout, nil, _IOLBF, 0)
    while let line = readLine(strippingNewline: true) {
        let started = Date()
        var reply: [String: Any] = [:]
        if let data = line.data(using: .utf8), let request = try? JSONDecoder().decode(ReadRequest.self, from: data),
           let path = request.image, let priceText = request.priceText {
            if let image = PumpQuadWarp.loadOrientedImage(from: URL(fileURLWithPath: path)).map(PumpQuadWarp.rgbImage(from:)) {
                let windows = (request.windows ?? []).map { PumpVideoFrameRead.Window(field: $0.field, quad: $0.quad) }
                if let read = PumpVideoFrameRead.read(reader: reader, image: image, windows: windows, priceText: priceText) {
                    reply["reading"] = read.reading
                    reply["label"] = read.label(priceText: priceText) ?? NSNull()
                } else {
                    reply["reading"] = NSNull()
                }
            } else {
                reply["error"] = "cannot load image"
            }
        } else {
            reply["error"] = "bad request"
        }
        reply["ms"] = Int(Date().timeIntervalSince(started) * 1000)
        if let out = try? JSONSerialization.data(withJSONObject: reply), let text = String(data: out, encoding: .utf8) {
            print(text)
        }
    }
    exit(0)
}

// `--trace-serve`: the annotator's pipeline view (TraceServe.swift).
if arguments.contains("--trace-serve") {
    runTraceServe(defaultClassifier: classifierPath, defaultDetector: detectorPath)
}

// `--request <file>` reads the request from a file: a profiler launch has no stdin.
let requestPath = arguments.firstIndex(of: "--request").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
let stdin = requestPath.flatMap { FileManager.default.contents(atPath: $0) } ?? FileHandle.standardInput.readDataToEndOfFile()
let request = (try? JSONDecoder().decode(Request.self, from: stdin)) ?? Request()
guard let oriented = PumpQuadWarp.loadOrientedImage(from: URL(fileURLWithPath: arguments[1])) else {
    print("{\"error\": \"cannot load image\"}")
    exit(1)
}
let model = try PumpSegmentsModel(contentsOf: URL(fileURLWithPath: classifierPath))
let detector = detectorPath.flatMap { path in
    FileManager.default.fileExists(atPath: path) ? try? PumpRowDetector.load(contentsOf: URL(fileURLWithPath: path)) : nil
}
let reader = PumpReader(model: model, detector: detector,
                        deskew: request.deskew.flatMap(PumpReader.DeskewMode.init(rawValue:)) ?? .off)
let photo = PumpQuadWarp.rgbImage(from: oriented)
let image = request.level.map { PumpRowDeskew.levelled(photo, degrees: $0) } ?? photo
let currency = request.currency.flatMap { CurrencyCode(rawValue: $0) }
// The app's own guard (decision 11): the currency-wide band bounds the price a
// total + volume pair implies. The tool reads the same bundled pack the app
// does, so its diagnostic verdict matches the app's.
let priceBand = currency.flatMap { code in
    (try? FuelPriceBandStore.bundledPack())?.currencyBand(currency: code)
}
var reply: [String: Any] = [:]

func committed(_ reading: PumpDisplayReading) -> [String: Any] {
    func value(_ field: PumpFieldReading) -> Any { field.value.map { "\($0)" } ?? NSNull() }
    // The per-field reasons ride with the per-field values so the annotator can
    // mark the field that refused, not only the reading (PU.51).
    func reason(_ field: PumpFieldReading) -> Any { field.reason?.rawValue ?? NSNull() }
    return ["total": value(reading.total), "liters": value(reading.liters),
            "unitPrice": value(reading.unitPrice),
            "reasons": ["total": reason(reading.total), "liters": reason(reading.liters),
                        "unitPrice": reason(reading.unitPrice)]]
}

if let windows = request.windows, !windows.isEmpty {
    // Annotated quads are read on the oriented image in reading order, as the harness does.
    let located = locate(windows, in: image, rotationCW: request.rotationCW ?? 0)
    let reads = try reader.read(image: image, windows: located)
    var cellQuads: [String: [[String: Any]]] = [:]
    for window in located {
        cellQuads[window.field.rawValue] = slicedCells(image: image, window: window, dumpDirectory: dumpDirectory).quads
    }
    reply["windows"] = reads.map { read -> [String: Any] in
        let cells = read.cells.map { cell -> [String: Any] in
            let top = cell.ranked.first
            let second = cell.ranked.dropFirst().first
            return ["digit": top.map { String($0.digit) } ?? "?", "dp": cell.decimalPoint,
                    "margin": (top?.logPosterior ?? 0) - (second?.logPosterior ?? 0)]
        }
        let text = read.cells.map { cell in
            (cell.ranked.first.map { String($0.digit) } ?? "?") + (cell.decimalPoint ? "." : "")
        }.joined()
        return ["field": read.field.rawValue, "cells": cells, "text": text, "sliced": cellQuads[read.field.rawValue] ?? []]
    }
    let law = PumpReadingLaw.resolve(windows: reads.map { PumpLocatedWindow(field: $0.field, cells: $0.cells) },
                                     currency: currency, priceBand: priceBand)
    reply["committed"] = committed(law)
    reply["abstainReason"] = law.reason?.rawValue ?? NSNull()
} else {
    // Stage timings ride along so the annotator (and a latency question) can
    // see where the live path spends its time.
    var timings: [String: Int] = [:]
    func timed<T>(_ key: String, _ body: () throws -> T) rethrows -> T {
        let started = Date()
        defer { timings[key] = Int(Date().timeIntervalSince(started) * 1000) }
        return try body()
    }
    // PUMP_REPEAT=N runs the whole live read N extra times first, so a
    // profiler sees the steady state rather than the model's first load.
    if let repeats = ProcessInfo.processInfo.environment["PUMP_REPEAT"].flatMap(Int.init) {
        for _ in 0..<repeats {
            _ = try reader.readPhoto(image: image, rotationCW: request.rotationCW,
                                     currency: currency, priceBand: priceBand)
        }
    }
    // No rotation in the request means the reader searches for the display's
    // orientation, as the app does (it has no annotation to ask); a given one
    // is used as it is.
    let detailed = try timed("readPhoto") {
        try reader.readPhotoDetailed(image: image, rotationCW: request.rotationCW,
                                     currency: currency, priceBand: priceBand)
    }
    let reading = detailed.reading, readDeskewed = detailed.deskewed, readRotation = detailed.rotationCW
    reply["rotationCW"] = readRotation
    reply["levelDegrees"] = detailed.levelDegrees
    // The rows shown are the ones the reading came from: turned when the
    // reader turned them (always, or on a refusal it recovered from).
    reply["deskewed"] = readDeskewed
    reply["committed"] = committed(reading)
    reply["abstainReason"] = reading.reason?.rawValue ?? NSNull()
    // The diagnostics below run on the image the reading came from: turned to
    // its orientation and, when the reader levelled it, levelled too.
    let oriented = PumpPanelLocator.rotatedRGB(image, rotationCW: readRotation)
    let upright = detailed.levelDegrees == 0 ? oriented
        : PumpRowDeskew.levelled(oriented, degrees: detailed.levelDegrees)
    // A point normalised over that image, back in the photo's own frame: the
    // annotator draws on the photo as it was taken.
    func unturned(_ p: CGPoint) -> [Double] {
        let back = PumpRowDeskew.unlevelled(CGPoint(x: p.x * Double(upright.width), y: p.y * Double(upright.height)),
                                            degrees: detailed.levelDegrees, width: upright.width, height: upright.height)
        var point = CGPoint(x: back.x / Double(upright.width), y: back.y / Double(upright.height))
        for _ in 0..<((4 - ((readRotation % 360) + 360) % 360 / 90) % 4) { point = CGPoint(x: 1 - point.y, y: point.x) }
        // A hand-forced level turned the photo before everything: undo it last.
        if let level = request.level {
            let px = PumpRowDeskew.unlevelled(CGPoint(x: point.x * Double(photo.width), y: point.y * Double(photo.height)),
                                              degrees: level, width: photo.width, height: photo.height)
            point = CGPoint(x: px.x / Double(photo.width), y: px.y / Double(photo.height))
        }
        return [point.x, point.y]
    }
    if let detector, let cg = PumpQuadWarp.makeImage(upright.pixels, width: upright.width, height: upright.height) {
        timings["detectorOnly"] = timed("detectorOnly") { detector.detect(in: cg).count }
    }
    let candidates = timed("candidates") { reader.candidates(for: upright, deskewRows: readDeskewed) }
    let judged = try timed("verify") { try reader.verdicts(image: upright, candidates: candidates) }
    let verified = PumpReader.verified(from: judged)
    timings["textLines"] = timed("textLines") { PumpDisplayCapture.textLineCount(upright) }
    reply["timingsMs"] = timings
    let assignment = PumpRowAssignment.assign(
        windows: verified.map { PumpRowAssignment.Window(quad: $0.quad, glyphCount: $0.glyphCount) }, rotationCW: 0)
    // What the located rows read as, digit by digit, so a miss can be told
    // apart from a law that would not close.
    var assigned: [PumpReader.Window] = []
    for (window, role) in zip(verified, assignment.roles) {
        guard let role else { continue }
        assigned.append(PumpReader.Window(field: role, quad: window.quad))
    }
    timings["assign"] = 0
    let readsTimed = try? timed("read") { try reader.read(image: upright, windows: assigned) }
    if let readsTimed {
        _ = timed("law") {
            PumpReadingLaw.resolve(windows: readsTimed.map { PumpLocatedWindow(field: $0.field, cells: $0.cells) },
                                   currency: currency, priceBand: priceBand)
        }
        reply["cellsPerRow"] = readsTimed.map { $0.cells.count }
    }
    // The app's own path: the classification decision alone, and decision + read.
    if let cg = PumpQuadWarp.makeImage(upright.pixels, width: upright.width, height: upright.height) {
        let handle = PumpReaderHandle(reader: reader)
        let decision = timed("appDecide") { PumpDisplayCapture.detect(image: cg, reader: handle) }
        // The decision with the inputs it compared and the limits it compared
        // them against, so the annotator can say WHY a frame was refused.
        reply["appDecision"] = ["display": decision.isPumpDisplay, "rows": decision.displayRows,
                                "textLines": decision.textLines, "widestRow": decision.widestRow,
                                "path": decision.path.rawValue,
                                "limits": ["minimumRows": PumpDisplayCapture.minimumRows,
                                           "maximumTextLines": PumpDisplayCapture.maximumTextLines,
                                           "minimumWidestRow": PumpDisplayCapture.minimumWidestRowFraction]]
        // What the app itself would pre-fill: the display decision, then the read,
        // at the frame's own orientation - the app's entry point, not readPhoto.
        let app = timed("appClassifyAndRead") {
            PumpDisplayCapture.classify(image: cg, reader: handle, currency: currency, priceBand: priceBand)
        }
        let appFields = app.reading?.extraction
        var appCommitted: [String: Any] = ["total": NSNull(), "liters": NSNull(), "unitPrice": NSNull()]
        if let total = appFields?.total { appCommitted["total"] = "\(total)" }
        if let liters = appFields?.liters { appCommitted["liters"] = "\(liters)" }
        if let price = appFields?.unitPrice { appCommitted["unitPrice"] = "\(price)" }
        reply["appCommitted"] = appCommitted
        // Whether the app would take this frame down the pump path at all: a
        // reading, even an empty one, routes the capture as a pump photo.
        reply["appRoutedAsPump"] = app.reading != nil
    }
    reply["timingsMs"] = timings
    if let reads = readsTimed {
        reply["rowTexts"] = reads.map { read in
            read.field.rawValue + " " + read.cells.map { cell in
                (cell.ranked.first.map { String($0.digit) } ?? "?") + (cell.decimalPoint ? "." : "")
            }.joined() + " " + read.cells.map { String(format: "%.1f", ($0.ranked[0].logPosterior - $0.ranked[1].logPosterior)) }.joined(separator: ",")
        }
    }
    // Every candidate the verifier judged, kept or not, with why it went: the
    // annotator colours each hand window by whether a candidate found it and
    // whether the verifier kept it. A kept candidate absent from `rows` lost
    // to a stronger duplicate of the same row.
    reply["candidates"] = judged.map { v -> [String: Any] in
        let duplicate = v.kept && !verified.contains { PumpQuadWarp.iou($0.quad, v.quad) > 0.99 }
        return ["quad": v.quad.map { unturned(CGPoint(x: $0.x / Double(upright.width), y: $0.y / Double(upright.height))) },
                "detected": v.detected, "kept": v.kept && !duplicate, "cells": v.cells,
                "dropReasons": duplicate ? ["duplicate"] : v.dropReasons]
    }
    reply["candidatesOffered"] = candidates.count
    reply["rows"] = zip(verified, assignment.roles).map { window, role -> [String: Any] in
        ["field": role?.rawValue ?? NSNull(), "cells": window.glyphCount, "detected": window.detected,
         "quad": window.quad.map { unturned(CGPoint(x: $0.x / Double(upright.width), y: $0.y / Double(upright.height))) }]
    }
}
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: reply))
