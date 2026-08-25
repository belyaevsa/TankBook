import Foundation
import Testing
@testable import TankbookCore

/// P3.1a ServiceEntry rules (docs/JOURNEYS.md J7, docs/SCHEMA.md ->
/// ServiceRecord). The typed screen's invariants in pure form: the odometer
/// rule (required only when an item anchors on it), the lump-sum record
/// (one uncategorized item is a perfectly good record), `.other` free text
/// surviving a persistence round-trip, and exact `Decimal` money.
@Suite struct ServiceEntryTests {

    private func decimal(_ string: String) -> Decimal {
        Decimal(string: string)!
    }

    private func money(_ amount: String) -> Money {
        Money(amount: decimal(amount), currency: .eur, homeCurrency: .eur)
    }

    private func makeRepository() throws -> TankbookRepository {
        TankbookRepository(database: try TankbookDatabase.inMemory())
    }

    private func makeVehicle() -> Vehicle {
        let timestamp = Date(timeIntervalSince1970: 1_752_000_000)
        return Vehicle(
            id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_930)
    }

    private func draft(items: [ServiceItem], odometer: Int? = nil,
                       vendor: String? = nil) -> ServiceEntryDraft {
        ServiceEntryDraft(vendor: vendor, items: items,
                          date: Date(timeIntervalSince1970: 1_752_000_000),
                          odometer: odometer)
    }

    // MARK: - The odometer rule, both directions (docs/SCHEMA.md)

    @Test func odometerRuleRequiresOnlyWhenAnItemAnchorsOnIt() {
        let noLifetime = ServiceItem.make(title: "Oil service", category: .oil, cost: money("89.00"))
        let kmLifetime = ServiceItem.make(title: "Oil service", category: .oil,
                                          cost: money("89.00"),
                                          lifetime: ServiceItem.Lifetime(km: 15_000, months: 12))
        let monthsOnly = ServiceItem.make(title: "Check-up", category: .inspection,
                                          cost: nil,
                                          lifetime: ServiceItem.Lifetime(km: nil, months: 12))

        // Nothing anchors on the odometer: a blank odometer saves.
        #expect(!ServiceEntryDraft.requiresOdometer(items: [noLifetime], tireSetId: nil))
        #expect(!ServiceEntryDraft.requiresOdometer(items: [], tireSetId: nil))
        // A km lifetime anchors on it.
        #expect(ServiceEntryDraft.requiresOdometer(items: [kmLifetime], tireSetId: nil))
        // A months-only lifetime does not.
        #expect(!ServiceEntryDraft.requiresOdometer(items: [monthsOnly], tireSetId: nil))
        // A mounted tire set anchors on it even with no lifetime (P3.3 shape).
        #expect(ServiceEntryDraft.requiresOdometer(items: [noLifetime], tireSetId: UUID.v7()))
    }

    @Test func readinessBlocksOnlyABlankOdometerWithAKmLifetime() {
        let kmLifetime = ServiceItem.make(title: "Oil service", category: .oil,
                                          cost: money("89.00"),
                                          lifetime: ServiceItem.Lifetime(km: 15_000, months: 12))
        let plain = ServiceItem.make(title: "Brake pads", category: .brakes, cost: money("59.00"))

        // A record with no km lifetime saves with a blank odometer.
        #expect(draft(items: [plain], odometer: nil).readiness == .ready)
        // A record with a km lifetime and a blank odometer refuses to save.
        #expect(draft(items: [kmLifetime], odometer: nil).readiness == .odometerRequired)
        // The same record with the odometer filled is ready.
        #expect(draft(items: [kmLifetime], odometer: 118_930).readiness == .ready)
    }

    // MARK: - The lump sum is a first-class record (J7)

    @Test func lumpSumSavesReadsBackIntactAndAppearsInTheLogStream() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        // One uncategorized item carrying the whole total - built through the
        // same `draft.build` the screen's save path calls, never hand-rolled.
        let uncategorized = ServiceItem.make(title: "Annual service",
                                             category: .other(""),
                                             cost: money("148.00"))
        let built = draft(items: [uncategorized], odometer: 118_930)
            .build(vehicleId: vehicle.id, homeCurrency: vehicle.homeCurrency)
        #expect(built.items.count == 1)
        try repo.upsertServiceRecord(built)

