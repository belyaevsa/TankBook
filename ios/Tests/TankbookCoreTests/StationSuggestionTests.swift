import Testing
import Foundation
@testable import TankbookCore

/// PJ.19: the Confirm sheet's station suggestion ladder (docs/JOURNEYS.md -> J4
/// "Station suggestion - the logic"). The ladder, first match wins: a favourite
/// within 300 m -> the last-used station within 300 m -> the car's most recently
/// used station regardless of distance -> nothing. The tests assert WHICH
/// station wins (the order, never mere membership), the nil cases that must
/// leave the sheet exactly as it is, the last-visit fuel-kind default carried
/// from the ranked station, hard rule 13's "the user's pick is never
/// overridden", and hard rule 12's "no coordinate, name or distance is logged".
@Suite struct StationSuggestionTests {

    private static let reference = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let origin = GeoCoordinate(latitude: 59.4378, longitude: 24.7536)

    /// A station whose location is `deltaDegrees` north of the fixture origin
    /// (~111.3 km per degree of latitude, so +0.001 is ~111 m and +0.004 is
    /// ~445 m - one clearly inside the 300 m gate, one clearly outside).
    private func station(_ name: String, deltaDegrees: Double,
                         favorite: Bool = false, lastUsedAt: Date? = nil,
                         fuelKind: FuelKind? = nil, id: UUID = UUID.v7()) -> Station {
        Station(id: id, createdAt: Self.reference, updatedAt: Self.reference,
                deletedAt: nil, name: name, brand: nil,
                location: GeoCoordinate(latitude: origin.latitude + deltaDegrees,
                                        longitude: origin.longitude),
                favorite: favorite,
                defaults: Station.Defaults(fuelKind: fuelKind, fuelGrade: nil),
                lastUsedAt: lastUsedAt)
    }

    private func context(stations: [Station],
                         authorised: Bool = true,
                         fix: GeoCoordinate? = nil,
                         recentStationID: UUID? = nil,
                         fuelKinds: [FuelKind] = [.petrol95]) -> StationSuggestion.Context {
        StationSuggestion.Context(
            stations: stations,
            locationAuthorised: authorised,
            currentLocation: fix ?? (authorised ? origin : nil),
            recentStationIDForVehicle: recentStationID,
            vehicleFuelKinds: fuelKinds)
    }

    private func winner(in context: StationSuggestion.Context) -> Station? {
        StationSuggestion.propose(in: context)?.station
    }

    // MARK: - The distance helper

    @Test func distanceMetersIsZeroAtTheSamePoint() {
        #expect(StationSuggestion.distanceMeters(from: origin, to: origin) == 0)
    }

    @Test func distanceMetersMatchesADegreeOfLatitude() {
        let oneMeterNorth = GeoCoordinate(latitude: origin.latitude + 0.0001,
                                          longitude: origin.longitude)
        // 0.0001 degrees of latitude is ~11.1 m.
        let meters = StationSuggestion.distanceMeters(from: origin, to: oneMeterNorth)
        #expect(abs(meters - 11.13) < 1.0, "got \(meters)")
    }

    // MARK: - The ladder ORDER (the substance of the ranking)

    @Test func favouriteWithinRangeOutranksANearerLastUsedStation() {
        // Rung 1 beats rung 2 even when the last-used station is nearer: the
        // ladder is a priority, not a nearest-first sort.
        let favourite = station("Favourite near", deltaDegrees: 0.001, favorite: true)
        let nearerLastUsed = station("Last used nearer", deltaDegrees: 0.0002,
                                     lastUsedAt: Self.reference)
        let proposal = StationSuggestion.propose(in: context(
            stations: [nearerLastUsed, favourite]))
        #expect(proposal?.station.id == favourite.id)
    }

    @Test func nearestFavouriteWithinRangeWins() {
        // Two favourites in range: the NEAREST one proposes, not just any.
        let farFavourite = station("Favourite far", deltaDegrees: 0.001, favorite: true)
        let nearFavourite = station("Favourite near", deltaDegrees: 0.0001, favorite: true)
        let proposal = StationSuggestion.propose(in: context(
            stations: [farFavourite, nearFavourite]))
        #expect(proposal?.station.id == nearFavourite.id)
    }

    @Test func lastUsedWithinRangeOutranksTheCarRecentStationOutOfRange() {
        // No favourite: rung 2 (the in-range last-used station) beats rung 3
        // (the car's most recent station) when that one is out of range.
        let inRangeLastUsed = station("In-range last used", deltaDegrees: 0.001,
                                      lastUsedAt: Self.reference.addingTimeInterval(-86_400))
        let carRecent = station("Car recent far", deltaDegrees: 0.01,
                                lastUsedAt: Self.reference)
        let proposal = StationSuggestion.propose(in: context(
            stations: [carRecent, inRangeLastUsed],
            recentStationID: carRecent.id))
        #expect(proposal?.station.id == inRangeLastUsed.id)
    }

