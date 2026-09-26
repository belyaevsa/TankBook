import Foundation
import Testing
@testable import TankbookCore

/// The pair fallback (PU.97): on a multi-price board, a row taken as the paid
/// price that closes with nothing no longer throws away a right total and
/// volume. The pair commits - price abstained, with the shown-price caution -
/// only when some display price closes it exactly; a misread pair does not.
@Suite("Pump law: the board pair fallback (PU.97)")
struct PumpReadingLawBoardFallbackTests {
    private let eur = CurrencyCode(rawValue: "EUR")
    private let band = FuelPriceBand(low: 0.4, high: 3.0)

    private func window(_ field: PumpField, _ text: String) -> PumpLocatedWindow {
        PumpReadingLawTests.window(field, text)
    }

    @Test("a discounted fill whose price row is another grade commits total and volume with the caution")
    func discountOnAFourPriceBoard() {
        // The owner's Circle K photo, 2026-09-26: 24.77 L for 50.38 pays 2.034 a
        // litre (a miles+ discount) against a 2.019 / 2.069 / 2.079 / 2.179
        // board; one board row taken as the price closes with nothing.
        let reading = PumpReadingLaw.resolve(
            windows: [window(.total, "50,38"), window(.liters, "24,77"), window(.unitPrice, "2,019"),
                      window(.board, "2,069"), window(.board, "2,079"), window(.board, "2,179")],
            currency: eur, priceBand: band)
        #expect(reading.total.value == Decimal(string: "50.38"))
        #expect(reading.liters.value == Decimal(string: "24.77"))
        #expect(reading.unitPrice.value == nil, "the price is never taken from a board that did not close")
        guard case .shownPriceDiffers(let shown, _)? = reading.caution else {
            Issue.record("expected the shown-price caution, got \(String(describing: reading.caution))")
            return
        }
        #expect(shown == Decimal(string: "2.019"), "the nearest shown price is named")
    }

    @Test("a pair no display price can close stays refused - a misread volume is not committed")
    func misreadPairStaysRefused() {
        // pump-055 on the measured runtime: total 108.68 right, volume read
        // 56.09 for 56.05. 56.05 x 1.939 is 108.68; no price makes 56.09 into it.
        let reading = PumpReadingLaw.resolve(
            windows: [window(.total, "108,68"), window(.liters, "56,09"), window(.unitPrice, "1,944")],
            currency: eur, priceBand: band)
        #expect(reading.committedCount == 0)
        #expect(reading.reason == .nothingClosed)

        let right = PumpReadingLaw.resolve(
            windows: [window(.total, "108,68"), window(.liters, "56,05"), window(.unitPrice, "1,944")],
            currency: eur, priceBand: band)
        #expect(right.liters.value == Decimal(string: "56.05"))
        #expect(right.total.value == Decimal(string: "108.68"))
    }

    @Test("the paid price is one the display could show")
    func paidPriceCloses() {
        #expect(PumpReadingLaw.paidPriceCloses(liters: 24.77, total: 50.38, priceDecimals: 3))
        #expect(PumpReadingLaw.paidPriceCloses(liters: 13.70, total: 27.87, priceDecimals: 3), "pump-300 pays 2.034")
        #expect(!PumpReadingLaw.paidPriceCloses(liters: 56.09, total: 108.68, priceDecimals: 3))
    }
}
