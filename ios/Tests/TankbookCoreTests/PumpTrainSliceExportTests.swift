import Foundation
import Testing
@testable import TankbookCore

/// The real-glyph export for the classifier (PU.31, decision 9): every window
/// of every TRAIN still and of every tracked frame of a train still's Live
/// record, warped to the 96 px strip and cut by the production slicer, with
/// the annotation's text as the label. Written to
/// `ios/.build/pump-reader-out/train/` for `pump_reader.realglyphs`; nothing
/// here scores anything.
///
/// Opt-in by environment (`PUMP_TRAIN_EXPORT=1`): the walk is thousands of
/// windows and belongs to a training round, not to the gate.
@Suite("PU.31 train slice export")
struct PumpTrainSliceExportTests {
    private static var enabled: Bool { ProcessInfo.processInfo.environment["PUMP_TRAIN_EXPORT"] == "1" }
    private static let framesRoot = PumpReaderTestSupport.repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures/pump-live/frames")
    private static let outRoot = PumpReaderTestSupport.outRoot.appendingPathComponent("train")

    struct Source {
        let fixture: String
        let frame: String?
        let field: String
        let text: String
        let quad: [[Double]]
        let rotationCW: Int
        let imageURL: URL
    }

    @Test("exports the train split's windows as slicer cells with labels",
          .enabled(if: enabled && PumpReaderTestSupport.fixturesPresent, "PUMP_TRAIN_EXPORT=1 with the corpus"))
    func export() throws {
        let sources = try Self.collect()
        let stripsDir = Self.outRoot.appendingPathComponent("strips")
        try FileManager.default.createDirectory(at: stripsDir, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        var imageCache: (url: URL, image: PumpRGBImage)?
        var countOK = 0
        for (index, source) in sources.enumerated() {
            let image: PumpRGBImage
            if let cached = imageCache, cached.url == source.imageURL {
                image = cached.image
            } else {
                guard let loaded = PumpReaderTestSupport.loadRGB(url: source.imageURL) else { continue }
                image = loaded
                imageCache = (source.imageURL, loaded)
            }
            let quad = PumpQuadWarp.readingOrder(
                PumpReaderTestSupport.quadPixels(source.quad, width: image.width, height: image.height),
                rotationCW: source.rotationCW)
            guard let strip = PumpQuadWarp.warpToStrip(rgb: image, quad: quad, stripHeight: 96) else { continue }
            let cells = PumpGlyphSlicer.slice(PumpQuadWarp.rgbImage(from: strip).grayscale())
            let expected = PumpReaderTestSupport.glyphCount(source.text)
            if cells.count == expected { countOK += 1 }
            let stripName = String(format: "%06d.png", index)
            _ = PumpQuadWarp.writePNG(image: strip, to: stripsDir.appendingPathComponent(stripName))
            records.append([
                "fixture": source.fixture,
                "frame": source.frame ?? NSNull(),
                "field": source.field,
                "text": source.text,
                "strip": "strips/\(stripName)",
                "stripWidth": strip.width,
                "stripHeight": strip.height,
                "cells": cells.map { cell -> [String: Any] in
                    ["x0": Double(cell.rect.minX) / Double(strip.width),
                     "y0": Double(cell.rect.minY) / Double(strip.height),
                     "x1": Double(cell.rect.maxX) / Double(strip.width),
                     "y1": Double(cell.rect.maxY) / Double(strip.height),
                     "hasDecimalPoint": cell.hasDecimalPoint, "isBlank": cell.isBlank]
                },
            ] as [String: Any])
        }
        let manifest: [String: Any] = ["windows": records, "countAgreement": countOK, "total": records.count]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: Self.outRoot.appendingPathComponent("train-slices.json"))
        print("PU.31 export: \(records.count) windows, slicer count agrees on \(countOK)")
        #expect(!records.isEmpty)
    }

    /// Train stills' windows, then tracked frames of train records whose still
    /// is not marked `tracking: bad`. Partial and empty windows are skipped: a
    /// doubtful label is worse than no label.
    private static func collect() throws -> [Source] {
        let data = try Data(contentsOf: PumpReaderTestSupport.windowsURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var out: [Source] = []
        var trainStills: [String: [String: Any]] = [:]
        for (name, value) in root.sorted(by: { $0.key < $1.key }) {
            guard name != "_about", let ann = value as? [String: Any],
                  !PumpReaderTestSupport.isHeldout(name) else { continue }
            trainStills[name] = ann
            let rotation = (ann["rotationCW"] as? NSNumber)?.intValue ?? 0
            let url = PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)
            for window in ann["windows"] as? [[String: Any]] ?? [] {
                guard let source = source(window, fixture: name, frame: nil, rotation: rotation, url: url) else { continue }
                out.append(source)
            }
        }
        let folders = (try? FileManager.default.contentsOfDirectory(at: framesRoot, includingPropertiesForKeys: nil)) ?? []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let trackedURL = folder.appendingPathComponent("windows.json")
            guard let trackedData = try? Data(contentsOf: trackedURL),
                  let tracked = try? JSONSerialization.jsonObject(with: trackedData) as? [String: Any],
                  let still = tracked["_still"] as? String, let stillAnn = trainStills[still],
                  (stillAnn["tracking"] as? String) != "bad",
                  let frames = tracked["frames"] as? [String: Any] else { continue }
            for (frameName, value) in frames.sorted(by: { $0.key < $1.key }) {
                guard let frame = value as? [String: Any] else { continue }
                let url = folder.appendingPathComponent(frameName)
                for window in frame["windows"] as? [[String: Any]] ?? [] {
                    // Frames are extracted upright; the still's rotation is already
                    // in the homography that placed the quad.
                    guard let source = source(window, fixture: still, frame: "\(folder.lastPathComponent)/\(frameName)",
                                              rotation: 0, url: url) else { continue }
                    out.append(source)
                }
            }
        }
        return out
    }

    private static func source(_ window: [String: Any], fixture: String, frame: String?, rotation: Int, url: URL) -> Source? {
        guard let field = window["field"] as? String, let text = window["text"] as? String, !text.isEmpty,
              (window["legibility"] as? String) != "partial",
              let quad = (window["quad"] as? [[NSNumber]])?.map({ $0.map(\.doubleValue) }), quad.count == 4 else { return nil }
        return Source(fixture: fixture, frame: frame, field: field, text: text, quad: quad, rotationCW: rotation, imageURL: url)
    }
}
