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
    static let detectorURL: URL? = {
        let url = repoRoot.appendingPathComponent("ml/pump-reader/.out/det/DigitRows.mlmodel")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }()

    static func makeDetector() -> PumpRowDetector? {
        detectorURL.flatMap { try? PumpRowDetector(contentsOf: $0) }
    }

    static var fixturesPresent: Bool {
        FileManager.default.fileExists(atPath: windowsURL.path)
    }

    /// The fixtures a trained model may be scored on (decision 9,
    /// docs/EXTRACTION.md): `pump/split.csv` names each still `train` or
    /// `heldout`. The heldout set was drawn once (64 of the 211 stills on
    /// 2026-09-19) and is frozen; every still added since is training
    /// material, so a fixture absent from the file is `train`. The
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

    static func isHeldout(_ name: String) -> Bool { split[name] == "heldout" }

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
}

extension Trait where Self == ConditionTrait {
    static var pumpFixturesPresent: ConditionTrait {
        .enabled(if: PumpReaderTestSupport.fixturesPresent,
                 Comment(rawValue: "pump windows.json fixture corpus is not checked out"))
    }
}
