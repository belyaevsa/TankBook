import Foundation
import Testing
@testable import TankbookCore

#if canImport(Vision)
import Vision

// RV.48 diagnostics - the per-field, per-fixture miss report for the RECEIPT
// class. The ratchet reports one number per class; improving the parser needs
// to know WHICH cell missed on WHICH fixture and what the OCR actually said.
//
//   cd ios && TANKBOOK_WRITE_CORPUS_FILES=1 TANKBOOK_DIAG_OUT=/path/dir \
//     swift test --filter ReceiptFieldDiagnostics
//
// Without the env var it is a no-op, so CI never writes files.
@Suite("RV.48 receipt field diagnostics (Vision-gated)")
struct ReceiptFieldDiagnosticsTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let fixturesRoot = repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures")

    private static let languages = ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"]

    @Test func dumpReceiptFieldOutcomes() throws {
        guard ProcessInfo.processInfo.environment["TANKBOOK_WRITE_CORPUS_FILES"] == "1",
              let out = ProcessInfo.processInfo.environment["TANKBOOK_DIAG_OUT"] else { return }
        let outDir = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let folder = Self.fixturesRoot.appendingPathComponent("receipts")
        let expected = try CorpusScorer.loadExpected(folder.appendingPathComponent("expected.csv"))
        let images = try CorpusScorer.imageFilenames(in: folder)
        let extractor = FuelExtractor()

        var report = ""
        var lineDump = ""
        var hits = 0
        var total = 0
        var missesByField: [String: Int] = [:]
        for image in images {
            guard let want = expected[image] else { continue }
            let url = folder.appendingPathComponent(image)
            let ocrLines = try VisionTextRecognizer.recognizeText(in: url, languages: Self.languages)
            let got = extractor.extract(lines: ocrLines, source: .receipt)

            func cell(_ name: String, _ wantValue: Double?, _ gotValue: Double?) -> String {
                guard let wantValue else { return "" }
                total += 1
                let ok = gotValue.map { abs($0 - wantValue) < CorpusScorer.tolerance } ?? false
                if ok { hits += 1 } else { missesByField[name, default: 0] += 1 }
                let gotText = gotValue.map { String(format: "%.3f", $0) } ?? "nil"
                return "  \(ok ? "HIT " : "MISS") \(name): want \(String(format: "%.3f", wantValue)) got \(gotText)\n"
            }
            func enumCell(_ name: String, _ wantValue: String?, _ gotValue: String?) -> String {
                guard let wantValue else { return "" }
                total += 1
                let ok = wantValue == gotValue
                if ok { hits += 1 } else { missesByField[name, default: 0] += 1 }
                return "  \(ok ? "HIT " : "MISS") \(name): want \(wantValue) got \(gotValue ?? "nil")\n"
            }

            report += "\(image)\n"
            report += cell("liters", want.liters, got.liters)
            report += cell("unitPrice", want.unitPrice, got.unitPrice.map(\.corpusBoundaryDouble))
            report += cell("total", want.total, got.total.map(\.corpusBoundaryDouble))
            report += enumCell("fuelKind", want.fuelKind?.rawValue, got.fuelKind?.rawValue)
            report += enumCell("currency", want.currency?.rawValue, got.currency?.rawValue)
            report += "  crossCheck: \(got.crossCheck)  date: \(got.date.map(String.init(describing:)) ?? "nil")\n"

            lineDump += "===== \(image) =====\n"
            for line in ocrLines {
                if let noise = ReceiptNoiseFilter.classify(line.text) {
                    lineDump += "[FILTERED \(noise.rawValue)] \(line.text)\n"
                    continue
                }
                lineDump += String(format: "[y=%.3f x=%.3f w=%.3f conf=%.2f] %@\n",
                                   line.boundingBox.midY, line.boundingBox.midX,
                                   line.boundingBox.width, line.confidence, line.text)
            }
        }
        report = "receipts \(hits)/\(total)\nmisses by field: "
            + missesByField.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            + "\n\n" + report
        try report.write(to: outDir.appendingPathComponent("receipt-field-report.txt"),
                         atomically: true, encoding: .utf8)
        try lineDump.write(to: outDir.appendingPathComponent("receipt-ocr-lines.txt"),
                           atomically: true, encoding: .utf8)
    }
}

#endif
