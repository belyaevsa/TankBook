import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.144 L1 - BOTH edit paths route their money math through the shared
/// `Money.edited` rule (docs/SCHEMA.md -> Money), so an entry whose home
/// currency was stamped before the car's Garage home changed is re-homed to
/// the car's CURRENT home currency when the user edits it. The defect had two
/// copies: the fill-up path (`buildUpdatedFill`) and the non-fill path
/// (`editedMoney`); a test on only one leaves half the defect shipped. Lives in
/// the app-target test bundle because both wrappers are app code; the SwiftPM
/// core tests run on macOS and cannot reach them (the shared rule's own
/// semantics are covered there).
final class RV144EntryEditMoneyTests: XCTestCase {

    private func makeVehicle(homeCurrency: CurrencyCode) -> Vehicle {
        Vehicle(id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
                name: "Volvo V60", make: "Volvo", model: "V60", year: 2015, plate: nil,
                powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: 71,
                batteryCapacityKWh: nil, homeCurrency: homeCurrency,
                units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                     energy: .kWhPer100),
                photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 0)
    }

    /// A fill as the import wrote it while the car's home was still EUR: the
    /// money pair records `homeCurrency: EUR` while the car's Garage home is
    /// now USD. The three numbers cross-check (amount == volume x price), so
    /// the derived save state stays `.verified`.
    private func makeImportedFill(vehicleId: UUID, money: Money,
                                  volumeL: Double, unitPrice: String) -> FillUp {
        FillUp(id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
               vehicleId: vehicleId, date: Date(), odometer: 119_486,
               money: money, note: nil, attachments: [], provenance: .manual,
               conflict: .none, purchaseGroupId: nil,
               volumeL: volumeL, unitPrice: Decimal(string: unitPrice)!,
               fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
               stationId: nil, crossCheck: .verified, extraction: nil)
    }

    private func decimal(_ string: String) -> Decimal {
        Decimal(string: string)!
    }

    /// The fill-up path (the copy the owner actually hit): editing a stored
    /// USD/EUR-homed fill to RUB on a car whose home is now USD must end with
    /// `money.homeCurrency == .usd` - asserting the currency changed is the
    /// vacuous half; the row is about the home currency.
    func testFillPathCurrencyEditReHomesToTheCarsCurrentHomeCurrency() throws {
        let vehicle = makeVehicle(homeCurrency: .usd)
        let imported = Money(amount: decimal("2101.75"), currency: .usd, homeCurrency: .eur)
        let fill = makeImportedFill(vehicleId: vehicle.id, money: imported,
                                    volumeL: 60.05, unitPrice: "35.00")
        XCTAssertEqual(fill.money?.homeCurrency, .eur)

        var form = ManualFillUpFormState()
        form.load(from: fill, vehicle: vehicle)
        form.currency = .rub

        let derived = try XCTUnwrap(form.derived(volumeUnit: .l))
        let updated = form.buildUpdatedFill(from: fill, vehicle: vehicle,
                                            derived: derived,
                                            otherEntries: [], stationID: nil)

        let money = try XCTUnwrap(updated.money)
        XCTAssertEqual(money.homeCurrency, .usd,
                       "the edited fill must home to the car's CURRENT currency, got \(money.homeCurrency.rawValue)")
        XCTAssertEqual(money.currency, .rub)
        XCTAssertTrue(money.isRatePending,
                      "a changed-currency fill edit re-pends: it must not keep the EUR snapshot")
    }

    /// The same shape through the fill path, edited to the car's HOME currency:
    /// the pair is snapshotted at rate 1, resolved before the sheet closes,
    /// needing no rate and no network.
    func testFillPathEditToTheHomeCurrencySnapshotsAtRateOne() throws {
        let vehicle = makeVehicle(homeCurrency: .usd)
        let imported = Money(amount: decimal("2101.75"), currency: .pln, homeCurrency: .eur)
        let fill = makeImportedFill(vehicleId: vehicle.id, money: imported,
                                    volumeL: 60.05, unitPrice: "35.00")

        var form = ManualFillUpFormState()
        form.load(from: fill, vehicle: vehicle)
        form.currency = .usd

        let derived = try XCTUnwrap(form.derived(volumeUnit: .l))
        let updated = form.buildUpdatedFill(from: fill, vehicle: vehicle,
                                            derived: derived,
                                            otherEntries: [], stationID: nil)

        let money = try XCTUnwrap(updated.money)
        XCTAssertEqual(money.homeCurrency, .usd)
        XCTAssertEqual(money.currency, .usd)
        XCTAssertFalse(money.isRatePending, "a same-currency edit resolves at commit")
        XCTAssertEqual(money.homeAmount, money.amount)
        XCTAssertEqual(money.rate, Decimal(1))
    }

    /// Hard rule 3 through the fill path: a save that touches neither amount
    /// nor currency leaves a snapshotted pair byte-identical.
    func testFillPathNoTouchEditLeavesASnapshottedPairByteIdentical() throws {
        let vehicle = makeVehicle(homeCurrency: .usd)
        let original = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
            .converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: Date(), source: .ecb))
        let fill = makeImportedFill(vehicleId: vehicle.id, money: original,
                                    volumeL: 42.30, unitPrice: "6.844")

        var form = ManualFillUpFormState()
        form.load(from: fill, vehicle: vehicle)
        // The form's currency pre-fills from the stored money (PLN) - a no-touch save.

        let derived = try XCTUnwrap(form.derived(volumeUnit: .l))
        let updated = form.buildUpdatedFill(from: fill, vehicle: vehicle,
                                            derived: derived,
                                            otherEntries: [], stationID: nil)

        XCTAssertEqual(updated.money, original,
                       "a no-touch save must leave the snapshotted pair byte-identical (hard rule 3)")
    }

    /// The non-fill path (`editedMoney`): the second copy of the defect. An
    /// expense written with `homeCurrency: EUR`, edited to RUB on a car whose
    /// home is now USD, must re-home to USD.
    func testNonFillPathCurrencyEditReHomesToTheCarsCurrentHomeCurrency() {
        let form = EditEntryNonFillForm(amount: "2101.75", currency: .rub)
        let original = Money(amount: decimal("2101.75"), currency: .usd, homeCurrency: .eur)

        let money = form.editedMoney(original: original, homeCurrency: .usd)

        XCTAssertEqual(money?.homeCurrency, .usd,
                       "a non-fill currency edit must home to the car's CURRENT currency")
        XCTAssertEqual(money?.currency, .rub)
        XCTAssertEqual(money?.isRatePending, true)
    }

    /// The non-fill path, no-touch: an empty amount keeps the stored money
    /// untouched.
    func testNonFillPathEmptyAmountKeepsStoredMoneyUntouched() {
        var empty = EditEntryNonFillForm()
        empty.amount = ""
        let original = Money(amount: decimal("2101.75"), currency: .usd, homeCurrency: .eur)
        XCTAssertEqual(empty.editedMoney(original: original, homeCurrency: .usd), original)
    }
}
