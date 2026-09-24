import Foundation
import Testing
@testable import TankbookCore

// PU.4 - shared test plumbing: fixture paths, the two scorer oracles from a
// window's `text`, image loading, and the opt-in trait that skips the harness
// when the pump corpus is not checked out (CI without fixtures).

enum PumpReaderTestSupport {

    static let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent() // TankbookCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // repo root

    static let windowsURL = repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures/pump/windows.json")
    static let pumpFixturesRoot = repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures/pump")
    static let outRoot = repoRoot
        .appendingPathComponent("ios/.build/pump-reader-out")

    /// The row detector trained by ml/pump-reader/detector/train.swift (PU.33),
    /// when a training has produced it; the live path runs without it otherwise.
    /// `PUMP_DETECTOR=<path>` scores a candidate instead, so a candidate is never
    /// measured by overwriting the dev copy the shipped model is exported from.
    /// A `PUMP_DETECTOR` that names no file stops the run: silently falling back
    /// to no detector would score the candidate as the Vision-only locator.
    static let detectorURL: URL? = {
        if let path = ProcessInfo.processInfo.environment["PUMP_DETECTOR"], !path.isEmpty {
            precondition(FileManager.default.fileExists(atPath: path), "PUMP_DETECTOR names no file: \(path)")
            return URL(fileURLWithPath: path)
        }
        let url = repoRoot.appendingPathComponent("ml/pump-reader/.out/det/DigitRows.mlmodel")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }()

    static func makeDetector() -> PumpRowDetector? {
        if let path = ProcessInfo.processInfo.environment["PUMP_SEGMENTER"], !path.isEmpty {
            precondition(FileManager.default.fileExists(atPath: path), "PUMP_SEGMENTER names no file: \(path)")
            return try? PumpRowDetector.load(contentsOf: URL(fileURLWithPath: path))
        }
        return detectorURL.flatMap { try? PumpRowDetector(contentsOf: $0) }
    }

    static var fixturesPresent: Bool {
        FileManager.default.fileExists(atPath: windowsURL.path)
    }

    /// The fixtures a trained model may be scored on (decision 9,
    /// docs/EXTRACTION.md): `pump/split.csv` names each still `train` or
    /// `heldout`. The heldout set was drawn once (64 of the 211 stills on
    /// 2026-09-19) and is frozen except for the one written amendment in
    /// docs/EXTRACTION.md (four night stills, none trained on); every other
    /// still added since is training material, so a fixture absent from the
    /// file is `train`. The
    /// classifier learns from the train part's real glyphs, so a number
    /// measured on it is memorisation; every ratchet that runs the model
    /// reads the heldout set and nothing else.
    private static let split: [String: String] = {
        let url = pumpFixturesRoot.appendingPathComponent("split.csv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in text.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
            if cols.count == 2 { result[String(cols[0])] = String(cols[1]) }
        }
        return result
    }()

