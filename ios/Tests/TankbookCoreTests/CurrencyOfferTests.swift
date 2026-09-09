import Foundation
import Testing
@testable import TankbookCore

// RV.146: the currency chips adapt to where the user is. Ordering happens on
// the device, by the documented precedence (docs/SCHEMA.md -> Currency offer):
// the car's home currency, then the user's own history (most recent first),
// then the device region's neighbours, then a future detectedCountry hint,
// then the stable default. These tests pin the ORDER (never mere membership),
// the region table's rows, the unknown-region degradation, and that a currency
// a user picked is never reordered away by a later locale change or curation
// (hard rule 13). All pure functions - no network (hard rule 1).

private func cc(_ string: String) -> CurrencyCode { CurrencyCode(rawValue: string)! }
private let day: TimeInterval = 86_400

// MARK: - The builder

@Suite struct CurrencyOfferBuilderTests {
    @Test func homeCurrencyIsAlwaysFirstForEveryRegionAndHistory() {
        let homes: [CurrencyCode] = [.eur, .usd, .rub, .pln, .chf, cc("AED")]
        let regions: [String?] = ["RU", "KZ", "DE", "CH", "US", "ZZ", nil]
        let histories: [[CurrencyCode]] = [[], [.pln], [.czk, .pln], [.usd, .jpy], [.eur, .chf]]
        for home in homes {
            for region in regions {
                for history in histories {
                    let offer = CurrencyOfferBuilder.offer(homeCurrency: home,
                                                           history: history,
                                                           region: region)
                    #expect(offer.first == home,
                            "home \(home.rawValue) must lead the offer for region \(region ?? "nil")")
                    // Deduplicated: a currency appears once, at its highest tier.
                    #expect(Set(offer).count == offer.count)
                    // Never an empty row: the stable default always follows.
                    #expect(offer.count >= 4)
                }
            }
        }
    }

    @Test func historyRanksAheadOfTheRegionsCurrenciesInOrder() {
        let offer = CurrencyOfferBuilder.offer(homeCurrency: .usd,
                                               history: [.czk, .pln],
                                               region: "DE")
        #expect(Array(offer.prefix(4)) == [.usd, .czk, .pln, .eur],
                "home, then the user's most-recent currencies, then the region's - got \(offer.prefix(6))")
        #expect(offer.firstIndex(of: .czk)! < offer.firstIndex(of: .eur)!)
        #expect(offer.firstIndex(of: .pln)! < offer.firstIndex(of: .eur)!)
    }

    @Test func regionRowRanksAheadOfTheStableDefault() {
        // A US user in Kazakhstan gets KZT/RUB/KGS/UZS before any default.
        let offer = CurrencyOfferBuilder.offer(homeCurrency: .usd, region: "KZ")
        #expect(Array(offer.prefix(6)) == [.usd, .kzt, .rub, .kgs, .uzs, .eur],
                "region neighbours must precede the stable default - got \(offer.prefix(6))")
    }

    @Test func hintCountryAddsItsRowWithoutReshaping() {
        // The detectedCountry slot (docs/API.md) is inert today but defined:
        // when a server hint arrives it feeds the same table lookup, after the
        // device region and before the stable default.
        let offer = CurrencyOfferBuilder.offer(homeCurrency: .usd,
                                               region: "US",
                                               hint: "CH")
        #expect(offer.first == .usd)
        #expect(offer.firstIndex(of: .chf)! < offer.firstIndex(of: .gbp)!,
                "the hint's country must land after region, before defaults")
    }
}

// MARK: - The region table

@Suite struct CurrencyRegionCatalogTests {
    private let catalog = CurrencyRegionCatalog.bundled

    @Test func ruMapsToRubKztByn() {
        #expect(catalog.neighbours(for: "RU") == [.rub, .kzt, .byn])
    }

    @Test func kzMapsToKztRubKgsUzs() {
        #expect(catalog.neighbours(for: "KZ") == [.kzt, .rub, .kgs, .uzs])
    }

    @Test func eurozoneCountryMapsToEurPlnCzk() {
        for country in ["DE", "FR", "ES", "NL", "IE"] {
            #expect(catalog.neighbours(for: country) == CurrencyRegionCatalog.eurozoneDefault)
        }
    }

    @Test func unknownRegionDegradesToHomePlusStableDefault() {
        #expect(catalog.neighbours(for: "ZZ") == [])
        let offer = CurrencyOfferBuilder.offer(homeCurrency: .usd, region: "ZZ")
        #expect(offer == [.usd, .eur, .gbp, .pln, .rub, .uah, .kzt, .byn, .czk, .chf, .jpy],
                "an unknown region must not empty the row - got \(offer)")
    }

    @Test func regionLookupIsCaseInsensitive() {
        #expect(catalog.neighbours(for: "ru") == [.rub, .kzt, .byn])
        #expect(catalog.neighbours(for: nil) == [])
    }
}

// MARK: - Hard rule 13: a user's pick is never reordered away

