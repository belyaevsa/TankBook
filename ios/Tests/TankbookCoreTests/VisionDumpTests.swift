import Foundation
import Testing
@testable import TankbookCore

/// Writes what the running Vision reads on named corpus fixtures, one line per
/// OCR line with its box, to `ios/.build/vision-dump/<fixture>.txt` - how a
/// reading that differs between runtimes is looked at. Opt-in:
/// `VISION_DUMP=receipts/receipt-025-...png,receipts/receipt-057-...jpg`
/// (paths under `Spike/ReceiptSpike/fixtures`), run in the simulator for the
/// measured runtime (`scripts/vision-suites.sh VisionDumpTests`).
@Suite("Vision dump")
struct VisionDumpTests {
    @Test("dump the named fixtures' OCR lines",
          .enabled(if: ProcessInfo.processInfo.environment["VISION_DUMP"] != nil, "VISION_DUMP"))
    func dump() async throws {
        let names = (ProcessInfo.processInfo.environment["VISION_DUMP"] ?? "").split(separator: ",").map(String.init)
        let fixtures = PumpReaderTestSupport.repoRoot.appendingPathComponent("Spike/ReceiptSpike/fixtures")
        let out = PumpReaderTestSupport.repoRoot.appendingPathComponent("ios/.build/vision-dump")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for name in names {
            let lines = try await TestOCR.recognizeText(in: fixtures.appendingPathComponent(name),
                                                        languages: ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"])
            let text = lines.map { String(format: "%.3f %.3f  ", $0.midX, $0.midY) + $0.text }.joined(separator: "\n")
            let file = out.appendingPathComponent((name as NSString).lastPathComponent + ".txt")
            try (text + "\n").write(to: file, atomically: true, encoding: .utf8)
        }
        #expect(!names.isEmpty)
    }
}
