import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// Labels for the running-display videos (`pump-live/videos.json`): every
/// tracked frame's total and liters windows are read by the reader with the
/// video's constant price, and a frame's reading becomes its label only when
/// `total == round(liters x price)` to the cent - the display's own arithmetic
/// is the oracle, no annotation exists. The result is staged as one record's
/// readings plus its arithmetic labels and written through
/// `scripts/corpus_db.py import-readings`, which updates `readings` and `labels`
/// in one transaction and dumps `pump-live/video-labels.json` and
/// `frames/<stem>/readings.json`; the product owner's corrections in the
/// annotator carry `source: "owner"` and are never overwritten by a re-run; nor
/// is a video marked `reviewed` in `videos.json` or a frame the owner anchored
/// by hand (`verified` in the tracked `windows.json`).
///
/// Opt-in (`PUMP_VIDEO_READ=1`; `PUMP_VIDEO_READ_ONLY=video-002` for one clip):
/// four thousand frames through the reader.
@Suite("PU.19 video labels by arithmetic")
struct PumpVideoReadTests {
    private static var enabled: Bool { ProcessInfo.processInfo.environment["PUMP_VIDEO_READ"] == "1" }
    private static let live = PumpReaderTestSupport.repoRoot.appendingPathComponent("Spike/ReceiptSpike/fixtures/pump-live")
    private static let modelURL = PumpReaderTestSupport.repoRoot.appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")
    private static let stagingDirectory = PumpReaderTestSupport.outRoot.appendingPathComponent("video-read")

    /// A failed import must be loud: the old writer wrote the files directly and
    /// a missing `python3` would silently leave the database stale.
    private struct ImportError: Error, CustomStringConvertible {
        let path: String
        let status: Int32
        let detail: String
        var description: String {
            "corpus_db.py import-readings failed (status \(status)) for \(path): \(detail)"
        }
    }

    /// One record's readings plus its arithmetic labels to a staging file, then
    /// through `scripts/corpus_db.py import-readings`, which writes both tables
    /// in one transaction and dumps the two files.
    private static func stage(_ stem: String, readings: [String: Any], arithmetic: [String: Any]) throws {
        let staging = stagingDirectory.appendingPathComponent("\(stem).json")
        let staged: [String: Any] = ["record": stem, "readings": readings, "labels": arithmetic]
        try JSONSerialization.data(withJSONObject: staged, options: [.sortedKeys]).write(to: staging)
        try importReadings(staging)
    }

    private static func importReadings(_ staging: URL) throws {
        let script = PumpReaderTestSupport.repoRoot.appendingPathComponent("scripts/corpus_db.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, "import-readings", staging.path]
        process.currentDirectoryURL = PumpReaderTestSupport.repoRoot
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        do {
            try process.run()
        } catch {
            throw ImportError(path: staging.path, status: -1, detail: error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ImportError(path: staging.path, status: process.terminationStatus, detail: detail)
        }
    }

    @Test("every tracked video frame whose reading closes gets its label", .enabled(if: enabled, "PUMP_VIDEO_READ=1"))
    func label() throws {
        let model = try PumpSegmentsModel(contentsOf: Self.modelURL)
        let reader = PumpReader(model: model)
        let videos = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.live.appendingPathComponent("videos.json"))) as? [String: Any] ?? [:]
        let labelsURL = Self.live.appendingPathComponent("video-labels.json")
        let labels = (try? JSONSerialization.jsonObject(with: Data(contentsOf: labelsURL)) as? [String: Any]) ?? [:]
        try FileManager.default.createDirectory(at: Self.stagingDirectory, withIntermediateDirectories: true)
        var summary: [String] = []
        let only = ProcessInfo.processInfo.environment["PUMP_VIDEO_READ_ONLY"]
        for (stem, value) in videos.sorted(by: { $0.key < $1.key }) {
            if let only, !stem.hasPrefix(only) { continue }
            guard !stem.hasPrefix("_"), let video = value as? [String: Any],
                  // A video the owner marked processed is finished: its labels and
                  // pre-fills are not regenerated.
                  (video["reviewed"] as? Bool) != true,
                  let priceText = video["unitPrice"] as? String,
                  let price = Double(priceText.replacingOccurrences(of: ",", with: ".")) else { continue }
            let trackedURL = Self.live.appendingPathComponent("frames/\(stem)/windows.json")
            guard let tracked = try? JSONSerialization.jsonObject(with: Data(contentsOf: trackedURL)) as? [String: Any],
                  let frames = tracked["frames"] as? [String: Any] else { continue }
            let comma = priceText.contains(",")
            let existing = labels[stem] as? [String: Any] ?? [:]
            var readings: [String: Any] = [:]
            var arithmetic: [String: Any] = [:]
            var closed = 0, read = 0
            for (frameName, frameValue) in frames.sorted(by: { Int($0.key.dropLast(4)) ?? 0 < Int($1.key.dropLast(4)) ?? 0 }) {
                if let existing = existing[frameName] as? [String: Any], existing["source"] as? String == "owner" { continue }
                guard let frame = frameValue as? [String: Any], let windows = frame["windows"] as? [[String: Any]],
                      // A frame whose quads the owner placed by hand (a tracking anchor)
                      // is human-reviewed; it keeps whatever it has.
                      (frame["verified"] as? Bool) != true,
                      let image = PumpReaderTestSupport.loadRGB(url: Self.live.appendingPathComponent("frames/\(stem)/\(frameName)")) else { continue }
                var located: [PumpReader.Window] = []
                for w in windows {
                    guard let field = w["field"] as? String, let quad = (w["quad"] as? [[NSNumber]])?.map({ $0.map(\.doubleValue) }),
                          field != "unitPrice", let role = PumpField(rawValue: field) else { continue }
                    located.append(PumpReader.Window(field: role, quad: PumpReaderTestSupport.quadPixels(quad, width: image.width, height: image.height)))
                }
                guard let reads = try? reader.read(image: image, windows: located) else { continue }
                read += 1
                // The cells as strings, no law: the arithmetic is the whole check.
                var strings: [PumpField: String] = [:]
                for r in reads {
                    let digits = r.cells.map { cell -> String in
                        guard let best = cell.ranked.first else { return "?" }
                        return String(best.digit) + (cell.decimalPoint ? (comma ? "," : ".") : "")
                    }.joined()
                    strings[r.field] = digits
                }
                let t = strings[.total] ?? "", l = strings[.liters] ?? ""
                let total = Double(t.replacingOccurrences(of: ",", with: "."))
                let liters = Double(l.replacingOccurrences(of: ",", with: "."))
                let closes = !t.contains("?") && !l.contains("?") && total != nil && liters != nil && liters! > 0
                    && (abs(total! - (liters! * price * 100).rounded() / 100) < 0.011 || abs(total! - (liters! * price * 10).rounded() / 10) < 0.06)
                // Every reading is kept for the annotator's pre-fill; only a closing one is a label.
                readings[frameName] = ["total": t, "liters": l, "closes": closes]
                guard closes else { continue }
                closed += 1
                arithmetic[frameName] = ["total": t, "liters": l, "unitPrice": priceText, "source": "arithmetic"]
            }
            // One staging file per record: readings plus the arithmetic labels
            // the reader would write. `import-readings` keeps owner rows.
            try Self.stage(stem, readings: readings, arithmetic: arithmetic)
            let labelled = Set(existing.keys).union(arithmetic.keys)
            summary.append("\(stem.prefix(9)): \(closed) of \(read) frames closed (\(labelled.count) labelled)")
        }
        for line in summary { print("PU.19 \(line)") }
        #expect(!summary.isEmpty)
    }
}
