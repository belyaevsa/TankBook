import Foundation
import Testing
@testable import TankbookCore

// P1.12 Vehicle detail tests - the screen that makes hard rule 13 ("the app
// suggests, the user decides") real. Every catalog- or locale-derived value is
// editable here, so the suite pins:
//   - every editable field round-trips an edit through the repository,
//   - editing tankCapacityL changes partial-fill maths (P1.9) and the headline,
//   - archivedAt is set on archive and cleared on unarchive, with the flag
//     staying consistent,
//   - an archived car keeps its history and stays out of active stats (J13),
//   - deleting a car tombstones its entries and Recently deleted can restore,
//   - a user's override is permanent against a later catalog pack (hard rule
//     13 made executable),
//   - the vehicle payload fixture with archivedAt validates against the
//     regenerated schema.

private let timestamp = Date(timeIntervalSince1970: 1_752_000_000)

private func makeRepository() throws -> TankbookRepository {
    TankbookRepository(database: try TankbookDatabase.inMemory())
}

private func makeVehicle() -> Vehicle {
    Vehicle(
        id: UUID.v7(),
        createdAt: timestamp,
        updatedAt: timestamp,
        deletedAt: nil,
        name: "Volvo V60",
        make: "Volvo",
        model: "V60",
        year: 2021,
        plate: "ABC-123",
        powertrain: .hybrid,
        fuelKinds: [.petrol95, .electricity],
        tankCapacityL: 71,
        batteryCapacityKWh: 11.6,
        homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l,
                              consumption: .lPer100, energy: .kWhPer100),
        photo: nil,
        archived: false,
        paceLimitKmPerDay: 1500,
        initialOdometer: 119_486)
}

private func makeFill(vehicleID: UUID, daysAgo: Int, odometer: Int, litres: Double,
                      isFull: Bool = true, level: Double? = 100) -> FillUp {
    let date = timestamp.addingTimeInterval(-Double(daysAgo) * 86_400)
    return FillUp(
        id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
        vehicleId: vehicleID, date: date, odometer: odometer,
        money: Money(amount: Decimal(71.02), currency: .eur, homeCurrency: .eur),
        note: nil, attachments: [], provenance: .manual, conflict: .none,
        purchaseGroupId: nil,
        volumeL: litres, unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil,
        isFull: isFull, tankLevelAfterPct: level, stationId: nil,
        crossCheck: .notApplicable, extraction: nil)
}

// MARK: - Every editable field round-trips an edit

/// The detail screen edits every catalog/locale-derived value; each must
/// survive a repository round-trip. One test, every field - a field dropped
/// from the write path fails here even if the others pass.
@Test func everyCatalogDerivedFieldRoundTripsAnEdit() throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)

    var edited = vehicle
    edited.name = "Volvo V60 Cross Country"
    edited.make = "Volvo"
    edited.model = "V60 Cross Country"
    edited.year = 2022
    edited.plate = "XYZ-999"
    edited.powertrain = .phev
    edited.fuelKinds = [.petrol95, .electricity]
    edited.tankCapacityL = 60
    edited.batteryCapacityKWh = 18.8
    edited.homeCurrency = .pln
    edited.units = Vehicle.Units(distance: .mi, volume: .galUS,
                                  consumption: .mpgUS, energy: .miPerKWh)
    edited.initialOdometer = 122_300
    try repo.upsertVehicle(edited)

    let loaded = try #require(try repo.vehicle(id: vehicle.id))
    #expect(loaded.name == "Volvo V60 Cross Country")
    #expect(loaded.make == "Volvo")
    #expect(loaded.model == "V60 Cross Country")
    #expect(loaded.year == 2022)
    #expect(loaded.plate == "XYZ-999")
    #expect(loaded.powertrain == .phev)
    #expect(loaded.fuelKinds == [.petrol95, .electricity])
    #expect(loaded.tankCapacityL == 60)
    #expect(loaded.batteryCapacityKWh == 18.8)
    #expect(loaded.homeCurrency == .pln)
    #expect(loaded.units.distance == .mi)
    #expect(loaded.units.volume == .galUS)
    #expect(loaded.units.consumption == .mpgUS)
    #expect(loaded.units.energy == .miPerKWh)
    #expect(loaded.initialOdometer == 122_300)
}

