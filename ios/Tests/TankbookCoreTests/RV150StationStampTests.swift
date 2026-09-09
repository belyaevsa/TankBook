import Foundation
import Testing
@testable import TankbookCore

/// RV.150 - the fill-up save stamps the fields the station ranking reads
/// (docs/JOURNEYS.md -> J4, docs/SCHEMA.md -> Station). PJ.19 shipped the
/// ranking but the save never wrote `Station.lastUsedAt`, `Station.defaults` or
/// a missing `Station.location`, so rungs 1-2 ranked on fields that only an
/// import or a test seed populated and a by-hand user degraded to rung 3
/// forever. These tests pin the stamp the save now makes, the fill-blanks-only
/// location rule, the no-op guard ([RV.136]: a save that changes nothing writes
/// nothing), and the point of the whole row - that after a save the RANKING
/// orders differently, never merely that a field changed.
@Suite struct RV150StationStampTests {

    private static let reference = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let origin = GeoCoordinate(latitude: 59.4378, longitude: 24.7536)
    private let other = GeoCoordinate(latitude: 59.4378, longitude: 24.8000)

    private func makeRepository() throws -> TankbookRepository {
        try TankbookRepository(database: TankbookDatabase.inMemory())
    }

    private func stampDate() -> Date { Self.reference.addingTimeInterval(2 * 86_400) }

    private func station(_ name: String,
                         location: GeoCoordinate? = nil,
                         favorite: Bool = false,
                         lastUsedAt: Date? = nil,
                         fuelKind: FuelKind? = nil,
                         fuelGrade: String? = nil,
                         createdAt: Date = Self.reference) -> Station {
        Station(id: UUID.v7(), createdAt: createdAt, updatedAt: createdAt,
                deletedAt: nil, name: name, brand: "Prima Group",
                location: location, favorite: favorite,
                defaults: Station.Defaults(fuelKind: fuelKind, fuelGrade: fuelGrade),
                lastUsedAt: lastUsedAt)
    }

    // MARK: - The stamp's shape

