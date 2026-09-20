import Foundation
@testable import TankbookCore

// P4.12 - the ONE scorer for the corpus A/B (cloud vision model vs the rules
// parser). The comparison is shared between the two arms on purpose: the whole
// point of the measurement is that both are scored by the same function and the
// same tolerance, so neither arm can be flattered by a subtly different
// comparison. The tolerance and the empty-skip rule are copied from
// `AccuracyRatchetTests` (abs(got - want) < 0.005; an empty expected.csv field
// is skipped, never scored as a miss).
//
// P6.14 - the scorer now also measures `fuelKind` and `currency`, which
// `FuelExtraction` has always carried and which neither the ratchet nor the A/B
// scored. An empty expected cell stays skipped, never a miss, for these columns
// exactly as for the numerics. The P4.12/P4.13 committed result files predate
// the two new columns and carry no value for either, so those frozen arms are
// scored through `loadExpectedNumericsOnly` - same scorer, same tolerance, an
// expected set from which the unmeasured columns are absent.

/// One image's extracted fields, as written by the sweep script (LLM arm) or the
/// rules dump (rules arm). A field is `nil` when the engine abstained or the call
/// failed; `error` carries the failure text when the whole image failed.
struct ExtractionRecord: Codable, Equatable, Sendable {
    let filename: String
    let liters: Double?
    let unitPrice: Double?
    let total: Double?
    let fuelKind: FuelKind?
    let currency: CurrencyCode?
    let latencySeconds: Double?
    let error: String?
    /// The station identity line the extractor offered (RV.161), scored by the
    /// `stations` class (RV.179). Absent from the frozen `vision-ab` files,
    /// which decode it as nil.
    let stationName: String?

    init(
        filename: String,
        liters: Double?,
        unitPrice: Double?,
        total: Double?,
        fuelKind: FuelKind? = nil,
        currency: CurrencyCode? = nil,
        latencySeconds: Double? = nil,
        error: String? = nil,
        stationName: String? = nil
    ) {
        self.filename = filename
        self.liters = liters
        self.unitPrice = unitPrice
        self.total = total
        self.fuelKind = fuelKind
        self.currency = currency
        self.latencySeconds = latencySeconds
        self.error = error
        self.stationName = stationName
    }
}

// MARK: - The boundary: extraction (Decimal money) -> record (Double)

extension ExtractionRecord {
    /// The one place a live `FuelExtraction` becomes a scored record (P2.2b).
    ///
    /// The record deliberately keeps `Double` money fields: it is the shape of
    /// the COMMITTED `vision-ab/*.json` result files, which are a frozen
    /// measurement whose values decode as JSON numbers. Re-typing them to
    /// `Decimal` would not add exactness (Swift's default `Decimal` decoding
    /// routes through `Double` anyway) and would churn the decoder for no
    /// measured gain: the scorer compares with `abs(got - want) < 0.005`, far
    /// above any representation error for a 2-3 decimal money value, so the
    /// pinned totals cannot move either way. `Decimal -> Double` here is exact
    /// in the measured direction - `NSDecimalNumber(decimal:).doubleValue` is
    /// the nearest `Double` to the exact decimal, i.e. the same `Double` the
    /// pre-P2.2b pipeline stored.
    init(filename: String, extraction: FuelExtraction,
         latencySeconds: Double? = nil, error: String? = nil) {
        self.init(
            filename: filename,
            liters: extraction.liters,
            unitPrice: extraction.unitPrice.map(\.corpusBoundaryDouble),
            total: extraction.total.map(\.corpusBoundaryDouble),
            fuelKind: extraction.fuelKind,
            currency: extraction.currency,
            latencySeconds: latencySeconds,
            error: error,
            stationName: extraction.stationName
        )
    }
}

// MARK: - The Double the pre-P2.2b pipeline stored

extension Decimal {
    /// The `Double` whose value equals this decimal's shortest decimal
    /// representation - the faithful inverse of the extraction's
    /// `Double -> Decimal(string:)` boundary. This is the same `Double` the
    /// old Double pipeline stored, so converting an extraction's Decimal back
    /// for the scorer reproduces the committed numbers bit-for-bit. Plain
    /// `NSDecimalNumber(decimal:).doubleValue` is NOT guaranteed correct here:
    /// it lands one ULP off for values like 1.774.
    var corpusBoundaryDouble: Double {
        Double("\(self)") ?? 0
    }
}

/// The committed per-class result file (one of `vision-ab/rules-*.json` /
/// `vision-ab/llm-*.json`). Self-describing so a re-score never has to guess
/// which engine produced it.
struct ABResultFile: Codable {
    let engine: String
    let className: String
    let generated: String
    let entries: [ExtractionRecord]

