import Foundation
import Testing
@testable import TankbookCore

/// AdBlue is its own entry type with its own figures; fuel figures never
/// read it and car money always counts it (docs/SCHEMA.md -> AdBlueFill).
@Suite("AdBlue top-ups (P1.14)")
struct AdBlueTests {
    private let vehicleID = UUID.v7()
    private let day0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func day(_ offset: Int) -> Date { day0.addingTimeInterval(Double(offset) * 86_400) }

    private func adBlue(_ offset: Int, odo: Int?, litres: Double, euros: String? = nil) -> AdBlueFill {
        AdBlueFill(id: UUID.v7(), createdAt: day(offset), updatedAt: day(offset), vehicleId: vehicleID,
                   date: day(offset), odometer: odo,
                   money: euros.map { Money(amount: Decimal(string: $0)!, currency: .eur, homeCurrency: .eur) },
                   provenance: .manual, volumeL: litres, unitPrice: Decimal(string: "0.899"))
    }

    private func diesel(_ offset: Int, odo: Int, litres: Double, euros: String, price: String) -> FillUp {
        FillUp(id: UUID.v7(), createdAt: day(offset), updatedAt: day(offset), vehicleId: vehicleID,
               date: day(offset), odometer: odo,
               money: Money(amount: Decimal(string: euros)!, currency: .eur, homeCurrency: .eur),
               provenance: .manual, volumeL: litres, unitPrice: Decimal(string: price),
               fuelKind: .diesel, isFull: true, crossCheck: .verified)
    }