    /// Entries a human has confirmed (`reviewed: true` in windows.json). An
    /// unreviewed heldout still - boxes auto-placed by the reader, texts not
    /// yet the display's own - measures nothing: its miscounts are the
    /// annotation's, not the reader's, so the model-scored ratchets leave it
    /// out until the owner marks it processed. It is never train material
    /// either (`isTrain`), so no model learns from it in the meantime.
    private static let reviewed: Set<String> = {
        guard let data = try? Data(contentsOf: windowsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return Set(json.compactMap { name, value in
            ((value as? [String: Any])?["reviewed"] as? Bool) == true ? name : nil
        })
    }()

    /// A still the model-scored ratchets measure: in the heldout split AND reviewed.
    static func isHeldout(_ name: String) -> Bool { split[name] == "heldout" && reviewed.contains(name) }
    /// A still a model may train on: in the train split (absent from the file = train).
    static func isTrain(_ name: String) -> Bool { (split[name] ?? "train") == "train" }
    /// A train still a human has confirmed - the calibration population of the
    /// in-sample certificate (`agents/research/PU.68.md` §6).
    static func isReviewedTrain(_ name: String) -> Bool { isTrain(name) && reviewed.contains(name) }

    /// The glyph-count oracle: digits plus leading spaces, never separators.
    static func glyphCount(_ text: String) -> Int {
        text.reduce(0) { count, ch in count + ((ch.isNumber || ch == " ") ? 1 : 0) }
    }

    /// The dp oracle: the cell index (in the digit/blank sequence) of the digit
    /// immediately before a `.`/`,`, or nil when the window has no separator.
    static func dpCellIndex(_ text: String) -> Int? {
        var cell = 0
        var result: Int?
        for ch in text {
            if ch == "." || ch == "," {
                result = cell > 0 ? cell - 1 : nil
            } else if ch.isNumber || ch == " " {
                cell += 1
            }
        }
        return result
    }

    static func loadRGB(url: URL) -> PumpRGBImage? {
        guard let cg = PumpQuadWarp.loadOrientedImage(from: url) else { return nil }
        return PumpQuadWarp.rgbImage(from: cg)
    }

    /// The quad as pixel coordinates in the EXIF-oriented image.
    static func quadPixels(_ quad: [[Double]], width: Int, height: Int) -> [CGPoint] {
        quad.map { CGPoint(x: $0[0] * Double(width), y: $0[1] * Double(height)) }
    }

    // MARK: - Live records

    static let pumpLiveFramesRoot = repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures/pump-live/frames")

    /// A still's tracked Live record: the frames `pump_reader.track` kept and
    /// the still's quads carried into each. Quads stay normalised over the
    /// frame until the frame is decoded, when they are converted with the
    /// frame's own size.
    struct PumpLiveRecord {
        let id: String
        let still: String
        let framesDirectory: URL
        let frameNames: [String]
        let windows: [String: [(field: PumpField, quad: [[Double]])]]
    }

    /// Every tracked record whose still is heldout (decision 9). The frame
    /// media is gitignored and lives in the corpus bucket; absent, the list is
    /// empty and the fusion test has nothing to measure.
    static func heldoutLiveRecords() -> [PumpLiveRecord] {
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: pumpLiveFramesRoot, includingPropertiesForKeys: nil) else { return [] }
        var out: [PumpLiveRecord] = []
        for dir in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("windows.json")),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let still = root["_still"] as? String,
                  (root["_split"] as? String) == "heldout",
                  let frames = root["frames"] as? [String: Any] else { continue }
            var windows: [String: [(field: PumpField, quad: [[Double]])]] = [:]
            for (name, value) in frames {
                guard let entry = value as? [String: Any],
                      let raw = entry["windows"] as? [[String: Any]] else { continue }
                windows[name] = raw.compactMap { window in
                    guard let fieldName = window["field"] as? String,
                          let field = PumpField(rawValue: fieldName),
                          let quad = window["quad"] as? [[Double]] else { return nil }
                    return (field, quad)
                }
            }
            out.append(PumpLiveRecord(id: dir.lastPathComponent, still: still,
                                      framesDirectory: dir, frameNames: frames.keys.sorted(),
                                      windows: windows))
        }
        return out
    }

    /// The annotation's stated rotation. The live path no longer reads this -
    /// the phone never has it (PU.53) - it exists for the orientation
    /// measurement's baseline arm only.
    static func annotationRotation(_ annotation: [String: Any]) -> Int {
        (annotation["rotationCW"] as? NSNumber)?.intValue ?? 0
    }

    /// The still's annotated windows in pixel coordinates, the shape
    /// `read`/`resolve` take.
    static func annotatedWindows(_ annotation: [String: Any], image: PumpRGBImage) -> [PumpReader.Window] {
        let rotation = (annotation["rotationCW"] as? NSNumber)?.intValue ?? 0
        var out: [PumpReader.Window] = []
        for raw in annotation["windows"] as? [[String: Any]] ?? [] {
            guard let fieldName = raw["field"] as? String, let field = PumpField(rawValue: fieldName),
                  let text = raw["text"] as? String, !text.isEmpty,
                  let quad = raw["quad"] as? [[Double]] else { continue }
            let pixels = PumpQuadWarp.readingOrder(
                quadPixels(quad, width: image.width, height: image.height), rotationCW: rotation)
            out.append(PumpReader.Window(field: field, quad: pixels))
        }
        return out
    }

    /// The record's frames as a lazy sequence, one decoded frame alive at a
    /// time: a 4K movie frame is 33 MB and a record can hold two hundred.
    static func trackedFrames(for record: PumpLiveRecord, step: Int = 1) -> AnySequence<PumpTrackedFrame> {
        AnySequence {
            var index = 0
            return AnyIterator {
                while index < record.frameNames.count {
                    let name = record.frameNames[index]
                    index += max(1, step)
                    guard let image = loadRGB(url: record.framesDirectory.appendingPathComponent(name))
                    else { continue }
                    let windows = (record.windows[name] ?? []).map { entry in
                        PumpReader.Window(field: entry.field,
                                          quad: entry.quad.map { CGPoint(x: $0[0] * Double(image.width),
                                                                         y: $0[1] * Double(image.height)) })
                    }
                    return PumpTrackedFrame(image: image, windows: windows)
                }
                return nil
            }
        }
    }
}

extension Trait where Self == ConditionTrait {
    static var pumpFixturesPresent: ConditionTrait {
        .enabled(if: PumpReaderTestSupport.fixturesPresent,
                 Comment(rawValue: "pump windows.json fixture corpus is not checked out"))
    }
}
