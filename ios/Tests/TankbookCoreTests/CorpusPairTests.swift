import Foundation
import Testing
@testable import TankbookCore

#if canImport(Vision)
import Vision

// RV.114 - the matched pairs are the corpus's only second source of truth: the
// same fill photographed as the pump display AND its receipt. Everywhere else a
// fixture's expected row is a hand-typed expectation; here the two documents
// must agree with each other, which is a check on the ORACLE, not only on the
// parser. Two tests: the oracle-level one runs everywhere (it reads the two
// `expected.csv` files and no image), the extraction-level one only on the
// measured Vision runtime, where a value both halves commit must be the same
// value.

/// A fill photographed twice. `totalsAgree` is false where the two papers
/// genuinely print different totals - a display that truncates its total to
/// whole minor units (`truncated-total` in the pump's filename) or a receipt
/// that rounds - and the reason is written beside it; litres and unit price
/// must always agree.
private struct MatchedPair: Sendable {
    let pump: String
    let receipt: String
    var totalsAgree = true
    var note = ""
}

private let matchedPairs: [MatchedPair] = [
    MatchedPair(pump: "pump-002", receipt: "receipt-007", totalsAgree: false,
                note: "the receipt prints the rounded 4334.00 for the display's 4334.83"),
    MatchedPair(pump: "pump-030", receipt: "receipt-041"),
    MatchedPair(pump: "pump-065", receipt: "receipt-047"),
    MatchedPair(pump: "pump-066", receipt: "receipt-048"),
    MatchedPair(pump: "pump-067", receipt: "receipt-049"),   // glare on the display's total, the receipt holds it
    MatchedPair(pump: "pump-068", receipt: "receipt-050"),   // the receipt photographed 90 degrees rotated
    MatchedPair(pump: "pump-083", receipt: "receipt-060", totalsAgree: false,
                note: "a Tokheim display truncates 1437.24 to 1437.20"),
    MatchedPair(pump: "pump-084", receipt: "receipt-061"),
    MatchedPair(pump: "pump-085", receipt: "receipt-062"),
    MatchedPair(pump: "pump-086", receipt: "receipt-063"),
    MatchedPair(pump: "pump-095", receipt: "receipt-064"),
    MatchedPair(pump: "pump-096", receipt: "receipt-065"),
    MatchedPair(pump: "pump-100", receipt: "receipt-066"),
    MatchedPair(pump: "pump-104", receipt: "receipt-067"),
    MatchedPair(pump: "pump-107", receipt: "receipt-068"),
    MatchedPair(pump: "pump-107", receipt: "receipt-069"),
    MatchedPair(pump: "pump-109", receipt: "receipt-070"),
    MatchedPair(pump: "pump-110", receipt: "receipt-071", totalsAgree: false,
                note: "a Wayne display truncates 2953.02 to 2953.00"),
    MatchedPair(pump: "pump-115", receipt: "receipt-074"),
    MatchedPair(pump: "pump-116", receipt: "receipt-075"),
    MatchedPair(pump: "pump-248", receipt: "receipt-084"),
    MatchedPair(pump: "pump-249", receipt: "receipt-084"),   // the same fill, a closer still
    MatchedPair(pump: "pump-253", receipt: "receipt-085"),
    MatchedPair(pump: "pump-278", receipt: "receipt-086"),   // the display's 69,91 against 34.97 x 1.999 = 69.90: the paper prints 69,91 too
    MatchedPair(pump: "pump-279", receipt: "receipt-087"),
    MatchedPair(pump: "pump-286", receipt: "receipt-088"),
    // The display is a Wayne board head, so the pump side asserts no unitPrice;
    // the paper carries a 0,36 loyalty discount line and its printed total is
    // the paid one.
    MatchedPair(pump: "pump-290", receipt: "receipt-089"),
    // The Capture lab's first run (2026-09-25), its high1080 preset: 1080x1920,
    // the smallest frame the lab captures. The paper's EXTRA SOODUS line is
    // informational; the paid total is the display's.
    MatchedPair(pump: "pump-336", receipt: "receipt-098")
]

@Suite("Matched pump/receipt pairs (RV.114)")
struct CorpusPairTests {
    private static let fixturesRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Spike/ReceiptSpike/fixtures")
    private static let languages = ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"]

