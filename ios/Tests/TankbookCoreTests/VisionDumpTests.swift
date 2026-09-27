import Foundation
import Testing
@testable import TankbookCore

/// Writes what the running Vision reads on named corpus fixtures, one line per
/// OCR line - `minX minY width height  text`, the normalised box - to
/// `ios/.build/vision-dump/<fixture>.txt`: how a reading that differs between
/// runtimes is looked at, and what an extractor change is replayed against.
/// Opt-in: `VISION_DUMP=receipts/receipt-025-...png,receipts/receipt-057-...jpg`
/// or `VISION_DUMP=receipts/*` for a whole class (paths under
/// `Spike/ReceiptSpike/fixtures`), run in the simulator for the
/// measured runtime (`scripts/vision-suites.sh VisionDumpTests`).
@Suite("Vision dump")
struct VisionDumpTests {
    @Test("dump the named fixtures' OCR lines",
          .enabled(if: ProcessInfo.processInfo.environment["VISION_DUMP"] != nil, "VISION_DUMP"))
    func dump() async throws {
        let fixtures = PumpReaderTestSupport.repoRoot.appendingPathComponent("Spike/ReceiptSpike/fixtures")
        let names = (ProcessInfo.processInfo.environment["VISION_DUMP"] ?? "").split(separator: ",")
            .flatMap { entry -> [String] in
                guard entry.hasSuffix("/*") else { return [String(entry)] }
                let folder = String(entry.dropLast(2))
                let files = (try? FileManager.default.contentsOfDirectory(
                    atPath: fixtures.appendingPathComponent(folder).path)) ?? []
                return files.filter { CorpusScorer.imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
                    .sorted().map { "\(folder)/\($0)" }
            }
        let out = PumpReaderTestSupport.repoRoot.appendingPathComponent("ios/.build/vision-dump")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for name in names {
            let lines = try await TestOCR.recognizeText(in: fixtures.appendingPathComponent(name),
                                                        languages: ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"])
            let text = lines.map { line in
                let box = line.boundingBox
                return String(format: "%.4f %.4f %.4f %.4f  ", box.minX, box.minY, box.width, box.height) + line.text
            }.joined(separator: "\n")
            let file = out.appendingPathComponent((name as NSString).lastPathComponent + ".txt")
            try (text + "\n").write(to: file, atomically: true, encoding: .utf8)
        }
        #expect(!names.isEmpty)
    }
}
