import Foundation

/// The capture screen's mode row (design/screens/Capture.dc.html): Fill-up
/// (the default), Charge, Service, Expense. This is the capture-mode contract,
/// not a persisted entity - it lives in the core because P2.3+ forward exits
/// (Confirm variants, ServiceEntry) and the pump-mode feature flag (P2.7) all
/// switch on it, and because the "· auto" promise belongs next to a unit test,
/// not in UI prose.
public enum CaptureMode: String, Codable, Sendable, CaseIterable {
    case fillUpAuto
    case charge
    case service
    case expense

    /// True for the mode whose chip carries the "· auto" suffix, i.e. the one
    /// promising automatic surface detection. Only Fill-up makes that promise
    /// today; pump mode (P2.7) adds its own later.
    public var isSurfaceAutoDetected: Bool { self == .fillUpAuto }

    /// The modes worth offering for a given powertrain.
    ///
    /// Showing every mode to every car is noise: a petrol car can never log a
    /// charging session and an EV can never log a fill-up, so the chip is not
    /// merely unused - it invites an entry the vehicle cannot have.
    ///
    /// The distinction that is easy to get wrong is **hybrid vs plug-in
    /// hybrid**. A plain `.hybrid` (HEV) has no plug: its battery is charged by
    /// the engine and by regeneration, never from a charger, so it gets Fill-up
    /// and no Charge. Only `.phev` legitimately has a fill-up door among the
    /// electrics.
    ///
    /// PJ.12 deferral (docs/TASKS.md -> PJ.12): `.charge` is deliberately
    /// offered to **no** powertrain while EV charging stays out of v1 - J6 is
    /// `[v1.x]` in docs/JOURNEYS.md and no charge entry form exists, so the
    /// chip would be a dead door (decorative shutter, "Type it" opening the
    /// fill-up form for a car with no fuel tank). The enum case stays:
    /// `ChargeSession` is a real entity elsewhere. **Restored by** the v1.x EV
    /// charging work that closes J6 (a charge entry form exists), and only
    /// then: `.ev` regains `.charge` and `.phev` the four-chip row.
    ///
    /// `Vehicle.powertrain` is a catalog pre-fill the user may correct
    /// (CLAUDE.md rule 13), so this must be evaluated against the vehicle's
    /// current value, never against a cached guess.
    public static func modes(for powertrain: Powertrain) -> [CaptureMode] {
        switch powertrain {
        case .ice, .hybrid: return [.fillUpAuto, .service, .expense]
        case .ev: return [.service, .expense]
        case .phev: return [.fillUpAuto, .service, .expense]
        }
    }

    /// The mode a screen should start on for a powertrain - the first offered.
    public static func defaultMode(for powertrain: Powertrain) -> CaptureMode {
        modes(for: powertrain).first ?? .fillUpAuto
    }

    /// The manual entry form "Type it" opens for this mode (hard rule 15 - the
    /// typed door is a peer of capture and must open the form for the mode the
    /// user selected, never a fill-up form in Service mode).
    ///
    /// `.charge` deliberately shares the fill-up form: there is no charge entry
    /// form yet (PJ.12 owns the dead Charge chip for EV/PHEV), and the fill-up
    /// form is the only manual entry form that exists. Routing it there keeps
    /// "Type it" a working door in every mode and matches the shutter, which
    /// also lands a Charge-mode scan in that form. The mapping is a value so
    /// both call sites and the tests pin it together.
    public var manualEntryForm: CaptureEntryForm {
        switch self {
        case .fillUpAuto: return .fillUp
        case .charge: return .fillUp
        case .service: return .service
        case .expense: return .expense
        }
    }
}

/// The manual entry form a capture mode routes "Type it" to
/// (`CaptureMode.manualEntryForm`). One case per form that exists today; the
/// app maps a case to the sheet it presents (`SheetRoute`).
public enum CaptureEntryForm: String, Codable, Sendable, CaseIterable {
    case fillUp
    case service
    case expense
}
