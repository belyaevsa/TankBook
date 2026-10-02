import Foundation
import Testing
@testable import TankbookCore

/// When the car's home-city question is raised (docs/SCHEMA.md ->
/// Vehicle.homeCity): once, after the car's first scanned receipt, with the
/// receipt's city as the suggestion.
@Suite("Home-city question")
struct HomeCityQuestionTests {
    private let dictionary = CityDictionary(pack: .bundled)
    private let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let neste = ["NESTE", "TALLINN,", "PETERBURI TEE 52"].map { OCRLine(text: $0) }

    private func vehicle(homeCity: HomeCity? = nil) -> Vehicle {
        Vehicle(id: UUID.v7(), createdAt: day, updatedAt: day, name: "Passat", powertrain: .ice,
                fuelKinds: [.diesel], homeCurrency: .eur,
                units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
                homeCity: homeCity)
    }

    @Test func theFirstScannedReceiptRaisesItWithTheReceiptsCity() throws {
        let state = HomeCityQuestion.afterScannedSave(vehicle: vehicle(), current: nil, receiptLines: neste,
                                                      currency: .eur, deviceRegion: nil, dictionary: dictionary)
        let tallinn = try #require(dictionary.cities(named: "Tallinn").first)
        #expect(state == .pending(suggestedCityId: tallinn.id))
    }

    @Test func aReceiptWithoutACityStillAsksWithNoSuggestion() {
        let state = HomeCityQuestion.afterScannedSave(
            vehicle: vehicle(), current: nil, receiptLines: [OCRLine(text: "TOTAL 51,65")],
            currency: .eur, deviceRegion: nil, dictionary: dictionary)
        #expect(state == .pending(suggestedCityId: nil))
    }

    @Test func itIsAskedOnceAndNeverForACarWithACity() {
        for current in [HomeCityQuestion.State.done, .pending(suggestedCityId: nil)] {
            #expect(HomeCityQuestion.afterScannedSave(vehicle: vehicle(), current: current, receiptLines: neste,
                                                      currency: .eur, deviceRegion: nil, dictionary: dictionary) == nil)
        }
        let kept = vehicle(homeCity: HomeCity(name: "Tartu", country: "EE", latitude: 58.38, longitude: 26.72))
        #expect(HomeCityQuestion.afterScannedSave(vehicle: kept, current: nil, receiptLines: neste,
                                                  currency: .eur, deviceRegion: nil, dictionary: dictionary) == nil)
    }

    @Test func theCurrencyNamesTheCountryWhenItHasOne() {
        #expect(HomeCityQuestion.country(for: CurrencyCode(rawValue: "RUB")!) == "RU")
        #expect(HomeCityQuestion.country(for: .eur) == nil, "the euro names no single country")
    }
}
