import Foundation

// P4.12 - the ONE scorer for the corpus A/B (cloud vision model vs the rules
// parser). The comparison is shared between the two arms on purpose: the whole
// point of the measurement is that both are scored by the same function and the
// same tolerance, so neither arm can be flattered by a subtly different
// comparison. The tolerance and the empty-skip rule are copied from
// `AccuracyRatchetTests` (abs(got - want) < 0.005; an empty expected.csv field
// is skipped, never scored as a miss).

/// One image's extracted fields, as written by the sweep script (LLM arm) or the
/// rules dump (rules arm). A field is `nil` when the engine abstained or the call
/// failed; `error` carries the failure text when the whole image failed.
struct ExtractionRecord: Codable, Equatable, Sendable {
    let filename: String
    let liters: Double?
    let unitPrice: Double?
    let total: Double?
    let latencySeconds: Double?
    let error: String?

    init(
        filename: String,
        liters: Double?,
        unitPrice: Double?,
        total: Double?,
        latencySeconds: Double? = nil,
        error: String? = nil
    ) {
        self.filename = filename
        self.liters = liters
        self.unitPrice = unitPrice
        self.total = total
        self.latencySeconds = latencySeconds
        self.error = error
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
/// `nil` - that is what makes them "skipped, not missed".
struct ExpectedRow: Equatable, Sendable {
    let liters: Double?
    let unitPrice: Double?
    let total: Double?
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
        }
        return ScoredClass(name: name, hits: hits, total: total)
    }

    /// Parses a class's `expected.csv` (header `filename,liters,unitPrice,total`).
    /// An empty column becomes `nil` - the field is skipped, not guessed.
    static func loadExpected(_ url: URL) throws -> [String: ExpectedRow] {
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
    /// three ways). See `Spike/ReceiptSpike/fixtures/receipts/README.md`.
    static let byClass: [String: Set<String>] = [
        "receipts": [
            "receipt-036-tatneft-azs172-98-terminal-slip-ru.jpeg",
            "receipt-037-tatneft-azs172-98-vat22-qr-ru.jpeg",
        ],
        "pump": [
            "pump-018-gilbarco-tatneft-tver-98-ru.jpeg",
        ],
    ]

    static func forClass(_ name: String) -> Set<String> { byClass[name] ?? [] }
}
