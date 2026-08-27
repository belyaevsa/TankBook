import Foundation
import Testing
@testable import TankbookCore

// P4.13 - regenerates the committed PaddleOCR result + variance files from the
// raw sweep output (`vision-ab/.raw/`). The raw output carries PaddleOCR's PIXEL
// boxes; this dump normalises them to Vision space (via `PaddleOCRCoordinate`)
// and runs the SAME `FuelExtractor` as the rules arm, then writes:
//
//   vision-ab/paddleocr-a-<class>.json   (result: fields, engine="paddleocr-a")
//   vision-ab/paddleocr-b-<class>.json   (result: fields, engine="paddleocr-b")
//   vision-ab/paddleocr-a-runs-<class>.json  (three runs + latency)
//   vision-ab/paddleocr-b-runs-<class>.json
//
// Run by hand after a sweep; a no-op otherwise (CI stays fast and never writes):
//
//   cd ios && TANKBOOK_WRITE_CORPUS_FILES=1 swift test --filter PaddleOCRDump
@Suite("P4.13 PaddleOCR result generator (env-gated)")
struct PaddleOCRDumpTests {

    private static let classes = ["receipts", "pump", "fiscal", "screenshots"]

    @Test func regeneratePaddleOCRResults() throws {
        let writing = ProcessInfo.processInfo.environment["TANKBOOK_WRITE_CORPUS_FILES"] == "1"
        guard writing else { return }

        for arm in ["paddleocr-a", "paddleocr-b"] {
            var summaries: [String] = []
            var wroteAny = false
            for name in Self.classes {
                let rawURL = Self.rawURL(arm: arm, cls: name)
                guard FileManager.default.fileExists(atPath: rawURL.path) else { continue }
                wroteAny = true
                let rawFile = try Self.loadRaw(arm: arm, cls: name)
                let folder = PaddleOCRCorpus.fixturesRoot.appendingPathComponent(name)
                // Numeric-only view of expected: the regenerated snapshot must
                // stay comparable with the committed 2026-08-26 sweep, which
                // carried no fuelKind/currency (`CorpusScorer.loadExpectedNumericsOnly`).
                let expected = try CorpusScorer.loadExpectedNumericsOnly(folder.appendingPathComponent("expected.csv"))
                let images = try CorpusScorer.imageFilenames(in: folder)

                var records: [String: ExtractionRecord] = [:]
                var variance: [String: PaddleOCRVarianceEntry] = [:]

                for entry in rawFile.entries {
                    let runs = entry.runs.compactMap { run -> PaddleOCRRunRecord? in
                        let extraction = arm == "paddleocr-a"
                            ? PaddleOCRCorpus.extractArmA(run)
                            : PaddleOCRCorpus.extractArmB(run)
                        return PaddleOCRRunRecord(
                            liters: extraction.liters,
                            unitPrice: extraction.unitPrice.map(\.corpusBoundaryDouble),
                            total: extraction.total.map(\.corpusBoundaryDouble),
                            latencySeconds: run.latencySeconds
                        )
                    }
                    variance[entry.filename] = PaddleOCRVarianceEntry(
                        filename: entry.filename, runs: runs
                    )
                    let first = runs.first
                    let medianLatency = Self.median(runs.compactMap(\.latencySeconds))
                    records[entry.filename] = ExtractionRecord(
                        filename: entry.filename,
                        liters: first?.liters,
                        unitPrice: first?.unitPrice,
                        total: first?.total,
                        latencySeconds: medianLatency,
                        error: entry.error
                    )
                }

                let scored = CorpusScorer.score(
                    name: name, images: images, records: records, expected: expected
                )
                summaries.append("\(name): \(scored.hits)/\(scored.total)")

                try Self.writeResult(arm: arm, cls: name, records: records, images: images)
                try Self.writeVariance(arm: arm, cls: name, variance: variance, images: images)
            }
            if wroteAny {
                print("\(arm.uppercased()): \(summaries.joined(separator: ", "))")
            }
        }
    }

    // MARK: - Helpers

    private static func rawURL(arm: String, cls: String) -> URL {
        PaddleOCRCorpus.abRoot
            .appendingPathComponent(".raw")
            .appendingPathComponent("\(arm)-\(cls).json")
    }

    private static func loadRaw(arm: String, cls: String) throws -> PaddleOCRRawFile {
        try JSONDecoder().decode(PaddleOCRRawFile.self, from: Data(contentsOf: rawURL(arm: arm, cls: cls)))
    }

    private static func writeResult(
        arm: String, cls: String, records: [String: ExtractionRecord], images: [String]
    ) throws {
        let file = ABResultFile(
            engine: arm,
            className: cls,
            generated: "2026-08-26",
            entries: images.map { records[$0]! }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: PaddleOCRCorpus.abRoot.appendingPathComponent("\(arm)-\(cls).json"))
    }

    private static func writeVariance(
        arm: String, cls: String, variance: [String: PaddleOCRVarianceEntry], images: [String]
    ) throws {
        let file = PaddleOCRVarianceFile(
            engine: arm,
            className: cls,
            generated: "2026-08-26",
            entries: images.map { variance[$0]! }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(
            to: PaddleOCRCorpus.abRoot.appendingPathComponent("\(arm)-runs-\(cls).json")
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
