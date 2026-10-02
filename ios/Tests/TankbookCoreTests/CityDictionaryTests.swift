import Foundation
import Testing
@testable import TankbookCore

/// The bundled city dictionary and the receipt city finder (docs/SCHEMA.md ->
/// Places): the suggestion the car's home-city question starts from.
@Suite("City dictionary")
struct CityDictionaryTests {
    private let dictionary = CityDictionary(pack: .bundled)

    private func lines(_ texts: [String]) -> [OCRLine] { texts.map { OCRLine(text: $0) } }

    @Test func theBundledFileDecodesAndIsTheSizeWeShip() throws {
        let url = try #require(Bundle.module.url(forResource: "Cities.seed", withExtension: "json"))
        let bytes = try Data(contentsOf: url).count
        #expect(CityPack.bundled.version > 0)
        #expect(CityPack.bundled.cities.count > 5_000, "the dictionary must not ship empty")
        #expect(bytes < 1_200_000, "the bundled dictionary grew past its cap: \(bytes) bytes")
        #expect(Set(CityPack.bundled.cities.map(\.id)).count == CityPack.bundled.cities.count, "ids are unique")
    }

    @Test(arguments: ["Tallinn", "TALLINN,", "Таллин", "Таллинн", "TALLlNN", "tallinn"])
    func tallinnAnswersToItsSpellings(_ spelling: String) throws {
        let city = try #require(dictionary.cities(named: spelling).first)
        #expect(city.en == "Tallinn" && city.country == "EE")
    }

    @Test func diacriticsAndScriptsMeetOneCity() throws {
        #expect(dictionary.cities(named: "Rīga").first?.country == "LV")
        #expect(dictionary.cities(named: "RIGA").first?.country == "LV")
        #expect(dictionary.cities(named: "Рига").first?.country == "LV")
        #expect(dictionary.cities(named: "Москва").first?.en == "Moscow")
        #expect(dictionary.cities(named: "Moscow").first?.ru == "Москва")
    }

    @Test func aCountryNarrowsAnAmbiguousName() {
        let anywhere = dictionary.cities(named: "Frankfurt")
        #expect(anywhere.count >= 1)
        #expect(dictionary.cities(named: "Tallinn", country: "RU").isEmpty)
    }

    @Test func thePickerSearchesByPrefixHomeCountryFirst() {
        let found = dictionary.search("Tar", country: "EE")
        #expect(found.first?.en == "Tartu")
        let largest = dictionary.search("", country: "EE")
        #expect(largest.first?.en == "Tallinn", "an empty search lists the country's largest cities")
    }

    // MARK: The receipt finder

    /// receipt-111's header as Vision read it: the street is named after a
    /// city (Peterburi = St Petersburg) and the city is Tallinn.
    @Test func aStationAddressGivesItsCity() throws {
        let city = try #require(ReceiptCityFinder.city(in: lines([
            "NESTE", "120 MESTE EXPRESS VESOE", "TALLINN,", "PETERBURI TEE 52", "NESTE FESTI AS",
            "SÖPRUSE PST. 155 TALLINN", "REG.NR. 10167511",
        ]), dictionary: dictionary))
        #expect(city.en == "Tallinn")
    }

    /// receipt-027: `ул. Ленинградская` is a street, the city follows `Г.` at
    /// the end of the line before.
    @Test func aStreetNamedAfterACityIsNotTheCity() throws {
        let city = try #require(ReceiptCityFinder.city(in: lines([
            "АДРЕС МЕСТА РАСЧЕТОВ", "РОССИИСКАЯ ФЕДЕРАЦИЯ,", "Воронежская областы, Г.",
            "Воронеж, ул. Ленинградская,", "29в", "КАССОВЫЙ ЧЕК",
        ]), dictionary: dictionary, countryHints: ["RU"]))
        #expect(city.en == "Voronezh")
    }

    /// receipt-053: a highway named for the cities it joins is no city at all.
    @Test func aHighwayNameIsNotTheCity() {
        let city = ReceiptCityFinder.city(in: lines([
            "бласть, Калининский район. Заволжское с/п.12", "5км+880мСлево>автодороги Москва-Санкт-Пете",
            "РбУрг Место расчетов АЗС Nº12089",
        ]), dictionary: dictionary, countryHints: ["RU"])
        #expect(city == nil, "\(String(describing: city?.en))")
    }

    @Test func aReceiptWithNoCityGivesNil() {
        #expect(ReceiptCityFinder.city(in: lines(["KASSA 1", "TOTAL 51,65", "KOKKU 51,65 EUR"]),
                                       dictionary: dictionary) == nil)
    }
}