@Suite struct CurrencyOfferRule13Tests {
    @Test func localeChangeDoesNotReorderAUsedCurrency() {
        // The user has paid in CHF before; wherever the device is now, CHF stays
        // exactly one slot behind the home currency - history outranks region.
        for region in ["RU", "KZ", "DE", "CH", "ZZ", nil] {
            let offer = CurrencyOfferBuilder.offer(homeCurrency: .usd,
                                                   history: [.chf],
                                                   region: region)
            #expect(offer.first == .usd)
            #expect(offer.dropFirst().first == .chf,
                    "a used currency must hold its history slot whatever the region - got \(offer.prefix(4))")
        }
    }

    @Test func laterCurationCannotReorderOverAUsedCurrency() {
        // A corrected neighbours table (the future remote-config seam) only
        // replaces a region's row; a currency the user picked sits in history,
        // which outranks every row. The override must not move it.
        let curated = CurrencyRegionCatalog.bundled.applying([
            "RU": [.rub, .byn, .kzt, .jpy],
            "US": [.usd, .gbp]
        ])
        let offer = CurrencyOfferBuilder.offer(homeCurrency: .usd,
                                               history: [.chf],
                                               region: "RU",
                                               catalog: curated)
        #expect(offer.dropFirst().first == .chf,
                "curation must never reorder over a currency the user picked - got \(offer.prefix(4))")
        #expect(offer.contains(.jpy))
    }
}

// MARK: - The CHF gap (every chip reachable from "More…")

@Suite struct CurrencyOfferReachabilityTests {
    @Test func everyClassicChipStaysReachableFromTheCompleteList() {
        // The row that once hardcoded EUR/PLN/CZK/CHF: with no history and an
        // unknown region every one of those four must still be offered - CHF in
        // particular, which used to be a chip with no menu entry to return to.
        let offer = CurrencyOfferBuilder.offer(homeCurrency: .eur, region: "ZZ")
        for code in [.eur, .pln, .czk, CurrencyCode.chf] {
            #expect(offer.contains(code), "\(code.rawValue) must stay reachable")
        }
        // The menu is the complete offer and the chips are its prefix, so no
        // chip can ever be unreachable from "More…".
        for count in 0...offer.count {
            let chips = Array(offer.prefix(count))
            #expect(chips.allSatisfy { offer.contains($0) })
        }
    }
}

// MARK: - The history derivation and the local-only data path (hard rule 1)

@Suite struct CurrencyHistoryTests {
    @Test func recentCurrenciesDeriveFromEntryMoneyPairsMostRecentFirst() {
        let vehicleID = UUID.v7()
        let base = Date(timeIntervalSince1970: 1_752_000_000)
        func fill(_ date: Date, _ currency: CurrencyCode) -> FillUp {
            FillUp(
                id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
                vehicleId: vehicleID, date: date, odometer: 82_400,
                money: Money(amount: 71.02, currency: currency, homeCurrency: .usd),
                note: nil, attachments: [], provenance: .manual, conflict: .none,
                purchaseGroupId: nil, volumeL: 42.3, unitPrice: 1.679,
                fuelKind: .petrol95, fuelGrade: nil, isFull: true,
                tankLevelAfterPct: 100, stationId: nil,
                crossCheck: .notApplicable, extraction: nil)
        }
        let charge = ChargeSession(
            id: UUID.v7(), createdAt: base, updatedAt: base, deletedAt: nil,
            vehicleId: vehicleID, date: base, odometer: 18_000, money: nil,
            note: "free", attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, energyKWh: 43.2, unitPrice: nil,
            chargeType: .dcPublic, provider: nil, tariffId: nil,
            durationMin: 42, socStartPct: 18, socEndPct: 92,
            extraction: nil)
        let entries: [any Entry] = [
            fill(base.addingTimeInterval(-3 * day), .chf),   // three days ago
            fill(base.addingTimeInterval(-1 * day), .pln),   // yesterday - most recent
            fill(base.addingTimeInterval(-6 * day), .chf),   // older, same currency
            charge                                          // no money pair: ignored
        ]
        #expect(CurrencyHistory.recentCurrencies(in: entries) == [.pln, .chf])
    }

    @Test func offerIsBuiltFromLocalDataOnly() throws {
        // The full path the screen takes: read the car and its entries from the
        // LOCAL database, derive the history, build the offer. There is no
        // transport, no fetch, no async - the input set is entirely on-device
        // (hard rule 1). An in-memory database stands in for the on-disk one;
        // both are local and neither touches a network.
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        let vehicleID = UUID.v7()
        let vehicle = Vehicle(
            id: vehicleID, createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            name: "Volvo", powertrain: .ice, fuelKinds: [.petrol95],
            homeCurrency: .usd,
            units: Vehicle.Units(distance: .km, volume: .l,
                                 consumption: .lPer100, energy: .kWhPer100))
        try repository.upsertVehicle(vehicle)
        let base = Date()
        try repository.upsertFillUp(FillUp(
            id: UUID.v7(), createdAt: base, updatedAt: base, deletedAt: nil,
            vehicleId: vehicleID, date: base.addingTimeInterval(-2 * day),
            odometer: 1, money: Money(amount: 100, currency: .pln, homeCurrency: .usd),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 30, unitPrice: 3.3,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true,
            tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .notApplicable, extraction: nil))
        let entries = try repository.liveEntries(forVehicle: vehicleID)
        let offer = CurrencyOfferBuilder.offer(
            homeCurrency: vehicle.homeCurrency,
            history: CurrencyHistory.recentCurrencies(in: entries),
            region: "KZ")
        #expect(Array(offer.prefix(3)) == [.usd, .pln, .kzt],
                "history ahead of the region's own row - got \(offer.prefix(4))")
    }
}
