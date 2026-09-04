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

    init(
        filename: String,
        liters: Double?,
        unitPrice: Double?,
        total: Double?,
        fuelKind: FuelKind? = nil,
        currency: CurrencyCode? = nil,
        latencySeconds: Double? = nil,
        error: String? = nil
    ) {
        self.filename = filename
        self.liters = liters
        self.unitPrice = unitPrice
        self.total = total
        self.fuelKind = fuelKind
        self.currency = currency
        self.latencySeconds = latencySeconds
        self.error = error
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
            error: error
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

    init(
        liters: Double? = nil,
        unitPrice: Double? = nil,
        total: Double? = nil,
        fuelKind: FuelKind? = nil,
        currency: CurrencyCode? = nil
    ) {
        self.liters = liters
        self.unitPrice = unitPrice
        self.total = total
        self.fuelKind = fuelKind
        self.currency = currency
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
                currency: cols.count > 5 ? CurrencyCode(rawValue: cols[5]) : nil
            )
        }
        return result
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

/// Images added to the corpus **after** the 2026-08-26 A/B sweep, per class.
/// Adding a fixture means adding it here, which is the deliberate act that keeps
/// corpus growth from silently shrinking the A/B's coverage.
enum PostSweepCorpusAdditions {
    /// 2026-08-27, the Татнефть АЗС-172 triplet (one 25 L / 99.99 RUB fill shot
    /// three ways) and the Circle K Sikupilli set (a matched receipt/pump pair,
    /// a zero-volume receipt, and three sun-glared Wayne displays). See
    /// `Spike/ReceiptSpike/fixtures/receipts/README.md` and `pump/README.md`.
    static let byClass: [String: Set<String>] = [
        "receipts": [
            "receipt-036-tatneft-azs172-98-terminal-slip-ru.jpeg",
            "receipt-037-tatneft-azs172-98-vat22-qr-ru.jpeg",
            "receipt-038-circlek-sikupilli-95e0-pump8-ee.jpg",
            "receipt-039-circlek-sikupilli-zero-volume-pump7-ee.jpg",
            // The matched half of pump-029: same fill, same forecourt, same
            // minute. Declared, not swept - the A/B arms are frozen.
            "receipt-040-gpn-okulovka-gdrive95-fuelcard-ru.jpg",
            // 2026-08-30: the matched half of pump-030 - same fill, same
            // minute, a Tver fuel card. Declared, not swept.
            "receipt-041-zolotaya-seredina-tver-95-fuelcard-ru.jpg",
            // 2026-08-31: the matched half of pump-034 - Circle K Jarvevana,
            // Tallinn, 87.29 L of D B0 at 1.839. Declared, not swept.
            "receipt-042-circlek-jarvevana-tallinn-db0-pump7-ee.jpg",
            // 2026-09-01: a Sverdlovsk AI-95 receipt reposted through a news
            // channel, so a watermark is composited OVER the product line.
            // Declared, not swept.
            "receipt-043-artemovsk-gazservis-95-vat22-watermark-ru.jpg",
            // 2026-09-03: a Russian NON-FISCAL terminal slip (the matched half
            // of pump-044, and the corpus's first of that class - no fiscal QR
            // exists on one), and the paper half of pump-054, whose printed
            // total is a cent above litres x price. Declared, not swept.
            "receipt-044-rn-tver-chkalovskaya-95-nonfiscal-terminal-slip-ru.jpeg",
            "receipt-045-circlek-jarvevana-pump7-db0-2694l-ee.jpg",
            // 2026-09-04: the matched half of pump-057 - Circle K Sikupilli,
            // pump 5, 55.80 L of D B0 miles at 1.799 = 100.38, VAT 24%.
            // Declared, not swept.
            "receipt-046-circlek-sikupilli-pump5-db0-5580l-ee.jpg",
            // 2026-09-04: the matched halves of pump-065 and pump-066 - two RU
            // fills shot the same day, each photographed at the pump and on
            // paper. They bracket the RUB price band: 048's 15 L falls below
            // the 40 floor and sweeps 5/5, 047's 53 L sits inside it and
            // abstains on both operands. Declared, not swept - the arms are
            // frozen, and these arrived at 1280 px through Telegram.
            "receipt-047-gazpromneft-edrovo-gdrive95-fuelcard-pair-ru.jpeg",
            "receipt-048-rn-tver-budovo-95-nonfiscal-terminal-slip-pair-ru.jpeg",
        ],
        "pump": [
            "pump-018-gilbarco-tatneft-tver-98-ru.jpeg",
            "pump-019-gilbarco-circlek-sikupilli-pump8-ee.jpg",
            "pump-020-gilbarco-circlek-sikupilli-pump7-ee.jpg",
            "pump-021-wayne-circlek-sun-glare-ee.jpg",
            "pump-022-wayne-circlek-pump1-glare-ee.jpg",
            "pump-023-wayne-circlek-glare-ee.jpg",
            // 2026-08-28: five Estonian additions (Neste Wayne x2, Circle K
            // Gilbarco x3). Declared, not swept: the A/B result files are
            // frozen at their pinned numbers and re-running the arms would
            // rebaseline P4.12/P4.13, which is a separate decision.
            "pump-024-wayne-neste-ee-three-grade-prices.jpg",
            "pump-025-wayne-neste-ee-glare-obscured-total.jpg",
            "pump-026-gilbarco-circlek-ee-comma-decimal.jpg",
            "pump-027-gilbarco-circlek-ee-comma-glare.jpg",
            "pump-028-gilbarco-circlek-ee-comma-decimal-b.jpg",
            "pump-029-dresser-wayne-gpn-okulovka-ru-glare-total.jpg",
            // 2026-08-30: the corpus's first TOKHEIM, and the matched half
            // of receipt-041. Declared, not swept.
            "pump-030-tokheim-zolotaya-seredina-tver-ru-comma.jpg",
            // 2026-08-31: eight Estonian Circle K displays - two Gilbarco and
            // six Dresser Wayne, including the matched half of receipt-042.
            // Declared, not swept.
            "pump-031-gilbarco-circlek-ee-discount-mismatch.jpg",
            "pump-032-gilbarco-circlek-ee-clean.jpg",
            "pump-033-dresser-wayne-circlek-ee-fourprice-95.jpg",
            "pump-034-dresser-wayne-circlek-tallinn-ee-db0-pair.jpg",
            "pump-035-dresser-wayne-circlek-ee-rain-pump8.jpg",
            "pump-036-dresser-wayne-circlek-ee-pump4-95.jpg",
            "pump-037-dresser-wayne-circlek-ee-pump3-diesel.jpg",
            "pump-038-dresser-wayne-circlek-ee-reflection-95.jpg",
            // 2026-09-01: five more Circle K Estonia displays. pump-042 is the
            // corpus's first PRESET-AMOUNT fill (a round 20.00 total, the
            // volume derived), and pump-041's total is destroyed by sun glare -
            // both leave a cell EMPTY rather than guess. Declared, not swept.
            "pump-039-gilbarco-circlek-ee-1839-clean.jpg",
            "pump-040-gilbarco-circlek-ee-pump4-wide.jpg",
            "pump-041-dresser-wayne-circlek-ee-glare-total.jpg",
            "pump-042-dresser-wayne-circlek-ee-preset-20eur.jpg",
            "pump-043-dresser-wayne-circlek-ee-pump8-95.jpg",
            // 2026-09-03: thirteen more. pump-044 is a Roснефть display whose
            // price is truncated to one decimal where its paired receipt prints
            // two. pump-045..pump-056 are one Circle K forecourt shot across
            // BOTH vendors - Gilbarco with comma decimals, Wayne with dots -
            // which is why the separator is a per-pump property, not a
            // per-locale one. Five Wayne displays charge a price that is not
            // any of the four on the board, and two lose their total to glare;
            // all of those leave a cell EMPTY rather than guess. Declared, not
            // swept.
            "pump-044-rn-tver-chkalovskaya-95-comma-truncated-price-ru.jpeg",
            "pump-045-gilbarco-circlek-ee-1799-zeropad.jpg",
            "pump-046-gilbarco-circlek-ee-pump7-95-badge.jpg",
            "pump-047-gilbarco-circlek-ee-pump8-outdoor.jpg",
            "pump-048-gilbarco-circlek-ee-1889-near-preset.jpg",
            "pump-049-gilbarco-circlek-ee-faint-lcd-small-fill.jpg",
            "pump-050-gilbarco-circlek-ee-1929.jpg",
            "pump-051-wayne-circlek-ee-fourprice-none-matches.jpg",
            "pump-052-wayne-circlek-ee-glare-total-lost.jpg",
            "pump-053-wayne-circlek-ee-pump1-glare-total-digit.jpg",
            "pump-054-wayne-circlek-jarvevana-pump7-diesel-flare.jpg",
            "pump-055-wayne-circlek-ee-liitrid-variant.jpg",
            "pump-056-wayne-circlek-ee-preset-72eur.jpg",
            // 2026-09-04: eight more Circle K Sikupilli displays, four
            // Gilbarco and four Dresser Wayne, including the matched half of
            // receipt-046. pump-061 charges a price on no board price of its
            // own display, and pump-063's price display is physically covered
            // by a dead insect - a NEW occlusion class, an object on the glass
            // rather than glare or dirt. Declared, not swept.
            "pump-057-gilbarco-circlek-sikupilli-pump5-db0-pair.jpg",
            "pump-058-gilbarco-circlek-ee-dirty-lcd-1969.jpg",
            "pump-059-gilbarco-circlek-ee-pump3-1899.jpg",
            "pump-060-gilbarco-circlek-ee-1894.jpg",
            "pump-061-wayne-circlek-ee-discount-below-board.jpg",
            "pump-062-wayne-circlek-ee-pump8-1894.jpg",
            "pump-063-wayne-circlek-ee-insect-on-price-display.jpg",
            "pump-064-wayne-circlek-ee-4645l-1834.jpg",
            // 2026-09-04: the matched halves of receipt-047 and receipt-048.
            // pump-065's Tokheim truncates its total to one decimal (3765,7 vs
            // the paper's 3765.65) where pump-066 agrees to the cent - so total
            // precision is a property of the PUMP, not the country. Declared,
            // not swept.
            "pump-065-tokheim-gazpromneft-edrovo-truncated-total-pair-ru.jpeg",
            "pump-066-rn-tver-budovo-95-exact-total-pair-ru.jpeg",
        ],
    ]

    static func forClass(_ name: String) -> Set<String> { byClass[name] ?? [] }
}
