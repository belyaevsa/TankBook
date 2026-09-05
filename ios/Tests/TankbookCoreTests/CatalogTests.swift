import Foundation
import Testing
@testable import TankbookCore

// P1.2 catalog tests: lookup, ranking, pre-fill, the decoupling rule, seed
// pack integrity, and locale -> currency defaulting. All run on macOS with no
// simulator (docs/TESTING.md, L1).

private let testSeedURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/TankbookCore/Catalog/VehicleCatalog.seed.json")

private func makeTestEntries() -> [VehicleCatalogEntry] {
    [
        VehicleCatalogEntry(make: "Volvo", model: "V60", generation: "SPA",
                            years: [2018, nil], powertrain: .ice,
                            fuelKinds: [.petrol95, .diesel], tankCapacityL: 71,
                            batteryCapacityKWh: nil, packVersion: 1),
        VehicleCatalogEntry(make: "Volvo", model: "XC60", generation: "SPA",
                            years: [2017, nil], powertrain: .ice,
                            fuelKinds: [.petrol95, .diesel], tankCapacityL: 71,
                            batteryCapacityKWh: nil, packVersion: 1),
        VehicleCatalogEntry(make: "Toyota", model: "Corolla", generation: "E210",
                            years: [2018, nil], powertrain: .hybrid,
                            fuelKinds: [.petrol95, .electricity], tankCapacityL: 50,
                            batteryCapacityKWh: nil, packVersion: 1),
        VehicleCatalogEntry(make: "Lada", model: "Vesta", generation: "1.6/1.8",
                            years: [2015, nil], powertrain: .ice,
                            fuelKinds: [.petrol95], tankCapacityL: 55,
                            batteryCapacityKWh: nil, packVersion: 1),
        VehicleCatalogEntry(make: "Tesla", model: "Model 3", generation: "2017-",
                            years: [2017, nil], powertrain: .ev,
                            fuelKinds: [.electricity], tankCapacityL: nil,
                            batteryCapacityKWh: 60, packVersion: 1)
    ]
}

// MARK: - Seed pack integrity

@Test func bundledSeedPackParsesAndIsNonEmpty() throws {
    let entries = try VehicleCatalogStore.bundledEntries()
    #expect(entries.count >= 40)
}

@Test func seedEntriesCarryEveryRequiredFieldAndVersion() throws {
    let data = try Data(contentsOf: testSeedURL)
    let seed = try JSONDecoder().decode(VehicleCatalogSeed.self, from: data)
    #expect(seed.packVersion > 0)
    for entry in seed.entries {
        #expect(!entry.make.isEmpty)
        #expect(!entry.model.isEmpty)
        #expect(!entry.generation.isEmpty)
        #expect(entry.years.count == 2)
        #expect((entry.years[0] ?? 0) > 0)
        // The open end is `null`, never a literal 0: a sentinel year would be
        // read by date maths as 1970-ish. A closed end is a real year > 0.
        #expect(entry.years[1] == nil || (entry.years[1] ?? 0) > 0)
        #expect(!entry.fuelKinds.isEmpty)
        #expect(entry.packVersion == seed.packVersion)
    }
}

@Test func noSeedEntryEncodesZeroAsOpenEndSentinel() throws {
    let data = try Data(contentsOf: testSeedURL)
    let seed = try JSONDecoder().decode(VehicleCatalogSeed.self, from: data)
    for entry in seed.entries {
        #expect(!entry.years.compactMap({ $0 }).contains(0))
    }
}

@Test func seedPackContainsVolvoV60WithSeventyOneLiterTank() throws {
    let entries = try VehicleCatalogStore.bundledEntries()
    let v60 = try #require(entries.first { $0.make == "Volvo" && $0.model == "V60" })
    // The SCHEMA.md worked example: typing "Volvo V60" pre-fills 71 L.
    #expect(v60.tankCapacityL == 71)
    #expect(v60.yearsStart == 2018)
}

