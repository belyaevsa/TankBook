import Testing
import Foundation
@testable import TankbookCore

// MARK: - Golden fixture decoding (docs/fixtures/consumption-golden.json)

private struct GoldenFixture: Decodable {
    let asOf: Date
    let model: Model
    let drivers: [Driver]
    let editCases: [EditCase]

    struct Model: Decodable {
        let windowDays: Int
        let floorSegments: Int
    }

    struct Driver: Decodable {
        let id: String
        let name: String
        let fills: [Fill]
        let expectedSegments: [ExpectedSegment]
        let expectedHeadline: ExpectedHeadline
        let expectedLifetime: Double
    }

    struct Fill: Decodable {
        let date: Date
        let odometer: Int
        let litres: Double
        let isFull: Bool
    }

    struct ExpectedSegment: Decodable {
        let closes: Date
        let km: Double
        let litres: Double
        let per100: Double
    }

    struct ExpectedHeadline: Decodable {
        let value: Double
        let segmentCount: Int
        let spanDays: Int
        let windowExtended: Bool
        let totalLitres: Double
        let totalKm: Double
    }

    struct EditCase: Decodable {
        let id: String
        let name: String
        let basedOn: String
        let edit: Edit
        let expectedSegmentPer100: Per100ByClose?
        let expectedHeadline: HeadlineSubset?
        let expectedMergedSegment: ExpectedSegment?
        let expectedSegmentCount: Int?
        let expectedNewSegments: [ExpectedSegment]?

        struct Edit: Decodable {
            let date: Date
            let field: String
            let from: JSONScalar?
            let to: JSONScalar?
        }

        struct Per100ByClose: Decodable {
            let closes: Date
            let per100: Double
        }

        struct HeadlineSubset: Decodable {
            let value: Double
            let totalLitres: Double
            let totalKm: Double
        }
    }
}

private enum JSONScalar: Decodable {
    case bool(Bool)
    case number(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
            return
        }
        self = .number(try container.decode(Double.self))
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}

private func goldenFixtureURL() -> URL {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    for _ in 0 ..< 6 {
        let candidate = directory.appendingPathComponent("docs/fixtures/consumption-golden.json")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        directory = directory.deletingLastPathComponent()
    }
    fatalError("golden fixture docs/fixtures/consumption-golden.json not found above the test file")
}

private func loadFixture() throws -> GoldenFixture {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd"
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .formatted(formatter)
    let data = try Data(contentsOf: goldenFixtureURL())
    return try decoder.decode(GoldenFixture.self, from: data)
}

private func makeFill(_ fill: GoldenFixture.Fill, vehicleID: UUID) -> FillUp {
    FillUp(
        id: UUID.v7(),
        createdAt: fill.date,
        updatedAt: fill.date,
        deletedAt: nil,
        vehicleId: vehicleID,
        date: fill.date,
        odometer: fill.odometer,
        money: nil,
        note: nil,
        attachments: [],
        provenance: .manual,
        conflict: .none,
        purchaseGroupId: nil,
        volumeL: fill.litres,
        unitPrice: nil,
        fuelKind: .petrol95,
        fuelGrade: nil,
        isFull: fill.isFull,
        tankLevelAfterPct: nil,
        stationId: nil,
        crossCheck: .notApplicable,
        extraction: nil
    )
}

private func makeFill(id: UUID = UUID.v7(), date: Date, odometer: Int, litres: Double,
                      isFull: Bool, vehicleID: UUID = UUID.v7()) -> FillUp {
    FillUp(
        id: id,
        createdAt: date,
        updatedAt: date,
        deletedAt: nil,
        vehicleId: vehicleID,
        date: date,
        odometer: odometer,
        money: nil,
        note: nil,
        attachments: [],
        provenance: .manual,
        conflict: .none,
        purchaseGroupId: nil,
        volumeL: litres,
        unitPrice: nil,
        fuelKind: .petrol95,
        fuelGrade: nil,
        isFull: isFull,
        tankLevelAfterPct: nil,
        stationId: nil,
        crossCheck: .notApplicable,
        extraction: nil
    )
}

private func apply(_ edit: GoldenFixture.EditCase.Edit, to fills: [FillUp]) -> [FillUp] {
    fills.map { fill in
        guard fill.date == edit.date else { return fill }
        var copy = fill
        switch edit.field {
        case "litres":
            if let value = edit.to?.numberValue { copy.volumeL = value }
        case "isFull":
            if let value = edit.to?.boolValue { copy.isFull = value }
        default:
            break
        }
        return copy
    }
}

private func round1(_ value: Double) -> Double {
    (value * 10).rounded() / 10
}

private func round2(_ value: Double) -> Double {
    (value * 100).rounded() / 100
}

