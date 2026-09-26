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
@Suite("OCR corpus accuracy gate (L5)", .visionMeasuredRuntimeOnly)
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
        let expenses: ClassScore
        let stations: ClassScore

        func recorded(for name: String) -> ClassScore {
            switch name {
            case "receipts": return receipts
            case "pump": return pump
            case "fiscal": return fiscal
            case "expenses": return expenses
            case "stations": return stations
            default: return screenshots
            }
        }
    }

    @Test func corpusScoresDoNotRegress() async throws {
        let highWater = try loadHighWater()
        var failures: [String] = []
        for name in ["receipts", "pump", "fiscal", "screenshots", "expenses", "stations"] {
            // The pump class is scored under the re-scoped B1 metric (numeric
            // only, precision + coverage); the ratchet still guards its recall
            // (hits may not fall, total may not shrink). The expense class is
            // scored from its photographs where it has one, else from the
            // hand-authored `.txt` (RV.278). The station class is the receipts'
            // `station` column scored on its own (RV.179), so the receipts
            // marks keep their cell counts.
            let scored: ScoredClass
            switch name {
            case "pump": scored = try await scorePump().scoredClass
            case "expenses": scored = try await scoreExpenses().scoredClass
            case "stations": scored = try await scoreStations().score
            default: scored = try await scoreClass(name)
            }
            let recorded = highWater.recorded(for: name)
            print("L5 \(name): \(scored.hits)/\(scored.total) (mark \(recorded.hits)/\(recorded.total))")
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

    @Test func everyClassIsScored() async throws {
        for name in ["receipts", "pump", "fiscal", "screenshots", "expenses", "stations"] {
            let total: Int
            switch name {
            case "pump": total = try await scorePump().numericTotal
            case "expenses": total = try await scoreExpenses().total
            case "stations": total = try await scoreStations().score.total
            default: total = try await scoreClass(name).total
            }
            #expect(total > 0, "\(name) scored no fields")
        }
    }

    /// RV.179: the station mark is a real measurement only if it can miss. A
    /// class whose every asserted cell hits is, for a fresh extraction class,
    /// evidence of a circular oracle (RV.161's 46/46) rather than of quality -
    /// so the live score must record at least one miss, and each miss is
    /// printed with what the extractor offered against what the paper names.
    @Test func stationMarkIncludesAMiss() async throws {
        let scored = try await scoreStations()
        #expect(scored.score.hits < scored.score.total,
                "a station class with no miss is a circular oracle, not a perfect extractor")
        #expect(!scored.misses.isEmpty)
        print("stations \(scored.score.hits)/\(scored.score.total); misses:\n" + scored.misses.joined(separator: "\n"))
    }

    /// RV.277: the expense class is a real, scored corpus class now, not only a
    /// kind vocabulary. The recorded floor must cover every asserted cell (kind,
    /// total, currency, date), so a fixture silently dropped from the folder
    /// cannot shrink the total under the recorded one.
    @Test func expenseClassScoresKindAndMoneyCells() async throws {
        let scored = try await scoreExpenses()
        #expect(scored.total >= 12, "the expense class must assert at least one cell per fixture")
        #expect(scored.hits > 0, "the expense class resolved nothing")
    }

    /// RV.278: a photograph's committed `.txt` is a debugging dump, not the
    /// input, so a fresh OCR that no longer matches it is reported as **drift**
    /// and never scored. The score is the photograph's; this test only says the
    /// dump beside it still describes what Vision now reads. A non-empty list
    /// fails the suite, and the fix is to review the new OCR, regenerate the
    /// `.txt` with `--dump-text`, and re-check `expected.csv` against the paper.
    @Test func expensePhotoDumpsHaveNotDrifted() async throws {
        let fixtures = try await Self.expenseFixtureTask.value.fixtures
        let drifts = CorpusScorer.expenseDrifts(in: fixtures)
        #expect(drifts.isEmpty, Comment(stringLiteral: drifts.joined(separator: "\n")))
    }

    /// RV.270: the whole-class guard the boilerplate failure needs. A wrong
    /// non-nil `fuelKind` is a confident wrong value (hard rule 13), which the
    /// ratchet cannot see because it counts a miss and a contradiction the
    /// same. Here every receipt's committed kind is compared against its
    /// `expected.csv` cell: an abstention (`nil`) is allowed - an empty field
    /// the user fills - but a committed kind that contradicts the paper fails.
    /// The next legend read therefore fails the suite, not just lowers a score.
    @Test func noReceiptCommitsAFuelKindItsExpectedContradicts() async throws {
        let folder = Self.fixturesRoot.appendingPathComponent("receipts")
        let expected = try CorpusScorer.loadExpected(folder.appendingPathComponent("expected.csv"))
        let images = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { CorpusScorer.imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let records = try await extractRecords(folder: folder, images: images, expected: expected, source: .receipt)
        var contradictions: [String] = []
        for image in images {
            guard let wantKind = expected[image.lastPathComponent]?.fuelKind else { continue }
            // An abstention is the correct answer when the product line is
            // unreadable; only a committed, contradicting kind is a defect.
            guard let gotKind = records[image.lastPathComponent]?.fuelKind else { continue }
            if gotKind != wantKind {
                contradictions.append("\(image.lastPathComponent): committed \(gotKind.rawValue), "
                    + "expected \(wantKind.rawValue)")
            }
        }
        #expect(contradictions.isEmpty, Comment(stringLiteral: contradictions.joined(separator: "\n")))
    }

    /// The litres counterpart of the RV.56 (totals) and RV.270 (kinds)
    /// properties: a committed volume that contradicts the paper is a confident
    /// wrong value (hard rule 13), which the ratchet cannot see - it counts a
    /// miss and a contradiction the same, so `receipt-068`'s `1.0` and
    /// `receipt-072`'s ten-billion litres shipped as pre-fills while the score
    /// merely dropped. An abstention (`nil`) is allowed; a committed litres
    /// value off the expected one by the scorer's own tolerance fails. The next
    /// confident-wrong volume fails the suite instead of lowering a number.
    @Test func noReceiptCommitsAVolumeItsExpectedContradicts() async throws {
        let folder = Self.fixturesRoot.appendingPathComponent("receipts")
        let expected = try CorpusScorer.loadExpected(folder.appendingPathComponent("expected.csv"))
        let images = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { CorpusScorer.imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let records = try await extractRecords(folder: folder, images: images, expected: expected, source: .receipt)
        var contradictions: [String] = []
        for image in images {
            guard let want = expected[image.lastPathComponent]?.liters else { continue }
            guard let got = records[image.lastPathComponent]?.liters else { continue }
            if abs(got - want) >= 0.005 {
                contradictions.append("\(image.lastPathComponent): committed \(got) L, expected \(want) L")
            }
        }
        #expect(contradictions.isEmpty, Comment(stringLiteral: contradictions.joined(separator: "\n")))
    }

    /// P2.7 "the gate IS the check", made executable: the real, live-scored pump
    /// corpus must match the compile-time gate constants (so the constants cannot
    /// drift from reality), and the shipped flag must be off while the measured
    /// precision is below the 99% threshold or coverage below the 60% floor. A
    /// flag flipped on below the gate is exactly what `PumpPhotoGate.violation`
    /// catches.
    @Test func pumpModeShipsOffWhileTheCorpusIsBelowTheGate() async throws {
        let scored = try await scorePump()
        #expect(scored.numericHits == PumpPhotoGate.measuredNumericHits,
                "measured numeric hits \(PumpPhotoGate.measuredNumericHits) must match the live \(scored.numericHits)")
        #expect(scored.numericTotal == PumpPhotoGate.measuredNumericTotal,
                Comment(stringLiteral: "measured numeric total \(PumpPhotoGate.measuredNumericTotal) "
                    + "must match the live \(scored.numericTotal)"))
        #expect(scored.committed == PumpPhotoGate.measuredCommitted,
                "measured committed \(PumpPhotoGate.measuredCommitted) must match the live \(scored.committed)")
        #expect(scored.committedCorrect == PumpPhotoGate.measuredCommittedCorrect,
                Comment(stringLiteral: "measured committed-correct \(PumpPhotoGate.measuredCommittedCorrect) "
                    + "must match the live \(scored.committedCorrect)"))
        // The shipped flag is judged against the READER's measured accuracy - the
        // numbers `PumpPhotoGate.allowsPumpPhoto` gates on - not this rules-parser
        // score, which is not what a pump photo is read with (PU.61).
        let shipped = try ConfigDefaults.bundledAppConfig().flags["pumpPhoto"]?.enabled ?? false
        #expect(PumpPhotoGate.violation(flagEnabled: shipped,
                                        precision: PumpPhotoGate.readerPrecision,
                                        coverage: PumpPhotoGate.readerCoverage) == nil,
                Comment(stringLiteral: "the pump flag must stay off while precision is below "
                    + "\(PumpPhotoGate.precisionThreshold) or coverage below \(PumpPhotoGate.coverageFloor)"))
    }

    // MARK: - Scoring

    private func scoreStations() async throws -> (score: ScoredClass, misses: [String]) {
        let folder = Self.fixturesRoot.appendingPathComponent("receipts")
        let expected = try CorpusScorer.loadExpected(folder.appendingPathComponent("expected.csv"))
        let images = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { CorpusScorer.imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let records = try await extractRecords(folder: folder, images: images, expected: expected, source: .receipt)
        return CorpusScorer.scoreStations(images: images.map(\.lastPathComponent),
                                          records: records, expected: expected)
    }

    private func scoreClass(_ name: String) async throws -> ScoredClass {
        let folder = Self.fixturesRoot.appendingPathComponent(name)
        let expected = try CorpusScorer.loadExpected(folder.appendingPathComponent("expected.csv"))
        let images = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { CorpusScorer.imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let source: ExtractionSource = name == "pump" ? .pump : .receipt
        let records = try await extractRecords(folder: folder, images: images, expected: expected, source: source)
        // The same scorer `CorpusScorer` that the P4.12 A/B uses for both arms,
        // so the rules arm of the A/B is scored with an identical comparison.
        return CorpusScorer.score(
            name: name,
            images: images.map(\.lastPathComponent),
            records: records,
            expected: expected
        )
    }

    /// The pump class scored under the re-scoped B1 metric (numeric-only
    /// precision/coverage/recall, currency reported separately).
    private func scorePump() async throws -> PumpScore {
        let folder = Self.fixturesRoot.appendingPathComponent("pump")
        let expected = try CorpusScorer.loadExpected(folder.appendingPathComponent("expected.csv"))
        // Heldout only (PU.61). The reader is a trained model and the split is
        // frozen (decision 9), so scoring it over every fixture would score it
        // on its own training data. The rules arm is indifferent to the split;
        // the composite is not, and the composite is what this gate measures.
        let images = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { CorpusScorer.imageExtensions.contains($0.pathExtension.lowercased()) }
            .filter { PumpReaderTestSupport.isHeldout($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let records = try await extractRecords(folder: folder, images: images, expected: expected,
                                               source: .pump, pumpReader: Self.pumpReaderHandle())
        return CorpusScorer.scorePump(
            name: "pump",
            images: images.map(\.lastPathComponent),
            records: records,
            expected: expected
        )
    }

    /// The expense fixtures, loaded once per test process. A fixture with a
    /// photograph is OCR'd through the SAME `VisionTextRecognizer` the fuel
    /// classes use, and its fresh text is compared with the committed `.txt`
    /// dump to report drift. A hand-authored fixture with no photograph reads
    /// the `.txt` directly - there the `.txt` IS the input by construction. The
    /// cache keeps the four tests that score the class from paying the two
    /// photographs' OCR four times.
    private static let expenseFixtureTask: Task<
        (fixtures: [ExpenseFixture], expected: [ExpenseExpectedRow]), Error
    > = Task {
        try await loadExpenseFixtures()
    }

    private static func loadExpenseFixtures() async throws
        -> (fixtures: [ExpenseFixture], expected: [ExpenseExpectedRow]) {
        let folder = fixturesRoot.appendingPathComponent("expenses")
        let expected = try CorpusScorer.loadExpenseExpected(
            folder.appendingPathComponent("expected.csv"))
        var fixtures: [ExpenseFixture] = []
        for row in expected {
            if let photo = photograph(for: row.filename, in: folder) {
                let ocr = try await TestOCR.recognizeText(in: photo, languages: languages)
                let regenerated = ocr.map(\.text).joined(separator: "\n") + "\n"
                let dumpURL = folder.appendingPathComponent(row.filename)
                // `VISION_REWRITE_DUMPS=1` on the measured runtime rewrites the
                // dump from this OCR (scripts/vision-suites.sh); review its diff.
                if ProcessInfo.processInfo.environment["VISION_REWRITE_DUMPS"] == "1" {
                    try regenerated.write(to: dumpURL, atomically: true, encoding: .utf8)
                }
                let committed = try? String(contentsOf: dumpURL, encoding: .utf8)
                let drift = committed.flatMap { $0 == regenerated ? nil
                    : "\(row.filename): the committed Vision dump differs from a fresh OCR of "
                        + "\(photo.lastPathComponent); review the new text and regenerate the dump"
                }
                fixtures.append(ExpenseFixture(filename: row.filename, lines: ocr, drift: drift))
            } else {
                let url = folder.appendingPathComponent(row.filename)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
                    .map { OCRLine(text: String($0)) }
                fixtures.append(ExpenseFixture(filename: row.filename, lines: lines, drift: nil))
            }
        }
        return (fixtures, expected)
    }

    /// The photograph a `expected.csv` row names, by matching the `.txt` base
    /// name against the class's image extensions. Nil for a hand-authored text
    /// fixture, which has no photograph.
    private static func photograph(for filename: String, in folder: URL) -> URL? {
        let base = (filename as NSString).deletingPathExtension
        return CorpusScorer.imageExtensions.sorted().lazy
            .map { folder.appendingPathComponent("\(base).\($0)") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func scoreExpenses() async throws -> ExpenseScore {
        let loaded = try await Self.expenseFixtureTask.value
        return CorpusScorer.scoreExpenses(
            name: "expenses", fixtures: loaded.fixtures, expected: loaded.expected)
    }

    /// The reader the app runs ahead of the rules parser, or nil when the
    /// models are not in the tree. Built once per score: loading the classifier
    /// and compiling the detector per image would dominate the run.
    private static func pumpReaderHandle() -> PumpReaderHandle? {
        let modelURL = ProcessInfo.processInfo.environment["PUMP_MODEL"].map { URL(fileURLWithPath: $0) }
            ?? PumpReaderTestSupport.repoRoot
                .appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")
        guard let model = try? PumpSegmentsModel(contentsOf: modelURL) else { return nil }
        return PumpReaderHandle(reader: PumpReader(model: model,
                                                   detector: PumpReaderTestSupport.makeDetector(),
                                                   rowReader: PumpReaderTestSupport.makeRowReader()))
    }

    private func extractRecords(folder: URL, images: [URL], expected: [String: ExpectedRow],
                                source: ExtractionSource,
                                pumpReader: PumpReaderHandle? = nil) async throws -> [String: ExtractionRecord] {
        // The scorer injects the bundled band pack - a corpus fixture has no
        // user history (a fresh device, no prior fill-ups), so ladder step 3
        // yields nothing and the recorded number is the parser running with the
        // same curated band the app ships. Without this the scorer measures a
        // parser the app never runs.
        let pack = try FuelPriceBandStore.bundledPack()
        let extractor = FuelExtractor(bandProvider: DefaultFuelPriceBandProvider(pack: pack))
        var records: [String: ExtractionRecord] = [:]
        for image in images {
            guard expected[image.lastPathComponent] != nil else { continue }
            let ocrLines = try await TestOCR.recognizeText(in: image, languages: Self.languages)
            // The pump class is scored as a pump (source .pump) - the pump
            // parser paths (no fuel kind, P2.13 digit repair) are pump-source
            // behaviour, and scoring them as receipts would measure a parser
            // the app does not run for this class.
            // RV.56: the fiscal QR is composed into the extraction, exactly as
            // the app composes it, so the scored number measures the pipeline
            // the app runs rather than a weaker OCR-only one.
            let qrAnchor = CorpusScorer.qrAnchor(forImage: image.lastPathComponent, in: folder)
            var result = extractor.extract(lines: ocrLines, source: source, qrAnchor: qrAnchor)
            // PU.61: the app runs the reader FIRST and lets the rules arm fill
            // what it abstained on (`CapturePipeline.process`). Scoring either
            // arm alone measures a path the user never meets - which is what
            // this gate did until now, and why no reader change could move it.
            // The composition is deliberately the same three lines as the app's;
            // whether the fallthrough should exist at all is PU.62.
            if let pumpReader, source == .pump,
               let rgb = PumpReaderTestSupport.loadRGB(url: image),
               let cgImage = PumpQuadWarp.makeImage(rgb.pixels, width: rgb.width, height: rgb.height) {
                let currency = expected[image.lastPathComponent]?.currency
                // No wall-clock cap, as the live floor measures: a Debug build in
                // the simulator runs the verifier several times slower than the
                // Release app, so the app's cap would score this runtime's speed.
                let reading = PumpDisplayCapture.classify(
                    image: cgImage, reader: pumpReader, currency: currency,
                    priceBand: DefaultFuelPriceBandProvider(pack: pack).currencyBand(currency: currency),
                    budget: .infinity, rotationCW: 0).reading
                if let reading {
                    result.liters = reading.extraction.liters ?? result.liters
                    result.unitPrice = reading.extraction.unitPrice ?? result.unitPrice
                    result.total = reading.extraction.total ?? result.total
                }
            }
            // The record keeps Double money (the scorer's boundary - see
            // CorpusABScorer); the exact Decimal the extraction now carries is
            // converted through NSDecimalNumber, lossless in the measured
            // direction for corpus values.
            records[image.lastPathComponent] = ExtractionRecord(
                filename: image.lastPathComponent, extraction: result
            )
        }
        return records
    }

    private func loadHighWater() throws -> HighWater {
        let data = try Data(contentsOf: Self.highWaterURL)
        return try JSONDecoder().decode(HighWater.self, from: data)
    }
}
#endif
