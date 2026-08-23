import Testing
import Foundation
@testable import TankbookCore

private let entryDate = Date(timeIntervalSince1970: 1_752_000_000)

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string)!
}

private func double(_ value: Decimal) -> Double {
    NSDecimalNumber(decimal: value).doubleValue
}

/// The documented conversion example. NOTE: docs/SCHEMA.md quotes "67.80 EUR",
/// but 289.50 / 4.2706 = 67.7890... which rounds to 67.79 (the 67.80 figure is a
/// hand-rounding artifact of using the rate 4.27). The formula
/// `homeAmount = amount / rate` is normative; the worked example is not.
@Test func conversionDirectionIsAmountDividedByRate() {
    let money = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
    let converted = money.converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: entryDate, source: .ecb))

    #expect(converted.homeAmount == decimal("67.79"))
    #expect(converted.rate == decimal("4.2706"))
    #expect(converted.rateDate == entryDate)
    #expect(converted.rateSource == .ecb)
    #expect(converted.hasSnapshot)

    // Direction check: the rate is ORIGINAL per HOME, so rate x homeAmount ~= amount.
    let rederived = converted.homeAmount! * converted.rate!
    #expect(abs(double(converted.amount) - double(rederived)) < 0.02)
}

@Test func rateDateIsTheEntryDateNeverToday() {
    let money = Money(amount: decimal("100"), currency: .usd, homeCurrency: .eur)
    let converted = money.converted(using: RateSnapshot(rate: decimal("1.1"), rateDate: entryDate, source: .manual))

    #expect(converted.rateDate == entryDate)
    #expect(converted.rateDate != Date())
}

@Test func snapshotIsImmutable() {
    let money = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
    let first = money.converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: entryDate, source: .ecb))
    let second = first.converted(using: RateSnapshot(rate: decimal("4.5"), rateDate: entryDate, source: .ecb))

    #expect(second.homeAmount == first.homeAmount)
    #expect(second.rate == decimal("4.2706"))
    #expect(second.rateDate == entryDate)
}

@Test func backfillFillsBlanksOnly() {
    let money = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
    #expect(money.homeAmount == nil)

    let filled = money.converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: entryDate, source: .ecb))
    #expect(filled.homeAmount == decimal("67.79"))

    // A later, different rate never recomputes an existing snapshot.
    let later = filled.converted(using: RateSnapshot(rate: decimal("3.0"), rateDate: entryDate, source: .cis))
    #expect(later.homeAmount == filled.homeAmount)
    #expect(later.rate == decimal("4.2706"))
}

@Test func sameCurrencySnapshotsAtRateOne() {
    let money = Money(amount: decimal("67.80"), currency: .eur, homeCurrency: .eur)

    #expect(money.homeAmount == decimal("67.80"))
    #expect(money.rate == Decimal(1))
    #expect(money.rateSource == .ecb)
    #expect(money.hasSnapshot)

    // Converting a same-currency pair is a no-op.
    let converted = money.converted(using: RateSnapshot(rate: decimal("2"), rateDate: entryDate, source: .manual))
    #expect(converted == money)
}

@Test func editingAmountClearsTheSnapshot() {
    let money = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
    let converted = money.converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: entryDate, source: .ecb))
    #expect(converted.hasSnapshot)

    let edited = converted.replacingAmount(decimal("250.00"))
    #expect(edited.homeAmount == nil)
    #expect(edited.rate == nil)
    #expect(edited.rateDate == nil)
    #expect(edited.isRatePending)
}

@Test func editingCurrencyClearsTheSnapshot() {
    let money = Money(amount: decimal("100.00"), currency: .pln, homeCurrency: .eur)
    let converted = money.converted(using: RateSnapshot(rate: decimal("4.0"), rateDate: entryDate, source: .ecb))

    let edited = converted.replacingCurrency(.czk)
    #expect(edited.currency == .czk)
    #expect(edited.homeAmount == nil)
    #expect(edited.rate == nil)
    #expect(edited.isRatePending)
}

@Test func editingAmountKeepsSameCurrencySnapshotInSync() {
    let money = Money(amount: decimal("100.00"), currency: .eur, homeCurrency: .eur)
    let edited = money.replacingAmount(decimal("120.00"))

    #expect(edited.homeAmount == decimal("120.00"))
    #expect(edited.rate == Decimal(1))
    #expect(edited.hasSnapshot)
}

@Test func conversionRoundsToTheHomeCurrencysMinorUnits() {
    let money = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
    let converted = money.converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: entryDate, source: .ecb))

    #expect(converted.homeAmount != nil)
    #expect(converted.homeAmount!.rounded(decimalPlaces: 2) == converted.homeAmount!)
}