@Test func decoderAcceptsNullOpenEndAndClosedRange() throws {
    let open = """
        {"packVersion": 1, "entries": [{"make": "Volvo", "model": "V60",
          "generation": "SPA", "years": [2018, null], "powertrain": "ice",
          "fuelKinds": ["petrol95"], "tankCapacityL": 71,
          "batteryCapacityKWh": null, "packVersion": 1}]}
        """
    let openEntry = try #require(try JSONDecoder().decode(VehicleCatalogSeed.self,
                                                          from: Data(open.utf8)).entries.first)
    #expect(openEntry.years.count == 2)
    #expect(openEntry.years[0] == 2018)
    #expect(openEntry.years[1] == nil)
    #expect(openEntry.yearsEnd == nil)
    #expect(openEntry.yearsStart == 2018)

    let closed = """
        {"packVersion": 1, "entries": [{"make": "Volvo", "model": "V60",
          "generation": "SPA", "years": [2011, 2018], "powertrain": "ice",
          "fuelKinds": ["petrol95"], "tankCapacityL": 71,
          "batteryCapacityKWh": null, "packVersion": 1}]}
        """
    let closedEntry = try #require(try JSONDecoder().decode(VehicleCatalogSeed.self,
                                                            from: Data(closed.utf8)).entries.first)
    #expect(closedEntry.years[1] == 2018)
    #expect(closedEntry.yearsEnd == 2018)
}

@Test func bundledSeedEntriesHaveEitherTankOrBattery() throws {
    for entry in try VehicleCatalogStore.bundledEntries() {
        #expect(entry.tankCapacityL != nil || entry.batteryCapacityKWh != nil)
    }
}

// MARK: - Catalog lookup

@Test func exactMatchRanksFirst() {
    let suggester = CatalogSuggester(entries: makeTestEntries())
    let results = suggester.suggestions(for: "Volvo V60")
    #expect(results.first?.entry.title == "Volvo V60")
    #expect(results.first?.score == 100)
}

@Test func prefixMatchFindsMakeAndModel() {
    let suggester = CatalogSuggester(entries: makeTestEntries())
    let byMake = suggester.suggestions(for: "vol")
    #expect(byMake.contains { $0.entry.make == "Volvo" })
    let byModel = suggester.suggestions(for: "v60")
    #expect(byModel.contains { $0.entry.model == "V60" })
}

@Test func lookupIsCaseInsensitive() {
    let suggester = CatalogSuggester(entries: makeTestEntries())
    #expect(suggester.suggestions(for: "VOLVO V60") == suggester.suggestions(for: "volvo v60"))
    #expect(suggester.suggestions(for: "VOLVO V60").first?.entry.model == "V60")
}

@Test func missReturnsEmpty() {
    let suggester = CatalogSuggester(entries: makeTestEntries())
    #expect(suggester.suggestions(for: "xyzabc").isEmpty)
}

@Test func emptyQueryReturnsEmpty() {
    let suggester = CatalogSuggester(entries: makeTestEntries())
    #expect(suggester.suggestions(for: "   ").isEmpty)
}

@Test func suggestersIsolatedFromCatalogMutations() {
    var entries = makeTestEntries()
    let suggester = CatalogSuggester(entries: entries)
    let before = suggester.suggestions(for: "volvo")
    entries.removeAll()
    let after = suggester.suggestions(for: "volvo")
    #expect(before == after)
}

// MARK: - Ranking determinism

@Test func rankingIsDeterministicAndStable() {
    let suggester = CatalogSuggester(entries: makeTestEntries())
    let first = suggester.suggestions(for: "v", limit: 10)
    let second = suggester.suggestions(for: "v", limit: 10)
    #expect(first == second)
    #expect(first.map(\.entry.title) == second.map(\.entry.title))
}

@Test func rankingOrdersExactBeforePrefixBeforeSubstring() {
    let suggester = CatalogSuggester(entries: makeTestEntries())
    let results = suggester.suggestions(for: "Volvo V60", limit: 3)
    let scores = results.map(\.score)
    #expect(scores == scores.sorted(by: >))
}

@Test func limitCapsResultCount() {
    let suggester = CatalogSuggester(entries: makeTestEntries())
    let results = suggester.suggestions(for: "o", limit: 2)
    #expect(results.count <= 2)
}

// MARK: - Pre-fill mapping

