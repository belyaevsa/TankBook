import Foundation

/// Locale-driven vehicle defaults for the Add-car screen (docs/JOURNEYS.md J1:
/// "RU locale defaults to ₽ + RU fuel grades"). A locale guess is a default
/// input the user edits (hard rule 13) - never a fact - so every value here is
/// offered on the form and overridable there and again in Garage.
public enum VehicleDefaults {
    /// The fuel kinds a newly-added petrol car defaults to. The RU locale
    /// (the market that pumps АИ-92 and АИ-95 side by side) defaults to both
    /// grades alongside the RUB currency guess; everywhere else 95 alone - the
    /// most common European grade. The user keeps both chips, drops one, or
    /// picks another grade the moment the form renders.
    public static func defaultFuelKinds(for locale: Locale = .current) -> [FuelKind] {
        switch locale.region?.identifier.uppercased() {
        case "RU": return [.petrol92, .petrol95]
        default: return [.petrol95]
        }
    }
}
