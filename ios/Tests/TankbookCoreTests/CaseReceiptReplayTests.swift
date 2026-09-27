import Foundation
import Testing
@testable import TankbookCore

/// Replays a debug case's receipt scans through `FuelExtractor` on this tree:
/// the phone's own OCR lines from each `scan-N-record.json`, so a parser change
/// can be judged against what the device actually read, without Vision.
/// Opt-in, and only on the owner's machine - a case is user content and never
/// enters the repo (`.claude/skills/debug-case/SKILL.md`):
///
///   CASE_DIR=~/.cache/tankbook/cases/<id> swift test --filter CaseReceiptReplay
@Suite("Debug case receipt replay")
struct CaseReceiptReplayTests {
    @Test("replay a case's OCR lines", .enabled(if: ProcessInfo.processInfo.environment["CASE_DIR"] != nil))
    func replay() throws {
        let dir = try #require(ProcessInfo.processInfo.environment["CASE_DIR"])
        let extractor = FuelExtractor(bandProvider: DefaultFuelPriceBandProvider(pack: try FuelPriceBandStore.bundledPack()))
        for index in 1...20 {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("scan-\(index)-record.json")
            guard let data = try? Data(contentsOf: url),
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = root["ocrLines"] as? [[String: Any]] else { continue }
            let lines = raw.map { line -> OCRLine in
                let box = (line["box"] as? [Double]) ?? [0, 0, 0, 0]
                return OCRLine(text: line["text"] as? String ?? "",
                               confidence: Float(line["confidence"] as? Double ?? 1),
                               boundingBox: CGRect(x: box[0], y: box[1], width: box[2], height: box[3]))
            }
            let read = extractor.extract(lines: lines)
            func text(_ value: CustomStringConvertible?) -> String { value.map(\.description) ?? "-" }
            print("scan \(index): liters \(text(read.liters)) price \(text(read.unitPrice)) "
                  + "total \(text(read.total)) crossCheck \(read.crossCheck)")
        }
    }
}
