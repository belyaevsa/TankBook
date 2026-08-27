import Foundation
import Testing
@testable import TankbookCore

// The pure ratchet comparison: given a freshly scored class and the recorded
// high-water mark, returns a violation message or nil. Kept free of Vision so
// the "ratchet fails on regression" behaviour is testable without OCR.
enum AccuracyRatchet {
    /// The ratchet guards against **code** regressions and against a class being
    /// flattered by dropping fixtures. It must not punish the corpus for growing.
    ///
    /// So the two halves are deliberately asymmetric:
    ///
    /// - **Total may only grow.** Shrinking means fixtures were removed, which
    ///   raises a class average by deleting the evidence - the trap the ratchet
    ///   exists to catch.
    /// - **Hits may never fall.** Absolute hits, not a percentage. Adding a hard
    ///   new fixture legitimately lowers the *percentage* while leaving hits
    ///   untouched, so percentage would fire on corpus growth - and a gate that
    ///   fires every time someone adds a photo is a gate that gets deleted.
    ///   Only the code getting worse can reduce hits.
    static func violation(
        name: String, currentHits: Int, currentTotal: Int, recordedHits: Int, recordedTotal: Int
    ) -> String? {
        if currentTotal < recordedTotal {
            return "\(name): corpus shrank (\(currentTotal) vs \(recordedTotal)); a class may never lose fixtures"
        }
        if currentHits < recordedHits {
            return "\(name): \(currentHits)/\(currentTotal) resolved, below the high-water mark of "
                + "\(recordedHits) (recorded over \(recordedTotal)). The corpus may grow, but the "
                + "number of fields the parser resolves may not fall."
        }
        return nil
    }
}

@Suite("OCR corpus accuracy ratchet")
struct AccuracyRatchetTests {

    /// Adding a fixture the parser cannot yet handle lowers the percentage while
    /// leaving hits untouched. That must NOT fire - otherwise every corpus
    /// contribution breaks CI and the gate gets switched off.
    @Test("growing the corpus with a fixture the parser fails does not fire")
    func corpusGrowthIsAllowed() {
        #expect(AccuracyRatchet.violation(
            name: "receipts", currentHits: 29, currentTotal: 50, recordedHits: 29, recordedTotal: 47
        ) == nil)
    }

    /// The trap the size check exists for: deleting the fixtures a class fails.
    @Test("shrinking the corpus fires even when the percentage improves")
    func corpusShrinkFires() {
        #expect(AccuracyRatchet.violation(
            name: "receipts", currentHits: 29, currentTotal: 30, recordedHits: 29, recordedTotal: 47
        ) != nil)
    }

    /// A real regression stays caught while the corpus grows.
    @Test("a code regression still fires on a grown corpus")
    func regressionFiresEvenWhenTheCorpusGrew() {
        #expect(AccuracyRatchet.violation(
            name: "receipts", currentHits: 28, currentTotal: 50, recordedHits: 29, recordedTotal: 47
        ) != nil)
    }

    @Test("the ratchet fails when accuracy drops below the high-water mark")
    func ratchetFailsOnRegression() {
        #expect(AccuracyRatchet.violation(
            name: "receipts", currentHits: 17, currentTotal: 47, recordedHits: 18, recordedTotal: 47
        ) != nil)
    }

    @Test("the ratchet passes when accuracy matches or exceeds the mark")
    func ratchetPassesAtOrAbove() {
        #expect(AccuracyRatchet.violation(
            name: "receipts", currentHits: 18, currentTotal: 47, recordedHits: 18, recordedTotal: 47
        ) == nil)
        #expect(AccuracyRatchet.violation(
            name: "receipts", currentHits: 25, currentTotal: 47, recordedHits: 18, recordedTotal: 47
        ) == nil)
    }

    @Test("the ratchet fails when a class shrinks")
    func ratchetFailsOnShrunkCorpus() {
        #expect(AccuracyRatchet.violation(
            name: "receipts", currentHits: 18, currentTotal: 46, recordedHits: 18, recordedTotal: 47
        ) != nil)
    }
}

#if canImport(Vision)
import Vision

