import Foundation
import Testing
@testable import TankbookCore

// The pure ratchet comparison: given a freshly scored class and the recorded
// high-water mark, returns a violation message or nil. Kept free of Vision so
// the "ratchet fails on regression" behaviour is testable without OCR.
enum AccuracyRatchet {
    static func violation(
        name: String, currentHits: Int, currentTotal: Int, recordedHits: Int, recordedTotal: Int
    ) -> String? {
        if currentTotal != recordedTotal {
            return "\(name): corpus changed size (\(currentTotal) vs \(recordedTotal)); a class may never lose fixtures"
        }
        if currentHits < recordedHits {
            return "\(name): \(currentHits)/\(currentTotal) below the high-water mark \(recordedHits)/\(recordedTotal)"
        }
        return nil
    }
}

@Suite("OCR corpus accuracy ratchet")
struct AccuracyRatchetTests {

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

    private struct ScoredClass {
        let name: String
        let hits: Int
        let total: Int
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

    // MARK: - Scoring

    private func scoreClass(_ name: String) throws -> ScoredClass {
        let folder = Self.fixturesRoot.appendingPathComponent(name)
        let expected = try loadExpected(folder.appendingPathComponent("expected.csv"))
        let images = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { ["jpg", "jpeg", "png", "heic", "tiff"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let extractor = FuelExtractor()
        var hits = 0
        var total = 0
        for image in images {
            guard let want = expected[image.lastPathComponent] else { continue }
            let ocrLines = try VisionTextRecognizer.recognizeText(in: image, languages: Self.languages)
            let result = extractor.extract(lines: ocrLines)
            if let wantValue = want.liters {
                total += 1
                if let got = result.liters, abs(got - wantValue) < 0.005 { hits += 1 }
            }
            if let wantValue = want.unitPrice {
                total += 1
                if let got = result.unitPrice, abs(got - wantValue) < 0.005 { hits += 1 }
            }
            if let wantValue = want.total {
                total += 1
                if let got = result.total, abs(got - wantValue) < 0.005 { hits += 1 }
            }
        }
        return ScoredClass(name: name, hits: hits, total: total)
    }

    private struct ExpectedRow {
        let liters: Double?
        let unitPrice: Double?
        let total: Double?
    }

    private func loadExpected(_ url: URL) throws -> [String: ExpectedRow] {
        let csv = try String(contentsOf: url, encoding: .utf8)
        var result: [String: ExpectedRow] = [:]
        for line in csv.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
            guard cols.count >= 4 else { continue }
            result[cols[0]] = ExpectedRow(
                liters: Double(cols[1]),
                unitPrice: Double(cols[2]),
                total: Double(cols[3])
            )
        }
        return result
    }

    private func loadHighWater() throws -> HighWater {
        let data = try Data(contentsOf: Self.highWaterURL)
        return try JSONDecoder().decode(HighWater.self, from: data)
    }
}
#endif