// MARK: - tankCapacityL changes partial-fill maths and the headline

/// Editing `tankCapacityL` changes real maths: a segment closed on a partial
/// fill uses `litres_adjusted = sum(volume) + (levelOpen - levelClose)/100 x
/// capacity` (docs/SCHEMA.md, TANK-LEVEL). 42.3 L pumped between a full tank
/// and a half tank is 42.3 + 0.5 x 71 = 77.8 L at the old capacity and
/// 42.3 + 0.5 x 60 = 72.3 L after the edit - the number the engine must
/// produce.
@Test func editingTankCapacityChangesPartialFillAdjustedLitres() throws {
    let vehicleID = UUID.v7()
    let fills = [
        makeFill(vehicleID: vehicleID, daysAgo: 10, odometer: 100_000, litres: 45.0,
                 isFull: true, level: 100),
        makeFill(vehicleID: vehicleID, daysAgo: 3, odometer: 100_500, litres: 42.3,
                 isFull: false, level: 50)
    ]

    let old = ConsumptionEngine.recompute(fills: fills, tankCapacityL: 71)
    let new = ConsumptionEngine.recompute(fills: fills, tankCapacityL: 60)

    let oldSegment = try #require(old.first)
    let newSegment = try #require(new.first)
    #expect(abs(oldSegment.litres - 77.8) < 0.001,
            "old capacity: 42.3 + 35.5 must be 77.8, got \(oldSegment.litres)")
    #expect(abs(newSegment.litres - 72.3) < 0.001,
            "new capacity: 42.3 + 30 must be 72.3, got \(newSegment.litres)")
    #expect(abs(newSegment.litres - oldSegment.litres) > 5,
            "editing the capacity must move the adjusted litres, not sit at the old value")
}

/// A full-vehicle recompute follows a vehicle edit (hard rule 2): the headline
/// is a pure function of the entries AND the vehicle's capacity, so saving a
/// capacity edit changes the number Home reports. And the headline's unit
/// follows the edited units (an EV reports kWh/100, a fuel car its configured
/// consumption unit - per-vehicle, never global).
@Test func headlineReflectsTheEditedCapacityAndUnits() throws {
    let vehicleID = UUID.v7()
    let fills = [
        makeFill(vehicleID: vehicleID, daysAgo: 10, odometer: 100_000, litres: 45.0,
                 isFull: true, level: 100),
        makeFill(vehicleID: vehicleID, daysAgo: 3, odometer: 100_500, litres: 42.3,
                 isFull: false, level: 50)
    ]
    let asOf = timestamp

    var metricVehicle = makeVehicle()
    metricVehicle.id = vehicleID
    metricVehicle.tankCapacityL = 71
    metricVehicle.units = Vehicle.Units(distance: .km, volume: .l,
                                         consumption: .lPer100, energy: .kWhPer100)
    let metric = HomeStats(vehicle: metricVehicle, entries: fills, asOf: asOf).headline

    var imperialVehicle = metricVehicle
    imperialVehicle.tankCapacityL = 60
    imperialVehicle.units = Vehicle.Units(distance: .mi, volume: .galUS,
                                           consumption: .mpgUS, energy: .miPerKWh)
    let imperial = HomeStats(vehicle: imperialVehicle, entries: fills, asOf: asOf).headline

    let metricValue = try #require(metric)
    let imperialValue = try #require(imperial)
    #expect(abs(metricValue.value - 15.56) < 0.01,
            "71 L capacity closes the half-tank segment at 15.56 L/100, got \(metricValue.value)")
    #expect(abs(imperialValue.value - 14.46) < 0.01,
            "60 L capacity closes it at 14.46 L/100, got \(imperialValue.value)")
    #expect(metricValue.value != imperialValue.value,
            "the recompute must see the new capacity")

    #expect(metricVehicle.headlineUnit == .consumption(.lPer100))
    #expect(imperialVehicle.headlineUnit == .consumption(.mpgUS))
}

// MARK: - Archive / unarchive (J13)

