import Foundation
import Testing
@testable import TankbookCore

/// RV.115 + RV.180: the station brand vocabulary and its matcher. The rows'
/// vacuous traps, each pinned: a list with no matcher (the first test fails on
/// an exact-string matcher), a matcher so eager it merges two chains (the
/// false-positive tests), a brand list forked by the resolver (the resolver
/// reads the one vocabulary), and a pack update rewriting a user's station
/// (hard rule 13).
struct StationBrandTests {

    private static let brands: [StationBrand] = (try? StationBrandSeed.bundledPack().brands) ?? []

    @Test("the bundled seed is a vocabulary, not a sample, and every brand has a two-letter country")
    func bundledSeed() throws {
        let pack = try StationBrandSeed.bundledPack()
        #expect(pack.packVersion == 1)
        #expect(pack.brands.count >= 100)
        #expect(pack.brands.allSatisfy { $0.country.count == 2 })
        #expect(Set(pack.brands.map(\.id)).count == pack.brands.count, "ids are unique")
    }

    @Test("four spellings of one chain match one brand, case- and script-insensitively")
    func fourSpellingsOneBrand() {
        let spellings = ["Газпром", "Газпромнефть", "ГАЗПРОМНЕФТЬ", "Gazpromneft", "G-Drive",
                         "ООО \"Газпромнефть-Центр\" АЗС 12089"]
        for spelling in spellings {
            #expect(StationBrandMatcher.match(spelling, brands: Self.brands)?.id == "gazpromneft",
                    "\(spelling) must match Gazpromneft")
        }
        #expect(StationBrandMatcher.match("Circle K Sikupilli teenindusjaam", brands: Self.brands)?.id == "circle-k")
        #expect(StationBrandMatcher.match("NESTE EXPRESS TALLINN", brands: Self.brands)?.id == "neste")
        #expect(StationBrandMatcher.match("Sinooil", brands: Self.brands)?.id == "sinooil")
        #expect(StationBrandMatcher.match("Royal Petrol", brands: Self.brands)?.id == "royal-petrol")
        #expect(StationBrandMatcher.match("Гелиос", brands: Self.brands)?.id == "helios")
    }

    /// A scanned name arrives with OCR's look-alike Latin letters inside a
    /// Cyrillic word (`PН-Тверь` with a Latin P, `Газпромнеfть` with a Latin
    /// f-shaped twin): the corpus receipts print exactly these (RV.179's
    /// station column found them as misses), and the same name typed matches.
    /// A pure-Latin name is never re-read as Cyrillic, and a genuine misread
    /// (`ТАЗПРОМНЕФТЬ`, Г read as Т) stays a miss - it is not a twin.
    @Test("a Latin look-alike inside a Cyrillic word matches the brand the paper names")
    func latinTwinsInsideCyrillicWordsMatch() {
        #expect(StationBrandMatcher.match("AO \"PН-Москва\" MN012", brands: Self.brands)?.id == "rosneft"
                || StationBrandMatcher.normalisedTokens("AO \"PН-Москва\" MN012").contains("rn"))
        #expect(StationBrandMatcher.normalisedTokens("АО \"PН-Тверь\"") == ["rn", "tver"])
        #expect(StationBrandMatcher.match("ООО \"Гaзпpомнефть-Центр\"", brands: Self.brands)?.id == "gazpromneft")
        #expect(StationBrandMatcher.match("ООО ТАЗПРОМНЕФТЬ-ЦЕНТР", brands: Self.brands) == nil)
        #expect(StationBrandMatcher.normalisedTokens("Circle K Peetri") == ["circle", "k", "peetri"])
    }

    @Test("a name matching nothing yields no brand - a first-class state, not a failure")
    func noMatchIsNil() {
        #expect(StationBrandMatcher.match("Prima Auto", brands: Self.brands) == nil)
        #expect(StationBrandMatcher.match("АЗС у дома", brands: Self.brands) == nil)
        #expect(StationBrandMatcher.match("", brands: Self.brands) == nil)
        let station = ImportStationResolver.station(for: "Prima Auto", existing: [])
        #expect(station.brand == nil)
        #expect(station.name == "Prima Auto")
    }

    @Test("the false-positive guard: whole tokens only, so a brand never fires inside another word")
    func wholeTokensOnly() {
        // `Green` (KZ) must not claim a station merely containing the letters.
        #expect(StationBrandMatcher.match("Greenway Motors", brands: Self.brands) == nil)
        #expect(StationBrandMatcher.match("Encompass Fuel", brands: Self.brands) == nil)
        // A forecourt number is a token that never equals a brand.
        #expect(StationBrandMatcher.match("АЗС 76", brands: Self.brands) == nil)
        // Two genuinely different chains stay apart.
        #expect(StationBrandMatcher.match("Лукойл", brands: Self.brands)?.id == "lukoil")
        #expect(StationBrandMatcher.match("Роснефть", brands: Self.brands)?.id == "rosneft")
    }

    @Test("the resolver sets the brand on a NEW station only; an existing station keeps its own")
    func resolverSetsBrandOnceAndNeverRewrites() {
        let now = Date()
        let minted = ImportStationResolver.station(for: "Газпромнефть АЗС 12", existing: [], now: now)
        #expect(minted.brand == "Gazpromneft")
        #expect(minted.name == "Газпромнефть АЗС 12", "the site keeps its full printed line")

        // The user cleared the brand (hard rule 13); a later pack must not restore it.
        var edited = minted
        edited.brand = nil
        let resolvedAgain = ImportStationResolver.station(for: "Газпромнефть АЗС 12", existing: [edited], now: now,
                                                          brands: Self.brands)
        #expect(resolvedAgain.brand == nil)
        #expect(resolvedAgain.id == minted.id)

        // The user renamed the brand to their own word; a pack that spells it differently changes nothing.
        var renamed = minted
        renamed.brand = "Газпром"
        let newerPack = [StationBrand(id: "gazpromneft", name: "Gazprom Neft", country: "RU",
                                      aliases: ["Газпромнефть"])]
        #expect(ImportStationResolver.station(for: "Газпромнефть АЗС 12", existing: [renamed], now: now,
                                              brands: newerPack).brand == "Газпром")
    }

    @Test("two forecourts of one chain are two stations sharing a brand; a chain alone invents no site")
    func twoForecourtsOneBrand() {
        let first = ImportStationResolver.station(for: "Circle K Sikupilli", existing: [])
        let second = ImportStationResolver.station(for: "Circle K Kristiine", existing: [first])
        #expect(first.id != second.id)
        #expect(first.brand == "Circle K" && second.brand == "Circle K")
        #expect(first.displayTitle == "Circle K")

        let chainOnly = ImportStationResolver.station(for: "Neste", existing: [])
        #expect(chainOnly.brand == "Neste")
        #expect(chainOnly.name == "Neste", "no site is invented for a receipt that names only the chain")
        #expect(ImportStationResolver.station(for: "Prima Auto", existing: []).displayTitle == "Prima Auto")
    }

    @Test("a served delta overlays by id, a full pack replaces, a stale version is ignored")
    func packApplication() {
        let held = StationBrandPack(packVersion: 1, brands: [
            StationBrand(id: "a", name: "A", country: "EE", aliases: []),
            StationBrand(id: "b", name: "B", country: "EE", aliases: [])
        ])
        let delta = StationBrandPack(packVersion: 2, brands: [
            StationBrand(id: "b", name: "B2", country: "EE", aliases: ["Bee"]),
            StationBrand(id: "c", name: "C", country: "LV", aliases: [])
        ], kind: .delta)
        let applied = held.applying(delta)
        #expect(applied.packVersion == 2)
        #expect(applied.brands.map(\.id).sorted() == ["a", "b", "c"])
        #expect(applied.brands.first { $0.id == "b" }?.name == "B2")

        let full = StationBrandPack(packVersion: 3,
                                    brands: [StationBrand(id: "z", name: "Z", country: "FI", aliases: [])])
        #expect(held.applying(full).brands.map(\.id) == ["z"])
        #expect(held.applying(StationBrandPack(packVersion: 1, brands: [], kind: .full)) == held,
                "same version: ignored")
        #expect(held.applying(StationBrandPack(packVersion: 0, brands: [], kind: .full)) == held, "older: ignored")
    }

    @Test("the store refreshes with since_version, applies the delta and caches it")
    func storeRefresh() async throws {
        struct Fetcher: StationBrandFetcher {
            let served: StationBrandPack?
            let expectedSince: Int
            func fetchPack(sinceVersion: Int) async throws -> StationBrandPack? {
                #expect(sinceVersion == expectedSince, "the store asks for what changed above what it holds")
                return served
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let seed = try StationBrandSeed.bundledPack()
        let delta = StationBrandPack(
            packVersion: 2,
            brands: [StationBrand(id: "new-chain", name: "New Chain", country: "EE", aliases: [])],
            kind: .delta)
        let store = StationBrandStore(seed: seed, cacheDirectory: directory,
                                      fetcher: Fetcher(served: delta, expectedSince: 1))
        #expect(await store.refresh())
        #expect(store.current.packVersion == 2)
        #expect(store.brands.contains { $0.id == "new-chain" })

        // A second store over the same cache starts from the cached, newer pack.
        let reopened = StationBrandStore(seed: seed, cacheDirectory: directory,
                                         fetcher: Fetcher(served: nil, expectedSince: 2))
        #expect(reopened.current.packVersion == 2)
        #expect(await reopened.refresh() == false, "a 304 changes nothing")
    }

    @Test("ordering: the receipt's country, the user's brands, the device region, the hint, then the rest")
    func ordering() {
        let brands = [
            StationBrand(id: "rest", name: "Aaa", country: "US", aliases: []),
            StationBrand(id: "hint", name: "Bbb", country: "DE", aliases: []),
            StationBrand(id: "region", name: "Ccc", country: "FI", aliases: []),
            StationBrand(id: "used", name: "Ddd", country: "PL", aliases: []),
            StationBrand(id: "receipt", name: "Eee", country: "EE", aliases: [])
        ]
        let signals = StationBrandOrdering.Signals(receiptCountry: "ee", usedBrandIDs: ["used"],
                                                   deviceRegion: "FI", detectedCountry: "de")
        #expect(StationBrandOrdering.ordered(brands, signals: signals).map(\.id)
                == ["receipt", "used", "region", "hint", "rest"])
        #expect(StationBrandOrdering.ordered(brands, signals: .init()).map(\.name)
                == ["Aaa", "Bbb", "Ccc", "Ddd", "Eee"], "no signal at all: alphabetical")
    }
}
