import Foundation
import Testing
@testable import TankbookCore

// RV.161 - a scanned fuel receipt's station line.
//
// These assertions are structural: the resolver converges, the seam never logs
// a station value, and a scanned name reaches the entry only through the
// editable selection. The corpus does NOT yet score station accuracy - the
// `station` column in `expected.csv` is present and EMPTY, because ground truth
// written from the extractor's own output measures nothing (RV.179).
@Suite("RV.161 fuel-receipt station extraction")
struct RV161StationExtractionTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let receiptsFolder = repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures/receipts")


    /// L1: a receipt that names no station yields nil and nothing is written.
    /// The lines are ordinary receipt text with no company line at all - the
    /// negative case that keeps the extractor from returning the first line it
    /// sees, which is what "a station was found" would accept.
    @Test func aReceiptWithNoIdentifiableStationYieldsNil() {
        let name = StationNameExtractor.stationName(from: [
            OCRLine(text: "КАССОВЫЙ ЧЕК"),
            OCRLine(text: "20.05.2026 14:32"),
            OCRLine(text: "АИ-95  42,00 л x 59,90"),
            OCRLine(text: "ИТОГО = 2515,80"),
            OCRLine(text: "НДС 20%")
        ])
        #expect(name == nil,
                "a receipt with no company line must yield nil, got \(name ?? "-")")
    }

    /// L1: the scanned name and a typed one resolve to ONE station id. The
    /// extractor's own output is the scanned name; the resolver's determinism
    /// is what makes the two entry paths converge (RV.156).
    @Test func aScannedNameAndATypedNameResolveToOneStation() throws {
        let scanned = StationNameExtractor.stationName(from: [
            OCRLine(text: "Кассовый чек"),
            OCRLine(text: "ООО \"Газпромнефть-Центр\" АЗС 12089")
        ])
        #expect(scanned == "ООО \"Газпромнефть-Центр\" АЗС 12089")

        let repo = try TankbookRepository(database: TankbookDatabase.inMemory())
        let fromScan = try repo.createStation(named: scanned ?? "")
        let typed = try repo.createStation(named: scanned ?? "")
        #expect(fromScan?.id == typed?.id,
                "a scanned name and a typed one must resolve to one station id")
        #expect(try repo.liveStations().count == 1,
                "the second path resolves the first record, never mints a duplicate")
    }
}

// MARK: - The write path (hard rule 13) and the logging gate (hard rule 12)

/// RV.161 - two source-scan guards over the station extraction and pre-fill
/// seams. A station name, brand or address is a domain value: it may reach the
/// entry only through the Confirm pre-fill the user can see and change (hard
/// rule 13), and it may never be logged (hard rule 12). The scans are pure
/// functions over source text so a hand-written fixture can prove their teeth.
@Suite("RV.161 station write-path and logging gate")
struct RV161StationLoggingGateTests {

    private static var iosRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TankbookCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ios
    }

    private func read(_ relative: String) throws -> String {
        try String(contentsOf: Self.iosRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    /// The core extraction files perform no logging at all.
    @Test func theExtractionSeamNeverLogs() throws {
        let files = [
            "Sources/TankbookCore/Extraction/StationNameExtractor.swift",
            "Sources/TankbookCore/Extraction/FuelExtraction.swift"
        ]
        for relative in files {
            let contents = try read(relative)
            let offenders = StationLogScanner.forbiddenTokens.filter { contents.contains($0) }
            #expect(offenders.isEmpty,
                    "\(relative) must never log (hard rule 12). Offenders: \(offenders)")
        }
    }

    /// In the app seams, no LINE that carries a station value may also log. The
    /// pre-fill and save files log legitimately elsewhere, so the scan is
    /// line-scoped: a station name, brand or address never rides a log call.
    @Test func noStationValueBearingLineLogs() throws {
        let files = [
            "App/Sources/ConfirmManual/ManualFillUpView.swift",
            "App/Sources/ConfirmManual/ManualFillUpView+StationStamp.swift",
            "App/Sources/ConfirmManual/ConfirmPrefill.swift",
            "Sources/TankbookCore/Extraction/FuelExtractor.swift"
        ]
        var offenders: [String] = []
        for relative in files {
            let contents = try read(relative)
            offenders.append(contentsOf: StationLogScanner.offenders(inFile: relative, text: contents))
        }
        #expect(offenders.isEmpty, Comment(stringLiteral: offenders.joined(separator: "\n")))
    }

    /// The write path: the scanned station is selected (the editable pre-fill)
    /// and persisted only at save, through the shared deterministic creator -
    /// never written from the raw extraction, and never with a fresh UUID.
    @Test func theScannedStationReachesTheEntryOnlyThroughTheEditableSelection() throws {
        let view = try read("App/Sources/ConfirmManual/ManualFillUpView.swift")
        #expect(view.contains("applyScannedStation(extraction.stationName)"),
                "the scan's station must flow into the editable row selection")
        #expect(view.contains("stationId: selectedStation?.id"),
                "the fill-up must carry the user-editable selection, not the raw extraction")
        #expect(!view.contains("stationId: extraction.stationName"),
                "the raw extraction must never be written straight onto the entry")

        let stamp = try read("App/Sources/ConfirmManual/ManualFillUpView+StationStamp.swift")
        #expect(stamp.contains("createStation(named:"),
                "the scanned station must persist through the shared deterministic creator")
        #expect(!stamp.contains("UUID("),
                "the scanned station must never mint a random UUID")
    }

    /// The scanner's teeth, proven on a deliberate violation: a station value
    /// on a logging line is flagged.
    @Test func theScannerFlagsADeliberateViolation() {
        let violating = """
            AppLog.error(operation: "x", category: .ui, error: error)
            AppLog.info(operation: "station.resolve", category: .ui, outcome: stationName)
            """
        let offenders = StationLogScanner.offenders(inFile: "Fixture.swift", text: violating)
        #expect(offenders.count == 1,
                "the scanner must flag exactly the line that logs a station value")
    }
}

/// The source scanner: flags a line that carries a station value AND a logging
/// call. Pure over text so a fixture can exercise it without a live tree.
enum StationLogScanner {
    /// Tokens that name a station value (never the bare word "station", which
    /// appears in stable operation codes like `confirmManual.stationCreate`).
    static let valueTokens = [
        "stationName", "selectedStation", "scannedStationID", "resolvedStation",
        "station.name", "station?.name", "brand", "address"
    ]

    static let forbiddenTokens = [
        "AppLog", "print(", "Logger(", "os_log", ".emit(", ".error(", ".warning(", ".info("
    ]

    static func offenders(inFile file: String, text: String) -> [String] {
        var found: [String] = []
        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("*") else { continue }
            let hasValue = valueTokens.contains { line.contains($0) }
            let logs = forbiddenTokens.contains { line.contains($0) }
            if hasValue, logs {
                found.append("\(file):\(index + 1): \(trimmed)")
            }
        }
        return found
    }
}
