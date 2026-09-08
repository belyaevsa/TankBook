import Foundation
import Testing
@testable import TankbookCore

// RV.142: the Log row's station chain and its per-fill consumption, at L1
// (docs/TESTING.md). Two bugs and one missing figure:
//   1. an imported station name is dropped on the way in - it must become a
//      `Station` record and a resolvable `stationId` on the fill;
//   2. `showsFuelKind` repeated the kind when the row's title already was that
//      kind - it must be title-aware;
//   3. per-fill consumption exists in the engine (`Segment.per100` keyed by
//      `closingFillID`) and must reach the row - ABSENT, never zero, for a fill
//      that closes no segment.

@Suite struct RV142StationAndConsumptionTests {

    private static func makeRepository() throws -> TankbookRepository {
        TankbookRepository(database: try TankbookDatabase.inMemory())
    }

    private static func makeVehicle(fuelKinds: [FuelKind] = [.diesel]) -> Vehicle {
        let now = Date(timeIntervalSinceReferenceDate: 700_000_000)
        return Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Škoda Octavia", make: "Škoda", model: "Octavia", year: 2020,
            plate: nil, powertrain: .ice, fuelKinds: fuelKinds,
            tankCapacityL: 50, batteryCapacityKWh: nil, homeCurrency: .rub,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 375_000)
    }

    private static func makeCandidate(row: Int,
                                      date: Date,
                                      odometer: Int,
                                      volumeL: Double = 42.0,
                                      station: String?) -> ImportCandidate {
        ImportCandidate(
            entityType: "fillUp", date: date, odometer: odometer, volumeL: volumeL,
            unitPrice: "1.9", money: ImportMoney(amount: "79.80", currency: "RUB"),
            fuelKind: "diesel", isFull: true, tankLevelAfterPct: 100, note: nil,
            vehicleName: nil, provenance: ImportProvenance(tag: "import", source: "drivvo"),
            sourceRow: row, station: station)
    }

    /// One ready fill for a candidate that is committable on its own (no
    /// odometer/date conflict against an empty history).
    private static func convert(_ candidate: ImportCandidate,
                                vehicle: Vehicle,
                                stations: [Station] = []) -> FillUp {
        ImportConverter.makeFill(from: candidate, vehicle: vehicle,
                                 source: "drivvo", existingStations: stations)!
    }

    // MARK: - The station chain: name -> candidate -> Station -> stationId

    @Test func importedStationNameArrivesWithAResolvableStationID() throws {
        let repo = try Self.makeRepository()
        let vehicle = Self.makeVehicle()
        try repo.upsertVehicle(vehicle)

        // The real Drivvo shape: a `Азс` value riding the refuelling row.
        let date = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let candidate = Self.makeCandidate(row: 1, date: date,
                                           odometer: 375_963, station: "Газпром")
        let fill = Self.convert(candidate, vehicle: vehicle)
        #expect(fill.stationId != nil, "the fill must carry a resolvable station id")

        // The commit materialises the Station and writes the fill atomically.
        let existing = try repo.liveStations()
        var nameByStationID: [UUID: String] = [:]
        nameByStationID[ImportStationResolver.station(for: "Газпром", existing: existing).id] = "Газпром"
        let records: [ArchiveImportRecord] = [.fillUp(fill)] +
            ImportStationResolver.missingStations(keptStationIDs: [fill.stationId!],
                                                  nameByID: nameByStationID,
                                                  existing: existing)
            .map(ArchiveImportRecord.station)
        try repo.commitImport(records, source: "drivvo")

        let stations = try repo.liveStations()
        let station = try #require(stations.first { $0.name == "Газпром" })
        #expect(station.id == fill.stationId,
                "the committed station is the one the fill references")
        let stored = try #require(try repo.liveFillUps(forVehicle: vehicle.id).first)
        #expect(stored.stationId == station.id,
                "the stored fill's stationId resolves against liveStations")
    }

    /// The regressed fallback (RV.142): an imported row WITHOUT a station keeps
    /// `nil`, the row titles itself with the fuel kind, and the subtitle never
    /// repeats that kind - even on a multi-fuel car, where the kind otherwise
    /// earns its place.
    @Test func importedRowWithoutAStationKeepsNilAndNeverRepeatsTheKind() throws {
        let repo = try Self.makeRepository()
        let vehicle = Self.makeVehicle(fuelKinds: [.diesel, .petrol95])
        try repo.upsertVehicle(vehicle)

        let date = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let stationless = Self.makeCandidate(row: 1, date: date,
                                             odometer: 375_963, station: nil)
        let fill = Self.convert(stationless, vehicle: vehicle)
        #expect(fill.stationId == nil,
                "a file with no station for the row must keep stationId nil")

        let entry = try #require(Self.firstEntry(of: LogStream(vehicle: vehicle,
                                                               entries: [fill])))
        // Multi-fuel: the kind earns its place against the vehicle, but the
        // title IS the kind (no station to name the row), so it must not repeat.
        #expect(entry.showsFuelKind == false)
        #expect(!entry.subtitleSegments.contains { segment in
            if case .fuelKind = segment { return true } else { return false }
        })
    }

    @Test func stationTitledRowShowsTheKindOnlyWhenItEarnsItsPlace() throws {
        let vehicle = Self.makeVehicle(fuelKinds: [.diesel, .petrol95])
        let station = Station(
            id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            name: "Shell", brand: nil, location: nil, favorite: true,
            defaults: Station.Defaults(fuelKind: .diesel, fuelGrade: nil),
            lastUsedAt: nil)

        let date = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let candidate = Self.makeCandidate(row: 1, date: date,
                                           odometer: 375_963, station: "Shell")
        let fill = Self.convert(candidate, vehicle: vehicle, stations: [station])

        let entry = try #require(Self.firstEntry(of: LogStream(vehicle: vehicle,
                                                               entries: [fill],
                                                               stations: [station])))
        // The title is the station; the kind earns its place on a multi-fuel car.
        #expect(entry.showsFuelKind == true)

        // The same row on a single-fuel diesel car: the kind is the usual one,
        // so it stays hidden even though the title is the station.
        let single = Self.makeVehicle(fuelKinds: [.diesel])
        let singleEntry = try #require(Self.firstEntry(of: LogStream(vehicle: single,
                                                                     entries: [fill],
                                                                     stations: [station])))
        #expect(singleEntry.showsFuelKind == false)
    }

    /// The first row's LogEntry when it is a standalone entry, else nil.
    private static func firstEntry(of stream: LogStream) -> LogStream.LogEntry? {
        guard case .entry(let entry)? = stream.allRows.first else { return nil }
        return entry
    }

    // MARK: - Per-fill consumption, read from the engine's segments

    @Test func perFillConsumptionIsTheSegmentsPer100ForTheClosingFill() throws {
        let vehicle = Self.makeVehicle()
        let date = Date(timeIntervalSinceReferenceDate: 700_000_000)
        func fill(_ date: Date, odo: Int, litres: Double) -> FillUp {
            FillUp(
                id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
                vehicleId: vehicle.id, date: date, odometer: odo,
                money: Money(amount: Decimal(string: "80")!, currency: .rub,
                             homeCurrency: .rub),
                note: nil, attachments: [], provenance: .import(source: "drivvo"),
                conflict: .none, purchaseGroupId: nil, volumeL: litres,
                unitPrice: nil, fuelKind: .diesel, fuelGrade: nil, isFull: true,
                tankLevelAfterPct: 100, stationId: nil, crossCheck: .notApplicable,
                extraction: nil)
        }
        // Two full fills 500 km apart; 42.0 L of the closing fill's own litres
        // rode the distance after the opening full tank -> 8.4 L/100km.
        let opening = fill(date, odo: 375_000, litres: 50)
        let closing = fill(date.addingTimeInterval(3 * 86_400), odo: 375_500, litres: 42.0)

        let stream = LogStream(vehicle: vehicle, entries: [opening, closing])
        let entries = stream.allRows.compactMap { row -> LogStream.LogEntry? in
            guard case .entry(let entry) = row else { return nil }
            return entry
        }
        let openingEntry = try #require(entries.first { $0.id == opening.id })
        let closingEntry = try #require(entries.first { $0.id == closing.id })

        #expect(closingEntry.consumptionPer100 == 8.4)
        #expect(closingEntry.subtitleSegments.contains { segment in
            if case .consumption(8.4) = segment { return true } else { return false }
        })
        // The fill that OPENS the segment closes none: ABSENT, never zero.
        #expect(openingEntry.consumptionPer100 == nil)
        #expect(!openingEntry.subtitleSegments.contains { segment in
            if case .consumption = segment { return true } else { return false }
        })
    }

    @Test func fillThatClosesNoSegmentShowsNoConsumptionNotZero() throws {
        // A single full fill (the first - no segment can close), and a
        // non-full fill after it (nothing to close): both are the RV.142 absent
        // case. A rendered `0.0 L/100km` would be a wrong claim about the car.
        let vehicle = Self.makeVehicle()
        let date = Date(timeIntervalSinceReferenceDate: 700_000_000)
        func fill(_ date: Date, odo: Int, isFull: Bool, level: Double?) -> FillUp {
            FillUp(
                id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
                vehicleId: vehicle.id, date: date, odometer: odo,
                money: nil, note: nil, attachments: [],
                provenance: .import(source: "drivvo"), conflict: .none,
                purchaseGroupId: nil, volumeL: 42.0, unitPrice: nil,
                fuelKind: .diesel, fuelGrade: nil, isFull: isFull,
                tankLevelAfterPct: level, stationId: nil,
                crossCheck: .notApplicable, extraction: nil)
        }
        // The first fill opens nothing; the second is a top-up that records no
        // tank level, so it is not a TANK-LEVEL boundary either (docs/SCHEMA.md)
        // - with the capacity set, a level-carrying top-up WOULD close. Neither
        // fill closes a segment: the row must show no consumption figure.
        let first = fill(date, odo: 375_000, isFull: true, level: 100)
        let topUp = fill(date.addingTimeInterval(3 * 86_400), odo: 375_300, isFull: false, level: nil)

        let stream = LogStream(vehicle: vehicle, entries: [first, topUp])
        let entries = stream.allRows.compactMap { row -> LogStream.LogEntry? in
            guard case .entry(let entry) = row else { return nil }
            return entry
        }
        for entry in entries {
            #expect(entry.consumptionPer100 == nil,
                    "a fill that closes no segment carries no consumption figure")
        }
    }

    // MARK: - Materialisation: kept fills only, matched stations reused

    @Test func missingStationsOnlyForKeptFillsAndNeverForExistingNames() throws {
        let now = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let existing = Station(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Shell", brand: nil, location: nil, favorite: true,
            defaults: Station.Defaults(fuelKind: .diesel, fuelGrade: nil),
            lastUsedAt: now)

        // A kept fill at the existing Shell must NOT mint a second record.
        let shellID = ImportStationResolver.station(for: "Shell", existing: [existing]).id
        #expect(shellID == existing.id,
                "an existing exact-name station is matched, never duplicated")
        let shellStations = ImportStationResolver.missingStations(
            keptStationIDs: [shellID], nameByID: [shellID: "Shell"],
            existing: [existing], now: now)
        #expect(shellStations.isEmpty)

        // A kept fill at a NEW name mints exactly one record; a skipped row's
        // name (not in keptStationIDs) mints none.
        let gazpromID = ImportStationResolver.station(for: "Газпром", existing: [existing]).id
        let missing = ImportStationResolver.missingStations(
            keptStationIDs: [gazpromID],
            nameByID: [gazpromID: "Газпром", shellID: "Shell"],
            existing: [existing], now: now)
        #expect(missing.count == 1)
        #expect(missing[0].name == "Газпром")
        #expect(missing[0].id == gazpromID)

        let noneKept = ImportStationResolver.missingStations(
            keptStationIDs: [], nameByID: [gazpromID: "Газпром"],
            existing: [], now: now)
        #expect(noneKept.isEmpty, "a skipped row must not mint a station")
    }

    @Test func unmatchedNameMintsADeterministicID() {
        let now = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let first = ImportStationResolver.station(for: "Neste", existing: [], now: now)
        let second = ImportStationResolver.station(for: "Neste", existing: [], now: now)
        #expect(first.id == second.id, "the same name must resolve to the same id every time")
        let other = ImportStationResolver.station(for: "Shell", existing: [], now: now)
        #expect(first.id != other.id)
        #expect(first.name == "Neste")
    }
}
