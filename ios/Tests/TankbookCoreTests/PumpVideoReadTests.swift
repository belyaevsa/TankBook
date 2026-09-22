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
/// An `interpolated` label (PU.45) is a keyframe pair's arithmetic fill: the
/// reader skips it only while the nearest owner keyframe on BOTH sides is still
/// `owner`, and regenerates it as `arithmetic` otherwise, because an
/// interpolation whose keyframe changed is stale. The reader also stages the
/// lowest cell margin of the total and liters windows as the frame's `margin`,
/// which the annotator shows beside the label.
///
/// Opt-in (`PUMP_VIDEO_READ=1`; `PUMP_VIDEO_READ_ONLY=video-002` for one clip):
/// four thousand frames through the reader. `PUMP_CORPUS_LABELS`,
/// `PUMP_CORPUS_FRAMES` and `PUMP_ANNOTATE_DB` redirect the write path to a
/// scratch copy when the interpolation check runs.
@Suite("PU.19 video labels by arithmetic")
struct PumpVideoReadTests {
    private static var enabled: Bool { ProcessInfo.processInfo.environment["PUMP_VIDEO_READ"] == "1" }
    private static let live = PumpReaderTestSupport.repoRoot.appendingPathComponent("Spike/ReceiptSpike/fixtures/pump-live")
    private static let modelURL = PumpReaderTestSupport.repoRoot.appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")
    private static let stagingDirectory = PumpReaderTestSupport.outRoot.appendingPathComponent("video-read")
    private static let scratchRoot = PumpReaderTestSupport.outRoot.appendingPathComponent("pu45-scratch")
    private static let realLabelsURL = live.appendingPathComponent("video-labels.json")

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

    /// The labels file under test: a scratch copy when the runner redirects it,
    /// else the checkout's own.
    private static var labelsURL: URL {
        if let path = ProcessInfo.processInfo.environment["PUMP_CORPUS_LABELS"] {
            return URL(fileURLWithPath: path)
        }
        return realLabelsURL
    }

