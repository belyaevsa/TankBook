import Foundation
import Testing
@testable import TankbookCore

#if canImport(Vision)
import Vision

/// The service documents (`fixtures/service`, J7) through the real OCR and the
/// deterministic split, scored against the hand-written `expected.csv`: the
/// vendor, the grand total, the date and the number of line items. The folder
/// is small and the split is young, so the mark is a floor that only rises; a
/// document that loses a cell it read before is a red to read, never a mark to
/// lower.
@Suite("Service documents through the invoice split (RV.320, L5)", .visionMeasuredRuntimeOnly)
struct ServiceCorpusTests {
    private static let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let folder = repoRoot.appendingPathComponent("Spike/ReceiptSpike/fixtures/service")
    /// The app's invoice OCR languages (`ServiceInvoiceScanner.languages`).
    private static let languages = ["en-US", "de-DE", "ru-RU"]

    /// Hits over asserted cells, recorded on the measured runtime.
    static let recorded = (hits: 7, total: 14)

    struct Row {
        let file: String
        let vendor: String
        let total: Decimal?
        let date: String
        let lineCount: Int?
    }

    static func rows() throws -> [Row] {
        let text = try String(contentsOf: folder.appendingPathComponent("expected.csv"), encoding: .utf8)
        return text.split(separator: "\n").dropFirst().map { line in
            let cells = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            return Row(file: cells[0], vendor: cells[1], total: Decimal(string: cells[2]),
                       date: cells[4], lineCount: Int(cells[5]))
        }
    }

    /// A vendor matches when the expected slug's letters appear in the read
    /// vendor's letters (`lr-west` in `LR-West`, `tireman` in `Tireman`).
    static func vendorMatches(_ read: String?, _ slug: String) -> Bool {
        let letters: (String) -> String = { $0.lowercased().filter { $0.isLetter } }
        guard let read, !slug.isEmpty else { return false }
        return letters(read).contains(letters(slug))
    }

    static func isoDay(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    @Test("the service documents' vendor, total, date and line count never fall below the mark")
    func scored() async throws {
        var hits = 0
        var total = 0
        var report: [String] = []
        for row in try Self.rows() {
            let url = Self.folder.appendingPathComponent(row.file)
            let lines = try await TestOCR.recognizeText(in: url, languages: Self.languages)
            let split = InvoiceSplitter().split(lines: lines)
            var cells: [String] = []
            if !row.vendor.isEmpty {
                total += 1
                let hit = Self.vendorMatches(split.vendor, row.vendor)
                hits += hit ? 1 : 0
                cells.append("vendor \(hit ? "ok" : "miss (\(split.vendor ?? "nil"))")")
            }
            if let expected = row.total {
                total += 1
                let hit = split.total == expected
                hits += hit ? 1 : 0
                cells.append("total \(hit ? "ok" : "miss (\(split.total.map { "\($0)" } ?? "nil"))")")
            }
            if !row.date.isEmpty {
                total += 1
                let read = split.date.map(Self.isoDay)
                let hit = read == row.date
                hits += hit ? 1 : 0
                cells.append("date \(hit ? "ok" : "miss (\(read ?? "nil"))")")
            }
            if let expected = row.lineCount {
                total += 1
                let hit = !split.lumpSum && split.items.count == expected
                hits += hit ? 1 : 0
                cells.append("lines \(hit ? "ok" : "miss (\(split.lumpSum ? "lump" : "\(split.items.count)"))")")
            }
            report.append("\(row.file): " + cells.joined(separator: ", "))
        }
        print("L5 service: \(hits)/\(total) (mark \(Self.recorded.hits)/\(Self.recorded.total))")
        report.forEach { print("  " + $0) }
        #expect(total == Self.recorded.total, "the asserted cells are a corpus fact")
        #expect(hits >= Self.recorded.hits, "a service cell the split read before is lost")
    }

    /// RV.319: the not-fuel offer. Every service document suggests Service in
    /// Fill-up mode, and no fuel receipt or fuel-app screenshot suggests any
    /// form - an offer on a fuel document would send a real fill-up away from
    /// its form.
    @Test("service documents are offered the Service form; no fuel document is offered anything")
    func notFuelOffer() async throws {
        let fixtures = Self.folder.deletingLastPathComponent()
        var offeredFuel: [String] = []
        for folder in ["receipts", "screenshots"] {
            let files = try FileManager.default.contentsOfDirectory(atPath: fixtures.appendingPathComponent(folder).path)
                .filter { $0.hasSuffix(".jpg") || $0.hasSuffix(".jpeg") || $0.hasSuffix(".png") }.sorted()
            for file in files {
                let url = fixtures.appendingPathComponent(folder).appendingPathComponent(file)
                let lines = try await TestOCR.recognizeText(in: url, languages: Self.languages)
                let extraction = FuelExtractor().extract(lines: lines)
                if let form = CaptureDocumentHint.suggestedForm(lines: lines, extraction: extraction) {
                    offeredFuel.append("\(file) -> \(form)")
                }
            }
        }
        var serviceMissed: [String] = []
        for row in try Self.rows() {
            let url = Self.folder.appendingPathComponent(row.file)
            let lines = try await TestOCR.recognizeText(in: url, languages: Self.languages)
            let form = CaptureDocumentHint.suggestedForm(lines: lines, extraction: FuelExtractor().extract(lines: lines))
            if form != .service { serviceMissed.append("\(row.file) -> \(form.map { "\($0)" } ?? "nil")") }
        }
        print("RV.319 offers on fuel documents: \(offeredFuel.count); service documents missed: \(serviceMissed.count)")
        (offeredFuel + serviceMissed).forEach { print("  " + $0) }
        #expect(offeredFuel.isEmpty, "a fuel document must never be offered another form")
        #expect(serviceMissed.isEmpty, "every service document must be offered the Service form")
    }
}
#endif
