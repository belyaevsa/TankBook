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

    static var fixturesPresent: Bool {
        FileManager.default.fileExists(atPath: windowsURL.path)
    }

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
