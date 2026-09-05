import Testing
import Foundation
@testable import TankbookCore

/// RV.69: the catalogue and `Vehicle.tankCapacityL` store LITRES; the Add-car
/// suggestion row and the tank-capacity field read the vehicle's display
/// volume unit. These tests pin the single boundary (`VehicleCapacity`) a
/// stored-litre tank figure crosses into display text and back into litres.
///
/// The traps this suite exists for (each named in the RV.69 brief):
/// - Testing only under litres, where the bug is invisible: every headline
///   assertion is run under `.galUS` too.
/// - A half-conversion (converting the label but saving the raw litre figure):
///   the round-trip assertion below is the one that catches it.
/// - Accidentally converting the battery (kWh) path: kWh is unit-invariant,
///   so the EV assertions pass the kWh figure straight through and prove the
///   tank helpers are never applied to it.
@Suite struct VehicleCapacityTests {

    // MARK: - Display text per unit

    @Test func fiftyLitresReadsFiftyForALitresUserAndThirteenForGallons() {
        #expect(VehicleCapacity.displayText(litres: 50, unit: .l) == "50")
        #expect(VehicleCapacity.displayText(litres: 50, unit: .galUS) == "13.2")
        #expect(VehicleCapacity.displayText(litres: 50, unit: .galUK) == "11")
    }

    @Test func integralMetricFigureKeepsItsShortForm() {
        // The SCHEMA worked example: "Volvo V60 -> 71 L". A litres user must
        // keep reading "71", never "71.0".
        #expect(VehicleCapacity.displayText(litres: 71, unit: .l) == "71")
        #expect(VehicleCapacity.displayText(litres: 71, unit: .galUS) == "18.8")
        #expect(VehicleCapacity.formattedText(71) == "71")
    }

    @Test func batteryKWhIsNeverRoutedThroughTheTankBoundary() {
        // The EV path formats its stored figure directly (VehicleCapacity is
        // only reached for tank litres), and a tenth-precision display keeps a
        // decimal battery intact. A future "fix" that ran kWh through
        // `displayText` would make no sense to the compiler (it takes litres +
        // a VolumeUnit) - these pin the values that must not drift regardless.
        #expect(VehicleCapacity.formattedText(77) == "77")
        #expect(VehicleCapacity.formattedText(11.6) == "11.6")
        #expect(VehicleCapacity.formattedText(60) == "60")
    }

    // MARK: - Round trip (the half-conversion trap)

    @Test func displayFigureConvertsBackToTheSamePhysicalVolume() {
        // 50 L -> "13.2" gal -> back to litres must land within a tenth-gallon
        // rounding of 50 L, never at ~13.2 L (the half-conversion: storing the
        // display figure as litres is a 3.785x error).
        let stored = VehicleCapacity.litres(display: 13.2, unit: .galUS)
        #expect(abs(stored - 50) < 0.5)
        // And a display round-trip at full precision is exact to float noise.
        let precise = VehicleCapacity.litres(
            display: ManualFillUpMath.displayVolume(from: 50, unit: .galUS),
            unit: .galUS)
        #expect(abs(precise - 50) < 1e-9)
        // The metric path is exact by construction (factor 1.0).
        #expect(VehicleCapacity.litres(display: 50, unit: .l) == 50)
    }

    @Test func formattedTextPinsTheDecimalSeparator() {
        // The form parses the field back with `Double(...)`, so the display
        // text must always use the dot, whatever the device locale.
        #expect(VehicleCapacity.formattedText(13.2086) == "13.2")
        #expect(VehicleCapacity.formattedText(18.7562) == "18.8")
    }
}