    @Test func theMostRecentlyUsedWithinRangeWinsAmongSeveral() {
        let older = station("Older", deltaDegrees: 0.001,
                            lastUsedAt: Self.reference.addingTimeInterval(-10 * 86_400))
        let newer = station("Newer", deltaDegrees: 0.0005,
                            lastUsedAt: Self.reference.addingTimeInterval(-86_400))
        let proposal = StationSuggestion.propose(in: context(stations: [older, newer]))
        #expect(proposal?.station.id == newer.id)
    }

    @Test func outOfRangeFallsThroughToTheCarRecentStation() {
        // ERRORS.md -> Confirm: "none within 300 m -> falls through to the most
        // recent station".
        let outOfRange = station("Far", deltaDegrees: 0.01)
        let proposal = StationSuggestion.propose(in: context(
            stations: [outOfRange], recentStationID: outOfRange.id))
        #expect(proposal?.station.id == outOfRange.id)
    }

    @Test func rung3ProposesTheCarRecentStationRegardlessOfPermission() {
        // ERRORS.md -> Confirm, "location denied": the ranking runs without its
        // distance rungs - the car's most recent station is still proposed.
        let carRecent = station("Car recent", deltaDegrees: 0.01)
        let proposal = StationSuggestion.propose(in: context(
            stations: [carRecent], authorised: false, fix: nil,
            recentStationID: carRecent.id))
        #expect(proposal?.station.id == carRecent.id)
    }

    // MARK: - The nil cases: a suggestion's absence is a non-event

    @Test func noStationsProposesNothing() {
        #expect(winner(in: context(stations: [])) == nil)
    }

    @Test func noPermissionAndNoCarStationHistoryProposesNothing() {
        // Stations exist but none is the car's, and the distance rungs cannot
        // run: nothing is proposed and nothing is pre-selected.
        let somewhere = station("Somewhere", deltaDegrees: 0.001, favorite: true)
        let proposal = StationSuggestion.propose(in: context(
            stations: [somewhere], authorised: false, fix: nil))
        #expect(proposal == nil)
    }

    @Test func noFixAndNoCarStationHistoryProposesNothing() {
        // Authorised but no fix yet (the read has not answered): the distance
        // rungs have nothing to measure and the car has no station history.
        let somewhere = station("Somewhere", deltaDegrees: 0.001, favorite: true)
        let proposal = StationSuggestion.propose(in: StationSuggestion.Context(
            stations: [somewhere], locationAuthorised: true,
            currentLocation: nil, recentStationIDForVehicle: nil,
            vehicleFuelKinds: [.petrol95]))
        #expect(proposal == nil)
    }

    @Test func nothingWithinRangeAndNoCarStationHistoryProposesNothing() {
        let far = station("Far", deltaDegrees: 0.02)
        let proposal = StationSuggestion.propose(in: context(
            stations: [far], recentStationID: nil))
        #expect(proposal == nil)
    }

    @Test func aStationWithNoCoordinateIsNeverInRange() {
        // A station without a recorded location cannot win a distance rung, and
        // with no car history nothing is proposed.
        let noCoordinate = Station(id: UUID.v7(), createdAt: Self.reference,
                                   updatedAt: Self.reference, deletedAt: nil,
                                   name: "No coordinate", brand: nil, location: nil,
                                   favorite: true,
                                   defaults: Station.Defaults(fuelKind: nil, fuelGrade: nil),
                                   lastUsedAt: nil)
        #expect(winner(in: context(stations: [noCoordinate])) == nil)
    }

    // MARK: - The last-visit fuel-kind default

    @Test func fuelDefaultComesFromTheRankedStation() {
        // Two favourites in range; only the nearer one carries a default. The
        // proposal must carry the RANKED station's default, never the loser's.
        let nearer = station("Near", deltaDegrees: 0.0001, favorite: true,
                             fuelKind: .petrol98)
        let farther = station("Far", deltaDegrees: 0.001, favorite: true,
                              fuelKind: .petrol92)
        let proposal = StationSuggestion.propose(in: context(stations: [farther, nearer]))
        #expect(proposal?.station.id == nearer.id)
        #expect(proposal?.fuelKindDefault == .petrol98)
    }

    @Test func fuelDefaultOnlyWhenTheVehicleCanTakeIt() {
        // Petrol grades share a tank (docs/DESIGN.md): a 95 car takes 98.
        let grade = station("Grade station", deltaDegrees: 0.001, favorite: true,
                            fuelKind: .petrol98)
        let proposal = StationSuggestion.propose(in: context(stations: [grade]))
        #expect(proposal?.fuelKindDefault == .petrol98)
    }

