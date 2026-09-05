import Foundation
import Testing
@testable import TankbookCore

#if canImport(Vision)
import Vision

// B2 diagnostics - the per-field, per-fixture report for the PUMP class, the
// twin of `ReceiptFieldDiagnosticsTests`. The gate reports precision and
// coverage over the class; improving the ladder needs to know WHICH cell was
// committed on WHICH fixture, which abstained, and what the OCR actually said.
//
//   cd ios && TANKBOOK_WRITE_CORPUS_FILES=1 TANKBOOK_DIAG_OUT=/path/dir \
//     swift test --filter PumpFieldDiagnostics
//
// Without the env vars it is a no-op, so CI never writes files.
@Suite("B2 pump field diagnostics (Vision-gated)")
struct PumpFieldDiagnosticsTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let fixturesRoot = repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures")

    private static let languages = ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"]

    @Test func dumpPumpFieldOutcomes() throws {
        guard ProcessInfo.processInfo.environment["TANKBOOK_WRITE_CORPUS_FILES"] == "1",
              let out = ProcessInfo.processInfo.environment["TANKBOOK_DIAG_OUT"] else { return }
        let outDir = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let folder = Self.fixturesRoot.appendingPathComponent("pump")
        let expected = try CorpusScorer.loadExpected(folder.appendingPathComponent("expected.csv"))
        let images = try CorpusScorer.imageFilenames(in: folder)
        let pack = try FuelPriceBandStore.bundledPack()
        let extractor = FuelExtractor(bandProvider: DefaultFuelPriceBandProvider(pack: pack))

        var report = ""
        var lineDump = ""
        var committed = 0, correct = 0, scored = 0
        for image in images {
            guard let want = expected[image] else { continue }
            let ocrLines = try VisionTextRecognizer.recognizeText(
                in: folder.appendingPathComponent(image), languages: Self.languages)
            let got = extractor.extract(lines: ocrLines, source: .pump)

            func cell(_ name: String, _ wantValue: Double?, _ gotValue: Double?) -> String {
                guard let wantValue else {
                    // Ground truth is empty: the photograph does not carry it, so
                    // committing anything here is a WRONG value, not a bonus.
                    guard let gotValue else { return "" }
                    committed += 1
                    return "  WRONG \(name): truth is EMPTY, got \(String(format: "%.3f", gotValue))\n"
                }
                scored += 1
                guard let gotValue else { return "  abstain \(name): want \(String(format: "%.3f", wantValue))\n" }
                committed += 1
                let ok = abs(gotValue - wantValue) < CorpusScorer.tolerance
                if ok { correct += 1 }
                return "  \(ok ? "HIT  " : "WRONG") \(name): want \(String(format: "%.3f", wantValue)) "
                    + "got \(String(format: "%.3f", gotValue))\n"
            }

            report += "\(image)\n"
            report += cell("liters", want.liters, got.liters)
            report += cell("unitPrice", want.unitPrice, got.unitPrice.map(\.corpusBoundaryDouble))
            report += cell("total", want.total, got.total.map(\.corpusBoundaryDouble))

            lineDump += "===== \(image) =====\n"
            for line in ocrLines {
                lineDump += String(format: "[y=%.3f x=%.3f w=%.3f] %@\n",
                                   line.boundingBox.midY, line.boundingBox.midX,
                                   line.boundingBox.width, line.text)
            }
        }
        let precision = committed > 0 ? Double(correct) / Double(committed) : 0
        let coverage = scored > 0 ? Double(committed) / Double(scored) : 0
        report = String(format: "pump numeric: %d/%d correct, committed %d, precision %.1f%%, coverage %.1f%%\n\n",
                        correct, scored, committed, precision * 100, coverage * 100) + report
        try report.write(to: outDir.appendingPathComponent("pump-field-report.txt"),
                         atomically: true, encoding: .utf8)
        try lineDump.write(to: outDir.appendingPathComponent("pump-ocr-geometry.txt"),
                           atomically: true, encoding: .utf8)
    }
}

#endif