        let readBack = try repo.liveServiceRecords(forVehicle: vehicle.id)
        #expect(readBack.count == 1)
        print("PROBE date", readBack[0].date == built.date, readBack[0].date.timeIntervalSince1970, built.date.timeIntervalSince1970)
        print("PROBE createdAt", readBack[0].createdAt == built.createdAt, readBack[0].createdAt.timeIntervalSince1970, built.createdAt.timeIntervalSince1970)
        print("PROBE updatedAt", readBack[0].updatedAt == built.updatedAt, readBack[0].updatedAt.timeIntervalSince1970, built.updatedAt.timeIntervalSince1970)
        print("PROBE money", readBack[0].money == built.money)
        print("PROBE items", readBack[0].items == built.items)
        print("PROBE cost", String(describing: readBack[0].items[0].cost?.amount), String(describing: built.items[0].cost?.amount))
        print("PROBE provenance", readBack[0].provenance == built.provenance, readBack[0].conflict == built.conflict)
        let a = readBack[0], b = built
        print("PROBE rest", a.id == b.id, a.vehicleId == b.vehicleId, a.deletedAt == b.deletedAt,
              a.odometer == b.odometer, a.note == b.note, a.vendor == b.vendor,
              a.attachments == b.attachments, a.usedParts == b.usedParts,
              a.tireSetId == b.tireSetId, a.proposedReminderId == b.proposedReminderId,
              a.purchaseGroupId == b.purchaseGroupId)
        print("PROBE moneyparts", String(describing: a.money?.amount), String(describing: b.money?.amount),
              String(describing: a.money?.homeAmount), String(describing: b.money?.homeAmount),
              String(describing: a.money?.rate), String(describing: b.money?.rate),
              String(describing: a.money?.rateDate), String(describing: b.money?.rateDate))
        // Everything the record carries survives the round trip - except the
        // two envelope timestamps, which drift by one Double ulp (~1.2e-7 s).
        // `Records.swift` stores dates as `timeIntervalSince1970`, and adding
        // the 978307200 s epoch offset shifts the fractional bits out of the
        // mantissa. The drift is **idempotent** (a second round trip is stable,
        // asserted below), so sync's `updatedAt` LWW ordering is unaffected -
        // but "reads back identical" is not literally true, and pretending it
        // is would be the vacuous version of this test. Recorded as **P4.11**.
        var normalized = readBack[0]
        normalized.createdAt = built.createdAt
        normalized.updatedAt = built.updatedAt
        #expect(normalized == built, "every field but the envelope timestamps must round-trip exactly")
        #expect(abs(readBack[0].createdAt.timeIntervalSinceReferenceDate
                    - built.createdAt.timeIntervalSinceReferenceDate) < 0.001,
                "timestamp drift must stay in the sub-millisecond noise floor, not become a real offset")

        // The drift converges: writing what we read back changes nothing.
        try repo.upsertServiceRecord(readBack[0])
        #expect(try repo.liveServiceRecords(forVehicle: vehicle.id)[0] == readBack[0],
                "the round trip must be idempotent - otherwise every sync cycle would dirty the record")

        // It appears in the Log stream (the union of every entry type).
        let entries = try repo.liveEntries(forVehicle: vehicle.id)
        let stream = LogStream(vehicle: vehicle, entries: entries)
        let serviceRows = stream.allRows.compactMap { row -> LogStream.LogEntry? in
            if case .entry(let entry) = row, entry.kind == .service { return entry }
            return nil
        }
        #expect(serviceRows.count == 1)
        #expect(serviceRows[0].id == built.id)
        #expect(serviceRows[0].money?.amount == decimal("148.00"))
    }

    // MARK: - `.other(String)` free text survives a round-trip

    @Test func otherFreeTextSurvivesAPersistenceRoundTrip() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        let tuning = ServiceItem.make(title: "ECU tuning", category: .other("tuning"),
                                      cost: money("300.00"))
        let built = draft(items: [tuning], odometer: 118_930)
            .build(vehicleId: vehicle.id, homeCurrency: vehicle.homeCurrency)
        try repo.upsertServiceRecord(built)

        let readBack = try repo.liveServiceRecords(forVehicle: vehicle.id)
        #expect(readBack.count == 1)
        #expect(readBack[0].items[0].category == .other("tuning"))
    }

    // MARK: - Money is exact

    @Test func moneyIsExactAndTheItemSumEqualsTheHeaderTotal() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        let oil = ServiceItem.make(title: "Oil service incl. filter", category: .oil,
                                   cost: money("89.00"))
        let brakes = ServiceItem.make(title: "Brake pads front", category: .brakes,
                                      cost: money("59.00"))
        let built = draft(items: [oil, brakes], odometer: 118_930,
                          vendor: "Bosch Service")
            .build(vehicleId: vehicle.id, homeCurrency: vehicle.homeCurrency)

        // The header total is the exact Decimal sum of the item costs.
        #expect(built.money?.amount == decimal("148.00"))
        let itemSum = built.items.reduce(Decimal.zero) { $0 + ($1.cost?.amount ?? .zero) }
        #expect(itemSum == decimal("148.00"))
        #expect(itemSum == built.money?.amount)

        try repo.upsertServiceRecord(built)
        let readBack = try repo.liveServiceRecords(forVehicle: vehicle.id)
        #expect(readBack.count == 1)
        #expect(readBack[0].money?.amount == decimal("148.00"))
        #expect(readBack[0].items[0].cost?.amount == decimal("89.00"))
        #expect(readBack[0].items[1].cost?.amount == decimal("59.00"))
    }
}