    @Test func aFuelKindTheVehicleDoesNotOfferIsNeverADefault() {
        // A diesel default on a petrol-only car is never applied - the station
        // itself still proposes, only its fuel default stays off.
        let dieselStation = station("Diesel forecourt", deltaDegrees: 0.001,
                                    favorite: true, fuelKind: .diesel)
        let proposal = StationSuggestion.propose(in: context(stations: [dieselStation]))
        #expect(proposal?.station.id == dieselStation.id)
        #expect(proposal?.fuelKindDefault == nil)
    }

    @Test func aStationWithNoRecordedKindCarriesNoFuelDefault() {
        let plain = station("Plain", deltaDegrees: 0.001, favorite: true, fuelKind: nil)
        let proposal = StationSuggestion.propose(in: context(stations: [plain]))
        #expect(proposal?.fuelKindDefault == nil)
    }

    // MARK: - Rung 3's input derivation

    @Test func recentStationIDComesFromTheCarsMostRecentFilledFill() {
        let stationA = station("A", deltaDegrees: 0)
        let stationB = station("B", deltaDegrees: 0)
        let older = makeFill(using: stationA.id, date: Self.reference.addingTimeInterval(-86_400))
        let newer = makeFill(using: stationB.id, date: Self.reference)
        #expect(StationSuggestion.recentStationID(for: [older, newer]) == stationB.id)
    }

    @Test func recentStationIDSkipsFillsThatNameNoStation() {
        let stationA = station("A", deltaDegrees: 0)
        let stationless = makeFill(using: nil, date: Self.reference)
        let withStation = makeFill(using: stationA.id, date: Self.reference.addingTimeInterval(-86_400))
        #expect(StationSuggestion.recentStationID(for: [stationless, withStation]) == stationA.id)
    }

    @Test func recentStationIDIsNilWithNoFilledFills() {
        let stationless = makeFill(using: nil, date: Self.reference)
        #expect(StationSuggestion.recentStationID(for: [stationless]) == nil)
    }

    // MARK: - Hard rule 13: a user's pick is never overridden

    @Test func aUserChosenStationIsNeverReplacedByALaterPass() {
        #expect(StationSuggestionApplication.shouldApply(userChoseStation: true,
                                                         pendingSuggestionExists: true) == false)
        #expect(StationSuggestionApplication.shouldApply(userChoseStation: true,
                                                         pendingSuggestionExists: false) == false)
    }

    @Test func aPassMayApplyOnlyWhileTheUserHasChosenNothing() {
        #expect(StationSuggestionApplication.shouldApply(userChoseStation: false,
                                                         pendingSuggestionExists: true) == true)
        #expect(StationSuggestionApplication.shouldApply(userChoseStation: false,
                                                         pendingSuggestionExists: false) == false)
    }

    private func makeFill(using stationID: UUID?, date: Date) -> FillUp {
        FillUp(id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
               vehicleId: UUID.v7(), date: date, odometer: nil,
               money: Money(amount: 1, currency: .eur, homeCurrency: .eur),
               note: nil, attachments: [], provenance: .manual, conflict: .none,
               purchaseGroupId: nil, volumeL: 1, unitPrice: nil,
               fuelKind: .petrol95, fuelGrade: nil, isFull: true,
               tankLevelAfterPct: 100, stationId: stationID,
               crossCheck: .notApplicable, extraction: nil)
    }
}

/// Hard rule 12: the ranking and the location client never log a coordinate, a
/// station name or a distance - they perform no logging at all, and a source
/// scan pins that (the same text-scan pattern as `ConfigBaseURLGrepGateTests`).
@Suite struct StationSuggestionLoggingGateTests {

    private static var iosRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TankbookCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ios
    }

    @Test func theFeatureNeverLogs() throws {
        let files = [
            "Sources/TankbookCore/Domain/StationSuggestion.swift",
            "App/Sources/ConfirmManual/ForecourtLocationReader.swift"
        ]
        let forbidden = ["AppLog", "print(", "Logger(", "Logging/", ".error(operation:"]
        var offenders: [String] = []
        for relative in files {
            let url = Self.iosRoot.appendingPathComponent(relative)
            let contents = try String(contentsOf: url, encoding: .utf8)
            if forbidden.contains(where: { contents.contains($0) }) {
                offenders.append(relative)
            }
        }
        #expect(offenders.isEmpty,
                "the station ranking and its location seam must never log (hard rule 12). Offenders: \(offenders)")
    }
}