@Test func prefillMapsTankAndFuelKinds() {
    let entry = VehicleCatalogEntry(make: "Volvo", model: "V60", generation: "SPA",
                                    years: [2018, 0], powertrain: .ice,
                                    fuelKinds: [.petrol95, .diesel], tankCapacityL: 71,
                                    batteryCapacityKWh: nil, packVersion: 1)
    let prefill = entry.prefill(currentYear: 2026)
    #expect(prefill.tankCapacityL == 71)
    #expect(prefill.fuelKinds == [.petrol95, .diesel])
    #expect(prefill.powertrain == .ice)
    #expect(prefill.make == "Volvo")
    #expect(prefill.model == "V60")
}

@Test func prefillWithoutTankLeavesFieldEmpty() {
    let entry = VehicleCatalogEntry(make: "Tesla", model: "Model 3", generation: "2017-",
                                    years: [2017, 0], powertrain: .ev,
                                    fuelKinds: [.electricity], tankCapacityL: nil,
                                    batteryCapacityKWh: 60, packVersion: 1)
    let prefill = entry.prefill(currentYear: 2026)
    #expect(prefill.tankCapacityL == nil)
    #expect(prefill.batteryCapacityKWh == 60)
    #expect(prefill.fuelKinds == [.electricity])
}

@Test func prefillPicksEndOfRangeYearAndCurrentForPresent() {
    let ended = VehicleCatalogEntry(make: "Volvo", model: "V60", generation: "SPA",
                                    years: [2018, 2021], powertrain: .ice,
                                    fuelKinds: [.petrol95], tankCapacityL: nil,
                                    batteryCapacityKWh: nil, packVersion: 1)
    #expect(ended.prefill(currentYear: 2026).year == 2021)
    let present = VehicleCatalogEntry(make: "Volvo", model: "V60", generation: "SPA",
                                      years: [2018, nil], powertrain: .ice,
                                      fuelKinds: [.petrol95], tankCapacityL: nil,
                                      batteryCapacityKWh: nil, packVersion: 1)
    #expect(present.prefill(currentYear: 2026).year == 2026)
}

// MARK: - Suggestion-list visibility (RV.67)

/// The Add-car suggestion list's mount predicate, pinned as a pure function of
/// the field's text and the applied state (RV.67). The signature is the rule:
/// it takes NO focus argument, so a later change that re-ties the list to
/// first-responder state has to leave this function behind - and the L4
/// scroll-and-tap test catches that at the screen level. Focus is deliberately
/// not an input: gating on focus unmounted the list the instant a scroll
/// dismissed the keyboard, which is the gesture the lower rows of a five-row
/// match need to become reachable.

@Test func suggestionsShowWhileQueryIsBeingTyped() {
    #expect(ModelSuggestionGate.shouldShow(query: "Vol", accepted: nil))
    #expect(ModelSuggestionGate.shouldShow(query: "Volvo V60", accepted: nil))
}

@Test func suggestionsHideWhenFieldIsEmpty() {
    #expect(!ModelSuggestionGate.shouldShow(query: "", accepted: nil))
    #expect(!ModelSuggestionGate.shouldShow(query: "   ", accepted: nil))
    #expect(!ModelSuggestionGate.shouldShow(query: "", accepted: "Volvo · V60 · 2026"))
}

@Test func suggestionsHideWhenQueryIsTheAcceptedText() {
    // Right after apply the field holds exactly what the suggestion wrote;
    // showing the list again would cover the values the user just chose.
    let accepted = "Volvo · V60 · 2026"
    #expect(!ModelSuggestionGate.shouldShow(query: accepted, accepted: accepted))
}

@Test func editingTheAcceptedTextReoffersSuggestions() {
    // Hard rule 13's second half: the applied value stays editable, and editing
    // it turns the field back into a query - the list must re-offer.
    let accepted = "Volvo · V60 · 2026"
    #expect(ModelSuggestionGate.shouldShow(query: "Volvo · V60 CC · 2026", accepted: accepted))
    #expect(ModelSuggestionGate.shouldShow(query: "Volvo V60", accepted: accepted))
}

@Test func clearedFieldThenRetypedQueryShowsAgain() {
    let accepted = "Volvo · V60 · 2026"
    #expect(!ModelSuggestionGate.shouldShow(query: "", accepted: accepted))
    #expect(ModelSuggestionGate.shouldShow(query: "VW", accepted: accepted))
}

