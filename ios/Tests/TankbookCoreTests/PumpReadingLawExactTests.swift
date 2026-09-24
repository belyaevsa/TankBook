import Foundation
import Testing
@testable import TankbookCore

/// The exact close and exact pair agreement (agents/research/PU.78.md): a
/// misread in the last digit never commits as agreement, and a near miss is
/// a difference the form names, never a match.
@Suite("Pump reading law - exact closes")
struct PumpReadingLawExactTests {
    private static func window(_ field: PumpField, _ text: String) -> PumpLocatedWindow {
        PumpReadingLawTests.window(field, text)
    }

    @Test("a total one cent off the product does not close: the check is exact")
    func oneCentMissDoesNotClose() {
        // pump-251's shape: 35.90 x 2.099 = 75.3541, shown 75.35 by the pump; a
        // total read 75.36 is a misread, and a one-cent tolerance admitted it.
        // Exact, it never commits as 75.36 - here the beam's 6 -> 5 runner-up
        // closes the shown 75.35 instead.
        let reading = PumpReadingLaw.resolve(
            windows: [Self.window(.total, "75,36"), Self.window(.liters, "35,90"), Self.window(.unitPrice, "2,099")],
            currency: CurrencyCode(rawValue: "EUR"))
        #expect(reading.total.value != Decimal(string: "75.36"))
        #expect(reading.total.value == Decimal(string: "75.35"))
        let exact = PumpReadingLaw.resolve(
            windows: [Self.window(.total, "75,35"), Self.window(.liters, "35,90"), Self.window(.unitPrice, "2,099")],
            currency: CurrencyCode(rawValue: "EUR"))
        #expect(exact.committedCount == 3)
    }

    @Test("a pair a cent off an exact close against the board is cautioned, not agreed")
    func pairCentOffIsCautioned() {
        // pump-275's shape: 51.71 L, total read 103.31 (the display shows
        // 103.37), board 1.999. 51.71 x 1.999 = 103.368 -> 103.37, so 103.31 is
        // not agreement; the old 0.5 % band passed it as agreement with no
        // caution. It is inside the 5 % discount band, so it commits under the
        // shown-price caution for the user to check.
        let reading = PumpReadingLaw.resolve(
            windows: [Self.window(.total, "103,31"), Self.window(.liters, "51,71"), Self.window(.board, "1,999")],
            currency: CurrencyCode(rawValue: "EUR"), priceBand: FuelPriceBand(low: 0.4, high: 3.0))
        #expect(reading.total.value == Decimal(string: "103.31"))
        if case .shownPriceDiffers? = reading.caution {} else { Issue.record("expected shownPriceDiffers") }
    }

    @Test("a pair near a shown price but not exact is a difference, not agreement")
    func nearMissIsNotAgreement() {
        // 10.00 L for 20.01 implies 2.001 against a 2.000 board: 0.05 % off,
        // which the old 0.5 % agreement band passed as agreement. No confusion
        // repair closes it, so it commits under the shown-price caution.
        let reading = PumpReadingLaw.resolve(
            windows: [Self.window(.total, "20,01"), Self.window(.liters, "10,00"), Self.window(.board, "2,000")],
            currency: CurrencyCode(rawValue: "EUR"), priceBand: FuelPriceBand(low: 0.4, high: 3.0))
        #expect(reading.committedCount == 2)
        if case .shownPriceDiffers? = reading.caution {} else { Issue.record("expected shownPriceDiffers") }
    }
}