    @Test func aSaveStampsLastUsedAtAndNothingElseAboutTheStation() throws {
        // A station that already has a location (so the fill-blanks rule is not
        // the thing being tested here): the save must touch lastUsedAt and the
        // bought defaults, and NOTHING else - name, brand, favourite, id and
        // createdAt survive untouched.
        let repo = try makeRepository()
        let original = station("Prima Auto", location: other, favorite: true,
                               lastUsedAt: Self.reference.addingTimeInterval(-86_400))
        try repo.upsertStation(original)

        let saved = try repo.station(id: original.id)
        #expect(saved != nil, "the station must be on file before the save")

        let now = Self.reference.addingTimeInterval(2 * 86_400)
        #expect(try repo.stampStation(id: original.id, fuelKind: .petrol98,
                                      fuelGrade: nil, locationFix: origin,
                                      at: now))

        guard let stamped = try repo.station(id: original.id) else {
            Issue.record("the station must still exist after the save")
            return
        }
        #expect(stamped.id == original.id)
        #expect(stamped.createdAt == original.createdAt)
        #expect(stamped.name == original.name)
        #expect(stamped.brand == original.brand)
        #expect(stamped.favorite == original.favorite)
        #expect(stamped.updatedAt == now)
        #expect(stamped.lastUsedAt == now,
                "the save stamps lastUsedAt on the station the user confirmed")
        #expect(stamped.location == other,
                "a station that already has a location keeps it - never overwritten")
    }

    @Test func theWrittenDefaultsAreTheKindActuallyBought() throws {
        // The last-visit default the ranking applies must be what was really
        // bought there, not whatever the station recorded before.
        let repo = try makeRepository()
        let original = station("Prima Auto", fuelKind: .petrol92)
        try repo.upsertStation(original)

        try repo.stampStation(id: original.id, fuelKind: .petrol98,
                              fuelGrade: nil, locationFix: nil,
                              at: Self.reference.addingTimeInterval(86_400))

        let stamped = try repo.station(id: original.id)
        #expect(stamped?.defaults.fuelKind == .petrol98,
                "the default must follow the fill, never the previously stored kind")
    }

    @Test func aFillWithNoGradeLeavesTheStoredGradeAlone() throws {
        let repo = try makeRepository()
        let original = station("Prima Auto", fuelKind: .petrol95, fuelGrade: "ЭКТО")
        try repo.upsertStation(original)

        try repo.stampStation(id: original.id, fuelKind: .petrol95,
                              fuelGrade: nil, locationFix: nil,
                              at: Self.reference.addingTimeInterval(86_400))

        let stamped = try repo.station(id: original.id)
        #expect(stamped?.defaults.fuelGrade == "ЭКТО",
                "blanks-fill-only: a fill with no grade does not wipe a stored grade")
    }

    @Test func aStationThatAlreadyHasALocationIsNeverOverwrittenByAFix() throws {
        let repo = try makeRepository()
        let original = station("Prima Auto", location: other, lastUsedAt: nil)
        try repo.upsertStation(original)

        // A LATER fix at a different point must not displace the recorded one.
        let laterFix = GeoCoordinate(latitude: 59.5, longitude: 24.8)
        try repo.stampStation(id: original.id, fuelKind: .petrol95,
                              fuelGrade: nil, locationFix: laterFix,
                              at: Self.reference.addingTimeInterval(86_400))

        #expect(try repo.station(id: original.id)?.location == other,
                "a coordinate the station already has is the user's own - never overwritten")
    }

    @Test func withNoFixTheSaveWritesNoLocationAndDoesNotFail() throws {
        let repo = try makeRepository()
        let original = station("Prima Auto", location: nil, lastUsedAt: nil)
        try repo.upsertStation(original)

        // No permission / no fix: the save proceeds, stamps lastUsedAt and the
        // defaults, and leaves location nil. A non-event, never an error.
        let now = Self.reference.addingTimeInterval(86_400)
        let wrote = try repo.stampStation(id: original.id, fuelKind: .petrol95,
                                          fuelGrade: nil, locationFix: nil, at: now)
        #expect(wrote)
        let stamped = try repo.station(id: original.id)
        #expect(stamped?.lastUsedAt == now)
        #expect(stamped?.location == nil,
                "no fix means no location is written")
        #expect(stamped?.defaults.fuelKind == .petrol95)
    }

    @Test func theStampTargetsTheLiveRowNotASheetSnapshot() throws {
        // The save reloads the current station before stamping: a field that
        // arrived by sync AFTER the Confirm sheet loaded must survive the stamp
        // (a stale snapshot would silently revert it - hard rule 13).
        let repo = try makeRepository()
        let original = station("Prima Auto", favorite: false)
        try repo.upsertStation(original)
        // The sheet opened with the ORIGINAL (favorite false); meanwhile the
        // row moved on (a sync merge set favorite true).
        var newer = original
        newer.favorite = true
        newer.updatedAt = Self.reference.addingTimeInterval(3600)
        try repo.upsertStation(newer, syncState: .synced(scn: 7))

        try repo.stampStation(id: original.id, fuelKind: .petrol95,
                              fuelGrade: nil, locationFix: origin,
                              at: Self.reference.addingTimeInterval(7200))

        let stamped = try repo.station(id: original.id)
        #expect(stamped?.favorite == true,
                "the stamp must build on the LIVE row, never the sheet's stale copy")
        #expect(stamped?.location == origin)
    }

    // MARK: - The RV.136 guard: a save that changes nothing writes nothing

    @Test func aStampThatChangesNothingWritesNothing() throws {
        let repo = try makeRepository()
        let now = Self.reference.addingTimeInterval(86_400)
        let seeded = station("Prima Auto", location: origin, lastUsedAt: now,
                             fuelKind: .petrol95)
        try repo.upsertStation(seeded, syncState: .synced(scn: 3))

        // A second save with the very same stamp content: every field the stamp
        // owns already holds the value it would write.
        let wrote = try repo.stampStation(id: seeded.id, fuelKind: .petrol95,
                                          fuelGrade: nil, locationFix: origin,
                                          at: now)
        #expect(!wrote, "a save that changes nothing must write nothing")
        #expect(try repo.fetchDirtyRows().isEmpty,
                "the no-op stamp must not dirty the row ([RV.136])")
        guard case .synced = try repo.localSyncRecord(id: seeded.id,
                                                      entityType: Station.entityType)?.syncState else {
            Issue.record("the station must still be synced after the no-op")
            return
        }
    }

    @Test func aMissingStationIsANonEvent() throws {
        let repo = try makeRepository()
        let wrote = try repo.stampStation(id: UUID.v7(), fuelKind: .petrol95,
                                          fuelGrade: nil, locationFix: origin)
        #expect(!wrote, "no station on file means nothing to stamp - never an error")
    }

    // MARK: - The point of the row: the RANKING orders differently after a save

    @Test func afterASaveTheRankingOrdersDifferently() throws {
        // A hand-typed user's station list before RV.150: the station she fills
        // at has no location and no lastUsedAt, so rungs 1-2 cannot order it -
        // nothing is proposed. After her save stamps it, the SAME station is
        // the in-range, last-used winner. This asserts the RANKING, never the
        // field - the field is the mechanism, the ordering is the feature.
        let repo = try makeRepository()
        let car = RV150TestVehicle.make()
        try repo.upsertVehicle(car)
        // The station the user keeps filling at by hand: no location, never
        // used, not a favourite - invisible to rungs 1-2 before the save.
        let handTyped = station("Prima Auto", location: nil, lastUsedAt: nil,
                                fuelKind: .petrol95)
        // A favourite far away: cannot win rung 1, and with no car history
        // nothing falls through to rung 3.
        let farFavourite = station("Shell Far", location: other, favorite: true,
                                   fuelKind: .petrol95)
        try repo.upsertStation(handTyped)
        try repo.upsertStation(farFavourite)

        func propose() throws -> Station? {
            let stations = try repo.liveStations()
            return StationSuggestion.propose(in: StationSuggestion.Context(
                stations: stations, locationAuthorised: true,
                currentLocation: origin, recentStationIDForVehicle: nil,
                vehicleFuelKinds: [.petrol95]))?.station
        }

        #expect(try propose() == nil,
                "before the save the by-hand station cannot win a distance rung")

        // The save at the chosen station (the fix the Confirm sheet already read).
        let now = Self.reference.addingTimeInterval(2 * 86_400)
        #expect(try repo.stampStation(id: handTyped.id, fuelKind: .petrol95,
                                      fuelGrade: nil, locationFix: origin, at: now))

        #expect(try propose()?.id == handTyped.id,
                "after the save the station is in range AND last used - the ranking must order differently")
    }
}

