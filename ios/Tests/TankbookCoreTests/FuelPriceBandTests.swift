import Foundation
import Testing
@testable import TankbookCore

// MARK: - RV.48 the fuel-price band pack + the resolution ladder's steps 3/4

// The bundled seed pack, the pack lookup, the user-history median, and the
// ladder decision table that ties them together (docs/SCHEMA.md -> Fuel price
// bands). The decision-table tests run the REAL extractor over `[String]` line
// arrays (the `extract(textLines:)` overload) - no images, no Vision - and are
// named after the corpus fixtures they pin, because those fixtures are the
// traps: a band that "resolves" receipt-008 or swaps receipt-012 is overfitted,
// not working.

private func bandExtractor() throws -> FuelExtractor {
    let pack = try FuelPriceBandStore.bundledPack()
    return FuelExtractor(bandProvider: DefaultFuelPriceBandProvider(pack: pack))
}

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

/// Runs the extractor over a minimal receipt: a product line (fuel kind), the
/// operand pair, a document-evidence line (currency), and an optional date.
private func resolve(_ pair: String, fuel: String, currency: String,
                     date: String? = nil) throws -> FuelExtraction {
    var lines = [fuel, pair, currency]
    if let date { lines.append(date) }
    return try bandExtractor().extract(textLines: lines)
}

// MARK: - The bundled seed pack

@Suite("Fuel price band: bundled seed pack")
struct FuelPriceBandPackTests {

    @Test("the bundled pack parses and is non-empty")
    func bundledPackParses() throws {
        let pack = try FuelPriceBandStore.bundledPack()
        #expect(!pack.entries.isEmpty)
    }

    @Test("every band has a positive, ordered range")
    func bandsAreOrdered() throws {
        let pack = try FuelPriceBandStore.bundledPack()
        for entry in pack.entries {
            #expect(entry.low > 0)
            #expect(entry.high > entry.low)
        }
    }

    @Test("no duplicate (currency, fuel kind, period) keys")
    func noDuplicateKeys() throws {
        let pack = try FuelPriceBandStore.bundledPack()
        var keys = Set<String>()
        for entry in pack.entries {
            let key = "\(entry.currency.rawValue)|\(entry.fuelKind.rawValue)|\(entry.periodStart)"
            #expect(keys.insert(key).inserted, "duplicate band key \(key)")
        }
    }

    @Test("the pack covers the currencies the corpus exercises")
    func coversCorpusCurrencies() throws {
        let pack = try FuelPriceBandStore.bundledPack()
        for code in ["RUB", "EUR", "KZT"] {
            #expect(pack.entries.contains { $0.currency == CurrencyCode(rawValue: code)! })
        }
    }

    @Test("the era key is load-bearing: 2019 petrol floor sits below 38.28")
    func eraKeySelectsPeriodBand() throws {
        let pack = try FuelPriceBandStore.bundledPack()
        let d2019 = day(2019, 3, 20)
        let d2026 = day(2026, 8, 16)
        // A 2019 receipt gets the pre-2024 petrol band (floor 35, so a 38.28 L
        // volume reads as a plausible price and abstains); a 2026 receipt gets
        // the 40-500 band.
        #expect(pack.band(currency: .rub, fuelKind: .petrol95, date: d2019)?.low == 35)
        #expect(pack.band(currency: .rub, fuelKind: .petrol95, date: d2026)?.low == 40)
    }

    @Test("an unknown fuel kind returns no band, never a petrol fallback")
    func unknownFuelKindAbstains() throws {
        let pack = try FuelPriceBandStore.bundledPack()
        // LPG at 23.99 must never be fed a petrol band - that is the swap the
        // fuel-kind key prevents (receipt-012).
        #expect(pack.band(currency: .rub, fuelKind: .lpg, date: day(2023, 8, 29))?.low == 15)
        // CNG and electricity are not per-litre; e85 is priced below petrol in
        // some markets, so none of the three is given a petrol band.
        #expect(pack.band(currency: .rub, fuelKind: .cng, date: day(2026, 1, 1)) == nil)
        #expect(pack.band(currency: .rub, fuelKind: .e85, date: day(2026, 1, 1)) == nil)
        #expect(pack.band(currency: .rub, fuelKind: .electricity, date: day(2026, 1, 1)) == nil)
    }

    @Test("a date before every period returns no band")
    func tooEarlyDateAbstains() throws {
        let pack = try FuelPriceBandStore.bundledPack()
        #expect(pack.band(currency: .rub, fuelKind: .petrol95, date: day(2000, 1, 1)) == nil)
    }

