#if EXPERIMENTS
import SwiftUI

/// Every feature that ships to the beta (Tankbook β) and not to the store.
/// Code behind `#if EXPERIMENTS` compiles into Debug and Beta and is absent from
/// Release; About lists each case, so the beta always shows what it carries.
/// A case leaves this enum only by the owner's decision - promoted to the store
/// build or removed with its code (`docs/CONFIG.md` -> "Build channels and
/// experiments"). `scripts/experiments-check.sh` names each case's types and
/// fails a Release build that contains any of them.
enum BetaExperiment: String, CaseIterable, Identifiable {
    case captureLab
    case sendDiagnostics

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .captureLab: "Capture lab"
        case .sendDiagnostics: "Send diagnostics"
        }
    }
}
#endif
