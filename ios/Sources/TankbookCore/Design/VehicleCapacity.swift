import Foundation

/// RV.69: the tank-capacity unit boundary.
///
/// `Vehicle.tankCapacityL` and the catalogue's `tankCapacityL` are stored in
/// LITRES (docs/SCHEMA.md - the storage unit is the authority); the Add-car
/// suggestion row and the tank-capacity form field read in the vehicle's
/// display volume unit. These functions are the only places a stored-litre
/// tank capacity crosses into display text, and a display-unit figure crosses
/// back into litres. Battery kWh is unit-invariant and is deliberately never
/// routed through here.
///
/// The conversion factor is `ManualFillUpMath` - the codebase's one
/// litre<->display volume converter, the same factor fill volumes use - never
/// a second copy.
public enum VehicleCapacity {

    /// Renders a stored-litre tank capacity as the figure the user's volume
    /// unit reads: "50" for a 50 L tank to a litres user, "13.2" gal to a US
    /// user. Display precision is one tenth so a converted figure never floods
    /// the field with raw `Double` noise ("13.20860364..."), and the decimal
    /// point is pinned (en_US_POSIX) so the text parses back through
    /// `Double(...)` under every locale (NumericInputSanitizer's pinned parse
    /// separator).
    public static func displayText(litres: Double, unit: VolumeUnit) -> String {
        formattedText(ManualFillUpMath.displayVolume(from: litres, unit: unit))
    }

    /// The stored litres behind a display-unit figure: "13.2" gal -> ~50 L.
    /// The exact inverse of `displayText`.
    public static func litres(display: Double, unit: VolumeUnit) -> Double {
        ManualFillUpMath.volumeL(from: display, unit: unit)
    }

    /// Formats a capacity figure ("71.0" -> "71", "13.2086..." -> "13.2") for
    /// a text field or suggestion subtitle. Shared by the tank boundary above
    /// and the unit-invariant battery (kWh) path.
    public static func formattedText(_ value: Double) -> String {
        let tenths = (value * 10).rounded() / 10
        if tenths == tenths.rounded() {
            return String(Int(tenths))
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), tenths)
    }
}