/// Pins the ranking RV.67's L4 scroll test depends on: typing "Lada" offers
/// five rows (the Add-car limit) and the LAST one - the row that needs a
/// scroll to reach - is the Vesta with its 55 L tank. If the catalog or the
/// tie-break ever reorders this, the L4 assertion would be silently asserting
/// the wrong car, so the coupling is stated here.
@Test func ladaQueryRanksFiveRowsWithVestaLast() throws {
    let suggester = CatalogSuggester(entries: try VehicleCatalogStore.bundledEntries())
    let results = suggester.suggestions(for: "Lada", limit: 5)
    #expect(results.count == 5)
    #expect(results.allSatisfy { $0.entry.make == "Lada" })
    let last = try #require(results.last)
    #expect(last.entry.model == "Vesta")
    #expect(last.entry.tankCapacityL == 55)
}

// MARK: - Decoupling rule

@Test func savedVehicleCarriesNoCatalogIdOrPackVersion() throws {
    let entry = try VehicleCatalogStore.bundledEntries().first { $0.make == "Volvo" }!
    let prefill = entry.prefill(currentYear: 2026)
    let vehicle = Vehicle(
        id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
        name: "Volvo V60", make: prefill.make, model: prefill.model, year: prefill.year,
        plate: nil, powertrain: prefill.powertrain, fuelKinds: prefill.fuelKinds,
        tankCapacityL: prefill.tankCapacityL, batteryCapacityKWh: prefill.batteryCapacityKWh,
        homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
        photo: nil, archived: false, paceLimitKmPerDay: 1500)
    let data = try JSONEncoder().encode(vehicle)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["catalogId"] == nil)
    #expect(object["packVersion"] == nil)
    #expect(object["tankCapacityL"] as? Double == 71)
}

@Test func vehiclePrefilledFromCatalogRoundTripsThroughRepository() throws {
    let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
    let entry = try VehicleCatalogStore.bundledEntries().first { $0.model == "V60" }!
    let prefill = entry.prefill(currentYear: 2026)
    let vehicle = Vehicle(
        id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
        name: "\(prefill.make) \(prefill.model)", make: prefill.make, model: prefill.model,
        year: prefill.year, plate: nil, powertrain: prefill.powertrain,
        fuelKinds: prefill.fuelKinds, tankCapacityL: prefill.tankCapacityL,
        batteryCapacityKWh: prefill.batteryCapacityKWh, homeCurrency: .rub,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
        photo: nil, archived: false, paceLimitKmPerDay: 1500)
    try repository.upsertVehicle(vehicle)
    let loaded = try #require(try repository.vehicle(id: vehicle.id))
    #expect(loaded.make == "Volvo")
    #expect(loaded.model == "V60")
    #expect(loaded.tankCapacityL == 71)
    #expect(loaded.homeCurrency == .rub)
}

// MARK: - Locale -> currency defaulting

@Test func ruLocaleDefaultsToRuble() {
    #expect(LocaleCurrency.defaultCurrency(for: Locale(identifier: "ru_RU")) == CurrencyCode(rawValue: "RUB")!)
}

@Test func cisLocalesDefaultToTheirCurrencies() {
    #expect(LocaleCurrency.defaultCurrency(for: Locale(identifier: "uk_UA")) == CurrencyCode(rawValue: "UAH")!)
    #expect(LocaleCurrency.defaultCurrency(for: Locale(identifier: "kk_KZ")) == CurrencyCode(rawValue: "KZT")!)
    #expect(LocaleCurrency.defaultCurrency(for: Locale(identifier: "be_BY")) == CurrencyCode(rawValue: "BYN")!)
}

@Test func euLocalesDefaultToTheirCurrencies() {
    #expect(LocaleCurrency.defaultCurrency(for: Locale(identifier: "pl_PL")) == .pln)
    #expect(LocaleCurrency.defaultCurrency(for: Locale(identifier: "cs_CZ")) == .czk)
}

@Test func deLocaleDefaultsToEuro() {
    #expect(LocaleCurrency.defaultCurrency(for: Locale(identifier: "de_DE")) == .eur)
}

@Test func usLocaleDefaultsToDollar() {
    #expect(LocaleCurrency.defaultCurrency(for: Locale(identifier: "en_US")) == .usd)
}
