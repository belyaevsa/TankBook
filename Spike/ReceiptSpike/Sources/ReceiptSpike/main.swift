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
//
// An EXPENSE folder (`fixtures/expenses`) is recognised by its expected.csv
// header carrying `category`. There the fixtures are `.txt` OCR dumps, not
// photographs: the harness scores each `.txt` directly (total, currency, date,
// kind), writes `recognised.csv` beside `expected.csv` with what it produced,
// and with `--dump-text` turns a newly dropped photograph into the `.txt` its
// expected.csv row names. `recognised.csv` is a review artefact, NEVER an
// oracle: ground truth stays in `expected.csv`, written by hand.

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

let expectedURL = folderURL.appendingPathComponent("expected.csv")
let expectedCSV = try? String(contentsOf: expectedURL, encoding: .utf8)
let expectedHeader = expectedCSV?.split(separator: "\n").first.map(String.init) ?? ""

let languages = ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"]

// MARK: - Expense folder

/// One `expenses/expected.csv` row, raw strings - the oracle is read here and
/// only here, never from `recognised.csv`.
struct ExpenseExpectedRow {
    let filename: String
    let category: String
    let total: String
    let currency: String
    let date: String
}

func parseExpenseRows(_ csv: String) -> [ExpenseExpectedRow] {
    csv.split(separator: "\n").dropFirst().map { line in
        let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        func cell(_ index: Int) -> String {
            index < cols.count ? cols[index].trimmingCharacters(in: .whitespaces) : ""
        }
        return ExpenseExpectedRow(filename: cell(0), category: cell(1), total: cell(2),
                                  currency: cell(3), date: cell(4))
    }
}