// L5 accuracy gate (docs/TESTING.md): the Spike harness grown into a test. It
// OCRs the fixture corpus with Vision and scores each class against its
// expected.csv, then ratchets against Spike/ReceiptSpike/fixtures/high-water.json.
@Suite("OCR corpus accuracy gate (L5)")
struct CorpusAccuracyGateTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let fixturesRoot = repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures")
    private static let highWaterURL = fixturesRoot.appendingPathComponent("high-water.json")

    private static let languages = ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"]

    private struct ClassScore: Decodable {
        let hits: Int
        let total: Int
    }

    private struct HighWater: Decodable {
        let receipts: ClassScore
        let pump: ClassScore
        let fiscal: ClassScore
        let screenshots: ClassScore

        func recorded(for name: String) -> ClassScore {
            switch name {
            case "receipts": return receipts
            case "pump": return pump
            case "fiscal": return fiscal
            default: return screenshots
            }
        }
    }

    @Test func corpusScoresDoNotRegress() throws {
        let highWater = try loadHighWater()
        var failures: [String] = []
        for name in ["receipts", "pump", "fiscal", "screenshots"] {
            let scored = try scoreClass(name)
            let recorded = highWater.recorded(for: name)
            if let violation = AccuracyRatchet.violation(
                name: name,
                currentHits: scored.hits,
                currentTotal: scored.total,
                recordedHits: recorded.hits,
                recordedTotal: recorded.total
            ) {
                failures.append(violation)
            }
        }
        #expect(failures.isEmpty, Comment(stringLiteral: failures.joined(separator: "\n")))
    }

    @Test func everyClassIsScored() throws {
        for name in ["receipts", "pump", "fiscal", "screenshots"] {
            let scored = try scoreClass(name)
            #expect(scored.total > 0, "\(name) scored no fields")
        }
    }

    /// P2.7 "the gate IS the check", made executable: the real, live-scored pump
    /// corpus must match the compile-time gate constant (so the constant cannot
    /// drift from reality), and the shipped flag must be off while that measured
    /// accuracy is below the 95% threshold. A flag flipped on below the gate is
    /// exactly what `PumpPhotoGate.violation` catches.
    @Test func pumpModeShipsOffWhileTheCorpusIsBelowTheGate() throws {
        let scored = try scoreClass("pump")
        #expect(scored.hits == PumpPhotoGate.measuredHits,
                "measured pump hits \(PumpPhotoGate.measuredHits) must match the live \(scored.hits)")
        #expect(scored.total == PumpPhotoGate.measuredTotal,
                "measured pump total \(PumpPhotoGate.measuredTotal) must match the live \(scored.total)")
        let accuracy = Double(scored.hits) / Double(scored.total)
        let shipped = try ConfigDefaults.bundledAppConfig().flags["pumpPhoto"]?.enabled ?? false
        #expect(PumpPhotoGate.violation(flagEnabled: shipped, accuracy: accuracy) == nil,
                "the pump flag must stay off while the measured accuracy is below \(PumpPhotoGate.threshold)")
    }

    // MARK: - Scoring

    private func scoreClass(_ name: String) throws -> ScoredClass {
        let folder = Self.fixturesRoot.appendingPathComponent(name)
        let expected = try CorpusScorer.loadExpected(folder.appendingPathComponent("expected.csv"))
        let images = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { CorpusScorer.imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let extractor = FuelExtractor()
        var records: [String: ExtractionRecord] = [:]
        for image in images {
            guard expected[image.lastPathComponent] != nil else { continue }
            let ocrLines = try VisionTextRecognizer.recognizeText(in: image, languages: Self.languages)
            let result = extractor.extract(lines: ocrLines)
            records[image.lastPathComponent] = ExtractionRecord(
                filename: image.lastPathComponent,
                liters: result.liters,
                unitPrice: result.unitPrice,
                total: result.total,
                fuelKind: result.fuelKind,
                currency: result.currency
            )
        }
        // The same scorer `CorpusScorer` that the P4.12 A/B uses for both arms,
        // so the rules arm of the A/B is scored with an identical comparison.
        return CorpusScorer.score(
            name: name,
            images: images.map(\.lastPathComponent),
            records: records,
            expected: expected
        )
    }

    private func loadHighWater() throws -> HighWater {
        let data = try Data(contentsOf: Self.highWaterURL)
        return try JSONDecoder().decode(HighWater.self, from: data)
    }
}
#endif
