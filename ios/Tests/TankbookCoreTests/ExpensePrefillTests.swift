import Foundation
import Testing
@testable import TankbookCore

/// RV.62: the Expense-mode capture pre-fill. The extraction -> prefill mapping
/// is the L1 boundary that keeps the fill-up recognition (liters, unit price,
/// fuel kind) from ever reaching an expense form. The three assertions the
/// defect calls for: the expense prefill carries total/currency/date; the fuel
/// fields never leak across - asserted explicitly, so a later "just pipe the
/// fill-up prefill over" cannot pass silently; and an extraction that resolves
/// nothing yields an empty prefill (the form then opens empty, never an error -
/// hard rule 7).
@Suite struct ExpensePrefillTests {

    private func extraction(total: Decimal? = nil, currency: CurrencyCode? = nil,
                            date: String? = nil, liters: Double? = nil,
                            unitPrice: Decimal? = nil, fuelKind: FuelKind? = nil) -> FuelExtraction {
        FuelExtraction(liters: liters, unitPrice: unitPrice, total: total,
                       currency: currency, fuelKind: fuelKind, date: date)
    }

    @Test func expensePrefillCarriesTotalCurrencyAndDate() {
        let prefill = ExpensePrefillBuilder.prefill(from: extraction(
            total: Decimal(string: "12.40"),
            currency: .eur,
            date: "09.08.2026"))
        #expect(prefill.total == Decimal(string: "12.40"))
        #expect(prefill.currency == .eur)
        #expect(prefill.date == ConfirmDate.parse("09.08.2026"))
    }

    @Test func fuelFieldsNeverLeakIntoTheExpensePrefill() {
        // The fill-up recogniser's own output on a fuel receipt: liters, unit
        // price and fuel kind all present, nothing the expense form could use.
        // The expense prefill must come out empty - the fuel fields have no
        // path into it, and none of them may stand in for a total.
        let prefill = ExpensePrefillBuilder.prefill(from: extraction(
            liters: 42.30, unitPrice: Decimal(string: "1.679"),
            fuelKind: .petrol95))
        #expect(prefill.total == nil)
        #expect(prefill.currency == nil)
        #expect(prefill.date == nil)
    }

    @Test func anExtractionThatResolvesNothingYieldsAnEmptyPrefill() {
        let prefill = ExpensePrefillBuilder.prefill(from: FuelExtraction())
        #expect(prefill == ExpensePrefill())
    }

    @Test func anUnparsableExtractionDateStaysNil() {
        let prefill = ExpensePrefillBuilder.prefill(from: extraction(
            total: Decimal(string: "12.40"), date: "not-a-date"))
        #expect(prefill.total == Decimal(string: "12.40"))
        #expect(prefill.date == nil,
                "a date the extractor would not emit must not be forced into the form")
    }

    @Test func currencyIsCarriedEvenWhenItIsNotTheHomeCurrency() {
        // The expense form's honesty gate is the app's to apply; the mapping
        // must not pre-decide by guessing the vehicle. A foreign total is
        // carried with its currency so the form can choose.
        let prefill = ExpensePrefillBuilder.prefill(from: extraction(
            total: Decimal(string: "289.50"), currency: .pln))
        #expect(prefill.total == Decimal(string: "289.50"))
        #expect(prefill.currency == .pln)
    }
}
