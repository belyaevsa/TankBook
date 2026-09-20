import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// PU.34b: where the decimal mark is lost. For the clips the row carries
/// (video-002/003/004), every tenth owner-labelled frame is read with its owner
/// quads and the mark the owner's label asserts is compared with the mark the
/// slicer places and the mark the classifier fires. Prints per-clip
/// recall/precision for both detectors and, on a slicer miss, the band rows,
/// threshold and the truth cell's column profile.
///
/// Opt-in (`PUMP_MARK_DIAG=1`), prints only: a reading aid, not a check.
@Suite("PU.34b decimal mark diagnostic")
struct PumpMarkDiagnosticTests {
    private static var enabled: Bool { ProcessInfo.processInfo.environment["PUMP_MARK_DIAG"] == "1" }
    private static let live = PumpReaderTestSupport.repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures/pump-live")
    private static let modelURL = PumpReaderTestSupport.repoRoot
        .appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")

    private static let clips = [
        "video-002-wayne-running-display-slow-fill-ru",
        "video-003-wayne-circlek-fill-ends-ee",
        "video-004-gilbarco-veederroot-running-display-fill-ends-som-kg"
    ]

    /// One owner-labelled frame: the clip it belongs to, its name, the owner's
    /// per-field text, and its tracked windows.
    private struct Frame {
        let clip: String
        let name: String
        let label: [String: Any]
        let tracked: [String: Any]
    }

    private struct Score {
        var truePositive = 0
        var falsePositive = 0
        var falseNegative = 0
        var truthPresent = 0
        var recall: Double { truthPresent > 0 ? Double(truePositive) / Double(truthPresent) : 0 }
        var precision: Double {
            let predicted = truePositive + falsePositive
            return predicted > 0 ? Double(truePositive) / Double(predicted) : 0
        }
        var text: String {
            String(format: "%d/%d recall %.2f, %d/%d precision %.2f",
                   truePositive, truthPresent, recall, truePositive, truePositive + falsePositive, precision)
        }
    }

    @Test("the slicer and classifier mark against the owner labels",
          .enabled(if: enabled, "PUMP_MARK_DIAG=1"))
    func diagnose() throws {
        let model = try PumpSegmentsModel(contentsOf: Self.modelURL)
        let labels = try JSONSerialization.jsonObject(
            with: Data(contentsOf: Self.live.appendingPathComponent("video-labels.json"))) as? [String: Any] ?? [:]
        for clip in Self.clips {
            try Self.diagnose(clip: clip, labels: labels, model: model)
        }
    }

    private static func diagnose(clip: String, labels: [String: Any], model: PumpSegmentsModel) throws {
        guard let perClip = labels[clip] as? [String: Any],
              let tracked = try? JSONSerialization.jsonObject(
                with: Data(contentsOf: live.appendingPathComponent("frames/\(clip)/windows.json"))) as? [String: Any],
              let frames = tracked["frames"] as? [String: Any] else { return }
        let ownerFrames = frames.keys
            .filter { (perClip[$0] as? [String: Any])?["source"] as? String == "owner" }
            .sorted { frameNumber($0) < frameNumber($1) }
        var slicer = Score(), classifier = Score()
        var lines: [String] = []
        for (position, frameName) in ownerFrames.enumerated() where position % 10 == 0 {
            let frame = Frame(clip: clip, name: frameName, label: perClip[frameName] as? [String: Any] ?? [:],
                              tracked: frames[frameName] as? [String: Any] ?? [:])
            lines += windows(frame: frame, model: model, slicer: &slicer, classifier: &classifier)
        }
        print("PU.34b \(clip.prefix(9)): slicer \(slicer.text); classifier \(classifier.text)")
        for line in lines { print(line) }
    }