    private static func fixture(_ prefix: String, in folder: URL) throws -> URL {
        let matches = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(prefix + "-")
                && CorpusScorer.imageExtensions.contains($0.pathExtension.lowercased()) }
        try #require(matches.count == 1, "\(prefix) must name exactly one image, found \(matches.count)")
        return matches[0]
    }

    /// The two expected rows of every pair agree to the cent on litres and unit
    /// price, and on the total unless the pair says why not. A pair whose
    /// oracles disagree is a wrong expectation somewhere, and a wrong oracle
    /// freezes a defect as the standard.
    @Test func everyPairsExpectationsAgree() throws {
        let pumpFolder = Self.fixturesRoot.appendingPathComponent("pump")
        let receiptFolder = Self.fixturesRoot.appendingPathComponent("receipts")
        let pumpExpected = try CorpusScorer.loadExpected(pumpFolder.appendingPathComponent("expected.csv"))
        let receiptExpected = try CorpusScorer.loadExpected(receiptFolder.appendingPathComponent("expected.csv"))
        var disagreements: [String] = []
        for pair in matchedPairs {
            let pump = try #require(pumpExpected[try Self.fixture(pair.pump, in: pumpFolder).lastPathComponent])
            let receiptName = try Self.fixture(pair.receipt, in: receiptFolder).lastPathComponent
            let receipt = try #require(receiptExpected[receiptName])
            func check(_ cell: String, _ display: Double?, _ paper: Double?) {
                guard let display, let paper else { return }
                if abs(display - paper) >= 0.005 {
                    disagreements.append("\(pair.pump)/\(pair.receipt) \(cell): \(display) vs \(paper)")
                }
            }
            check("liters", pump.liters, receipt.liters)
            check("unitPrice", pump.unitPrice, receipt.unitPrice)
            if pair.totalsAgree { check("total", pump.total, receipt.total) }
        }
        #expect(disagreements.isEmpty, Comment(stringLiteral: disagreements.joined(separator: "\n")))
    }

    /// Where BOTH halves of a pair commit a cell, they commit the same value.
    /// A display read that contradicts the receipt of the same fill is the
    /// most provable confident-wrong value the corpus can produce.
    @Test(.visionMeasuredRuntimeOnly)
    func noPairCommitsTwoDifferentValuesForOneFill() async throws {
        let pumpFolder = Self.fixturesRoot.appendingPathComponent("pump")
        let receiptFolder = Self.fixturesRoot.appendingPathComponent("receipts")
        let pack = try FuelPriceBandStore.bundledPack()
        let extractor = FuelExtractor(bandProvider: DefaultFuelPriceBandProvider(pack: pack))
        var contradictions: [String] = []
        for pair in matchedPairs {
            let pumpImage = try Self.fixture(pair.pump, in: pumpFolder)
            let receiptImage = try Self.fixture(pair.receipt, in: receiptFolder)
            let pumpRead = extractor.extract(
                lines: try await TestOCR.recognizeText(in: pumpImage, languages: Self.languages),
                source: .pump, qrAnchor: nil)
            let receiptRead = extractor.extract(
                lines: try await TestOCR.recognizeText(in: receiptImage, languages: Self.languages),
                source: .receipt,
                qrAnchor: CorpusScorer.qrAnchor(forImage: receiptImage.lastPathComponent, in: receiptFolder))
            func check(_ cell: String, _ display: Double?, _ paper: Double?) {
                guard let display, let paper else { return }
                if abs(display - paper) >= 0.005 {
                    contradictions.append(
                        "\(pair.pump)/\(pair.receipt) \(cell): display \(display) vs receipt \(paper)")
                }
            }
            func double(_ value: Decimal?) -> Double? { value.map { NSDecimalNumber(decimal: $0).doubleValue } }
            check("liters", pumpRead.liters, receiptRead.liters)
            check("unitPrice", double(pumpRead.unitPrice), double(receiptRead.unitPrice))
            if pair.totalsAgree { check("total", double(pumpRead.total), double(receiptRead.total)) }
        }
        #expect(contradictions.isEmpty, Comment(stringLiteral: contradictions.joined(separator: "\n")))
    }
}
#endif

// MARK: - The station column's oracle (RV.179), checked without Vision

/// The `station` column's two runtime-independent properties: every receipt
/// with an empty cell is listed in `stations.md` with its reason (a blank for
/// any other reason is a miss hiding), and the recorded mark is not a full
/// score (a fresh extraction class at 100% is a circular oracle).
@Suite("The station column's oracle (RV.179)")
struct StationOracleTests {
    private static let receiptsFolder = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Spike/ReceiptSpike/fixtures/receipts")

    @Test func everyBlankStationCellIsListedWithAReason() throws {
        let expected = try CorpusScorer.loadExpected(Self.receiptsFolder.appendingPathComponent("expected.csv"))
        let ledger = try String(contentsOf: Self.receiptsFolder.appendingPathComponent("stations.md"), encoding: .utf8)
        let blanks = expected.filter { $0.value.station == nil }.map(\.key).sorted()
        let listed = blanks.filter { ledger.contains("| `\($0)` |") }
        #expect(listed.count == blanks.count,
                "blank cells without a stated reason: \(Set(blanks).subtracting(listed).sorted())")
        let asserted = expected.count - blanks.count
        #expect(ledger.contains("Asserted: \(asserted) of \(expected.count) receipts"),
                "the ledger's counts must match the column (\(asserted) asserted, \(blanks.count) blank)")
        #expect(!blanks.isEmpty && blanks.count < expected.count)
    }

    @Test func theRecordedStationMarkIsNotAFullScore() throws {
        struct Mark: Decodable { let hits: Int; let total: Int }
        struct HighWater: Decodable { let stations: Mark }
        let url = Self.receiptsFolder.deletingLastPathComponent().appendingPathComponent("high-water.json")
        let mark = try JSONDecoder().decode(HighWater.self, from: Data(contentsOf: url)).stations
        #expect(mark.total > 0)
        #expect(mark.hits < mark.total, "a 100% station mark is evidence of circularity, not quality")
    }
}
