import Foundation

// ReceiptSpike – measure how well on-device OCR + deterministic rules extract
// fuel data from receipt and pump-display photos, before building any app UI.
//
// Usage:
//   swift run ReceiptSpike <folder-with-images> [--dump-text] [--json]
//
// Optional ground truth: put expected.csv next to the images with lines like
//   filename,liters,unitPrice,total
//   receipt-01.jpg,42.30,1.679,71.02
// and the tool reports field-level accuracy.

let arguments = CommandLine.arguments.dropFirst()
let dumpText = arguments.contains("--dump-text")
let asJSON = arguments.contains("--json")
guard let folder = arguments.first(where: { !$0.hasPrefix("--") }) else {
    print("Usage: swift run ReceiptSpike <folder-with-images> [--dump-text] [--json]")
    exit(1)
}

let folderURL = URL(fileURLWithPath: folder)
let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff"]
let files = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil))?
    .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

guard !files.isEmpty else {
    print("No images found in \(folderURL.path). Drop receipt/pump photos there first.")
    exit(1)
}

// Ground truth, if provided.
struct Expected { let liters: Double?; let unitPrice: Double?; let total: Double? }
var expected: [String: Expected] = [:]
if let csv = try? String(contentsOf: folderURL.appendingPathComponent("expected.csv"), encoding: .utf8) {
    for line in csv.split(separator: "\n").dropFirst() {
        let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard cols.count >= 4 else { continue }
        expected[cols[0]] = Expected(liters: Double(cols[1]), unitPrice: Double(cols[2]), total: Double(cols[3]))
    }
}

let languages = ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"]
let parser = FuelReceiptParser()

func fmt(_ value: Double?) -> String { value.map { String(format: "%.3f", $0) } ?? "–" }
func matches(_ got: Double?, _ want: Double?) -> Bool? {
    guard let want else { return nil }
    guard let got else { return false }
    return abs(got - want) < 0.005
}

struct Report: Codable {
    let file: String
    let extraction: FuelExtraction
    let crossCheck: Bool
    let lineCount: Int
}

var reports: [Report] = []
var fieldHits = 0, fieldTotal = 0

for file in files {
    do {
        let lines = try recognizeText(in: file, languages: languages)
        if dumpText {
            print("\n═══ \(file.lastPathComponent) – raw OCR ═══")
            for line in lines {
                print(String(format: "  [%.2f] %@", line.confidence, line.text))
            }
        }
        let extraction = parser.parse(lines: lines.map(\.text))
        reports.append(Report(
            file: file.lastPathComponent,
            extraction: extraction,
            crossCheck: extraction.crossCheckPassed,
            lineCount: lines.count
        ))
        if let want = expected[file.lastPathComponent] {
            for check in [matches(extraction.liters, want.liters),
                          matches(extraction.unitPrice, want.unitPrice),
                          matches(extraction.total, want.total)] {
                if let check {
                    fieldTotal += 1
                    if check { fieldHits += 1 }
                }
            }
        }
    } catch {
        print("✗ \(file.lastPathComponent): \(error)")
    }
}

if asJSON {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(data: try encoder.encode(reports), encoding: .utf8)!)
} else {
    print("\nFile                            Liters    €/unit    Total     Curr  Fuel      Check")
    print(String(repeating: "─", count: 88))
    for r in reports {
        let e = r.extraction
        print(
            r.file.padding(toLength: 32, withPad: " ", startingAt: 0)
            + fmt(e.liters).padding(toLength: 10, withPad: " ", startingAt: 0)
            + fmt(e.unitPrice).padding(toLength: 10, withPad: " ", startingAt: 0)
            + fmt(e.total).padding(toLength: 10, withPad: " ", startingAt: 0)
            + (e.currency ?? "–").padding(toLength: 6, withPad: " ", startingAt: 0)
            + (e.fuelType ?? "–").padding(toLength: 10, withPad: " ", startingAt: 0)
            + (r.crossCheck ? "✓" : "✗")
        )
    }
    let passed = reports.filter(\.crossCheck).count
    print("\nCross-check passed: \(passed)/\(reports.count)")
    if fieldTotal > 0 {
        let pct = 100.0 * Double(fieldHits) / Double(fieldTotal)
        print(String(format: "Ground-truth field accuracy: %d/%d (%.1f%%)", fieldHits, fieldTotal, pct))
    } else {
        print("No expected.csv found – add one for field-level accuracy scoring.")
    }
}
