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
    /// and no Charge. Only `.phev` legitimately does both.
    ///
    /// `Vehicle.powertrain` is a catalog pre-fill the user may correct
    /// (CLAUDE.md rule 13), so this must be evaluated against the vehicle's
    /// current value, never against a cached guess.
    public static func modes(for powertrain: Powertrain) -> [CaptureMode] {
        switch powertrain {
        case .ice, .hybrid: return [.fillUpAuto, .service, .expense]
        case .ev: return [.charge, .service, .expense]
        case .phev: return [.fillUpAuto, .charge, .service, .expense]
        }
    }

    /// The mode a screen should start on for a powertrain - the first offered.
    public static func defaultMode(for powertrain: Powertrain) -> CaptureMode {
        modes(for: powertrain).first ?? .fillUpAuto
    }
}
