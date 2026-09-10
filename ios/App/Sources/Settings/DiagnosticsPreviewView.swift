import SwiftUI
import TankbookCore

/// The "Diagnostics preview" sheet (docs/LOGGING.md §5, design/screens/
/// About.dc.html's diagnostics row): shows EXACTLY the text that would be sent -
/// not a summary of it, not a count - and shares that same string through the
/// system share sheet. §5's whole point is that the user reads the bytes before
/// anything leaves the device; a screen that summarised instead would break it.
///
/// Reached from About -> the diagnostics consent card's "Preview what will be
/// shared" (only reachable once the opt-in is on). Back path: Close / swipe-down
/// returns to About (docs/SCREENMAP.md).
struct DiagnosticsPreviewView: View {
    @Bindable var model: DiagnosticsModel
    @Environment(\.dismiss) private var dismiss
    @State private var shareable: DiagnosticsShareable?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Diagnostics preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .foregroundStyle(Theme.Palette.action)
                            .accessibilityIdentifier("diagnosticsCloseButton")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Share") { presentShare() }
                            .foregroundStyle(Theme.Palette.action)
                            .disabled(model.previewText == nil)
                            .opacity(model.previewText == nil ? 0.5 : 1)
                            .accessibilityIdentifier("diagnosticsShareButton")
                    }
                }
                .sheet(item: $shareable) { item in
                    ActivityView(items: [item.text]) { outcome in
                        // Shape only (docs/LOGGING.md §4): that the share ended,
                        // how, and that the payload was text - never the text,
                        // its length, its hash or a destination app (hard rule
                        // 12).
                        AppLog.share(operation: "diagnostics.share", kind: "text",
                                     outcome: outcome)
                    }
                }
                .task { await model.buildPreviewText() }
        }
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        if let text = model.previewText {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("This is exactly what will be sent. Read it before you share.")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: text)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.Palette.ink)
                        .textSelection(.enabled)
                        .lineSpacing(1.2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("diagnosticsPreviewText")
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.vertical, 12)
                .padding(.bottom, 24)
            }
            .background(Theme.Palette.midnight)
        } else {
            ProgressView()
                .tint(Theme.Palette.inkSoft)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Palette.midnight)
        }
    }

    private func presentShare() {
        guard let text = model.previewText else { return }
        shareable = DiagnosticsShareable(text: text)
    }
}

/// The share-sheet payload: the exact preview text. Identifiable for `.sheet(item:)`.
private struct DiagnosticsShareable: Identifiable {
    let text: String
    var id: String { text }
}
