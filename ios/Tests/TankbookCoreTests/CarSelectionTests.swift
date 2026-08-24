import Foundation
import Testing
@testable import TankbookCore

// P1.11 - Car switcher + multi-vehicle state. The L1 face of the selected-car
// invariant (design/screens/CarSwitcher.dc.html footer): "Capture always logs
// to the selected car." The resolver (`VehicleSelection.resolve`) is the single
// source every entry-creating and stats-reading path uses, and the repository's
// `selectVehicle`/`selectedVehicleID` are the durable store behind it. A fill
// filed against the wrong car is invisible until consumption looks wrong months
// later, so the persisted `vehicleId` is asserted, never UI state.

private let timestamp = Date(timeIntervalSince1970: 1_752_000_000)

private func makeRepo() throws -> TankbookRepository {
    TankbookRepository(database: try TankbookDatabase.inMemory())
}

private func makeVehicle(id: UUID = UUID.v7(), name: String = "Volvo V60",
                         powertrain: Powertrain = .ice,
                         fuelKinds: [FuelKind] = [.petrol95, .diesel],
                         archived: Bool = false) -> Vehicle {
    Vehicle(id: id, createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
            name: name, make: nil, model: nil, year: 2021, plate: nil,
            powertrain: powertrain, fuelKinds: fuelKinds,
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: archived, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
}

private func makeFillUp(vehicleId: UUID, date: Date = timestamp,
                        odometer: Int = 118_000, litres: Double = 42.3) -> FillUp {
    FillUp(id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
           vehicleId: vehicleId, date: date, odometer: odometer,
           money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
           note: nil, attachments: [], provenance: .manual, conflict: .none,
           purchaseGroupId: nil, volumeL: litres,
           unitPrice: Decimal(string: "1.679"), fuelKind: .petrol95, fuelGrade: nil,
           isFull: true, tankLevelAfterPct: 100, stationId: nil,
           crossCheck: .notApplicable, extraction: nil)
}

private func makeCharge(vehicleId: UUID, date: Date, odometer: Int,
                        energyKWh: Double) -> ChargeSession {
    ChargeSession(id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
                  vehicleId: vehicleId, date: date, odometer: odometer,
                  money: Money(amount: Decimal(string: "20.00")!, currency: .eur, homeCurrency: .eur),
                  note: nil, attachments: [], provenance: .manual, conflict: .none,
                  purchaseGroupId: nil, energyKWh: energyKWh, unitPrice: nil,
                  chargeType: .dcPublic, provider: "Ionity", tariffId: nil,
                  durationMin: nil, socStartPct: nil, socEndPct: nil, extraction: nil)
}

/// The UI displays 1 decimal place (17.82 renders "17.8"), so compare at that
/// granularity.
private func close(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.05) -> Bool {
    abs(lhs - rhs) < tolerance
}

// MARK: - The selected-car invariant

@Test func entriesFileAgainstTheSelectedCar() throws {
    let repo = try makeRepo()
    let volvo = makeVehicle(name: "Volvo V60")
    let id4 = makeVehicle(name: "ID.4", powertrain: .ev, fuelKinds: [.electricity])
    try repo.upsertVehicle(volvo)
    try repo.upsertVehicle(id4)

    // With Volvo selected, a save lands on Volvo and nowhere else.
    try repo.selectVehicle(volvo.id)
    let selected = VehicleSelection.resolve(try repo.liveVehicles(),
                                            defaultID: try repo.selectedVehicleID())
    #expect(selected?.id == volvo.id)
    try repo.upsertFillUp(makeFillUp(vehicleId: selected!.id))
    #expect(try repo.liveFillUps(forVehicle: volvo.id).count == 1)
    #expect(try repo.liveFillUps(forVehicle: id4.id).isEmpty)
    // Assert the PERSISTED vehicleId, not any UI state.
    #expect(try repo.liveFillUps(forVehicle: volvo.id).first?.vehicleId == volvo.id)

    // Switch: the next save files to the OTHER car; Volvo's history is untouched.
    try repo.selectVehicle(id4.id)
    let switched = VehicleSelection.resolve(try repo.liveVehicles(),
                                            defaultID: try repo.selectedVehicleID())
    #expect(switched?.id == id4.id)
    try repo.upsertChargeSession(makeCharge(vehicleId: switched!.id,
                                            date: timestamp, odometer: 30_600, energyKWh: 60))
    #expect(try repo.liveChargeSessions(forVehicle: id4.id).count == 1)
    #expect(try repo.liveFillUps(forVehicle: volvo.id).count == 1,
            "switching must never move or re-file an existing entry")
}

