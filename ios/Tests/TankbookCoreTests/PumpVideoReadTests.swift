import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// Labels for the running-display videos (`pump-live/videos.json`): every
/// tracked frame's total and liters windows are read by the reader with the
/// video's constant price, and a frame's reading becomes its label only when
/// `total == round(liters x price)` to the cent - the display's own arithmetic
/// is the oracle, no annotation exists. Written to
/// `pump-live/video-labels.json` (committed) with `source: "arithmetic"`; the
/// product owner's corrections in the annotator overwrite entries with
/// `source: "owner"` and are never touched by a re-run; nor is a video marked
/// `reviewed` in `videos.json` or a frame the owner anchored by hand
/// (`verified` in the tracked `windows.json`).
///
/// Opt-in (`PUMP_VIDEO_READ=1`; `PUMP_VIDEO_READ_ONLY=video-002` for one clip):
/// four thousand frames through the reader.
@Suite("PU.19 video labels by arithmetic")
struct PumpVideoReadTests {
    private static var enabled: Bool { ProcessInfo.processInfo.environment["PUMP_VIDEO_READ"] == "1" }
    private static let live = PumpReaderTestSupport.repoRoot.appendingPathComponent("Spike/ReceiptSpike/fixtures/pump-live")
    private static let modelURL = PumpReaderTestSupport.repoRoot.appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")

    @Test("every tracked video frame whose reading closes gets its label", .enabled(if: enabled, "PUMP_VIDEO_READ=1"))
    func label() throws {
        let model = try PumpSegmentsModel(contentsOf: Self.modelURL)
        let reader = PumpReader(model: model)
        let videos = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.live.appendingPathComponent("videos.json"))) as? [String: Any] ?? [:]
        let labelsURL = Self.live.appendingPathComponent("video-labels.json")
        var labels = (try? JSONSerialization.jsonObject(with: Data(contentsOf: labelsURL)) as? [String: Any]) ?? [:]
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
            var perVideo = labels[stem] as? [String: Any] ?? [:]
            var readings: [String: Any] = [:]
            var closed = 0, read = 0
            for (frameName, frameValue) in frames.sorted(by: { Int($0.key.dropLast(4)) ?? 0 < Int($1.key.dropLast(4)) ?? 0 }) {
                if let existing = perVideo[frameName] as? [String: Any], existing["source"] as? String == "owner" { continue }
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
                perVideo[frameName] = ["total": t, "liters": l, "unitPrice": priceText, "source": "arithmetic"]
            }
            labels[stem] = perVideo
            let readingsData = try JSONSerialization.data(withJSONObject: readings, options: [.sortedKeys])
            try readingsData.write(to: Self.live.appendingPathComponent("frames/\(stem)/readings.json"))
            summary.append("\(stem.prefix(9)): \(closed) of \(read) frames closed (\(perVideo.count) labelled)")
        }
        let data = try JSONSerialization.data(withJSONObject: labels, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: labelsURL)
        for line in summary { print("PU.19 \(line)") }
        #expect(!summary.isEmpty)
    }
}
