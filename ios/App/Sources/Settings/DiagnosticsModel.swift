import Foundation
import Observation
import TankbookCore

/// The About "Attach diagnostics" state (docs/LOGGING.md §5): the consent mirror
/// and the built preview text. The consent store is the source of truth for
/// persistence; the model caches the value for the toggle and writes through on
/// change (hard rule 13: a value the user set is theirs, changeable afterwards).
/// Default OFF and never automatic - §5's whole point - exactly the once-asked
/// shape PJ.20's feedback consent takes.
@MainActor
@Observable
final class DiagnosticsModel {
    private let consentStore: DiagnosticsConsentStore

    /// The once-asked opt-in, mirrored for the toggle. Default OFF; written
    /// through to the persisted store on every change.
    var hasConsented: Bool {
        didSet { consentStore.setConsented(hasConsented) }
    }

    /// The full text the user previews and the share sheet sends. Built fresh on
    /// every preview open (`buildPreviewText`), never cached across opens - a
    /// preview must reflect the log up to the moment it appears.
    private(set) var previewText: String?

    init(consentStore: DiagnosticsConsentStore) {
        self.consentStore = consentStore
        self.hasConsented = consentStore.hasConsented
    }

    /// Assembles the current bundle (24 h log window + sync state + row counts)
    /// and renders it - exactly the text the share sheet will send.
    func buildPreviewText() async {
        previewText = await DiagnosticsService.makePreviewText()
    }
}
