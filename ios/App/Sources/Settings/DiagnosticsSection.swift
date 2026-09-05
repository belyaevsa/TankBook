import SwiftUI
import TankbookCore

/// The About screen's "Attach diagnostics" card (docs/LOGGING.md §5): a
/// once-asked opt-in, default OFF, persisted and changeable afterwards (hard
/// rule 13 - the same consent shape PJ.20's feedback composer uses). While it is
/// OFF the preview is unreachable; the moment it is ON the card offers
/// "Preview what will be shared", which opens the exact-text preview screen.
/// Never silent, never automatic, never on by default - §5's whole point.
struct DiagnosticsSection: View {
    @Bindable var model: DiagnosticsModel
    /// Opens the preview sheet (About owns the presentation).
    let onPreview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $model.hasConsented) {
                Text("Attach diagnostics")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
            }
            .tint(Theme.Palette.taillight)
            .accessibilityIdentifier("diagnosticsConsentToggle")
            Text("Tankbook's own recent log (last 24 hours), the sync result and entry counts. Stations, notes and amounts never leave – you preview first.")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.3)
                .fixedSize(horizontal: false, vertical: true)
            if model.hasConsented {
                previewRow
            }
        }
        .padding(14)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("aboutDiagnosticsCard")
    }

    /// "Preview what will be shared" - only reachable once the opt-in is on.
    /// The next screen shows exactly the bytes that would be sent (§5).
    private var previewRow: some View {
        Button(action: onPreview) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.action)
                Text("Preview what will be shared")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .accessibilityIdentifier("diagnosticsPreviewButton")
    }
}