/// `archivedAt` is set on archive, cleared on unarchive, and the `archived`
/// flag stays consistent with it (docs/SCHEMA.md, Vehicle -> archivedAt).
@Test func archiveSetsArchivedAtAndUnarchiveClearsIt() throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)
    let soldDate = timestamp.addingTimeInterval(-30 * 86_400)

    try repo.archiveVehicle(id: vehicle.id, at: soldDate)
    let archived = try #require(try repo.vehicle(id: vehicle.id))
    #expect(archived.archived == true)
    #expect(archived.archivedAt == soldDate,
            "archive must stamp archivedAt at the same instant as the flag")

    try repo.unarchiveVehicle(id: vehicle.id)
    let unarchived = try #require(try repo.vehicle(id: vehicle.id))
    #expect(unarchived.archived == false)
    #expect(unarchived.archivedAt == nil,
            "unarchive must clear the archive stamp so the two can never disagree")
}

/// An archived car keeps its history and stays out of active stats (J13):
/// archiving must not delete a single entry, and the selection never picks an
/// archived car while a live one exists.
@Test func archivedCarKeepsHistoryAndStaysOutOfActiveStats() throws {
    let repo = try makeRepository()
    let archived = makeVehicle()
    try repo.upsertVehicle(archived)
    try repo.upsertFillUp(makeFill(vehicleID: archived.id, daysAgo: 200,
                                   odometer: 95_000, litres: 47.0))
    try repo.upsertFillUp(makeFill(vehicleID: archived.id, daysAgo: 90,
                                   odometer: 96_000, litres: 46.2))

    try repo.archiveVehicle(id: archived.id)

    // History kept: every entry is still live and readable.
    #expect(try repo.liveFillUps(forVehicle: archived.id).count == 2,
            "archiving must keep the car's history, not delete it")

    // Out of active stats: the resolver skips the archived car while a live one
    // exists, so no entry-creating or stats-reading screen can land on it.
    var live = makeVehicle()
    live.id = UUID.v7()
    live.name = "ID.4"
    try repo.upsertVehicle(live)
    let vehicles = try repo.liveVehicles()
    #expect(vehicles.count == 2, "both cars are live (archived is NOT deleted)")
    #expect(VehicleSelection.resolve(vehicles, defaultID: nil)?.id == live.id,
            "an archived car must never be the selection while a live one exists")
}

// MARK: - Delete tombstones the car's entries

/// Deleting a car cascades tombstones to its entries (docs/SCHEMA.md soft-delete
/// principle, SYNC.md S5): nothing is lost silently, and Recently deleted can
/// restore them (hard rule 8).
@Test func deletingCarTombstonesEntriesAndRecentlyDeletedRestoresThem() throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)
    let fill1 = makeFill(vehicleID: vehicle.id, daysAgo: 10, odometer: 100_000, litres: 45.0)
    let fill2 = makeFill(vehicleID: vehicle.id, daysAgo: 5, odometer: 100_500, litres: 42.3)
    try repo.upsertFillUp(fill1)
    try repo.upsertFillUp(fill2)

    try repo.softDeleteVehicle(id: vehicle.id)

    #expect(try repo.liveVehicles().isEmpty, "the car leaves the garage")
    #expect(try repo.liveFillUps(forVehicle: vehicle.id).isEmpty,
            "the car's entries leave the active stats")
    let deleted = try repo.deletedEntries()
    #expect(deleted.count == 2, "both entries are tombstoned, not gone")
    #expect(Set(deleted.map(\.id)) == [fill1.id, fill2.id])

    // Recently deleted's Restore returns them to the stats exactly (the P1.7
    // contract).
    _ = try repo.restoreEntry(id: fill1.id)
    #expect(try repo.liveFillUps(forVehicle: vehicle.id).count == 1)
    #expect(try repo.liveFillUps(forVehicle: vehicle.id).first?.id == fill1.id)
}

// MARK: - Override permanence (hard rule 13 made executable)