    var recordsByFilename: [String: ExtractionRecord] {
        Dictionary(entries.map { ($0.filename, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Ground truth for one image, from a class's `expected.csv`. Empty fields stay
/// `nil` - that is what makes them "skipped, not missed". `fuelKind` and
/// `currency` are compared exactly (they are enum values, not measurements), so
/// they carry no tolerance.
struct ExpectedRow: Equatable, Sendable {
    let liters: Double?
    let unitPrice: Double?
    let total: Double?
    let fuelKind: FuelKind?
    let currency: CurrencyCode?
    /// RV.179: the station the paper names, as the runs of normalised tokens
    /// (`StationBrandMatcher.normalisedTokens`) the extracted line must contain
    /// - `circle k`, `krym oil`, `lukoil|lukoyl` for a brand the receipt may
    /// print in either script. Written from the fixture FILENAME, which the
    /// owner named from the paper before any station extractor existed, and
    /// cross-checked against the OCR text; a cell the two cannot agree on is
    /// left empty and listed in `receipts/stations.md` with its reason.
    let station: [[String]]?

    init(
        liters: Double? = nil,
        unitPrice: Double? = nil,
        total: Double? = nil,
        fuelKind: FuelKind? = nil,
        currency: CurrencyCode? = nil,
        station: [[String]]? = nil
    ) {
        self.liters = liters
        self.unitPrice = unitPrice
        self.total = total
        self.fuelKind = fuelKind
        self.currency = currency
        self.station = station
    }

    /// Parses the `station` cell: alternatives separated by `|`, tokens by
    /// space, each run normalised exactly as the extracted line will be.
    static func parseStation(_ cell: String) -> [[String]]? {
        let runs = cell.split(separator: "|").map { StationBrandMatcher.normalisedTokens(String($0)) }
            .filter { !$0.isEmpty }
        return runs.isEmpty ? nil : runs
    }
}

/// Per-class hits/total, identical in shape to `AccuracyRatchetTests.ScoredClass`.
struct ScoredClass: Equatable, Sendable {
    let name: String
    let hits: Int
    let total: Int
}

enum CorpusScorer {
    /// The single tolerance every arm is scored with. Must match
    /// `AccuracyRatchetTests` exactly - do not fork it.
    static let tolerance = 0.005

    /// The image extensions the scorer walks, identical to the ratchet's.
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff"]

    /// Scores one class. `images` is the set of image files the corpus holds for
    /// that class (the same enumeration the ratchet walks); `records` maps each
    /// image to its extraction. An image with no record - the sweep never
    /// attempted it, or dropped it - counts every one of its expected fields as a
    /// miss, never as a skip: a silently skipped image would inflate the score.
    static func score(
        name: String,
        images: [String],
        records: [String: ExtractionRecord],
        expected: [String: ExpectedRow]
    ) -> ScoredClass {
        var hits = 0
        var total = 0
        for image in images {
            guard let want = expected[image] else { continue }
            let record = records[image] // nil => never attempted => all miss
            if let wantValue = want.liters {
                total += 1
                if let got = record?.liters, abs(got - wantValue) < tolerance { hits += 1 }
            }
            if let wantValue = want.unitPrice {
                total += 1
                if let got = record?.unitPrice, abs(got - wantValue) < tolerance { hits += 1 }
            }
            if let wantValue = want.total {
                total += 1
                if let got = record?.total, abs(got - wantValue) < tolerance { hits += 1 }
            }
            // P6.14: `fuelKind` and `currency` are enum values, so they are
            // compared exactly - the numeric tolerance does not apply. The
            // empty-skip rule is identical: an empty expected cell adds no total
            // and cannot miss; a nil extracted value against a non-empty
            // expectation is a miss, never a skip.
            if let wantKind = want.fuelKind {
                total += 1
                if record?.fuelKind == wantKind { hits += 1 }
            }
            if let wantCurrency = want.currency {
                total += 1
                if record?.currency == wantCurrency { hits += 1 }
            }
        }
        return ScoredClass(name: name, hits: hits, total: total)
    }

    // MARK: - Pump scoring (B1): numeric-only, precision + coverage

    // The pump class's re-scoped scorer lives in `CorpusPumpScorer.swift`, with
    // its score shape, to keep this file under its length limit. The pump is
    // scored on its 178 numeric cells only; `currency` is reported separately
    // and `fuelKind` is never scored (a pump parser must not produce it).

    /// Parses a class's `expected.csv` (header
    /// `filename,liters,unitPrice,total,fuelKind,currency`). An empty column
    /// becomes `nil` - the field is skipped, not guessed. `fuelKind` is written
    /// as a `FuelKind` raw value (e.g. `petrol95`, `diesel`), `currency` as an
    /// ISO-4217 code (e.g. `RUB`, `EUR`, `KZT`); both are compared exactly.
    static func loadExpected(_ url: URL) throws -> [String: ExpectedRow] {
        let csv = try String(contentsOf: url, encoding: .utf8)
        var result: [String: ExpectedRow] = [:]
        for line in csv.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 4 else { continue }
            result[cols[0]] = ExpectedRow(
                liters: Double(cols[1]),
                unitPrice: Double(cols[2]),
                total: Double(cols[3]),
                fuelKind: cols.count > 4 ? FuelKind(rawValue: cols[4]) : nil,
                currency: cols.count > 5 ? CurrencyCode(rawValue: cols[5]) : nil,
                station: cols.count > 6 ? ExpectedRow.parseStation(cols[6]) : nil
            )
        }
        return result
    }

    /// RV.179: the station class - one cell per receipt whose `station` column
    /// is asserted. A hit is an extracted line whose normalised tokens contain
    /// one of the expected runs; an abstention against an asserted cell is a
    /// MISS, never a skip (the generous-blank trap that produced a fake 46/46).
    /// Scored as its own class so the receipts marks - the ratchet's and
    /// `CorpusCompressionTests`' - keep their cell counts.
    static func scoreStations(
        images: [String],
        records: [String: ExtractionRecord],
        expected: [String: ExpectedRow]
    ) -> (score: ScoredClass, misses: [String]) {
        var hits = 0
        var total = 0
        var misses: [String] = []
        for image in images {
            guard let runs = expected[image]?.station else { continue }
            total += 1
            let tokens = records[image]?.stationName.map(StationBrandMatcher.normalisedTokens) ?? []
            let hit = runs.contains { run in
                guard run.count <= tokens.count else { return false }
                return (0...(tokens.count - run.count)).contains { Array(tokens[$0..<($0 + run.count)]) == run }
            }
            if hit {
                hits += 1
            } else {
                let wanted = runs.map { $0.joined(separator: " ") }.joined(separator: " | ")
                misses.append("\(image): got \(records[image]?.stationName ?? "nil"), expected \(wanted)")
            }
        }
        return (ScoredClass(name: "stations", hits: hits, total: total), misses)
    }

    /// The legacy numeric-only view of an `expected.csv` (columns
    /// `liters,unitPrice,total`), used by the P4.12/P4.13 A/B arms and their
    /// dump generators. Their committed result files predate the
    /// `fuelKind`/`currency` columns, so no record in them carries a value for
    /// either; scoring those columns against such a file would count every new
    /// field as a miss and silently rewrite what the frozen arms measured - and
    /// their pinned totals are part of the measurement (a re-sweep is not a way
    /// back: the cloud arm is stochastic). Same CSV, same header - only which
    /// columns are read differs. The comparison itself stays the one `score`.
    static func loadExpectedNumericsOnly(_ url: URL) throws -> [String: ExpectedRow] {
        let csv = try String(contentsOf: url, encoding: .utf8)
        var result: [String: ExpectedRow] = [:]
        for line in csv.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 4 else { continue }
            result[cols[0]] = ExpectedRow(
                liters: Double(cols[1]),
                unitPrice: Double(cols[2]),
                total: Double(cols[3])
            )
        }
        return result
    }

    /// Decodes a committed `vision-ab/*.json` result file.
    static func loadABResultFile(_ url: URL) throws -> ABResultFile {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ABResultFile.self, from: data)
    }

    /// The image filenames in a class folder, sorted, using the same extension
    /// filter as the ratchet. `.qr.txt`, `.pdf` and README files are excluded.
    static func imageFilenames(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .map(\.lastPathComponent)
            .sorted()
    }

    /// The fiscal-QR anchor a fixture's committed `.qr.txt` sidecar decodes to,
    /// or nil when the fixture has no sidecar (or one that fails to parse). A
    /// missing QR is a plain absence, never an error - the extraction then runs
    /// on OCR alone, exactly as the app does when the detector finds no barcode.
    static func qrAnchor(forImage image: String,
                         in folder: URL,
                         timeZone: TimeZone = .current) -> FiscalQRAnchor? {
        let base = (image as NSString).deletingPathExtension
        let url = folder.appendingPathComponent("\(base).qr.txt")
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return (try? FiscalQRParser.parse(raw.trimmingCharacters(in: .whitespacesAndNewlines),
                                          timeZone: timeZone))?.anchor
    }

    /// The images a committed sweep actually covered: the live folder narrowed
    /// to the filenames the result file holds a record for.
    ///
    /// **Why the A/B is scored over this and not over the live folder.** The
    /// P4.12/P4.13 sweeps are a FROZEN measurement of one corpus snapshot
    /// (2026-08-26), and their whole value is that three arms scored the *same*
    /// images. The corpus keeps growing, and re-sweeping is not a way back:
    /// the cloud arm is stochastic (`vision-ab/README.md` - a re-sweep does not
    /// reproduce these values, which is itself a P4.12 finding), and the
    /// PaddleOCR arm needs a container P4.13 concluded is not worth running.
    /// So a fixture added after the sweep is **outside** the snapshot, not a
    /// hole in it.
    ///
    /// This does not weaken the "no image silently skipped" guarantee, because
    /// the per-class totals stay pinned as literals (96 / 46 / 3 / 24): a
    /// record missing from the sweep lowers the total and fails that pin. What
    /// the callers add on top is the other direction - every live image must be
    /// either swept or listed as a known post-sweep addition, so growth is
    /// declared rather than absorbed.
    static func sweptImages(in folder: URL, coveredBy file: ABResultFile) throws -> [String] {
        try imageFilenames(in: folder).filter { file.recordsByFilename[$0] != nil }
    }
}