    private static func loadJSON(_ url: URL) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
    }

    private static func writeJSON(_ object: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
    }

    /// One record's readings plus its arithmetic labels to a staging file, then
    /// through `scripts/corpus_db.py import-readings`, which writes both tables
    /// in one transaction and dumps the two files. `extraEnv` redirects the
    /// write path to a scratch copy.
    private static func stage(_ stem: String, readings: [String: Any], arithmetic: [String: Any],
                              from: String? = nil, frames: [String]? = nil, env: [String: String]? = nil) throws {
        let staging = stagingDirectory.appendingPathComponent("\(stem).json")
        var staged: [String: Any] = ["record": stem, "readings": readings, "labels": arithmetic]
        // A scoped read replaces only what it read - the frames from `from` on,
        // or exactly `frames` - and the import keeps every other frame's rows.
        if let from { staged["from"] = from }
        if let frames { staged["frames"] = frames }
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: staged, options: [.sortedKeys]).write(to: staging)
        try importReadings(staging, extraEnv: env)
    }

    private static func importReadings(_ staging: URL, extraEnv: [String: String]? = nil) throws {
        let script = PumpReaderTestSupport.repoRoot.appendingPathComponent("scripts/corpus_db.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, "import-readings", staging.path]
        process.currentDirectoryURL = PumpReaderTestSupport.repoRoot
        if let extraEnv {
            process.environment = ProcessInfo.processInfo.environment.merging(extraEnv) { _, new in new }
        }
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

    /// Frames the reader must not regenerate: every `owner` label, and an
    /// `interpolated` label whose nearest owner keyframe on both sides is still
    /// `owner`. An interpolation whose keyframe was changed is not skipped.
    private static func humanSkipped(_ frameNames: [String], labels: [String: Any]) -> Set<String> {
        var skip = Set<String>()
        for (i, name) in frameNames.enumerated() {
            guard let lab = labels[name] as? [String: Any], let source = lab["source"] as? String else { continue }
            if source == "owner" { skip.insert(name); continue }
            guard source == "interpolated" else { continue }
            let before = (0..<i).reversed().contains { index in
                (labels[frameNames[index]] as? [String: Any])?["source"] as? String == "owner"
            }
            let after = ((i + 1)..<frameNames.count).contains { index in
                (labels[frameNames[index]] as? [String: Any])?["source"] as? String == "owner"
            }
            if before && after { skip.insert(name) }
        }
        return skip
    }

    /// One record's reader output: the per-frame readings to pre-fill, the
    /// arithmetic labels for the frames that closed, and the counts for the run
    /// summary.
    private struct ReadResult {
        let readings: [String: Any]
        let arithmetic: [String: Any]
        let closed: Int
        let read: Int
    }

    /// Read every frame the skip set leaves in, and stage a reading per frame
    /// (`closes` plus the lowest cell margin of the total and liters windows)
    /// and an arithmetic label for each closing frame.
    private static func readFrames(stem: String, video: [String: Any], frameNames: [String],
                                   skip: Set<String>) throws -> ReadResult {
        guard let priceText = video["unitPrice"] as? String,
              Double(priceText.replacingOccurrences(of: ",", with: ".")) != nil else {
            return ReadResult(readings: [:], arithmetic: [:], closed: 0, read: 0)
        }
        let trackedURL = live.appendingPathComponent("frames/\(stem)/windows.json")
        guard let tracked = try? JSONSerialization.jsonObject(with: Data(contentsOf: trackedURL)) as? [String: Any],
              let frames = tracked["frames"] as? [String: Any] else {
            return ReadResult(readings: [:], arithmetic: [:], closed: 0, read: 0)
        }
        let model = try PumpSegmentsModel(contentsOf: modelURL)
        let reader = PumpReader(model: model)
        var readings: [String: Any] = [:]
        var arithmetic: [String: Any] = [:]
        var closed = 0, read = 0
        for frameName in frameNames {
            if skip.contains(frameName) { continue }
            guard let frame = frames[frameName] as? [String: Any], let windows = frame["windows"] as? [[String: Any]],
                  // A frame whose quads the owner placed by hand (a tracking anchor)
                  // is human-reviewed; it keeps whatever it has.
                  (frame["verified"] as? Bool) != true,
                  let image = PumpReaderTestSupport.loadRGB(url: live.appendingPathComponent("frames/\(stem)/\(frameName)")) else { continue }
            let windowsIn = windows.compactMap { window -> PumpVideoFrameRead.Window? in
                guard let field = window["field"] as? String,
                      let quad = (window["quad"] as? [[NSNumber]])?.map({ $0.map(\.doubleValue) }) else { return nil }
                return PumpVideoFrameRead.Window(field: field, quad: quad)
            }
            guard let frameRead = PumpVideoFrameRead.read(reader: reader, image: image, windows: windowsIn,
                                                          priceText: priceText) else { continue }
            read += 1
            // Every reading is kept for the annotator's pre-fill; only a closing
            // one is a label.
            readings[frameName] = frameRead.reading
            guard let label = frameRead.label(priceText: priceText) else { continue }
            closed += 1
            arithmetic[frameName] = label
        }
        return ReadResult(readings: readings, arithmetic: arithmetic, closed: closed, read: read)
    }

    private static func copyDatabase(to dest: URL) throws {
        let real = live.deletingLastPathComponent().appendingPathComponent("corpus.sqlite")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["sqlite3", real.path, ".backup \(dest.path)"]
        process.standardError = Pipe()
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ImportError(path: dest.path, status: process.terminationStatus, detail: "sqlite3 .backup failed")
        }
    }

    private static func runPython(_ code: String, env: [String: String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", code]
        process.currentDirectoryURL = PumpReaderTestSupport.repoRoot
        process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        process.standardError = Pipe()
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ImportError(path: "python3 -c", status: process.terminationStatus, detail: "migrate failed")
        }
    }

    /// Replace a record's labels in the scratch database (the reader's write
    /// store) and dump them to the scratch labels file, so the test's scenario
    /// and the reader see the same labels.
    private static func seedLabels(_ stem: String, frames: [String: Any], scratch: URL,
                                   env: [String: String]) throws {
        let scenarioURL = scratch.appendingPathComponent("scenario.json")
        try writeJSON(frames, to: scenarioURL)
        let code = """
        import json, sys
        sys.path.insert(0, 'scripts')
        import corpus_db
        corpus_db.save_labels(\(String(reflecting: stem)), json.load(open(\(String(reflecting: scenarioURL.path)))))
        corpus_db.dump([corpus_db.LABELS_FILE])
        """
        try runPython(code, env: env)
    }

    @Test("every tracked video frame whose reading closes gets its label", .enabled(if: enabled, "PUMP_VIDEO_READ=1"))
    func label() throws {
        let videos = Self.loadJSON(Self.live.appendingPathComponent("videos.json"))
        let labels = Self.loadJSON(Self.labelsURL)
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
                  Double(priceText.replacingOccurrences(of: ",", with: ".")) != nil else { continue }
            let trackedURL = Self.live.appendingPathComponent("frames/\(stem)/windows.json")
            guard let tracked = try? JSONSerialization.jsonObject(with: Data(contentsOf: trackedURL)) as? [String: Any],
                  let frames = tracked["frames"] as? [String: Any] else { continue }
            // `PUMP_VIDEO_READ_FROM=NNN.jpg` reads only that frame and the later
            // ones - the annotator's "retrack and re-read from here".
            let from = ProcessInfo.processInfo.environment["PUMP_VIDEO_READ_FROM"].flatMap { Int($0.dropLast(4)) }
            // `PUMP_VIDEO_READ_FRAMES=014.jpg,015.jpg` reads exactly those - the
            // frames a re-fit actually moved.
            let only = ProcessInfo.processInfo.environment["PUMP_VIDEO_READ_FRAMES"]
                .map { Set($0.split(separator: ",").map(String.init)) }
            let names = frames.keys.sorted { (Int($0.dropLast(4)) ?? 0) < (Int($1.dropLast(4)) ?? 0) }
                .filter { from == nil || (Int($0.dropLast(4)) ?? 0) >= from! }
                .filter { only == nil || only!.contains($0) }
            let existing = labels[stem] as? [String: Any] ?? [:]
            // A frame the owner marked `skipped` shows no display; reading it
            // would label a hand or a glare pass.
            let skip = Self.humanSkipped(names, labels: existing).union(names.filter {
                (frames[$0] as? [String: Any])?["skipped"] as? Bool == true
            })
            let result = try Self.readFrames(stem: stem, video: video, frameNames: names, skip: skip)
            // One staging file per record: readings plus the arithmetic labels
            // the reader would write. `import-readings` keeps owner and
            // surviving interpolated rows.
            try Self.stage(stem, readings: result.readings, arithmetic: result.arithmetic,
                           from: ProcessInfo.processInfo.environment["PUMP_VIDEO_READ_FROM"],
                           frames: only.map { Array($0).sorted() })
            let labelled = Set(existing.keys).union(result.arithmetic.keys)
            summary.append("\(stem.prefix(9)): \(result.closed) of \(result.read) frames closed (\(labelled.count) labelled)")
        }
        for line in summary { print("PU.19 \(line)") }
        #expect(!summary.isEmpty)
    }

    @Test("interpolated frames follow their keyframes across a re-run", .enabled(if: enabled, "PUMP_VIDEO_READ=1"))
    func interpolatedFramesFollowTheirKeyframes() throws {
        guard let only = ProcessInfo.processInfo.environment["PUMP_VIDEO_READ_ONLY"] else {
            print("PU.45: set PUMP_VIDEO_READ_ONLY=<stem> to run the interpolation check")
            return
        }
        let videos = Self.loadJSON(Self.live.appendingPathComponent("videos.json"))
        guard let video = videos[only] as? [String: Any], let priceText = video["unitPrice"] as? String else {
            print("PU.45: no video \(only)"); return
        }
        let trackedURL = Self.live.appendingPathComponent("frames/\(only)/windows.json")
        guard let tracked = try? JSONSerialization.jsonObject(with: Data(contentsOf: trackedURL)) as? [String: Any],
              let frames = tracked["frames"] as? [String: Any] else { print("PU.45: no tracked frames for \(only)"); return }
        let names = frames.keys.sorted { (Int($0.dropLast(4)) ?? 0) < (Int($1.dropLast(4)) ?? 0) }
        guard names.count >= 3 else { print("PU.45: \(only) has fewer than 3 frames"); return }

        // A scratch copy of the database and the labels: this check never writes
        // the checkout's own corpus.
        let scratch = Self.scratchRoot.appendingPathComponent(only)
        try FileManager.default.createDirectory(at: scratch.appendingPathComponent("frames"), withIntermediateDirectories: true)
        let scratchDB = scratch.appendingPathComponent("corpus.sqlite")
        let scratchLabels = scratch.appendingPathComponent("video-labels.json")
        let scratchFrames = scratch.appendingPathComponent("frames")
        try Self.copyDatabase(to: scratchDB)
        let env = ["PUMP_ANNOTATE_DB": scratchDB.path, "PUMP_CORPUS_LABELS": scratchLabels.path,
                   "PUMP_CORPUS_FRAMES": scratchFrames.path]
        try Self.runPython("import sys; sys.path.insert(0, 'scripts'); import corpus_db; corpus_db.migrate()", env: env)

        let real = Self.loadJSON(Self.realLabelsURL)
        var scenario = real[only] as? [String: Any] ?? [:]
        let first = names.first!, last = names.last!
        let middles = Array(names.dropFirst().dropLast())
        scenario[first] = ["unitPrice": priceText, "total": "1.00", "liters": "1.00", "source": "owner"]
        scenario[last] = ["unitPrice": priceText, "total": "9.99", "liters": "9.99", "source": "owner"]
        for middle in middles {
            scenario[middle] = ["unitPrice": priceText, "total": "5.00", "liters": "5.00", "source": "interpolated"]
        }
        try Self.seedLabels(only, frames: scenario, scratch: scratch, env: env)

        // Both keyframes owner: every interpolated frame is skipped, so it survives.
        let skip1 = Self.humanSkipped(names, labels: scenario)
        #expect(Set(middles).isSubset(of: skip1))
        let r1 = try Self.readFrames(stem: only, video: video, frameNames: names, skip: skip1)
        try Self.stage(only, readings: r1.readings, arithmetic: r1.arithmetic, env: env)
        let after1 = Self.loadJSON(scratchLabels)[only] as? [String: Any] ?? [:]
        for middle in middles {
            #expect((after1[middle] as? [String: Any])?["source"] as? String == "interpolated", "\(middle) survived")
        }

        // One keyframe reverted to arithmetic: the middle is no longer bounded by
        // two owners, so it is regenerated (or left unlabelled), never interpolated.
        scenario[last] = ["unitPrice": priceText, "total": "9.99", "liters": "9.99", "source": "arithmetic"]
        try Self.seedLabels(only, frames: scenario, scratch: scratch, env: env)
        let skip2 = Self.humanSkipped(names, labels: scenario)
        #expect(!skip2.contains(middles.first!))
        let r2 = try Self.readFrames(stem: only, video: video, frameNames: names, skip: skip2)
        try Self.stage(only, readings: r2.readings, arithmetic: r2.arithmetic, env: env)
        let after2 = Self.loadJSON(scratchLabels)[only] as? [String: Any] ?? [:]
        // A hand-anchored frame (`verified`) is human-reviewed and skipped by the
        // reader whatever its label; every other middle frame is regenerated.
        let regenerated = middles.filter { (frames[$0] as? [String: Any])?["verified"] as? Bool != true }
        #expect(!regenerated.isEmpty)
        for middle in regenerated {
            #expect((after2[middle] as? [String: Any])?["source"] as? String != "interpolated", "\(middle) regenerated")
        }
        print("PU.45 interpolation: \(middles.count) middle frames survived two owner keyframes and were regenerated after one was reverted")
    }
}