/// Parses either the extractor's `dd.MM.yy` / `dd.MM.yyyy` or the oracle's
/// `yyyy-MM-dd` into a comparable `Date` (day granularity).
func parseDay(_ raw: String) -> Date? {
    let parts = raw.trimmingCharacters(in: .whitespaces)
        .split(whereSeparator: { $0 == "." || $0 == "/" || $0 == "-" }).compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    let calendar = Calendar(identifier: .gregorian)
    if parts[0] > 31 {
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
    let year = parts[2] < 100 ? (parts[2] < 50 ? 2000 + parts[2] : 1900 + parts[2]) : parts[2]
    return calendar.date(from: DateComponents(year: year, month: parts[1], day: parts[0]))
}

func fmtExpense(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "" }

/// One fixture's produced row plus its scored cells.
struct ExpenseRowScore {
    let line: String
    let hits: Int
    let total: Int
}

/// Turns a newly dropped photograph into the `.txt` its expected.csv row names,
/// once. An existing `.txt` - a committed Vision dump or a hand-authored
/// fixture - is never overwritten.
func dumpNewPhotographs() {
    for image in files {
        let base = image.deletingPathExtension().lastPathComponent
        let txtURL = folderURL.appendingPathComponent("\(base).txt")
        guard !FileManager.default.fileExists(atPath: txtURL.path) else { continue }
        do {
            let lines = try recognizeText(in: image, languages: languages)
            print("\n═══ \(image.lastPathComponent) – raw OCR ═══")
            for line in lines { print(String(format: "  [%.2f] %@", line.confidence, line.text)) }
            try lines.map(\.text).joined(separator: "\n")
                .appending("\n").write(to: txtURL, atomically: true, encoding: .utf8)
            print("wrote \(txtURL.lastPathComponent) (\(lines.count) lines)")
        } catch {
            print("✗ \(image.lastPathComponent): \(error)")
        }
    }
}

/// One fixture's produced values (the `recognised.csv` row) plus the cells it
/// scored. The `.txt` is the extractor's INPUT, so it is scored without a
/// second Vision pass; the photograph is only where the `.txt` came from.
func scoreExpenseRow(_ row: ExpenseExpectedRow,
                     parser: FuelReceiptParser) -> ExpenseRowScore {
    let txtURL = folderURL.appendingPathComponent(row.filename)
    guard let text = try? String(contentsOf: txtURL, encoding: .utf8) else {
        print("✗ \(row.filename): no .txt fixture (drop the photo and run with --dump-text)")
        return ExpenseRowScore(line: "\(row.filename),,,,", hits: 0, total: 0)
    }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    let extraction = parser.parse(lines: lines)
    let kind = FuelReceiptParser.expenseKind(lines: lines)
    let line = "\(row.filename),\(fmtExpense(extraction.total)),\(extraction.currency ?? ""),"
        + "\(extraction.date ?? ""),\(kind ?? "")"

    var hits = 0
    var total = 0
    if !row.category.isEmpty {
        total += 1
        if (kind ?? "none") == row.category { hits += 1 }
    }
    if let want = Double(row.total) {
        total += 1
        if let got = extraction.total, abs(got - want) < 0.005 { hits += 1 }
    }
    if !row.currency.isEmpty {
        total += 1
        if extraction.currency == row.currency { hits += 1 }
    }
    if !row.date.isEmpty {
        total += 1
        if let got = extraction.date.flatMap(parseDay), let want = parseDay(row.date),
           got == want { hits += 1 }
    }
    return ExpenseRowScore(line: line, hits: hits, total: total)
}

func writeRecognised(_ lines: [String]) {
    do {
        try lines.joined(separator: "\n").appending("\n")
            .write(to: folderURL.appendingPathComponent("recognised.csv"),
                   atomically: true, encoding: .utf8)
    } catch {
        print("✗ could not write recognised.csv: \(error)")
    }
}

func reportExpenseScore(hits: Int, total: Int) {
    if asJSON {
        let payload: [String: Any] = ["class": "expenses", "hits": hits, "total": total]
        if let data = try? JSONSerialization.data(withJSONObject: payload,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            print(String(data: data, encoding: .utf8) ?? "")
        }
    } else {
        let pct = total > 0 ? 100.0 * Double(hits) / Double(total) : 0
        print(String(format: "\nexpenses: %d/%d (%.1f%%)", hits, total, pct))
        print("wrote recognised.csv beside expected.csv")
    }
}

/// Scores the expense folder and writes its `recognised.csv`.
func runExpenseFolder(_ csv: String) {
    let parser = FuelReceiptParser()
    let rows = parseExpenseRows(csv)
    guard !rows.isEmpty else {
        print("No expected.csv rows in \(folderURL.path).")
        return
    }
    if dumpText { dumpNewPhotographs() }

    var hits = 0
    var total = 0
    var recognised = [
        "# recognised.csv - what the extractor PRODUCED, written by `swift run ReceiptSpike fixtures/expenses`.",
        "# NEVER the oracle: ground truth is expected.csv, written by hand from the paper.",
        "filename,total,currency,date,kind"
    ]
    for row in rows {
        let scored = scoreExpenseRow(row, parser: parser)
        recognised.append(scored.line)
        hits += scored.hits
        total += scored.total
    }
    writeRecognised(recognised)
    reportExpenseScore(hits: hits, total: total)
}

if expectedHeader.contains("category") {
    if let csv = expectedCSV {
        runExpenseFolder(csv)
    } else {
        print("No expected.csv found in \(folderURL.path). Add one for field-level accuracy scoring.")
    }
    exit(0)
}

guard !files.isEmpty else {
    print("No images found in \(folderURL.path). Drop receipt/pump photos there first.")
    exit(1)
}

// MARK: - Fuel folder

// Ground truth, if provided.
struct Expected { let liters: Double?; let unitPrice: Double?; let total: Double? }
var expected: [String: Expected] = [:]
if let csv = expectedCSV {
    for line in csv.split(separator: "\n").dropFirst() {
        let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard cols.count >= 4 else { continue }
        expected[cols[0]] = Expected(liters: Double(cols[1]), unitPrice: Double(cols[2]), total: Double(cols[3]))
    }
}

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
