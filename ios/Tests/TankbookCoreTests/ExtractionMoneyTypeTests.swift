import Foundation
import Testing
@testable import TankbookCore

// P2.2b - the extraction types money as Decimal, never Double.
//
// docs/SCHEMA.md types money as Decimal (FillUp.unitPrice: Decimal?,
// Money.amount: Decimal), and `FuelExtraction.total`/`unitPrice` must feed
// those fields without a binary-float round trip: `4201.68` is not exactly
// representable as a Double, so a value born Double loses precision at the
// boundary. `liters` deliberately stays Double (SCHEMA.md types `volumeL:
// Double` - it is a volume, not money).
//
// Three checks:
//   1. `4201.68` round-trips exactly from the OCR lines through a saved
//      `FillUp`, asserted with `Decimal(string:)` equality - never a tolerance
//      (a tolerance test passes the bug).
//   2. A genuinely lossy value - one `Decimal(Double)` really does corrupt -
//      survives exactly, with a negative control proving the test is not
//      vacuous.
//   3. Structurally, no money-valued `Double` property remains in
//      `Extraction/`, and `liters` is still `Double`.

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

@Suite("Extraction money typing (P2.2b)")
struct ExtractionMoneyTypeTests {

    // MARK: - 1. The exact round trip, extraction -> saved FillUp

    @Test("4201.68 round-trips exactly from extraction through to a saved FillUp")
    func totalRoundTripsExactlyThroughToASavedFillUp() throws {
        // receipt-011's fuel line: 62.89 x 66.810 = 4201.68. The total is OCR'd
        // as "4201.68" - a value `Double` cannot hold exactly.
        let lines = [
            "1 ДТ-Л-К5 N 1:09005", "=4201.68", "62.89*66.810л", "НДС 20%", "ДТ-Л-К5",
            "=4201.68", "ИТОГ", "=700.28", "СУММА НДС 20%", "=4201.68", "БЕЗНАЛИЧНЫМИ"
        ]
        let extraction = FuelExtractor().extract(textLines: lines)
        let total = try #require(extraction.total)
        let unitPrice = try #require(extraction.unitPrice)
        // Exact, not tolerance: `== Decimal(string: "4201.68")`.
        #expect(total == decimal("4201.68"))
        #expect(unitPrice == decimal("62.89"))

        let repository = try TankbookRepository(database: TankbookDatabase.inMemory())
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            name: "Volvo V60", make: nil, model: nil, year: nil, plate: nil,
            powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: nil,
            batteryCapacityKWh: nil, homeCurrency: .rub,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: nil)
        try repository.upsertVehicle(vehicle)

        let now = Date()
        let fillUp = FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 119_486,
            money: Money(amount: total, currency: .rub, homeCurrency: .rub),
            note: nil, attachments: [], provenance: .receiptScan, conflict: .none,
            purchaseGroupId: nil,
            volumeL: extraction.liters ?? 0, unitPrice: unitPrice, fuelKind: .diesel,
            fuelGrade: nil, isFull: true, tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .notApplicable, extraction: nil)
        try repository.upsertFillUp(fillUp)

        let saved = try #require(try repository.liveFillUps(forVehicle: vehicle.id).first)
        #expect(saved.money?.amount == decimal("4201.68"))
        #expect(saved.unitPrice == decimal("62.89"))
    }

    // MARK: - 2. A genuinely lossy value survives exactly

    @Test("a value Decimal(Double) really does corrupt survives exactly")
    func genuinelyLossyMoneySurvivesExactly() {
        // 1.679 / 71.02 are NOT exactly representable as Double: the naive
        // `Decimal(Double)` path produces 1.67899999999999984... and
        // 71.01999999999998976... The extractor must not use that path - its
        // money is born `Decimal(string:)` from the OCR text, so the extraction
        // holds the exact decimal.
        let extraction = FuelExtractor().extract(
            textLines: ["ДТ-Л-К5", "42.30 л X 1.679", "ИТОГ", "71.02"])
        #expect(extraction.unitPrice == decimal("1.679"))
        #expect(extraction.total == decimal("71.02"))
        // The derived fuel line is exact too - the raw Decimal product, no
        // Double noise: 42.30 x 1.679 = 71.0217 exactly.
        #expect(extraction.fuelLineAmount == decimal("71.0217"))

        // The negative control proves these assertions are not vacuous: the
        // naive Double round trip really does destroy both values.
        #expect(Decimal(Double("1.679")!) != decimal("1.679"))
        #expect(Decimal(Double("71.02")!) != decimal("71.02"))
    }

    // MARK: - 3. Structurally: no money-valued Double property in Extraction/

    private static let extractionDir = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent() // TankbookCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // ios
        .appendingPathComponent("Sources/TankbookCore/Extraction")

    @Test("no money-valued Double stored property remains in Extraction/")
    func noMoneyValuedDoublePropertyRemainsInExtraction() throws {
        // A stored property whose name names money must never be a Double. This
        // catches a regression that re-declares `total`, `unitPrice`, an amount
        // or a fuel line as Double. It deliberately does not scan the OCR
        // parsing layer's locals (NumberScanner, OperandPair, the total-finder's
        // mode selection) - those are display-precision numbers that must stay
        // Double so the volume shares one path and the modal tie-break compares
        // bit-identically (a Decimal re-key would move the pinned corpus
        // measurements, and `volumeL` is Double by SCHEMA.md). Those are
        // converted to exact Decimal at the money boundary.
        let moneyName = #"(unitPrice|total|amount|price|money|cost|fee|fuelLine\w*|grandTotal)"#
        let accessors = #"(?:(?:public|private|fileprivate|internal|package|open)\s+)*(?:weak\s+)?"#
        let propertyPrefix = #"^\s{4}"# + accessors + #"(?:var|let)\s+"#
        let storedDouble = propertyPrefix + moneyName + #"\w*\s*:\s*Double\??"#
        let regex = try Regex(storedDouble)
        let files = try FileManager.default.contentsOfDirectory(
            at: Self.extractionDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        var hits: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for (lineNo, line) in source.split(separator: "\n").enumerated()
            where line.contains(regex) {
                hits.append("\(file.lastPathComponent):\(lineNo + 1): \(line)")
            }
        }
        #expect(hits.isEmpty, Comment(stringLiteral: hits.joined(separator: "\n")))
    }

    @Test("liters deliberately stays Double - it is a volume, not money")
    func litersStaysDouble() throws {
        // SCHEMA.md types `volumeL: Double` on purpose; the extraction field is
        // the same kind of quantity and must not have been pulled into the money
        // refactor.
        let source = try String(
            contentsOf: Self.extractionDir.appendingPathComponent("FuelExtraction.swift"),
            encoding: .utf8)
        #expect(source.contains("public var liters: Double?"))
        #expect(source.contains("public var unitPrice: Decimal?"))
        #expect(source.contains("public var total: Decimal?"))
    }
}
