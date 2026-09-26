import Foundation
import Testing
@testable import TankbookCore

/// The currency the pump reader is given: the car's, then the phone region's
/// (`PumpReaderCurrency`). A phone set to Russia at an Estonian pump is the
/// case that found it - the reader refused every euro display.
@Suite("Pump reader currency")
struct PumpReaderCurrencyTests {
    private static let russia = Locale(identifier: "ru_RU")
    private static let eur = CurrencyCode(rawValue: "EUR")!

    @Test("the car's home currency wins over the phone's region")
    func homeCurrencyWins() {
        #expect(PumpReaderCurrency.choose(homeCurrency: Self.eur, region: Self.russia) == Self.eur)
    }

    @Test("with no car, the phone's region decides")
    func regionIsTheFallback() {
        #expect(PumpReaderCurrency.choose(homeCurrency: nil, region: Self.russia)?.rawValue == "RUB")
    }

    /// The Capture Lab's Run 4 photo (a Circle K Gilbarco, 110.97 / 54.69 at
    /// 2.029), its annotated windows resolved under the currency the capture
    /// path chooses for a phone in Russia: with a euro car it commits all
    /// three; with no car, under the region, it refuses - which is what the
    /// phone did. The law alone, over the strings the display shows: the
    /// currency enters nowhere else, and no model runs here.
    @Test("a euro pump reads on a Russian-region phone when the car is in euros",
          .pumpFixturesPresent)
    func euroPumpReadsUnderTheCarsCurrency() throws {
        let name = "pump-342-gilbarco-circlek-11097-5469l-2029-night-high1080-ee.jpg"
        let root = try JSONSerialization.jsonObject(
            with: Data(contentsOf: PumpReaderTestSupport.windowsURL)) as? [String: Any] ?? [:]
        let entry = try #require(root[name] as? [String: Any])
        let windows = (entry["windows"] as? [[String: Any]] ?? []).compactMap { raw -> PumpLocatedWindow? in
            guard let field = (raw["field"] as? String).flatMap(PumpField.init(rawValue:)),
                  let text = raw["text"] as? String, !text.isEmpty else { return nil }
            return PumpLocatedWindow(field: field, cells: PumpReadingLawTests.cells(for: text))
        }
        #expect(windows.count == 3)
        let pack = try FuelPriceBandStore.bundledPack()
        func read(home: CurrencyCode?) -> PumpDisplayReading {
            let currency = PumpReaderCurrency.choose(homeCurrency: home, region: Self.russia)
            return PumpReadingLaw.resolve(windows: windows, currency: currency,
                                          priceBand: currency.flatMap { pack.currencyBand(currency: $0) })
        }
        let withCar = read(home: Self.eur)
        #expect(withCar.total.value == Decimal(string: "110.97"))
        #expect(withCar.unitPrice.value == Decimal(string: "2.029"))
        #expect(withCar.liters.value == Decimal(string: "54.69"))
        #expect(read(home: nil).committedCount == 0)
    }
}
