import Foundation
import Testing
@testable import TankbookCore

/// The car's home city and the tire set's season: optional fields that sync,
/// persist and round-trip, and an open season value that survives a build that
/// does not know it (docs/SCHEMA.md -> Vehicle.homeCity, TireSet.season).
@Suite("Home city and tire season")
struct HomeCityAndSeasonTests {
    private let day = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func vehicle(homeCity: HomeCity?) -> Vehicle {
        Vehicle(id: UUID.v7(), createdAt: day, updatedAt: day, name: "Passat", powertrain: .ice,
                fuelKinds: [.diesel], homeCurrency: .eur,
                units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
                homeCity: homeCity)
    }

    @Test func aHomeCityPersistsAndSyncs() throws {
        let tallinn = try #require(CityDictionary(pack: .bundled).cities(named: "Tallinn").first)
        let car = vehicle(homeCity: HomeCity(city: tallinn))
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        try repository.upsertVehicle(car)
        #expect(try repository.liveVehicles().first?.homeCity == car.homeCity)

        let envelope = try PayloadCodec.encode(car)
        #expect(try PayloadCodec.decode(envelope, as: Vehicle.self).entity.homeCity?.cityId == tallinn.id)
        #expect(try PayloadCodec.decode(PayloadCodec.encode(vehicle(homeCity: nil)), as: Vehicle.self)
            .entity.homeCity == nil, "a car without a home city stays without one")
    }

    @Test func theStoredCityIsTheCarsOwnCopy() throws {
        let typed = HomeCity(name: "Peetri", country: "EE", latitude: 59.39, longitude: 24.81)
        #expect(typed.displayName(russian: true, dictionary: CityDictionary(pack: .bundled)) == "Peetri",
                "a city typed under Other shows as typed")
        let empty = CityDictionary(pack: CityPack(version: 1, cities: []))
        let tallinn = HomeCity(cityId: 588409, name: "Tallinn", country: "EE", latitude: 59.437, longitude: 24.7535)
        #expect(tallinn.displayName(russian: true, dictionary: empty) == "Tallinn",
                "a dictionary that lost the entry still shows the car's own name")
    }

    @Test func aSeasonPersistsAndAnUnknownSeasonRoundTrips() throws {
        let car = vehicle(homeCity: nil)
        var set = TireSet(id: UUID.v7(), createdAt: day, updatedAt: day, vehicleId: car.id, name: "Nokian")
        set.season = .winter
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        try repository.upsertVehicle(car)
        try repository.upsertTireSet(set)
        #expect(try repository.liveTireSets(forVehicle: car.id).first?.season == .winter)

        var future = try PayloadCodec.encode(set)
        var payload = try #require(future.payload.objectValue)
        payload["season"] = .string("studded")
        future.payload = .object(payload)
        let decoded = try PayloadCodec.decode(future, as: TireSet.self).entity
        #expect(decoded.season?.rawValue == "studded", "a season this build does not offer is kept, not a decode failure")
        #expect(try PayloadCodec.encode(decoded).payload.objectValue?["season"] == .string("studded"))
    }

    @Test func theCityStoreKeepsTheHigherVersion() async {
        struct Served: CityPackFetcher {
            let pack: CityPack?
            func fetchPack() async throws -> CityPack? { pack }
        }
        let seed = CityPack(version: 5, cities: [])
        let tallinn = City(id: 1, name: "Tallinn", en: "Tallinn", country: "EE", latitude: 59, longitude: 24, population: 1)
        let older = CityStore(seed: seed, fetcher: Served(pack: CityPack(version: 4, cities: [tallinn])))
        #expect(await older.refresh() == false)
        #expect(older.current.pack.version == 5)
        let newer = CityStore(seed: seed, fetcher: Served(pack: CityPack(version: 6, cities: [tallinn])))
        #expect(await newer.refresh())
        #expect(newer.current.cities(named: "Tallinn").count == 1)
    }
}