// MARK: - Golden vector tests

@Test func driversD1ThroughD4ReproduceGoldenVectors() throws {
    let fixture = try loadFixture()
    let vehicleID = UUID.v7()

    for driver in fixture.drivers {
        let fills = driver.fills.map { makeFill($0, vehicleID: vehicleID) }
        let segments = ConsumptionEngine.segments(for: fills)

        #expect(segments.count == driver.expectedSegments.count, "\(driver.id) segment count")
        for (segment, expected) in zip(segments, driver.expectedSegments) {
            #expect(segment.closes == expected.closes, "\(driver.id) closes")
            #expect(abs(segment.km - expected.km) <= 0.005, "\(driver.id) km")
            #expect(abs(segment.litres - expected.litres) <= 0.005, "\(driver.id) litres")
            #expect(round2(segment.per100) == expected.per100, "\(driver.id) per100")
        }

        let headline = ConsumptionEngine.headline(
            segments: segments,
            asOf: fixture.asOf,
            windowDays: fixture.model.windowDays,
            floor: fixture.model.floorSegments
        )
        #expect(headline != nil, "\(driver.id) headline")
        if let headline {
            #expect(round1(headline.value) == driver.expectedHeadline.value, "\(driver.id) headline.value")
            #expect(headline.segmentCount == driver.expectedHeadline.segmentCount, "\(driver.id) segmentCount")
            #expect(headline.spanDays == driver.expectedHeadline.spanDays, "\(driver.id) spanDays")
            #expect(headline.windowExtended == driver.expectedHeadline.windowExtended, "\(driver.id) windowExtended")
            #expect(abs(headline.totalLitres - driver.expectedHeadline.totalLitres) <= 0.005, "\(driver.id) totalLitres")
            #expect(abs(headline.totalKm - driver.expectedHeadline.totalKm) <= 0.005, "\(driver.id) totalKm")
        }

        let lifetime = ConsumptionEngine.lifetime(segments: segments)
        #expect(lifetime != nil, "\(driver.id) lifetime")
        if let lifetime {
            #expect(round1(lifetime) == driver.expectedLifetime, "\(driver.id) lifetime")
        }
    }
}

@Test func editCasesE1ThroughE3ReproduceGoldenVectors() throws {
    let fixture = try loadFixture()
    let vehicleID = UUID.v7()

    for editCase in fixture.editCases {
        guard let base = fixture.drivers.first(where: { $0.id == editCase.basedOn }) else {
            #expect(Bool(false), "edit case \(editCase.id) missing base driver")
            continue
        }
        let baseFills = base.fills.map { makeFill($0, vehicleID: vehicleID) }
        let editedFills = apply(editCase.edit, to: baseFills)
        let segments = ConsumptionEngine.segments(for: editedFills)

        if let expected = editCase.expectedSegmentPer100 {
            let segment = segments.first { $0.closes == expected.closes }
            #expect(segment != nil, "\(editCase.id) segment by close")
            #expect(round2(segment?.per100 ?? -1) == expected.per100, "\(editCase.id) per100")
        }

        if let merged = editCase.expectedMergedSegment {
            let segment = segments.first { $0.closes == merged.closes }
            #expect(segment != nil, "\(editCase.id) merged segment")
            #expect(abs((segment?.km ?? -1) - merged.km) <= 0.005, "\(editCase.id) merged km")
            #expect(abs((segment?.litres ?? -1) - merged.litres) <= 0.005, "\(editCase.id) merged litres")
            #expect(round2(segment?.per100 ?? -1) == merged.per100, "\(editCase.id) merged per100")
        }

        for expected in editCase.expectedNewSegments ?? [] {
            let segment = segments.first { $0.closes == expected.closes }
            #expect(segment != nil, "\(editCase.id) new segment \(expected.closes)")
            #expect(abs((segment?.km ?? -1) - expected.km) <= 0.005, "\(editCase.id) new km")
            #expect(abs((segment?.litres ?? -1) - expected.litres) <= 0.005, "\(editCase.id) new litres")
            #expect(round2(segment?.per100 ?? -1) == expected.per100, "\(editCase.id) new per100")
        }

        if let expectedCount = editCase.expectedSegmentCount {
            #expect(segments.count == expectedCount, "\(editCase.id) segment count")
        }

        if let expected = editCase.expectedHeadline,
           let headline = ConsumptionEngine.headline(
               segments: segments,
               asOf: fixture.asOf,
               windowDays: fixture.model.windowDays,
               floor: fixture.model.floorSegments
           ) {
            #expect(round1(headline.value) == expected.value, "\(editCase.id) headline.value")
            #expect(abs(headline.totalLitres - expected.totalLitres) <= 0.005, "\(editCase.id) totalLitres")
            #expect(abs(headline.totalKm - expected.totalKm) <= 0.005, "\(editCase.id) totalKm")
        }
    }
}