    private static func windows(
        frame: Frame, model: PumpSegmentsModel, slicer: inout Score, classifier: inout Score
    ) -> [String] {
        guard let windows = frame.tracked["windows"] as? [[String: Any]],
              let image = PumpReaderTestSupport.loadRGB(
                url: live.appendingPathComponent("frames/\(frame.clip)/\(frame.name)")) else { return [] }
        var lines: [String] = []
        for window in windows {
            guard let field = window["field"] as? String, let text = frame.label[field] as? String, !text.isEmpty,
                  let quad = (window["quad"] as? [[NSNumber]])?.map({ $0.map(\.doubleValue) }),
                  let strip = strip(image: image, quad: quad) else { continue }
            let stripRGB = PumpQuadWarp.rgbImage(from: strip)
            let gray = stripRGB.grayscale()
            let diag = PumpGlyphSlicer.diagnostics(gray)
            let cells = diag?.cells ?? []
            let truth = PumpReaderTestSupport.dpCellIndex(text)
            let slicerIndex = cells.firstIndex(where: \.hasDecimalPoint)
            let classifierIndex = mark(model: model, stripRGB: stripRGB, cells: cells)
            tally(&slicer, truth: truth, predicted: slicerIndex)
            tally(&classifier, truth: classifierTruthIndex(truth: truth, cells: cells), predicted: classifierIndex)
            lines.append("    \(frame.name) \(field) '\(text)' truth \(truth.map(String.init) ?? "-") "
                + "slicer \(slicerIndex.map(String.init) ?? "-") classifier \(classifierIndex.map(String.init) ?? "-") "
                + (truth == slicerIndex ? "ok" : "MISS"))
            if truth != slicerIndex, let diag, let truth, truth < cells.count {
                lines += missLines(diag: diag, cells: cells, truth: truth)
            }
        }
        return lines
    }

    private static func strip(image: PumpRGBImage, quad: [[Double]]) -> CGImage? {
        let pixels = PumpQuadWarp.readingOrder(
            PumpReaderTestSupport.quadPixels(quad, width: image.width, height: image.height), rotationCW: 0)
        return PumpQuadWarp.warpToStrip(rgb: image, quad: pixels, stripHeight: PumpReader.stripHeight)
    }

    /// The classifier's own bit (`probabilities[7]`), without the slicer's mark
    /// ORed in by `PumpReader.read`.
    private static func mark(model: PumpSegmentsModel, stripRGB: PumpRGBImage, cells: [GlyphCell]) -> Int? {
        var cellIndex = -1
        for cell in cells where !cell.isBlank {
            cellIndex += 1
            guard let probabilities = try? PumpReader.averaged(
                model: model, crops: PumpReader.cropCell(stripRGB, rect: cell.rect)) else { continue }
            if probabilities.count > 7, probabilities[7] >= 0.5 { return cellIndex }
        }
        return nil
    }

    private static func missLines(diag: PumpGlyphSlicer.Diagnostics, cells: [GlyphCell], truth: Int) -> [String] {
        var lines = ["      band \(diag.bandTop)-\(diag.bandBottom) h \(diag.bandHeight) pitch \(diag.pitch) "
            + "threshold \(String(format: "%.2f", diag.threshold))"]
        // The mark sits in the gap inside the truth cell's own pitch slot; the
        // cell's profile shows the stroke edges and the dot's bump between them.
        let cell = cells[truth]
        let x0 = max(0, Int(cell.rect.minX))
        let x1 = min(diag.width - 1, Int(cell.rect.maxX) - 1)
        if x1 > x0 {
            lines.append("      cell \(truth) x \(x0)-\(x1): "
                + (x0...x1).map { String(format: "%.1f", diag.profile[$0]) }.joined(separator: " "))
        }
        return lines
    }

    /// The truth index in the classifier's cell space: `PumpReader.read` drops
    /// blank cells, so a blank before the mark shifts the index left by one.
    private static func classifierTruthIndex(truth: Int?, cells: [GlyphCell]) -> Int? {
        guard let truth else { return nil }
        var seen = 0
        for index in 0...min(truth, cells.count - 1) where !cells[index].isBlank { seen += 1 }
        return seen - 1
    }

    private static func tally(_ score: inout Score, truth: Int?, predicted: Int?) {
        if truth != nil { score.truthPresent += 1 }
        switch (truth, predicted) {
        case let (want?, got?) where want == got: score.truePositive += 1
        case (_?, _?): score.falsePositive += 1; score.falseNegative += 1
        case (nil, _?): score.falsePositive += 1
        case (_?, nil): score.falseNegative += 1
        default: break
        }
    }

    private static func frameNumber(_ name: String) -> Int { Int(name.dropLast(4)) ?? 0 }
}
