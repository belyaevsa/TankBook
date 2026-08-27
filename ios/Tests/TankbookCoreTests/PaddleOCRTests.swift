import Foundation
import Testing
@testable import TankbookCore

// P4.13 - offline tests for the PaddleOCR arms. No Docker, no model call: the
// committed result files are scored here with the SAME `CorpusScorer` (and the
// same 0.005 tolerance) as the rules and DeepSeek arms, so no arm can be
// flattered by a subtly different comparison.

@Suite("P4.13 PaddleOCR arms - offline scoring")
struct PaddleOCRTests {

    private static let classes = ["receipts", "pump", "fiscal", "screenshots"]

    // MARK: - 1. Arm A shares the one scorer, at the same tolerance

    @Test("Arm A (PP-OCRv5 -> FuelExtractor) scores over the committed sweep, per class")
    func armAScores() throws {
        #expect(try Self.scoreClass("receipts", engine: "paddleocr-a") == ScoredClass(name: "receipts", hits: 29, total: 96))
        #expect(try Self.scoreClass("pump", engine: "paddleocr-a") == ScoredClass(name: "pump", hits: 2, total: 46))
        #expect(try Self.scoreClass("fiscal", engine: "paddleocr-a") == ScoredClass(name: "fiscal", hits: 1, total: 3))
        #expect(try Self.scoreClass("screenshots", engine: "paddleocr-a") == ScoredClass(name: "screenshots", hits: 7, total: 24))
    }

    // MARK: - 2. Coverage: no image silently skipped

    @Test("every image is either swept by Arm A or a declared post-sweep addition")
    func armACoversEveryImage() throws {
        for cls in Self.classes {
            let folder = PaddleOCRCorpus.fixturesRoot.appendingPathComponent(cls)
            let images = try CorpusScorer.imageFilenames(in: folder)
            let file = try CorpusScorer.loadABResultFile(
                PaddleOCRCorpus.abRoot.appendingPathComponent("paddleocr-a-\(cls).json")
            )
            let declared = PostSweepCorpusAdditions.forClass(cls)
            for image in images where !declared.contains(image) {
                #expect(file.recordsByFilename[image] != nil, "\(cls)/\(image) has no Arm A record")
            }
            for recorded in file.recordsByFilename.keys {
                #expect(images.contains(recorded), "\(cls)/\(recorded) has an Arm A record but no image")
            }
        }
    }

    // MARK: - 3 & 4. Scorer semantics, re-asserted on this arm

    @Test("an empty expected field is skipped, never scored as a miss")
    func emptyExpectedFieldIsSkipped() {
        // receipt-034 prints a zero price (contract fuel card); its unitPrice is
        // empty in ground truth, so a nil from the engine is a skip, not a miss.
        let expected = ["x.jpg": ExpectedRow(liters: 30.61, unitPrice: nil, total: nil)]
        let records = ["x.jpg": ExtractionRecord(filename: "x.jpg", liters: 30.61, unitPrice: 0.0, total: 0.0)]
        let scored = CorpusScorer.score(name: "x", images: ["x.jpg"], records: records, expected: expected)
        #expect(scored.total == 1, "only liters is scored; unitPrice/total are empty")
        #expect(scored.hits == 1)
    }

    @Test("a recorded error counts as a miss, never as a skip")
    func recordedErrorCountsAsAMiss() {
        let expected = ["a.jpg": ExpectedRow(liters: 10.0, unitPrice: 2.0, total: 20.0)]
        let records = ["a.jpg": ExtractionRecord(filename: "a.jpg", liters: nil, unitPrice: nil, total: nil, error: "HTTP 500")]
        let scored = CorpusScorer.score(name: "x", images: ["a.jpg"], records: records, expected: expected)
        #expect(scored.total == 3)
        #expect(scored.hits == 0)
    }

    // MARK: - 5. Determinism: the variance is pinned, not averaged away

    /// PaddleOCR's OCR is byte-identical across the three runs (the sweep writes
    /// three runs and the Swift dump scores them independently). The ONLY images
    /// whose three runs disagree are the three receipts where the *parser's*
    /// total-finder ties - a pre-existing `FuelExtractor.modal` non-determinism
    /// (Swift `Dictionary(grouping:)` iteration order) that PaddleOCR's label
    /// misreads expose (`ИТОГ` read as `НТОГ` drops the primary label, leaving
    /// two payment candidates tied). Asserting exactly these three, and no
    /// other, pins that: the variance is the parser, not the reader.
    @Test("Arm A: only the three parser-tie receipts disagree across runs")
    func armAVarianceIsTheParserNotTheReader() throws {
        let expectedDisagreement: Set<String> = [
            "receipt-021-web-2018-ru.jpg",
            "receipt-026-kedr-feodosia-95-ru.png",
            "receipt-029-lukoil-dashboard-100-2021-ru.png",
        ]
        for cls in Self.classes {
            let file = try Self.loadVariance("paddleocr-a", cls)
            let disagreeing = file.disagreeingFilenames(tolerance: CorpusScorer.tolerance)
            if cls == "receipts" {
                #expect(Set(disagreeing) == expectedDisagreement, "\(cls) disagreement: \(disagreeing)")
            } else {
                #expect(disagreeing.isEmpty, "\(cls) must be deterministic; got \(disagreeing)")
            }
        }
    }

    // MARK: - 6. Latency against the 3 s device budget

    /// Median and max are recorded per class. On this CPU-only host the median
    /// is 4.5-8.4 s and the max 6.0-21.0 s - every class above the 3 s budget,
    /// and in the same band as the cloud arm (6.5-8.3 s median). Self-hosting
    /// does not buy latency back without a GPU.
    @Test("latency is recorded for every class and every run")
    func latencyRecordedPerClass() throws {
        for cls in Self.classes {
            let file = try Self.loadVariance("paddleocr-a", cls)
            let latencies = file.entries.flatMap { $0.runs.compactMap(\.latencySeconds) }
            #expect(latencies.count == file.entries.count * 3, "\(cls) must record three latencies per image")
            #expect(latencies.allSatisfy { $0 > 0 })
        }
    }

    // MARK: - Helpers

    private static func scoreClass(_ name: String, engine: String) throws -> ScoredClass {
        let folder = PaddleOCRCorpus.fixturesRoot.appendingPathComponent(name)
        let expected = try CorpusScorer.loadExpected(folder.appendingPathComponent("expected.csv"))
        let file = try CorpusScorer.loadABResultFile(
            PaddleOCRCorpus.abRoot.appendingPathComponent("\(engine)-\(name).json")
        )
        // Scored over the sweep's own snapshot, not the live folder - the same
        // frozen-artefact rule as the DeepSeek arm (`CorpusScorer.sweptImages`).
        let images = try CorpusScorer.sweptImages(in: folder, coveredBy: file)
        return CorpusScorer.score(
            name: name, images: images, records: file.recordsByFilename, expected: expected
        )
    }

    private static func loadVariance(_ engine: String, _ cls: String) throws -> PaddleOCRVarianceFile {
        let url = PaddleOCRCorpus.abRoot.appendingPathComponent("\(engine)-runs-\(cls).json")
        return try JSONDecoder().decode(PaddleOCRVarianceFile.self, from: Data(contentsOf: url))
    }
}
