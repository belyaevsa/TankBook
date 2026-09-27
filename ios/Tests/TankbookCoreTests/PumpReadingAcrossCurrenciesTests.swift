import Foundation
import Testing
@testable import TankbookCore

/// Currency supports the read and never blocks it (docs/EXTRACTION.md): the
/// law under the capture's currency first, then under every other measured
/// currency, and when nothing closes anywhere the top read goes to the form
/// under the `.unclosed` caution.
@Suite("Pump reading across currencies")
struct PumpReadingAcrossCurrenciesTests {
    private static let eur = CurrencyCode(rawValue: "EUR")!
    private static let rub = CurrencyCode(rawValue: "RUB")!

    private static func windows(liters: String, price: String, total: String) -> [PumpLocatedWindow] {
        [PumpReadingLawTests.window(.liters, liters), PumpReadingLawTests.window(.unitPrice, price),
         PumpReadingLawTests.window(.total, total)]
    }

    @Test("a euro display commits under a rouble car, stamped with the currency it closed under")
    func euroDisplayUnderRoubleCar() {
        // Case 02412-PM1N2's display: 15.33 L at 2.129, 32.64.
        let windows = Self.windows(liters: "0015.33", price: "2.129", total: "0032.64")
        #expect(PumpReadingLaw.resolve(windows: windows, currency: Self.rub).committedCount == 0)
        let reading = PumpReadingLaw.resolveAcrossCurrencies(windows: windows, currency: Self.rub)
        #expect(reading.liters.value == Decimal(string: "15.33"))
        #expect(reading.unitPrice.value == Decimal(string: "2.129"))
        #expect(reading.total.value == Decimal(string: "32.64"))
        #expect(reading.closedUnder == Self.eur)
        #expect(reading.unclosed == nil)
    }

    @Test("a read that closes under the capture's currency is that currency's verdict")
    func ownCurrencyFirst() {
        let windows = Self.windows(liters: "0015.33", price: "2.129", total: "0032.64")
        let reading = PumpReadingLaw.resolveAcrossCurrencies(windows: windows, currency: Self.eur)
        #expect(reading == PumpReadingLaw.resolve(windows: windows, currency: Self.eur).closed(under: Self.eur))
    }

    @Test("no currency at all still reads a display whose arithmetic closes")
    func noCurrency() {
        let windows = Self.windows(liters: "0015.33", price: "2.129", total: "0032.64")
        #expect(PumpReadingLaw.resolveAcrossCurrencies(windows: windows, currency: nil).committedCount == 3)
    }

    @Test("nothing closes: nothing is committed, and the top read goes to the form under the unclosed caution")
    func unclosedTopRead() {
        let windows = Self.windows(liters: "0015.33", price: "2.129", total: "0040.00")
        let reading = PumpReadingLaw.resolveAcrossCurrencies(windows: windows, currency: Self.rub)
        #expect(reading.committedCount == 0)
        #expect(reading.caution == .unclosed)
        #expect(reading.unclosed == PumpUnclosedRead(liters: Decimal(string: "15.33"),
                                                     unitPrice: Decimal(string: "2.129"),
                                                     total: Decimal(string: "40.00")))
    }

    @Test("with no decimal mark seen, the top read takes the currency's placement")
    func unclosedPlacementFromConventions() {
        let windows = Self.windows(liters: "001533", price: "2129", total: "004000")
        let top = PumpReadingLaw.resolveAcrossCurrencies(windows: windows, currency: Self.eur).unclosed
        #expect(top == PumpUnclosedRead(liters: Decimal(string: "15.33"), unitPrice: Decimal(string: "2.129"),
                                        total: Decimal(string: "40.00")))
    }

    @Test("an idle pump hands nothing to the form")
    func idlePumpHasNoTopRead() {
        let windows = Self.windows(liters: "0000.00", price: "2.129", total: "0000.00")
        let reading = PumpReadingLaw.resolveAcrossCurrencies(windows: windows, currency: Self.eur)
        #expect(reading.unclosed == nil)
        #expect(reading.caution == nil)
    }

    /// The Capture Lab's Run 4 photo (110.97 / 54.69 at 2.029), its annotated
    /// windows resolved as a Russian-region phone with no car reads it: the
    /// region gives RUB, RUB refuses, and the read still commits.
    @Test("a euro pump reads on a Russian-region phone with no car", .pumpFixturesPresent)
    func euroPumpUnderTheRegion() throws {
        let name = "pump-342-gilbarco-circlek-11097-5469l-2029-night-high1080-ee.jpg"
        let root = try JSONSerialization.jsonObject(
            with: Data(contentsOf: PumpReaderTestSupport.windowsURL)) as? [String: Any] ?? [:]
        let entry = try #require(root[name] as? [String: Any])
        let windows = (entry["windows"] as? [[String: Any]] ?? []).compactMap { raw -> PumpLocatedWindow? in
            guard let field = (raw["field"] as? String).flatMap(PumpField.init(rawValue:)),
                  let text = raw["text"] as? String, !text.isEmpty else { return nil }
            return PumpLocatedWindow(field: field, cells: PumpReadingLawTests.cells(for: text))
        }
        let currency = PumpReaderCurrency.choose(homeCurrency: nil, region: Locale(identifier: "ru_RU"))
        let pack = try FuelPriceBandStore.bundledPack()
        let reading = PumpReadingLaw.resolveAcrossCurrencies(
            windows: windows, currency: currency, priceBand: currency.flatMap { pack.currencyBand(currency: $0) })
        #expect(reading.total.value == Decimal(string: "110.97"))
        #expect(reading.unitPrice.value == Decimal(string: "2.029"))
        #expect(reading.liters.value == Decimal(string: "54.69"))
    }
}
