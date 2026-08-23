import Testing
import Foundation
@testable import TankbookCore

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string)!
}

private func double(_ value: Decimal) -> Double {
    NSDecimalNumber(decimal: value).doubleValue
}

/// The ConfirmManual third-value derivation (docs/SCHEMA.md -> FillUp, the
/// `unitPrice` paragraph). P1.3 L1 suite: every derivation direction, the
/// `.notApplicable` rule for two-typed values, the cross-check for three, the
/// tolerance boundaries (the `0.02` floor AND the `0.5%` term), the no-drift
/// guarantee for values that do not divide evenly, and litres-at-rest.
@Suite struct ManualFillUpMathTests {

    // MARK: - Two values typed: third derives, crossCheck = .notApplicable

    @Test func totalPlusVolumeDerivesUnitPrice() {
        let derived = ManualFillUpMath.derive(from: .init(total: decimal("71.02"), volumeL: 42.30))

        #expect(derived != nil)
        #expect(derived?.total == decimal("71.02"))
        #expect(derived?.volumeL == 42.30)
        // 71.02 / 42.30 = 1.6789598... stored at full precision, not rounded.
        #expect(derived?.unitPrice == decimal("71.02") / decimal("42.30"))
        #expect(derived?.crossCheck == .notApplicable)
    }

    @Test func totalPlusUnitPriceDerivesVolume() {
        let derived = ManualFillUpMath.derive(from: .init(total: decimal("71.02"), unitPrice: decimal("1.679")))

        #expect(derived != nil)
        #expect(derived?.total == decimal("71.02"))
        #expect(derived?.unitPrice == decimal("1.679"))
        // 71.02 / 1.679 = 42.298... litres.
        #expect(abs((derived?.volumeL ?? 0) - double(decimal("71.02") / decimal("1.679"))) < 0.0001)
        #expect(derived?.crossCheck == .notApplicable)
    }

    @Test func volumePlusUnitPriceDerivesTotal() {
        let derived = ManualFillUpMath.derive(from: .init(volumeL: 42.30, unitPrice: decimal("1.679")))

        #expect(derived != nil)
        #expect(derived?.volumeL == 42.30)
        #expect(derived?.unitPrice == decimal("1.679"))
        #expect(derived?.total == decimal("42.30") * decimal("1.679"))
        #expect(derived?.crossCheck == .notApplicable)
    }

    // MARK: - Three values typed: the cross-check applies

    @Test func allThreeConsistentVerifies() {
        let derived = ManualFillUpMath.derive(
            from: .init(total: decimal("20.00"), volumeL: 10, unitPrice: decimal("2.00")))

        #expect(derived?.total == decimal("20.00"))
        #expect(derived?.volumeL == 10)
        #expect(derived?.unitPrice == decimal("2.00"))
        #expect(derived?.crossCheck == .verified)
    }

    @Test func allThreeInconsistentMismatches() {
        let derived = ManualFillUpMath.derive(
            from: .init(total: decimal("20.00"), volumeL: 10, unitPrice: decimal("2.10")))

        #expect(derived?.crossCheck == .mismatch(field: .total))
        // Values are never rewritten in the three-typed case.
        #expect(derived?.total == decimal("20.00"))
        #expect(derived?.volumeL == 10)
        #expect(derived?.unitPrice == decimal("2.10"))
    }

    // MARK: - Fewer than two: nothing to derive

    @Test func fewerThanTwoValuesDeriveNothing() {
        #expect(ManualFillUpMath.derive(from: .init(total: decimal("71.02"))) == nil)
        #expect(ManualFillUpMath.derive(from: .init(volumeL: 42.30)) == nil)
        #expect(ManualFillUpMath.derive(from: .init()) == nil)
    }

    // MARK: - Tolerance boundaries: max(0.02, amount x 0.005)

    @Test func smallAmountExercisesTheTwoCentFloor() {
        // computed = 0.5 x 2.00 = 1.00; tolerance = max(0.02, 1.00 x 0.005) = 0.02.
        let inside = ManualFillUpMath.derive(
            from: .init(total: decimal("1.02"), volumeL: 0.5, unitPrice: decimal("2.00")))
        #expect(inside?.crossCheck == .verified)   // diff 0.02 == tolerance: just inside

        let outside = ManualFillUpMath.derive(
            from: .init(total: decimal("1.03"), volumeL: 0.5, unitPrice: decimal("2.00")))
        #expect(outside?.crossCheck == .mismatch(field: .total))   // diff 0.03 > 0.02: just outside
    }

    @Test func largeAmountExercisesTheHalfPercentTerm() {
        // computed = 100 x 2.00 = 200.00; tolerance = max(0.02, 200 x 0.005) = 1.001.
        let inside = ManualFillUpMath.derive(
            from: .init(total: decimal("201.001"), volumeL: 100, unitPrice: decimal("2.00")))
        #expect(inside?.crossCheck == .verified)   // diff 1.001 == tolerance: just inside

        let outside = ManualFillUpMath.derive(
            from: .init(total: decimal("201.02"), volumeL: 100, unitPrice: decimal("2.00")))
        #expect(outside?.crossCheck == .mismatch(field: .total))   // diff 1.02 > 1.001: just outside
    }

    // MARK: - No drift: an uneven division does not disturb the stored pair

    @Test func unevenDivisionDoesNotDriftTheStoredPair() {
        let derived = ManualFillUpMath.derive(from: .init(total: decimal("71.02"), volumeL: 42.30))!

        // The derived unitPrice is stored at full precision (1.6789598...),
        // never the display-rounded 1.679, so multiplying back re-rounds to the
        // typed total - the stored pair is self-consistent.
        let reTotal = derived.unitPrice * Decimal(derived.volumeL)
        #expect(reTotal.rounded(decimalPlaces: 2) == decimal("71.02"))

        // Re-deriving from the stored pair reproduces the stored unitPrice.
        let reDerived = ManualFillUpMath.derive(from: .init(total: derived.total, volumeL: derived.volumeL))
        #expect(reDerived?.unitPrice == derived.unitPrice)
    }

    // MARK: - Volume is always stored in litres

    @Test func litresPerUnitConversions() {
        #expect(ManualFillUpMath.litresPerUnit(.l) == 1.0)
        #expect(ManualFillUpMath.litresPerUnit(.galUS) == 3.785411784)
        #expect(ManualFillUpMath.litresPerUnit(.galUK) == 4.54609)
    }

    @Test func volumeStoredInLitresWhenVehicleDisplaysGallons() {
        // User types 10 gal; the stored volume must be litres.
        let stored = ManualFillUpMath.volumeL(from: 10, unit: .galUS)
        #expect(abs(stored - 37.85411784) < 0.000001)

        // Display path: litres back into the display unit round-trips.
        let back = ManualFillUpMath.displayVolume(from: stored, unit: .galUS)
        #expect(abs(back - 10) < 0.000001)
    }

    @Test func derivedVolumeIsLitresForAGallonVehicle() {
        // total 71.02 @ 1.679 -> 42.298... L, stored in litres regardless of
        // how the vehicle displays volume; the user sees it in gallons.
        let derived = ManualFillUpMath.derive(from: .init(total: decimal("71.02"), unitPrice: decimal("1.679")))!
        #expect(abs(derived.volumeL - double(decimal("71.02") / decimal("1.679"))) < 0.0001)
        let display = ManualFillUpMath.displayVolume(from: derived.volumeL, unit: .galUS)
        #expect(abs(display - 11.174) < 0.01)
    }
}
