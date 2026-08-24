import SwiftUI
import TankbookCore

/// The capture screen's mode row (design/screens/Capture.dc.html): Fill-up
/// (the default, carrying the "· auto" surface-detection suffix), Charge,
/// Service, Expense. Selection is local state for P2.1; the forward exits
/// (Confirm variants, ServiceEntry) land in later tasks. The mode contract
/// lives in `TankbookCore.CaptureMode`; this file adds the presentation layer.
///
/// The "· auto" suffix is one full localised phrase per language, never
/// concatenation - the P1.4 RU pass proved composed strings need a full
/// phrase ("%@ spend" became "АВГУСТ РАСХОДЫ").
extension CaptureMode {
    /// UI-test identifier for the mode chip.
    var identifier: String { "captureMode_" + rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .fillUpAuto: "Fill-up · auto"
        case .charge: "Charge"
        case .service: "Service"
        case .expense: "Expense"
        }
    }
}