@Test func headlineLabelsAreHonest() throws {
    let fixture = try loadFixture()
    for driver in fixture.drivers {
        let fills = driver.fills.map { makeFill($0, vehicleID: UUID.v7()) }
        let segments = ConsumptionEngine.segments(for: fills)
        let headline = ConsumptionEngine.headline(
            segments: segments,
            asOf: fixture.asOf,
            windowDays: fixture.model.windowDays,
            floor: fixture.model.floorSegments
        )
        switch driver.id {
        case "D1": #expect(headline?.label == .window(months: 3), "D1 label")
        case "D2": #expect(headline?.label == .window(months: 3), "D2 label")
        case "D3": #expect(headline?.label == .window(months: 5), "D3 label")
        case "D4": #expect(headline?.label == .firstEstimate(cycles: 1), "D4 label")
        default: #expect(Bool(false), "unknown driver \(driver.id)")
        }
    }
}

// MARK: - Invariant tests beyond the golden vectors

@Test func headlineIsDistanceWeightedNotArithmeticMean() {
    let asOf = Date(timeIntervalSince1970: 1_752_000_000)
    let day: TimeInterval = 86_400
    // Short segment, high consumption; long segment, low consumption.
    let short = Segment(closes: asOf - 10 * day, km: 100, litres: 40,
                        openingFillID: UUID.v7(), closingFillID: UUID.v7())
    let long = Segment(closes: asOf - 5 * day, km: 1_000, litres: 10,
                       openingFillID: UUID.v7(), closingFillID: UUID.v7())

    let headline = ConsumptionEngine.headline(segments: [short, long], asOf: asOf,
                                              windowDays: 90, floor: 3)
    #expect(headline != nil)
    guard let headline else { return }

    let weighted = (40.0 + 10.0) / (100.0 + 1_000.0) * 100 // 4.545...
    let arithmeticMean = (short.per100 + long.per100) / 2 // (40 + 1) / 2 = 20.5

    #expect(abs(headline.value - weighted) < 0.01)
    #expect(abs(headline.value - arithmeticMean) > 1.0)
    #expect(headline.totalKm == 1_100)
}

@Test func conflictFlaggedFillExcludesItsSegments() {
    let day: TimeInterval = 86_400
    let base = Date(timeIntervalSince1970: 1_752_000_000)
    let f1 = makeFill(date: base, odometer: 100_000, litres: 40, isFull: true)
    var f2 = makeFill(date: base + 10 * day, odometer: 100_400, litres: 42, isFull: true)
    let f3 = makeFill(date: base + 20 * day, odometer: 100_800, litres: 44, isFull: true)
    let f4 = makeFill(date: base + 30 * day, odometer: 101_200, litres: 46, isFull: true)

    f2.conflict = .flagged(kind: .order, detectedAt: base)

    let segments = ConsumptionEngine.segments(for: [f1, f2, f3, f4])
    // f1->f2 and f2->f3 touch the flagged fill and are excluded; f3->f4 survives.
    #expect(segments.count == 1)
    #expect(segments.first?.openingFillID == f3.id)
    #expect(segments.first?.closingFillID == f4.id)

    let asOf = base + 40 * day
    let headline = ConsumptionEngine.headline(segments: segments, asOf: asOf,
                                              windowDays: 90, floor: 3)
    let lifetime = ConsumptionEngine.lifetime(segments: segments)
    let expected = 46.0 / 400.0 * 100 // 11.5 L/100km

    #expect(abs((headline?.value ?? 0) - expected) < 0.01)
    #expect(abs((lifetime ?? 0) - expected) < 0.01)
}

@Test func tankLevelRefinementClosesSegmentOnPartialFill() {
    let day: TimeInterval = 86_400
    let base = Date(timeIntervalSince1970: 1_752_000_000)
    var f1 = makeFill(date: base, odometer: 100_000, litres: 40, isFull: true)
    var f2 = makeFill(date: base + 10 * day, odometer: 100_400, litres: 20, isFull: false)
    f1.tankLevelAfterPct = 100
    f2.tankLevelAfterPct = 60

    let segments = ConsumptionEngine.segments(for: [f1, f2], tankCapacityL: 50)
    // litres_adjusted = 20 + (100 - 60)/100 x 50 = 40; km = 400.
    #expect(segments.count == 1)
    #expect(abs((segments.first?.litres ?? 0) - 40) < 0.001)
    #expect(abs((segments.first?.km ?? 0) - 400) < 0.001)
    #expect(abs((segments.first?.per100 ?? 0) - 10) < 0.001)
}