/// A small vehicle fixture for the ranking test (isolated so the suite owns its
/// own car rather than sharing one across tests).
private enum RV150TestVehicle {
    static func make() -> Vehicle {
        let createdAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return Vehicle(id: UUID.v7(), createdAt: createdAt, updatedAt: createdAt,
                       deletedAt: nil, name: "Test Volvo", make: "Volvo",
                       model: "V60", year: 2015, plate: nil, powertrain: .ice,
                       fuelKinds: [.petrol95], tankCapacityL: 71,
                       batteryCapacityKWh: nil, homeCurrency: .eur,
                       units: Vehicle.Units(distance: .km, volume: .l,
                                            consumption: .lPer100, energy: .kWhPer100),
                       photo: nil, archived: false, paceLimitKmPerDay: 1500,
                       initialOdometer: 119_486)
    }
}

/// Hard rule 12: the stamp's write path never logs a coordinate, a station name
/// or a distance - the core stamp performs no logging at all, and the app-side
/// save seam only ever records the operation name and the station id (Safe
/// class, docs/LOGGING.md). A source scan pins both halves (the same text-scan
/// pattern as `StationSuggestionLoggingGateTests`).
@Suite struct RV150StationStampLoggingGateTests {

    private static var iosRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TankbookCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ios
    }

    @Test func theCoreStampNeverLogs() throws {
        let url = Self.iosRoot
            .appendingPathComponent("Sources/TankbookCore/Domain/StationStamp.swift")
        let contents = try String(contentsOf: url, encoding: .utf8)
        let forbidden = ["AppLog", "print(", "Logger(", "Logging/", ".error(operation:", ".emit("]
        let offenders = forbidden.filter { contents.contains($0) }
        #expect(offenders.isEmpty,
                "the station stamp must never log (hard rule 12). Offenders: \(offenders)")
    }

    @Test func noCoordinateBearingLineInTheSaveSeamLogs() throws {
        // The app seam files: ManualFillUpView carries legitimate operation
        // logging elsewhere (confirmManual.save), so the scan is line-scoped -
        // no LINE that mentions a coordinate may also log. A coordinate is a
        // domain value (hard rule 12), whatever the level.
        let files = [
            "App/Sources/ConfirmManual/ManualFillUpView.swift",
            "App/Sources/ConfirmManual/ManualFillUpView+StationStamp.swift",
            "App/Sources/ConfirmManual/ManualFillUpView+StationSuggestion.swift",
            "App/Sources/ConfirmManual/ForecourtLocationReader.swift",
            "App/Sources/Garage/GarageView.swift",
            "App/Sources/StationSettings/StationSettingsView.swift",
            "App/Sources/StationSettings/StationsListView.swift"
        ]
        let forbidden = ["AppLog", "print(", "Logger(", ".error(", ".emit(", "log("]
        var offenders: [String] = []
        for relative in files {
            let url = Self.iosRoot.appendingPathComponent(relative)
            let contents = try String(contentsOf: url, encoding: .utf8)
            for line in contents.split(separator: "\n") {
                let text = String(line)
                let mentionsCoordinate = text.contains("latitude")
                    || text.contains("longitude")
                    || text.contains("GeoCoordinate")
                    || text.contains("locationFix")
                    || text.contains("stationLocationFix")
                if mentionsCoordinate, forbidden.contains(where: { text.contains($0) }) {
                    offenders.append("\(relative): \(text.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(offenders.isEmpty,
                "no coordinate-bearing line in the station stamp seam may log. Offenders: \(offenders)")
    }

    @Test func theAppSaveSeamCallsTheStamp() throws {
        // Wiring pin: the ManualFillUpView save must route through the core
        // stamp. Without this the L1 tests pass (they drive the core directly)
        // while the feature stays dead in the app.
        let appURL = Self.iosRoot
            .appendingPathComponent("App/Sources/ConfirmManual/ManualFillUpView.swift")
        let appContents = try String(contentsOf: appURL, encoding: .utf8)
        #expect(appContents.contains("upsertFillUp(toSave)"),
                "the fill-up save must still write the entry")
        #expect(appContents.contains("stampChosenStation("),
                "the fill-up save must stamp the chosen station after the entry write")
        let seamURL = Self.iosRoot
            .appendingPathComponent("App/Sources/ConfirmManual/ManualFillUpView+StationStamp.swift")
        let seamContents = try String(contentsOf: seamURL, encoding: .utf8)
        #expect(seamContents.contains("stampStation("),
                "the stamp seam must call repository.stampStation")
    }
}
