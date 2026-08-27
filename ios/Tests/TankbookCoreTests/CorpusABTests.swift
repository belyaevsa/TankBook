import Foundation
import Testing
@testable import TankbookCore

// P4.12 - the offline A/B: scores the committed rules and LLM result files with
// the SAME `CorpusScorer`, and asserts the two named failure modes as cases
// rather than averaging them away. No Vision, no network, no model call: the
// suite stays deterministic and CI never pays for or depends on the sweep.

@Suite("P4.12 corpus A/B - offline scoring")
struct CorpusABTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent() // TankbookCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // repo root
    private static let fixturesRoot = repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures")
    private static let abRoot = fixturesRoot.appendingPathComponent("vision-ab")

    private static let classes = ["receipts", "pump", "fiscal", "screenshots"]

    // MARK: - Loading / scoring helpers

    private static func scoreClass(_ name: String, engine: String) throws -> ScoredClass {
        let folder = fixturesRoot.appendingPathComponent(name)
        let expected = try CorpusScorer.loadExpected(folder.appendingPathComponent("expected.csv"))
        let file = try CorpusScorer.loadABResultFile(
            abRoot.appendingPathComponent("\(engine)-\(name).json")
        )
        // Scored over the sweep's own snapshot, not the live folder - see
        // `CorpusScorer.sweptImages`. The pinned totals below are what keeps a
        // missing record visible.
        let images = try CorpusScorer.sweptImages(in: folder, coveredBy: file)
        return CorpusScorer.score(
            name: name, images: images, records: file.recordsByFilename, expected: expected
        )
    }

    private static func llmEntry(_ name: String, in cls: String) throws -> ExtractionRecord {
        let file = try CorpusScorer.loadABResultFile(
            abRoot.appendingPathComponent("llm-\(cls).json")
        )
        return try #require(file.recordsByFilename[name])
    }

    // MARK: - 1. The two arms share one scorer

    @Test("the rules arm scores identically to the live AccuracyRatchet run")
    func rulesArmMatchesTheLiveRatchet() throws {
        #expect(try Self.scoreClass("receipts", engine: "rules") == ScoredClass(name: "receipts", hits: 46, total: 96))
        #expect(try Self.scoreClass("pump", engine: "rules") == ScoredClass(name: "pump", hits: 1, total: 46))
        #expect(try Self.scoreClass("fiscal", engine: "rules") == ScoredClass(name: "fiscal", hits: 1, total: 3))
        #expect(
            try Self.scoreClass("screenshots", engine: "rules")
                == ScoredClass(name: "screenshots", hits: 7, total: 24)
        )
    }

    @Test("the LLM arm scores over the committed sweep, per class")
    func llmArmScores() throws {
        #expect(try Self.scoreClass("receipts", engine: "llm") == ScoredClass(name: "receipts", hits: 84, total: 96))
        #expect(try Self.scoreClass("pump", engine: "llm") == ScoredClass(name: "pump", hits: 31, total: 46))
        #expect(try Self.scoreClass("fiscal", engine: "llm") == ScoredClass(name: "fiscal", hits: 2, total: 3))
        #expect(
            try Self.scoreClass("screenshots", engine: "llm")
                == ScoredClass(name: "screenshots", hits: 22, total: 24)
        )
    }

    /// A silently skipped image inflates the score. Every live image must be
    /// either covered by the sweep or **declared** as a post-sweep addition -
    /// an image that is neither is the silent skip this test exists to catch.
    @Test("every image is either swept by the LLM arm or a declared post-sweep addition")
    func llmSweepCoveredEveryImage() throws {
        for cls in Self.classes {
            let folder = Self.fixturesRoot.appendingPathComponent(cls)
            let images = try CorpusScorer.imageFilenames(in: folder)
            let file = try CorpusScorer.loadABResultFile(
                Self.abRoot.appendingPathComponent("llm-\(cls).json")
            )
            let declared = PostSweepCorpusAdditions.forClass(cls)
            for image in images where !declared.contains(image) {
                #expect(file.recordsByFilename[image] != nil, "\(cls)/\(image) has no LLM record")
            }
            // The other direction: a record for an image that no longer exists
            // means a fixture was renamed or deleted under the frozen sweep.
            for recorded in file.recordsByFilename.keys {
                #expect(images.contains(recorded), "\(cls)/\(recorded) has an LLM record but no image")
            }
        }
    }

    // MARK: - 2 & 3. The two named failure modes, asserted - not averaged away

    /// `receipt-035` prints `70.44 X 39.000` (price-first). The model read the
    /// volume/price pair swapped, and the arithmetic cross-check passes anyway,
    /// because `a x b == b x a`. A confident swap is worse than the parser's nil
    /// (hard rule 13).
    @Test("receipt-035: the model swaps volume and price, and the cross-check passes")
    func receipt035SwapSurvivesTheCrossCheck() throws {
        let record = try Self.llmEntry("receipt-035-gdrive95-fuelcard-priced-ru.jpeg", in: "receipts")
        let liters = try #require(record.liters)
        let unitPrice = try #require(record.unitPrice)
        let total = try #require(record.total)

        // Ground truth: 39.000 L at 70.44 = 2747.16. The model returned it the
        // other way round.
        #expect(abs(liters - 70.44) < 0.005)
        #expect(abs(unitPrice - 39.0) < 0.005)
        #expect(abs(total - 2747.16) < 0.005)
        // The recorded pair is the swap of ground truth, not a match.
        #expect(abs(liters - 39.000) >= 0.005)
        #expect(abs(unitPrice - 70.44) >= 0.005)

        let extraction = FuelExtraction(liters: liters, unitPrice: unitPrice, total: total)
        #expect(extraction.crossCheckPassed, "the swap must pass the cross-check - that is the trap")
    }

    /// The decimal-separator loss (a clean factor-of-ten shift) did not land on
    /// `pump-005` in this committed sweep - it landed on the zero-padded
    /// `pump-009`. The failure is the same class and the cross-check is just as
    /// blind: `400 x 50.95 = 20380` is exactly as self-consistent as
    /// `40 x 50.95 = 2038`. See EXTRACTION.md for the determinism note.
    @Test("pump-009: the model shifts by a factor of ten, and the cross-check passes")
    func pump009DecimalShiftSurvivesTheCrossCheck() throws {
        let record = try Self.llmEntry("pump-009-gilbarco-zero-padded-ru.png", in: "pump")
        let liters = try #require(record.liters)
        let unitPrice = try #require(record.unitPrice)
        let total = try #require(record.total)

        // Ground truth 40.00 L x 50.95 = 2038.00. Recorded is a clean 10x shift
        // on both liters and total, with the price intact.
        #expect(abs(liters - 400.0) < 0.005)
        #expect(abs(unitPrice - 50.95) < 0.005)
        #expect(abs(total - 20380.0) < 0.005)
        #expect(abs(liters - 40.00 * 10) < 0.005)
        #expect(abs(total - 2038.00 * 10) < 0.005)

        let extraction = FuelExtraction(liters: liters, unitPrice: unitPrice, total: total)
        #expect(extraction.crossCheckPassed, "the shift must pass the cross-check - scale-invariant")
    }

    /// The probe of 2026-08-26 recorded the decimal shift on `pump-005`. In this
    /// committed sweep the model read it exactly - three times in a row. The
    /// model is stochastic: the failure mode is real and recurring, but which
    /// fixture it lands on is not stable. That is itself the finding - a reader
    /// you cannot trust to be consistent cannot be trusted at all.
    @Test("pump-005: the probe's shift did not reproduce; the model read it exactly")
    func pump005ReadsCorrectlyInThisSweep() throws {
        let record = try Self.llmEntry("pump-005-dresser-wayne-four-prices-ru.png", in: "pump")
        #expect(abs((record.liters ?? 0) - 87.92) < 0.005)
        #expect(abs((record.unitPrice ?? 0) - 52.56) < 0.005)
        #expect(abs((record.total ?? 0) - 4621.08) < 0.005)
    }

    // MARK: - 4 & 5. Scorer semantics the sweep must not flatter itself with

    @Test("an empty expected field is skipped, never scored as a miss")
    func emptyExpectedFieldIsSkipped() {
        let expected = [
            "x.jpg": ExpectedRow(liters: 10.0, unitPrice: nil, total: 100.0)
        ]
        let records = [
            "x.jpg": ExtractionRecord(filename: "x.jpg", liters: 10.0, unitPrice: 5.0, total: nil)
        ]
        let scored = CorpusScorer.score(name: "x", images: ["x.jpg"], records: records, expected: expected)
        // unitPrice is empty in ground truth, so only liters and total are scored.
        #expect(scored.total == 2)
        #expect(scored.hits == 1) // liters hits, total misses - the empty field is not a miss
    }

    @Test("a recorded error counts as a miss, never as a skip")
    func recordedErrorCountsAsAMiss() {
        let expected = [
            "a.jpg": ExpectedRow(liters: 10.0, unitPrice: 2.0, total: 20.0),
            "b.jpg": ExpectedRow(liters: 5.0, unitPrice: nil, total: nil)
        ]
        // "a.jpg" failed; "b.jpg" has no record at all (the sweep never wrote it).
        let records = [
            "a.jpg": ExtractionRecord(
                filename: "a.jpg", liters: nil, unitPrice: nil, total: nil, error: "opencode exit 1"
            )
        ]
        let scored = CorpusScorer.score(name: "x", images: ["a.jpg", "b.jpg"], records: records, expected: expected)
        // Every expected field of the failed and missing images is a miss.
        #expect(scored.total == 4) // a.jpg: 3 fields, b.jpg: 1 field
        #expect(scored.hits == 0)
    }

    // MARK: - Latency against the 3 s device budget

    /// `API.md` gives the device 3 s per attempt. Every class's median is above
    /// that - including the fastest (screenshots, 6.5 s). This is a product
    /// finding: the cloud model cannot meet the budget on-device, whatever the
    /// extraction quality.
    @Test("the median per-image latency exceeds the 3 s device budget in every class")
    func latencyExceedsTheDeviceBudget() throws {
        for cls in Self.classes {
            let file = try CorpusScorer.loadABResultFile(
                Self.abRoot.appendingPathComponent("llm-\(cls).json")
            )
            let latencies = file.entries.compactMap(\.latencySeconds)
            #expect(!latencies.isEmpty, "\(cls) recorded no latency")
            let sorted = latencies.sorted()
            let median = sorted[sorted.count / 2]
            #expect(median > 3.0, "\(cls) median \(median)s must exceed the 3 s budget")
        }
    }
}
