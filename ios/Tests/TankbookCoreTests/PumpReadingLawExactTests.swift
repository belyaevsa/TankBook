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

    @Test("a currency with no measured conventions abstains instead of guessing placements")
    func unmeasuredCurrencyAbstains() {
        let reading = PumpReadingLaw.resolve(
            windows: [Self.window(.total, "20,00"), Self.window(.liters, "10,00"), Self.window(.unitPrice, "2,000")],
            currency: CurrencyCode(rawValue: "USD"))
        #expect(reading.committedCount == 0)
        #expect(reading.reason == .currencyUnmeasured)
    }

    @Test("GBP reads its measured placements, so a tenfold shrink no longer closes beside the truth")
    func gbpTenfoldShrinkDoesNotClose() {
        // pump-137's display: 52.30 L at 182.8 p (1.828 GBP), total 95.60, and
        // no decimal mark seen (as on the real still, whose marks sit in the
        // wrong cells). The old default placements also closed 5.230 x 18.28;
        // GBP's measured row keeps only the true triple.
        let reading = PumpReadingLaw.resolve(
            windows: [Self.window(.total, "9560"), Self.window(.liters, "5230"), Self.window(.unitPrice, "1828")],
            currency: CurrencyCode(rawValue: "GBP"))
        #expect(reading.liters.value == Decimal(string: "52.3"))
        #expect(reading.unitPrice.value == Decimal(string: "1.828"))
        #expect(reading.total.value == Decimal(string: "95.6"))
    }

    @Test("a window with a cell count its currency never shows is refused")
    func impossibleCellCountIsRefused() {
        // An EUR price is four cells (or an idle two); three is a mis-slice.
        let reading = PumpReadingLaw.resolve(
            windows: [Self.window(.total, "20,00"), Self.window(.liters, "10,00"), Self.window(.unitPrice, "200")],
            currency: CurrencyCode(rawValue: "EUR"))
        #expect(reading.committedCount == 0)
        #expect(reading.reason == .cellCountImpossible)
    }


    @Test("KZT reads a whole-tenge total and a whole or one-decimal price")
    func kztZeroDecimalTotal() {
        // 40.00 L x 244 = 9760 tenge, printed without decimals (pump-006's shape).
        // With no marks the digits also read 24.4 x 40.00 = 976,0 truncated; the
        // tenge price band the app passes (50-1000) is what rules that out.
        let reading = PumpReadingLaw.resolve(
            windows: [Self.window(.total, "9760"), Self.window(.liters, "40,00"), Self.window(.unitPrice, "244")],
            currency: CurrencyCode(rawValue: "KZT"), priceBand: FuelPriceBand(low: 50, high: 1000))
        #expect(reading.total.value == Decimal(string: "9760"))
        #expect(reading.unitPrice.value == Decimal(string: "244"))
    }

    @Test("RUB reads a one-decimal price and a one-decimal total when the product reproduces it")
    func rubOneDecimalPriceAndTotal() {
        // 50.00 L x 68.3 = 3415.00, shown 3415,0: the product reproduces the
        // display exactly, so the total is read.
        let reading = PumpReadingLaw.resolve(
            windows: [Self.window(.total, "3415,0"), Self.window(.liters, "50,00"), Self.window(.unitPrice, "68,3")],
            currency: CurrencyCode(rawValue: "RUB"))
        #expect(reading.unitPrice.value == Decimal(string: "68.3"))
        #expect(reading.liters.value == Decimal(string: "50"))
        #expect(reading.total.value == Decimal(string: "3415"))
        #expect(reading.total.provenance == .read)
    }

    @Test("a one-decimal total the product only truncates to commits as derived")
    func truncatedTotalStaysDerived() {
        // 36.60 L x 68.3 = 2499.78, shown 2499,8. The display cannot say whether
        // the charge was 2499.8 or 2499.78 (the corpus holds both kinds), so the
        // total is the product, marked derived - never the display read as fact.
        let reading = PumpReadingLaw.resolve(
            windows: [Self.window(.total, "2499,8"), Self.window(.liters, "36,60"), Self.window(.unitPrice, "68,3")],
            currency: CurrencyCode(rawValue: "RUB"))
        #expect(reading.unitPrice.value == Decimal(string: "68.3"))
        #expect(reading.liters.value == Decimal(string: "36.6"))
        #expect(reading.total.value == Decimal(string: "2499.78"))
        #expect(reading.total.provenance == .derived)
    }

    @Test("the pair tier refuses a window with a cell count its currency never shows")
    func pairTierAuditsCellCounts() {
        // No price window; the EUR litres row has 2 cells - never an EUR count.
        let reading = PumpReadingLaw.resolve(
            windows: [Self.window(.total, "20,00"), Self.window(.liters, "10"), Self.window(.board, "2,000")],
            currency: CurrencyCode(rawValue: "EUR"), priceBand: FuelPriceBand(low: 0.4, high: 3.0))
        #expect(reading.committedCount == 0)
        #expect(reading.reason == .cellCountImpossible)
    }

}
