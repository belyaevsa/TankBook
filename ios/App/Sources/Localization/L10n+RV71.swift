import Foundation
import TankbookCore

// RV.71 the fuel-kind mismatch warn on the Confirm sheet (scan moment).
// In its own file so the L10n enum body and the L10n.swift file both stay
// within the lint budget - the L10n+X convention (L10n+Language, L10n+Inbox).

extension L10n {
    /// The localized display label for one fuel kind ("Diesel", "92", "LPG",
    /// ...) as a `String` - the composed-sentence form of the chips' `labelKey`
    /// (which cannot be read back as a String). A fuel kind is an undeclined
    /// TOKEN in Russian ("Дизель", "95"), so a phrase can weave one in without
    /// governing a case (docs/LOCALIZATION.md).
    static func fuelKindLabel(_ kind: FuelKind) -> String {
        switch kind {
        case .diesel: return localize("Diesel")
        case .petrol92: return localize("92")
        case .petrol95: return localize("95")
        case .petrol98: return localize("98")
        case .petrol100: return localize("100")
        case .lpg: return localize("LPG")
        case .cng: return localize("CNG")
        case .e85: return localize("E85")
        case .electricity: return localize("Electricity")
        }
    }

    /// "The receipt reads Diesel, but this car is set up for 95. Check the
    /// fuel kind before saving." - the RV.71 mismatch warn (docs/ERRORS.md ->
    /// Confirm). One full localised phrase per language, never concatenation;
    /// both slots receive fuel-kind labels (undeclined tokens in RU). The
    /// car-side list is the vehicle's own declared kinds without its
    /// electricity side - the warn is about a liquid/gas fill, and a hybrid's
    /// charging half is irrelevant to it.
    static func fuelKindMismatchMessage(scannedKind: FuelKind,
                                        declaredKinds: [FuelKind]) -> String {
        let carKinds = declaredKinds
            .filter { $0 != .electricity }
            .map { fuelKindLabel($0) }
            .joined(separator: ", ")
        return String(format: localize(
            "The receipt reads %1$@, but this car is set up for %2$@. Check the fuel kind before saving."),
            fuelKindLabel(scannedKind), carKinds)
    }
}