@Test func tankLevelRefinementFallsBackToFullToFullWithoutCapacity() {
    let day: TimeInterval = 86_400
    let base = Date(timeIntervalSince1970: 1_752_000_000)
    var f1 = makeFill(date: base, odometer: 100_000, litres: 40, isFull: true)
    var f2 = makeFill(date: base + 10 * day, odometer: 100_400, litres: 20, isFull: false)
    f1.tankLevelAfterPct = 100
    f2.tankLevelAfterPct = 60

    // Without a capacity the non-full fill is not a boundary: no segment closes.
    let segments = ConsumptionEngine.segments(for: [f1, f2], tankCapacityL: nil)
    #expect(segments.isEmpty)
}

@Test func evSegmentsShareSegmentStructure() {
    let day: TimeInterval = 86_400
    let base = Date(timeIntervalSince1970: 1_752_000_000)
    let c1 = ChargeSession(
        id: UUID.v7(), createdAt: base, updatedAt: base, deletedAt: nil,
        vehicleId: UUID.v7(), date: base, odometer: 10_000, money: nil, note: nil,
        attachments: [], provenance: .manual, conflict: .none, purchaseGroupId: nil,
        energyKWh: 30, unitPrice: nil, chargeType: .acHome, provider: nil,
        tariffId: nil, durationMin: nil, socStartPct: nil, socEndPct: nil,
        extraction: nil
    )
    let c2 = ChargeSession(
        id: UUID.v7(), createdAt: base + day, updatedAt: base + day, deletedAt: nil,
        vehicleId: UUID.v7(), date: base + day, odometer: 10_300, money: nil, note: nil,
        attachments: [], provenance: .manual, conflict: .none, purchaseGroupId: nil,
        energyKWh: 25, unitPrice: nil, chargeType: .acHome, provider: nil,
        tariffId: nil, durationMin: nil, socStartPct: nil, socEndPct: nil,
        extraction: nil
    )
    let segments = ConsumptionEngine.evSegments(for: [c1, c2])
    #expect(segments.count == 1)
    // Same shape as fuel: the closing session's energy over the segment's km.
    // kWh/100km = 25 / 300 x 100; the opening session (30 kWh) fills the battery.
    #expect(abs((segments.first?.litres ?? 0) - 25) < 0.001)
    #expect(abs((segments.first?.per100 ?? 0) - 8.333) < 0.001)
}

@Test func costPerKmSumsAllEntryTypesInWindow() {
    let day: TimeInterval = 86_400
    let asOf = Date(timeIntervalSince1970: 1_752_000_000)
    var fuel = makeFill(date: asOf - 5 * day, odometer: 100_000, litres: 40, isFull: true)
    fuel.money = Money(amount: 50, currency: .eur, homeCurrency: .eur)
    let service = ServiceRecord(
        id: UUID.v7(), createdAt: asOf, updatedAt: asOf, deletedAt: nil,
        vehicleId: UUID.v7(), date: asOf - 2 * day, odometer: 100_500, money: nil,
        note: nil, attachments: [], provenance: .manual, conflict: .none,
        purchaseGroupId: nil, vendor: "Garage", items: [], usedParts: [],
        tireSetId: nil, proposedReminderId: nil
    )
    let expense = Expense(
        id: UUID.v7(), createdAt: asOf, updatedAt: asOf, deletedAt: nil,
        vehicleId: UUID.v7(), date: asOf - 1 * day, odometer: 100_600,
        money: Money(amount: 200, currency: .eur, homeCurrency: .eur), note: nil,
        attachments: [], provenance: .manual, conflict: .none, purchaseGroupId: nil,
        category: .insurance, title: "Insurance", recurrence: nil, installedInServiceId: nil
    )
    // Window km span: 100600 - 100000 = 600 km. Home total: 50 + 200 = 250.
    let perKm = ConsumptionEngine.costPerKm(entries: [fuel, service, expense],
                                            windowDays: 90, asOf: asOf)
    #expect(abs((perKm ?? 0) - 250.0 / 600.0) < 0.001)

    // Out-of-window entries contribute neither money nor km span: fuel and
    // service span 100500 - 100000 = 500 km; late's 9999 EUR is excluded.
    var late = makeFill(date: asOf + 200 * day, odometer: 110_000, litres: 40, isFull: true)
    late.money = Money(amount: 9_999, currency: .eur, homeCurrency: .eur)
    let latePerKm = ConsumptionEngine.costPerKm(entries: [fuel, service, late],
                                                windowDays: 90, asOf: asOf)
    #expect(abs((latePerKm ?? 0) - 50.0 / 500.0) < 0.001)
}
