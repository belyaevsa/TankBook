import TankbookCore

/// The one display string for a stored litre figure in the car's own unit. The
/// log's quantity segment, the S2 duplicate card and the excluded-entries list
/// all print the same figure, so a fourth caller cannot invent a second factor
/// (RV.273). The conversion is `ManualFillUpMath` - the codebase's one
/// litre<->display converter - never a copy.
enum VolumeDisplay {
    /// "51.1 L" / "13.5 gal" - a stored `volumeL` in the car's display unit.
    static func text(_ litres: Double, unit: VolumeUnit, fractionDigits: Int = 1) -> String {
        let display = ManualFillUpMath.displayVolume(from: litres, unit: unit)
        return "\(ManualFillUpFormat.decimal(display, fractionDigits: fractionDigits)) \(L10n.volumeUnit(unit))"
    }
}