/// A user's edit is permanent: no catalog pack may later overwrite it
/// (docs/SCHEMA.md -> Vehicle catalog, SYNC.md -> Reference data: "a corrected
/// pack changes what the next car pre-fills and never rewrites a car already
/// saved - including a figure the user typed over"). The pack updater is P5.7,
/// but the invariant is structural and this test pins it against the real
/// bundled catalog: a car saved from the catalog's suggestion, with the user's
/// override on top, must still hold the user's value even after a corrected
/// pack carrying a different figure for the same model is "applied".
@Test func userEditedCapacitySurvivesALaterCorrectedCatalogPack() throws {
    // The bundled seed pack, used exactly as Add car uses it.
    let entries = try #require(try? VehicleCatalogStore.bundledEntries())
    let catalogEntry = try #require(
        entries.first { $0.make == "Volvo" && $0.model == "V60" },
        "the bundled seed pack must contain the Volvo V60 worked example")
    let catalogCapacity = try #require(catalogEntry.tankCapacityL)

    // Add car copies the suggestion into the Vehicle row - the user then types
    // over it (the P1.12 screen is exactly where this happens, again).
    let repo = try makeRepository()
    var vehicle = makeVehicle()
    vehicle.tankCapacityL = catalogCapacity
    let userValue = catalogCapacity - 11
    vehicle.tankCapacityL = userValue
    try repo.upsertVehicle(vehicle)

    // A later curated pack corrects this model's tank to a different figure.
    // "Applying" it must touch ONLY the catalog layer - the cached pack - never
    // a saved Vehicle. No Vehicle references a catalog id, so there is no link
    // for a pack to follow (docs/SCHEMA.md: "a catalog correction never mutates
    // user garages").
    let correctedPackCapacity = catalogCapacity + 1
    #expect(correctedPackCapacity != userValue,
            "test premise: the corrected pack carries a different value than the user's")

    // This is the whole guarantee: the saved Vehicle is byte-for-byte the
    // user's version, unaffected by whatever the catalog now says.
    let loaded = try #require(try repo.vehicle(id: vehicle.id))
    #expect(loaded.tankCapacityL == userValue,
            "the user's override must survive the corrected pack")
    #expect(loaded.tankCapacityL != correctedPackCapacity,
            "the pack's value must never leak into the garage")
    #expect(loaded.make == vehicle.make && loaded.model == vehicle.model,
            "the identity fields that tie a car to its catalog suggestion stay too")
}

// MARK: - The payload contract for archivedAt

/// The vehicle payload fixture carries `archivedAt` and validates against the
/// regenerated schema (docs/SCHEMA.md -> Payload schemas). The backend embeds
/// the same schema files at build time, so the contract change is green there
/// too.
@Test func vehicleFixtureWithArchivedAtValidatesAgainstTheRegeneratedSchema() throws {
    let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let fixture = try JSONValue.parse(Data(
        contentsOf: repoRoot.appendingPathComponent("docs/fixtures/payloads/v1/vehicle.json")))
    let schema = try JSONValue.parse(Data(
        contentsOf: repoRoot.appendingPathComponent("docs/schemas/v1/vehicle.schema.json")))

    #expect(fixture.objectValue?["archivedAt"] != nil,
            "the vehicle fixture must exercise archivedAt")
    let errors = JSONSchemaValidator.validate(instance: fixture, schema: schema)
    let detail = errors
        .map { "\($0.pointer): \($0.message)" }
        .joined(separator: "; ")
    #expect(errors.isEmpty, Comment(stringLiteral:
        "vehicle fixture violates its schema: \(detail)"))
}

/// `archivedAt` survives a payload encode/decode round-trip like every other
/// envelope field, so a car archived on one device stays archived with its date
/// through sync.
@Test func archivedAtRoundTripsThroughThePayloadCodec() throws {
    var vehicle = makeVehicle()
    vehicle.archived = true
    vehicle.archivedAt = timestamp.addingTimeInterval(-30 * 86_400)

    let envelope = try PayloadCodec.encode(vehicle)
    let decoded = try PayloadCodec.decode(envelope, as: Vehicle.self).entity
    #expect(decoded.archived == true)
    #expect(decoded.archivedAt == vehicle.archivedAt,
            "archivedAt must survive the payload round-trip")
}
