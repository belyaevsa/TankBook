import SwiftUI
import TankbookCore

// MARK: - PJ.17 the empty-but-alive caption (F1)

/// PJ.17 (docs/JOURNEYS.md F1): a scan that resolved NOTHING but kept its
/// photo - the empty-but-alive state. The failure state IS the manual form
/// (hard rule 15), so the only trace of the failed scan is a quiet inkSoft
/// caption and Total focused on appear. Never amber (hard rule 5): this is not
/// an error state, and the typed path shows no caption at all (hard rule 15 -
/// typing is a peer door, not a degraded one). The decision lives in core
/// (`ConfirmEmptyScanCaption.shouldShow`) so it is L1-testable; this file is
/// only the rendering and the focus.
extension ManualFillUpView {
    /// Whether the empty-but-alive caption (and the Total focus) applies.
    var emptyScanCaptionShows: Bool {
        ConfirmEmptyScanCaption.shouldShow(
            extraction: prefill?.extraction,
            qrAnchor: prefill?.qrAnchor,
            hasPhoto: prefill?.sourceImage != nil)
    }

    /// PJ.17 (F1): focuses Total on appear - the one field a receipt always
    /// shows. Called from `load()` once the form is ready; a `.task` on the
    /// caption itself was swallowed by the sheet's first-render focus system,
    /// so the hop lands a runloop turn later, after the numbers card exists.
    func focusEmptyScanTotalIfShown() {
        guard emptyScanCaptionShows else { return }
        DispatchQueue.main.async { focus = .total }
    }

    /// The quiet caption: inkSoft (a hint, never amber), a caption never a
    /// banner, shown ONLY when a photo arrived and nothing resolved. Copy is
    /// the exact F1 verdict: "Couldn't read this one – type it, the photo
    /// stays attached." Focus is set by the form's `load()` (PJ.17), not here -
    /// a `.task` on a view that appears inside the sheet's first render is
    /// swallowed by the focus system.
    var emptyScanCaption: some View {
        Text("Couldn't read this one – type it, the photo stays attached.")
            .font(.footnote)
            .foregroundStyle(Theme.Palette.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("manualFillUpEmptyScanCaption")
    }
}