    @Test("a nil date uses the most recent period")
    func nilDateUsesLatest() throws {
        let pack = try FuelPriceBandStore.bundledPack()
        #expect(pack.band(currency: .rub, fuelKind: .petrol95, date: nil)?.low == 40)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}

// MARK: - The ladder decision table, by fixture

@Suite("Fuel price band: the ladder decision table (by fixture)")
struct FuelPriceBandDecisionTableTests {

    @Test("receipt-012 LPG: the LPG band contains both operands -> nil, never a swap")
    func receipt012LPGAbstains() throws {
        let result = try resolve("52.15 Х 23.99", fuel: "ТРК-19 СУГ, Л", currency: "ЗН ККТ 00106906149101")
        #expect(result.liters == nil)
        #expect(result.unitPrice == nil)
    }

    @Test("receipt-007 the swap fixture: both operands in the petrol band -> nil")
    func receipt007SwapAbstains() throws {
        let result = try resolve("43.61 Х 99.40",
                                 fuel: "Бензин ЭКТО-100 (АИ-100-К5)",
                                 currency: "ЗН ККТ 00106906149101")
        #expect(result.liters == nil)
        #expect(result.unitPrice == nil)
    }

    @Test("receipt-008 the undecidable twin: 48.89 X 48.80 stays nil forever")
    func receipt008TwinAbstains() throws {
        let result = try resolve("48.89 Х 48.80",
                                 fuel: "Аи-95 ЕВРО",
                                 currency: "ЗН ККТ 00106906149101",
                                 date: "08-12.22")
        #expect(result.liters == nil)
        #expect(result.unitPrice == nil)
    }

    @Test("receipt-025 2019 petrol: 43.38 X 38.28 both plausible -> nil (history territory)")
    func receipt025BothPlausibleAbstains() throws {
        let result = try resolve("43.38 Х 38.28",
                                 fuel: "Бензин АИ-95-К5",
                                 currency: "ЗН ККТ 00106906149101",
                                 date: "20.03.19")
        #expect(result.liters == nil)
        #expect(result.unitPrice == nil)
    }

    @Test("receipt-029 2021 petrol100: 43.24 X 58.51 both plausible -> nil")
    func receipt029BothPlausibleAbstains() throws {
        let result = try resolve("43.24 Х 58.51",
                                 fuel: "ЭКТО-100 (АИ-100-К5)",
                                 currency: "ЗН ККТ 00106906149101",
                                 date: "2021-07-08")
        #expect(result.liters == nil)
        #expect(result.unitPrice == nil)
    }

    @Test("receipt-040 2026 petrol95: 71.18 x 57.000 both plausible -> nil")
    func receipt040BothPlausibleAbstains() throws {
        let result = try resolve("71.18 x 57.000",
                                 fuel: "Бензин G-Drive 95(АИ-95-К5)",
                                 currency: "ЗН ККТ 00106906149101")
        #expect(result.liters == nil)
        #expect(result.unitPrice == nil)
    }

    @Test("receipt-041 2026 petrol95: 68.44 X 54.000 both plausible -> nil")
    func receipt041BothPlausibleAbstains() throws {
        let result = try resolve("68.44 X 54.000",
                                 fuel: "Бензин АИ-95-К5",
                                 currency: "ЗН ККТ 00106906149101")
        #expect(result.liters == nil)
        #expect(result.unitPrice == nil)
    }

    @Test("receipt-003 diesel: 259.00*20 resolves to 20 L at 259")
    func receipt003Resolves() throws {
        let result = try resolve("259.00*20", fuel: "ДТ-Л-К5", currency: "ЗН ККТ 00106906149101")
        #expect(result.liters == 20.0)
        #expect(result.unitPrice == decimal("259.00"))
    }

    @Test("receipt-004 petrol95: 205.00*20 resolves to 20 L at 205")
    func receipt004Resolves() throws {
        let result = try resolve("205.00*20", fuel: "Бензин АИ-95-К5", currency: "ЗН ККТ 00106906149101")
        #expect(result.liters == 20.0)
        #expect(result.unitPrice == decimal("205.00"))
    }

    @Test("receipt-005 petrol95: 205.00*20 resolves to 20 L at 205")
    func receipt005Resolves() throws {
        let result = try resolve("205.00*20", fuel: "Бензин АИ-95-К5", currency: "ЗН ККТ 00106906149101")
        #expect(result.liters == 20.0)
        #expect(result.unitPrice == decimal("205.00"))
    }

    @Test("receipt-014 petrol95: 100.00*30 resolves to 30 L at 100")
    func receipt014Resolves() throws {
        let result = try resolve("100.00*30", fuel: "Бензин АИ-95-К5", currency: "ЗН ККТ 00106906149101")
        #expect(result.liters == 30.0)
        #expect(result.unitPrice == decimal("100.00"))
    }

    @Test("receipt-015 petrol95: 269.00*20 resolves to 20 L at 269")
    func receipt015Resolves() throws {
        let result = try resolve("269.00*20", fuel: "Бензин АИ-95-К5", currency: "ЗН ККТ 00106906149101")
        #expect(result.liters == 20.0)
        #expect(result.unitPrice == decimal("269.00"))
    }

    @Test("receipt-024 diesel: 245.00*13.540 resolves to 13.54 L at 245")
    func receipt024Resolves() throws {
        let result = try resolve("245.00*13.540", fuel: "ДТ-Л-К5", currency: "ЗН ККТ 00106906149101")
        #expect(result.liters == 13.540)
        #expect(result.unitPrice == decimal("245.00"))
    }

    @Test("receipt-026 petrol95: 269.00*20 resolves to 20 L at 269")
    func receipt026Resolves() throws {
        let result = try resolve("269.00*20", fuel: "Бензин АИ-95-К5", currency: "ЗН ККТ 00106906149101")
        #expect(result.liters == 20.0)
        #expect(result.unitPrice == decimal("269.00"))
    }

    @Test("receipt-017 diesel 2020: 48.09 X 20 resolves to 20 L at 48.09")
    func receipt017Resolves() throws {
        let result = try resolve("48.09 X 20", fuel: "ДТ-Е-К5 Танеко", currency: "ЗН ККТ 00106906149101",
                                 date: "24.06.20")
        #expect(result.liters == 20.0)
        #expect(result.unitPrice == decimal("48.09"))
    }

    @Test("receipt-028 petrol95 2023: 10 X 62.20 resolves to 10 L at 62.20")
    func receipt028Resolves() throws {
        let result = try resolve("10 Х 62.20", fuel: "Бензин АИ-95-К5", currency: "ЗН ККТ 00106906149101",
                                 date: "17.07.23")
        #expect(result.liters == 10.0)
        #expect(result.unitPrice == decimal("62.20"))
    }

    @Test("receipt-033 KZT petrol92: 24.690 X 243.00 resolves to 24.69 L at 243")
    func receipt033Resolves() throws {
        let result = try resolve("24.690 Х 243.00", fuel: "ТРК 1:АИ-92-К4", currency: "ЖИЫНЫ/ИТОГ")
        #expect(result.liters == 24.690)
        #expect(result.unitPrice == decimal("243.00"))
    }

    @Test("receipt-035 petrol95: 70.44 X 39.000 resolves to 39 L at 70.44")
    func receipt035Resolves() throws {
        let result = try resolve("70.44 X 39.000",
                                 fuel: "Бензин G-Drive 95(АИ-95-К5)",
                                 currency: "ЗН ККТ 00106906149101")
        #expect(result.liters == 39.0)
        #expect(result.unitPrice == decimal("70.44"))
    }

    @Test("receipt-025 mixed service: the service pair is not the fill-up -> nil")
    func receipt025MixedServiceAbstains() throws {
        // receipt-025 prints a service item (`69.28 X 1`) BEFORE the unmarked
        // fuel line (`43.38 Х 38.28`). The band must not resolve the FIRST pair
        // (the service) as the fill-up - with two unmarked pairs the parser
        // cannot know which is fuel, so it abstains (hard rule 13).
        let lines = ["Услуга по регистрации покупки", "69.28 X 1",
                     "ТРК-2 АИ-95-К5", "43.38 Х 38.28",
                     "ЗН ККТ 1713237", "20.03.19"]
        let result = try bandExtractor().extract(textLines: lines)
        #expect(result.liters == nil)
        #expect(result.unitPrice == nil)
    }

    @Test("receipt-032: an undetected fuel kind abstains, never a petrol guess")
    func receipt032NilFuelKindAbstains() throws {
        // "AM-95-K5" is the OCR of "АИ-95-К5" the normaliser does not map, so
        // fuelKind is nil. The band must abstain - a petrol band applied to an
        // unknown kind is exactly the swap receipt-012 proves the key prevents.
        let result = try resolve("73.15*20", fuel: "AM-95-K5 PuLsar-95", currency: "ЗН ККТ 00106906149101")
        #expect(result.liters == nil)
        #expect(result.unitPrice == nil)
    }

    @Test("receipt-043 width-dependent: 40 X 120.00 abstains (fuel kind undetected)")
    func receipt043Abstains() throws {
        // "ДИ-95" is the OCR of "АИ-95" the normaliser does not map. With no
        // fuel kind no band applies, so the pair abstains - the "soft" side of
        // the width trade-off. Even with a petrol band, 40 sits ON the 40 floor
        // and both operands land in band, so nil is the answer either way.
        let result = try resolve("40 Х 120.00", fuel: "ДИ-95 (1 ТРК)", currency: "ЗН ККТ 00106906149101")
        #expect(result.liters == nil)
        #expect(result.unitPrice == nil)
    }

    @Test("no provider means the pair is still undecided, not guessed")
    func noProviderStillAbstains() {
        let result = FuelExtractor().extract(textLines: ["Бензин АИ-95-К5", "205.00*20"])
        #expect(result.liters == nil)
        #expect(result.unitPrice == nil)
    }
}

// MARK: - Step 3: the user's price history

@Suite("Fuel price history (ladder step 3)")
struct FuelPriceHistoryTests {

    @Test("the median of an odd number of recent fill-ups")
    func medianOddCount() {
        let history = FillUpHistory(fillUps: [
            fill(price: "70.00", daysAgo: 0), fill(price: "68.00", daysAgo: 3),
            fill(price: "71.00", daysAgo: 6)
        ])
        #expect(history.historicalPrice(currency: .eur, fuelKind: .petrol95) == 70.0)
    }

    @Test("the median of an even number averages the middle two")
    func medianEvenCount() {
        let history = FillUpHistory(fillUps: [
            fill(price: "70.00", daysAgo: 0), fill(price: "68.00", daysAgo: 3),
            fill(price: "71.00", daysAgo: 6), fill(price: "69.00", daysAgo: 9)
        ])
        // sorted: 68, 69, 70, 71 -> median (69 + 70) / 2
        #expect(history.historicalPrice(currency: .eur, fuelKind: .petrol95) == 69.5)
    }

    @Test("only the most recent ten fill-ups feed the median")
    func windowIsTen() {
        // 12 fill-ups, the two oldest (price 999) are outside the window.
        var fills: [FillUp] = []
        for daysAgo in 0..<10 { fills.append(fill(price: "70.00", daysAgo: daysAgo)) }
        fills.append(fill(price: "999.00", daysAgo: 30))
        fills.append(fill(price: "999.00", daysAgo: 31))
        let history = FillUpHistory(fillUps: fills)
        #expect(history.historicalPrice(currency: .eur, fuelKind: .petrol95) == 70.0)
    }

    @Test("one fill-up is not history - a single point abstains")
    func singleSampleAbstains() {
        let history = FillUpHistory(fillUps: [fill(price: "70.00", daysAgo: 0)])
        #expect(history.historicalPrice(currency: .eur, fuelKind: .petrol95) == nil)
    }

    @Test("history is keyed on currency, not fuel kind")
    func keyedOnCurrencyNotFuelKind() {
        // Mixed grades, same currency -> the median over all of them.
        let history = FillUpHistory(fillUps: [
            fill(price: "70.00", daysAgo: 0, fuel: .petrol95),
            fill(price: "99.00", daysAgo: 3, fuel: .petrol100),
            fill(price: "71.00", daysAgo: 6, fuel: .petrol95)
        ])
        #expect(history.historicalPrice(currency: .eur, fuelKind: .petrol95) == 71.0)
        // A different currency has no history.
        #expect(history.historicalPrice(currency: .rub, fuelKind: .petrol95) == nil)
    }

    private func fill(price: String, daysAgo: Int, fuel: FuelKind = .petrol95) -> FillUp {
        let date = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: -daysAgo, to: day0)!
        return FillUp(id: UUID(), createdAt: date, updatedAt: date, deletedAt: nil,
                      vehicleId: UUID(), date: date, odometer: nil,
                      money: Money(amount: decimal(price), currency: .eur, homeCurrency: .eur),
                      note: nil, attachments: [], provenance: .manual, conflict: .none,
                      purchaseGroupId: nil, volumeL: 40,
                      unitPrice: decimal(price), fuelKind: fuel, fuelGrade: nil,
                      isFull: true, tankLevelAfterPct: nil, stationId: nil,
                      crossCheck: .notApplicable, extraction: nil)
    }

    private let day0 = Calendar(identifier: .gregorian)
        .date(from: DateComponents(year: 2026, month: 9, day: 4))!
}
