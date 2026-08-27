import Foundation
import Testing
@testable import TankbookCore

#if canImport(Vision)
import Vision

// P4.12 - regenerates the committed rules-arm snapshot
// (`Spike/ReceiptSpike/fixtures/vision-ab/rules-*.json`). The snapshot is what the
// offline A/B tests score against, so the suite never depends on Vision or on a
// paid model in CI. Run it by hand when the parser or the corpus changes:
//
//   cd ios && TANKBOOK_WRITE_CORPUS_FILES=1 swift test --filter CorpusABRulesDump
//
// Without the env var it is a no-op, so CI stays fast and never writes files.
@Suite("P4.12 rules-arm snapshot generator (Vision-gated)")
struct CorpusABRulesDumpTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent() // TankbookCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // repo root
    private static let fixturesRoot = repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures")
    private static let abRoot = fixturesRoot.appendingPathComponent("vision-ab")

    private static let languages = ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"]

    @Test func regenerateRulesSnapshot() throws {
        let writing = ProcessInfo.processInfo.environment["TANKBOOK_WRITE_CORPUS_FILES"] == "1"
        guard writing else { return } // CI no-op: the offline tests read the committed files.
        var summaries: [String] = []
        for name in ["receipts", "pump", "fiscal", "screenshots"] {
            let folder = Self.fixturesRoot.appendingPathComponent(name)
            // Numeric-only view of expected: the regenerated snapshot must stay
            // comparable with the committed 2026-08-26 sweep, which carried no
            // fuelKind/currency - see `CorpusScorer.loadExpectedNumericsOnly`.
            let expected = try CorpusScorer.loadExpectedNumericsOnly(folder.appendingPathComponent("expected.csv"))
            let imageURLs = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil
            )
            .filter { CorpusScorer.imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

            let extractor = FuelExtractor()
            var records: [String: ExtractionRecord] = [:]
            for image in imageURLs {
                guard expected[image.lastPathComponent] != nil else { continue }
                let ocrLines = try VisionTextRecognizer.recognizeText(in: image, languages: Self.languages)
                let result = extractor.extract(lines: ocrLines)
                records[image.lastPathComponent] = ExtractionRecord(
                    filename: image.lastPathComponent,
                    liters: result.liters,
                    unitPrice: result.unitPrice,
                    total: result.total
                )
            }

            let scored = CorpusScorer.score(
                name: name,
                images: imageURLs.map(\.lastPathComponent),
                records: records,
                expected: expected
            )
            summaries.append("\(name): \(scored.hits)/\(scored.total)")

            let file = ABResultFile(
                engine: "rules",
                className: name,
                generated: "2026-08-26",
                entries: imageURLs.map(\.lastPathComponent).compactMap { filename in
                    records[filename]
                }
            )
            try FileManager.default.createDirectory(
                at: Self.abRoot, withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let url = Self.abRoot.appendingPathComponent("rules-\(name).json")
            try encoder.encode(file).write(to: url)
        }
        print("RULES ARM (live Vision): \(summaries.joined(separator: ", "))")
    }
}
#endif
