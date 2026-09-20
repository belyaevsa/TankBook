// The pump reader as a command - what the annotator calls to show the model's
// reading of a frame or a still (tools/pump-annotate):
//
//   pump-read <image> [--classifier <PumpSegments.mlpackage>] [--detector <DigitRows.mlmodel>] < request.json
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
    var rotationCW: Int = 0
    var currency: String?
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
var index = 2
while index < arguments.count {
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
let stdin = FileHandle.standardInput.readDataToEndOfFile()
let request = (try? JSONDecoder().decode(Request.self, from: stdin)) ?? Request()
guard let oriented = PumpQuadWarp.loadOrientedImage(from: URL(fileURLWithPath: arguments[1])) else {
    print("{\"error\": \"cannot load image\"}")
    exit(1)
}
let model = try PumpSegmentsModel(contentsOf: URL(fileURLWithPath: classifierPath))
let detector = detectorPath.flatMap { path in
    FileManager.default.fileExists(atPath: path) ? try? PumpRowDetector(contentsOf: URL(fileURLWithPath: path)) : nil
}
let reader = PumpReader(model: model, detector: detector)
let image = PumpQuadWarp.rgbImage(from: oriented)
let currency = request.currency.flatMap { CurrencyCode(rawValue: $0) }
var reply: [String: Any] = [:]

func committed(_ reading: PumpDisplayReading) -> [String: Any] {
    func value(_ field: PumpFieldReading) -> Any { field.value.map { "\($0)" } ?? NSNull() }
    return ["total": value(reading.total), "liters": value(reading.liters), "unitPrice": value(reading.unitPrice)]
}

if let windows = request.windows, !windows.isEmpty {
    // Annotated quads are read on the oriented image in reading order, as the harness does.
    let located = windows.compactMap { window -> PumpReader.Window? in
        guard let field = PumpField(rawValue: window.field) else { return nil }
        let pixels = window.quad.map { CGPoint(x: $0[0] * Double(image.width), y: $0[1] * Double(image.height)) }
        return PumpReader.Window(field: field, quad: PumpQuadWarp.readingOrder(pixels, rotationCW: request.rotationCW))
    }
    let reads = try reader.read(image: image, windows: located)
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
        return ["field": read.field.rawValue, "cells": cells, "text": text]
    }
    let law = PumpReadingLaw.resolve(windows: reads.map { PumpLocatedWindow(field: $0.field, cells: $0.cells) },
                                     currency: currency, priceBand: nil)
    reply["committed"] = committed(law)
} else {
    let reading = try reader.readPhoto(image: image, rotationCW: request.rotationCW, currency: currency, priceBand: nil)
    reply["committed"] = committed(reading)
    let upright = PumpPanelLocator.rotatedRGB(image, rotationCW: request.rotationCW)
    let verified = try reader.verify(image: upright, candidates: reader.candidates(for: upright))
    let assignment = PumpRowAssignment.assign(
        windows: verified.map { PumpRowAssignment.Window(quad: $0.quad, glyphCount: $0.glyphCount) }, rotationCW: 0)
    reply["rows"] = zip(verified, assignment.roles).map { window, role -> [String: Any] in
        ["field": role?.rawValue ?? NSNull(), "cells": window.glyphCount, "detected": window.detected,
         "quad": window.quad.map { [$0.x / Double(upright.width), $0.y / Double(upright.height)] }]
    }
}
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: reply))