    private var vehicle: Vehicle {
        Vehicle(id: vehicleID, createdAt: day0, updatedAt: day0, name: "Passat", powertrain: .ice,
                fuelKinds: [.diesel], tankCapacityL: 66, homeCurrency: .eur,
                units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100))
    }

    // MARK: The rate

    @Test func aCarWithoutAdBlueHasNoAdBlueFigures() {
        #expect(AdBlueStats.compute(entries: [diesel(0, odo: 1000, litres: 50, euros: "80", price: "1.6")]) == nil)
    }

    @Test func oneTopUpShowsTheLastFillAndNoRate() throws {
        let only = adBlue(0, odo: 10_000, litres: 10)
        let stats = try #require(AdBlueStats.compute(entries: [only]))
        #expect(stats.lastFill == only)
        #expect(stats.litresPer1000 == nil, "one top-up measures no distance - never estimated")
    }

    /// Oracle by hand: 8 L used over 14000 - 10000 = 4000 km -> 2.0 L/1000 km.
    @Test func twoTopUpsGiveTheRate() throws {
        let stats = try #require(AdBlueStats.compute(entries: [
            adBlue(0, odo: 10_000, litres: 10), adBlue(30, odo: 14_000, litres: 8),
        ]))
        #expect(stats.litresPer1000 == 2.0)
    }

    /// Oracle by hand: every top-up but the first, 5 + 7.5 + 9 + 6 = 27.5 L, over
    /// 21000 - 10000 = 11000 km -> 2.5 L/1000 km. Entries arrive out of order.
    @Test func fiveTopUpsGiveTheDistanceWeightedRate() throws {
        let fills = [
            adBlue(40, odo: 18_500, litres: 9), adBlue(0, odo: 10_000, litres: 10),
            adBlue(60, odo: 21_000, litres: 6), adBlue(10, odo: 12_000, litres: 5),
            adBlue(25, odo: 15_000, litres: 7.5),
        ]
        let stats = try #require(AdBlueStats.compute(entries: fills))
        #expect(abs((stats.litresPer1000 ?? 0) - 2.5) < 1e-9)
        #expect(stats.lastFill.odometer == 21_000, "the last top-up is the newest, not the last in the array")
    }

    @Test func aTopUpWithoutAReadingIsTheLastFillButNotARatePoint() throws {
        let stats = try #require(AdBlueStats.compute(entries: [
            adBlue(0, odo: 10_000, litres: 10), adBlue(5, odo: nil, litres: 4),
        ]))
        #expect(stats.lastFill.odometer == nil)
        #expect(stats.litresPer1000 == nil)
    }

    // MARK: Fuel figures ignore it, car money counts it

    @Test func theFuelPriceIgnoresANewerAdBlueTopUp() throws {
        let entries: [any Entry] = [
            diesel(0, odo: 1000, litres: 50, euros: "80.00", price: "1.679"),
            adBlue(1, odo: 1050, litres: 10, euros: "8.99"),
        ]
        let stats = HomeStats(vehicle: vehicle, entries: entries, asOf: day(2))
        let price = try #require(stats.lastUnitPrice)
        #expect(price.amount == Decimal(string: "1.679"), "AdBlue at 0.899 must never be the fuel price")
    }

    /// 80 + 70 + 9 = 159 EUR over 1500 - 1000 = 500 km.
    @Test func costPerKmIncludesAdBlueMoney() throws {
        let entries: [any Entry] = [
            diesel(0, odo: 1000, litres: 50, euros: "80.00", price: "1.6"),
            adBlue(3, odo: 1200, litres: 10, euros: "9.00"),
            diesel(6, odo: 1500, litres: 44, euros: "70.00", price: "1.6"),
        ]
        let cost = try #require(HomeStats(vehicle: vehicle, entries: entries, asOf: day(7)).costPerKm)
        #expect(cost.amount == Decimal(159))
        #expect(cost.km == 500)
    }

    // MARK: Old clients

    /// The path an installed build takes for a top-up it cannot know: an
    /// unknown entity type applies as nothing and throws nothing, so the pull
    /// cursor advances. (Same `default` branch as the store build's
    /// `applyRecord`, checked against the `v1.0` tag.)
    @Test func anUnknownEntityTypeAppliesAsNothing() throws {
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        let record = SyncRecord(id: UUID.v7(), entityType: "notKnownYet",
                                schemaVersion: PayloadCodec.currentSchemaVersion,
                                payload: .object(["volumeL": .number("5.75")]),
                                clientUpdatedAt: day0, deleted: false)
        #expect(try repository.applyRemoteRecord(record, scn: 1).isEmpty)
    }

    // MARK: Storage, the Log and the archive

    @Test func aTopUpPersistsAndJoinsTheLogAsItsOwnKind() throws {
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        try repository.upsertVehicle(vehicle)
        let fill = adBlue(0, odo: 10_000, litres: 5.75, euros: "5.17")
        try repository.upsertAdBlueFill(fill)

        #expect(try repository.liveAdBlueFills(forVehicle: vehicleID) == [fill])
        let entries = try repository.liveEntries(forVehicle: vehicleID)
        #expect(entries.count == 1)
        let row = LogStream.LogEntry(vehicle: vehicle, entry: try #require(entries.first))
        #expect(row.kind == .adBlue)
        #expect(row.fuelKind == nil)
        #expect(row.consumptionPer100 == nil)

        try repository.softDeleteAdBlueFill(id: fill.id)
        #expect(try repository.liveEntries(forVehicle: vehicleID).isEmpty)
        #expect(try repository.deletedEntries().map(\.id) == [fill.id], "a deleted top-up is recoverable (hard rule 8)")
        #expect(try repository.restoreEntry(id: fill.id))
        #expect(try repository.liveAdBlueFills(forVehicle: vehicleID).count == 1)
    }

    /// An archive carries top-ups in their own top-level array: a build that
    /// predates AdBlue rejects an unknown type inside `entries` but ignores a
    /// key it does not read, so its import of the rest still succeeds.
    @Test func theArchiveCarriesTopUpsOutsideTheEntriesArray() throws {
        var contents = VehicleArchiveContents()
        contents.vehicles = [vehicle]
        contents.adBlueFills = [adBlue(0, odo: 10_000, litres: 5.75, euros: "5.17")]
        let tree = try ArchiveDataJSON.encode(contents, schemaVersion: PayloadCodec.currentSchemaVersion)
        let object = try #require(tree.objectValue)

        #expect(object["adBlueFills"]?.arrayValue?.count == 1)
        #expect(object["entries"]?.arrayValue?.isEmpty == true)

        let parsed = try ArchiveDataJSON.parse(tree)
        #expect(parsed.adBlueFills.count == 1)
        #expect(parsed.entryCount == 1)
    }
}
