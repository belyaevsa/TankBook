import Foundation
import GRDB
import Testing
@testable import TankbookCore

/// An invoice has one currency: a service line keeps only its amount and takes
/// the record's currency and rate, on every write and every read
/// (docs/SCHEMA.md -> ServiceRecord).
@Suite("Service lines share the invoice's currency")
struct ServiceItemCurrencyTests {
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func decimal(_ string: String) -> Decimal { Decimal(string: string)! }

    private func kzt(_ amount: String) -> Money {
        Money(amount: decimal(amount), currency: .kzt, homeCurrency: .eur)
    }

    private func snapshot(_ rate: String) -> RateSnapshot {
        RateSnapshot(rate: decimal(rate), rateDate: base, source: .cis)
    }

    private func makeRepository() throws -> (TankbookRepository, UUID) {
        let repo = TankbookRepository(database: try TankbookDatabase.inMemory())
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: base, updatedAt: base, deletedAt: nil, name: "Camry", make: nil,
            model: nil, year: nil, plate: nil, powertrain: .ice, fuelKinds: [.petrol92], tankCapacityL: 60,
            batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 200_000)
        try repo.upsertVehicle(vehicle)
        return (repo, vehicle.id)
    }

    private func service(vehicleId: UUID, total: Money?, lines: [Money?]) -> ServiceRecord {
        ServiceRecord(
            id: UUID.v7(), createdAt: base, updatedAt: base, deletedAt: nil, vehicleId: vehicleId,
            date: base, odometer: 207_800, money: total, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil, vendor: "СТО",
            items: lines.enumerated().map { index, cost in
                ServiceItem(title: "Line \(index)", category: .repair, cost: cost)
            },
            usedParts: [], tireSetId: nil)
    }

    @Test("a line converts at the total's rate, and stays pending while the total is")
    func lineSharesTheTotalsSnapshot() {
        let total = kzt("10000").converted(using: snapshot("500"))
        let line = total.sharingSnapshot(amount: decimal("2400"))
        #expect(line.currency == .kzt)
        #expect(line.homeAmount == decimal("4.8"))
        #expect(line.rate == decimal("500") && line.rateDate == base && line.rateSource == .cis)

        let pending = kzt("10000").sharingSnapshot(amount: decimal("2400"))
        #expect(pending.isRatePending)

        let same = Money(amount: decimal("80"), currency: .eur, homeCurrency: .eur)
            .sharingSnapshot(amount: decimal("30"))
        #expect(same.homeAmount == decimal("30"))
    }

    @Test("a line written in another currency is saved in the invoice's")
    func writeNormalisesTheLines() throws {
        let (repo, vehicleId) = try makeRepository()
        let euroLine = Money(amount: decimal("2400"), currency: .eur, homeCurrency: .eur)
        try repo.upsertServiceRecord(service(vehicleId: vehicleId, total: kzt("10000"), lines: [euroLine, nil]))
        let saved = try #require(try repo.liveServiceRecords(forVehicle: vehicleId).first)
        #expect(saved.items[0].cost?.currency == .kzt)
        #expect(saved.items[0].cost?.amount == decimal("2400"))
        #expect(saved.items[1].cost == nil)
    }

    @Test("changing the invoice's currency, or its rate landing, reaches every line")
    func currencyAndRateFollowTheTotal() throws {
        let (repo, vehicleId) = try makeRepository()
        var record = service(vehicleId: vehicleId, total: kzt("10000"), lines: [kzt("2400")])
        try repo.upsertServiceRecord(record)

        record.money = record.money?.converted(using: snapshot("500"))
        try repo.upsertServiceRecord(record)
        var saved = try #require(try repo.liveServiceRecords(forVehicle: vehicleId).first)
        #expect(saved.items[0].cost?.homeAmount == decimal("4.8"))

        record.money = record.money?.replacingCurrency(.rub)
        try repo.upsertServiceRecord(record)
        saved = try #require(try repo.liveServiceRecords(forVehicle: vehicleId).first)
        #expect(saved.items[0].cost?.currency == .rub)
        #expect(saved.items[0].cost?.isRatePending == true)
    }

    @Test("a line stored in another currency before the rule reads back in the invoice's")
    func readNormalisesOlderRows() throws {
        let (repo, vehicleId) = try makeRepository()
        let record = service(vehicleId: vehicleId, total: kzt("10000"), lines: [kzt("2400")])
        try repo.upsertServiceRecord(record)
        let stale = ServiceItem(title: "Line 0", category: .repair,
                                cost: Money(amount: decimal("2400"), currency: .usd, homeCurrency: .eur))
        try repo.database.write { db in
            try db.execute(sql: "DELETE FROM \(TankbookSchema.serviceItem) WHERE serviceRecordId = ?",
                           arguments: [record.id.uuidString])
            try ServiceItemRow(serviceRecordId: record.id, position: 0, item: stale).insert(db)
        }
        let read = try #require(try repo.liveServiceRecords(forVehicle: vehicleId).first)
        #expect(read.items[0].cost?.currency == .kzt)
    }
}