@Test func selectionPersistsAcrossAStoreReopen() throws {
    let directory = NSTemporaryDirectory()
    let path = directory + "tankbook-selection-\(UUID().uuidString).sqlite"
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }

    let first = TankbookRepository(database: try TankbookDatabase(path: path))
    let volvo = makeVehicle(name: "Volvo V60")
    try first.upsertVehicle(volvo)
    try first.selectVehicle(volvo.id)
    #expect(try first.selectedVehicleID() == volvo.id)

    // Reopen the same file as a fresh repository - the relaunch path.
    let reopened = TankbookRepository(database: try TankbookDatabase(path: path))
    #expect(try reopened.selectedVehicleID() == volvo.id,
            "the selection must survive a relaunch")
    #expect(VehicleSelection.resolve(try reopened.liveVehicles(),
                                     defaultID: try reopened.selectedVehicleID())?.id == volvo.id)
}

// MARK: - Per-vehicle stats independence

@Test func perVehicleStatsAreIndependent() throws {
    let repo = try makeRepo()
    let volvo = makeVehicle(name: "Volvo V60")
    let id4 = makeVehicle(name: "ID.4", powertrain: .ev, fuelKinds: [.electricity])
    try repo.upsertVehicle(volvo)
    try repo.upsertVehicle(id4)

    // Volvo: three full fills closing two segments -> 8.4 L/100 over 1000 km.
    try repo.upsertFillUp(makeFillUp(vehicleId: volvo.id,
                                     date: timestamp.addingTimeInterval(-80 * 86_400),
                                     odometer: 118_000, litres: 42))
    try repo.upsertFillUp(makeFillUp(vehicleId: volvo.id,
                                     date: timestamp.addingTimeInterval(-40 * 86_400),
                                     odometer: 118_500, litres: 41))
    try repo.upsertFillUp(makeFillUp(vehicleId: volvo.id,
                                     date: timestamp.addingTimeInterval(-5 * 86_400),
                                     odometer: 119_000, litres: 43))

    // ID.4: two charges closing one segment -> 17.8 kWh/100 over 303 km
    // (the engine's EV segment carries the closing charge's energy:
    // 54 kWh / 303 km x 100 = 17.8).
    try repo.upsertChargeSession(makeCharge(vehicleId: id4.id,
                                            date: timestamp.addingTimeInterval(-12 * 86_400),
                                            odometer: 30_937, energyKWh: 60))
    try repo.upsertChargeSession(makeCharge(vehicleId: id4.id,
                                            date: timestamp.addingTimeInterval(-3 * 86_400),
                                            odometer: 31_240, energyKWh: 54))

    let entriesA = try repo.liveEntries(forVehicle: volvo.id)
    let entriesB = try repo.liveEntries(forVehicle: id4.id)

    // The repository isolates by vehicle: neither list leaks the other's rows.
    #expect(entriesA.count == 3)
    #expect(entriesB.count == 2)
    #expect(entriesA.allSatisfy { $0.vehicleId == volvo.id })
    #expect(entriesB.allSatisfy { $0.vehicleId == id4.id })

    let statsA = HomeStats(vehicle: volvo, entries: entriesA)
    let statsB = HomeStats(vehicle: id4, entries: entriesB)
    #expect(statsA.headline != nil)
    #expect(statsB.headline != nil)
    #expect(close(statsA.headline!.value, 8.4),
            "Volvo's history must produce its own 8.4 L/100, got \(statsA.headline!.value)")
    #expect(close(statsB.headline!.value, 17.8),
            "the EV's history must produce its own 17.8 kWh/100, got \(statsB.headline!.value)")
    #expect(statsA.headline!.value != statsB.headline!.value)
    #expect(statsA.odometer == 119_000)
    #expect(statsB.odometer == 31_240)
}

// MARK: - Archived cars (J13)

