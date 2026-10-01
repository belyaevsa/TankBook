import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// Strips cut from the locator's OWN boxes, labelled with the hand window's
/// text, for the row reader's training (PU.91 experiment G). The shipped reader
/// learns from strips warped from hand quads, so it has never seen the shifted
/// and clipped strips the app hands it; this export runs the shipped locator
/// over the TRAIN stills (and a sample of their Live records' frames), matches
/// each located row to a hand window by overlap, and cuts the strip exactly as
/// the reader does - at the standard margins and at the wide margins of the
/// second read. Written to `ios/.build/pump-reader-out/located/` in the manifest
/// shape `pump_reader.rowreader.load_real` reads; nothing here scores anything.
///
/// Opt-in by environment (`PUMP_LOCATED_EXPORT=1`); `PUMP_LOCATED_FRAME_STEP`
/// thins the frames (default one in 5).
@Suite("PU.91 located strip export")
struct PumpLocatedStripExportTests {
    private static var enabled: Bool { ProcessInfo.processInfo.environment["PUMP_LOCATED_EXPORT"] == "1" }
    private static let outRoot = PumpReaderTestSupport.outRoot.appendingPathComponent("located")
    private static let framesRoot = PumpReaderTestSupport.repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures/pump-live/frames")
    /// The overlap a located row needs with a hand window to take its text.
    private static let matchIoU = 0.5

    struct Window { let field: String; let text: String; let quad: [[Double]] }
    struct Image { let fixture: String; let frame: String?; let url: URL; let rotationCW: Int; let windows: [Window] }

    @Test("exports strips cut from the locator's boxes, labelled by the matching hand window",
          .enabled(if: enabled && PumpReaderTestSupport.fixturesPresent, "PUMP_LOCATED_EXPORT=1 with the corpus"))
    func export() throws {
        let model = try PumpSegmentsModel(contentsOf: PumpReaderTestSupport.repoRoot
            .appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage"))
        let reader = PumpReader(model: model, detector: PumpReaderTestSupport.makeDetector(),
                                rowReader: PumpReaderTestSupport.makeRowReader())
        let stripsDir = Self.outRoot.appendingPathComponent("strips")
        try FileManager.default.createDirectory(at: stripsDir, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        var images = 0, windows = 0, matched = 0
        for image in try Self.collect() {
            guard let raw = PumpReaderTestSupport.loadRGB(url: image.url) else { continue }
            images += 1
            let upright = PumpPanelLocator.rotatedRGB(raw, rotationCW: image.rotationCW)
            // Candidates come normalised over the upright image; the reader works in its pixels.
            let candidates = reader.candidates(for: upright).filter(\.detected).map { candidate in
                candidate.quad.map { CGPoint(x: $0.x * CGFloat(upright.width), y: $0.y * CGFloat(upright.height)) }
            }
            for window in image.windows {
                windows += 1
                let hand = PumpQuadWarp.readingOrder(
                    PumpReaderTestSupport.quadPixels(window.quad, width: raw.width, height: raw.height),
                    rotationCW: image.rotationCW)
                let uprightHand = PumpQuadWarp.rotatePointsClockwise(
                    hand, rotationCW: image.rotationCW, oldSize: (raw.width, raw.height))
                guard let best = candidates.max(by: {
                    PumpQuadWarp.iou($0, uprightHand) < PumpQuadWarp.iou($1, uprightHand)
                }), PumpQuadWarp.iou(best, uprightHand) >= Self.matchIoU else { continue }
                matched += 1
                for (tag, margins) in [("s", PumpReader.DetectedMargins.standard), ("w", .wide)] {
                    guard let sliced = PumpReader.sliceDetectedOrOriginal(best, detected: true, in: upright,
                                                                          margins: margins),
                          let cg = PumpQuadWarp.makeImage(sliced.rgb.pixels, width: sliced.rgb.width,
                                                          height: sliced.rgb.height) else { continue }
                    let name = String(format: "l%@%07d.png", tag, records.count)
                    _ = PumpQuadWarp.writePNG(image: cg, to: stripsDir.appendingPathComponent(name))
                    records.append(["fixture": image.fixture, "frame": image.frame ?? NSNull(),
                                    "field": window.field, "text": window.text, "strip": "strips/\(name)",
                                    "stripWidth": sliced.rgb.width, "stripHeight": sliced.rgb.height,
                                    "margins": tag])
                }
            }
        }
        let manifest: [String: Any] = ["windows": records, "images": images, "handWindows": windows,
                                       "matched": matched, "total": records.count]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: Self.outRoot.appendingPathComponent("train-slices.json"))
        print("PU.91 located export: \(images) images, \(matched) of \(windows) hand windows matched, "
              + "\(records.count) strips")
        #expect(matched > 0)
    }

    /// Train stills with their hand windows, then every Nth tracked frame of a
    /// train still's Live record (frames are upright; their quads are the
    /// tracker's, carrying the still's text). Partial and empty windows are
    /// skipped, as the hand export skips them.
    private static func collect() throws -> [Image] {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: PumpReaderTestSupport.windowsURL))
            as? [String: Any] ?? [:]
        let step = Int(ProcessInfo.processInfo.environment["PUMP_LOCATED_FRAME_STEP"] ?? "") ?? 5
        var out: [Image] = []
        var trainStills: [String: [String: Any]] = [:]
        for (name, value) in root.sorted(by: { $0.key < $1.key }) {
            guard name != "_about", let ann = value as? [String: Any], PumpReaderTestSupport.isTrain(name) else {
                continue
            }
            trainStills[name] = ann
            out.append(Image(fixture: name, frame: nil,
                             url: PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name),
                             rotationCW: (ann["rotationCW"] as? NSNumber)?.intValue ?? 0,
                             windows: windows(ann["windows"])))
        }
        let folders = (try? FileManager.default.contentsOfDirectory(at: framesRoot, includingPropertiesForKeys: nil)) ?? []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let tracked = try? JSONSerialization.jsonObject(
                    with: Data(contentsOf: folder.appendingPathComponent("windows.json"))) as? [String: Any],
                  let still = tracked["_still"] as? String, let stillAnn = trainStills[still],
                  (stillAnn["tracking"] as? String) != "bad",
                  let frames = tracked["frames"] as? [String: Any] else { continue }
            for (index, name) in frames.keys.sorted().enumerated() where index % step == 0 {
                guard let frame = frames[name] as? [String: Any] else { continue }
                out.append(Image(fixture: still, frame: "\(folder.lastPathComponent)/\(name)",
                                 url: folder.appendingPathComponent(name), rotationCW: 0,
                                 windows: windows(frame["windows"])))
            }
        }
        return out
    }

    private static func windows(_ raw: Any?) -> [Window] {
        (raw as? [[String: Any]] ?? []).compactMap { window in
            guard let field = window["field"] as? String, let text = window["text"] as? String, !text.isEmpty,
                  (window["legibility"] as? String) != "partial",
                  let quad = (window["quad"] as? [[NSNumber]])?.map({ $0.map(\.doubleValue) }), quad.count == 4
            else { return nil }
            return Window(field: field, text: text, quad: quad)
        }
    }
}