@Test func archivedCarsStayOutOfActiveStatsButKeepHistory() throws {
    let repo = try makeRepo()
    let volvo = makeVehicle(name: "Volvo V60")
    let bmw = makeVehicle(name: "BMW 320d", archived: true)
    try repo.upsertVehicle(volvo)
    try repo.upsertVehicle(bmw)
    // History kept: the archived car keeps its entries in the repository.
    try repo.upsertFillUp(makeFillUp(vehicleId: bmw.id))
    try repo.upsertFillUp(makeFillUp(vehicleId: volvo.id))

    // Not selected by default: no preference -> the live car wins.
    #expect(VehicleSelection.resolve(try repo.liveVehicles(), defaultID: nil)?.id == volvo.id)
    // Even a stale preference pointing at the archived car falls back to live.
    try repo.selectVehicle(bmw.id)
    #expect(VehicleSelection.resolve(try repo.liveVehicles(),
                                     defaultID: try repo.selectedVehicleID())?.id == volvo.id,
            "an archived car must never win the selection while a live car exists")
    // Out of active stats: the archived car is not the selection, so its entries
    // never feed the on-screen engine.
    // History kept (J13): its entries are still retrievable, nothing is lost.
    #expect(try repo.liveEntries(forVehicle: bmw.id).count == 1)
    #expect(try repo.vehicle(id: bmw.id)?.archived == true)
}

// MARK: - Per-vehicle units

@Test func unitsArePerVehicleFromOneCodePath() throws {
    let ev = makeVehicle(name: "ID.4", powertrain: .ev, fuelKinds: [.electricity])
    let petrol = makeVehicle(name: "Volvo V60")

    #expect(ev.headlineUnit == .energyPer100)
    #expect(petrol.headlineUnit == .consumption(.lPer100))
    #expect(HeadlineUnit.consumption(.mpgUS) != HeadlineUnit.consumption(.lPer100))

    // The same code path all the way to the derived figure: HomeStats for the
    // EV reports a kWh number (energy segments), for the petrol car a litre
    // number (fuel segments).
    let repo = try makeRepo()
    try repo.upsertVehicle(ev)
    try repo.upsertChargeSession(makeCharge(vehicleId: ev.id,
                                            date: timestamp.addingTimeInterval(-12 * 86_400),
                                            odometer: 30_937, energyKWh: 60))
    try repo.upsertChargeSession(makeCharge(vehicleId: ev.id,
                                            date: timestamp.addingTimeInterval(-3 * 86_400),
                                            odometer: 31_240, energyKWh: 54))
    let evStats = HomeStats(vehicle: ev, entries: try repo.liveEntries(forVehicle: ev.id))
    #expect(close(evStats.headline!.value, 17.8),
            "an EV's headline must be the kWh figure, got \(evStats.headline!.value)")
}

// MARK: - The free-tier car limit (the ONE monetization surface)

@Test func carLimitRefusesAddsAtTheCap() throws {
    #expect(CarLimit.freeTierLimit == 3, "docs/ERRORS.md: 'Free keeps up to 3 cars.'")
    #expect(CarLimit.canAddCar(activeCount: 0))
    #expect(CarLimit.canAddCar(activeCount: 1))
    #expect(CarLimit.canAddCar(activeCount: 2))
    #expect(!CarLimit.canAddCar(activeCount: 3), "at the cap, adding is refused")
    #expect(!CarLimit.canAddCar(activeCount: 4))
    #expect(CarLimit.canAddCar(activeCount: 10, pro: true), "Pro lifts the cap (P6)")
}

@Test func carLimitNeverLocksExistingCars() throws {
    // The anti-CarScope promise (docs/COMPETITORS.md): hitting the cap prevents
    // ADDS; it never takes away what the user already has. Asserted explicitly
    // because a future "gate" could easily ship as a write block.
    let repo = try makeRepo()
    let vehicles = (0..<3).map { _ in makeVehicle() }
    for vehicle in vehicles {
        try repo.upsertVehicle(vehicle)
    }
    let active = try repo.liveVehicles().filter { !$0.archived }
    #expect(active.count == CarLimit.freeTierLimit)
    #expect(!CarLimit.canAddCar(activeCount: active.count))

    // Entries still saveable.
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicles[0].id))
    #expect(try repo.liveFillUps(forVehicle: vehicles[0].id).count == 1)

    // Vehicles still editable.
    var edited = vehicles[1]
    edited.name = "Renamed V60"
    try repo.upsertVehicle(edited)
    #expect(try repo.vehicle(id: vehicles[1].id)?.name == "Renamed V60")

    // Everything still readable.
    #expect(try repo.liveVehicles().count == 3)
    #expect(try repo.liveFillUps(forVehicle: vehicles[0].id).first != nil)
}
