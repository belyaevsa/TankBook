import SwiftUI
import TankbookCore

/// The "Diagnostics preview" sheet (docs/LOGGING.md §5, design/screens/
/// About.dc.html's diagnostics row): shows EXACTLY the text that would be sent -
/// not a summary of it, not a count - and shares that same text through the
/// system share sheet as a file (`DiagnosticsShare`). §5's whole point is that
/// the user reads the bytes before anything leaves the device; a screen that
/// summarised instead would break it.
///
/// Reached from About -> the diagnostics consent card's "Preview what will be
/// shared" (only reachable once the opt-in is on). Back path: Close / swipe-down
/// returns to About (docs/SCREENMAP.md).
///
/// The preview text is the bundle's `rendered()` output, which already carries
/// the in-memory breadcrumb ring (docs/LOGGING.md §4-§5) - so the last share's
/// `app.event operation=… outcome=…` line and, when a destination failed, its
/// `app.warning … reason=activity=… error=…` line are on screen here. That is
/// the device evidence path: a failed share can be screenshotted without the
/// share sheet itself having to arrive (RV.181).
struct DiagnosticsPreviewView: View {
    @Bindable var model: DiagnosticsModel
    @Environment(\.dismiss) private var dismiss

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
                .task {
                    await model.buildPreviewText()
                    presentShareIfRequested()
                }
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
        DiagnosticsShare.present(text: text)
    }

    /// DEBUG/screenshot only: `-diagnosticsAutoShare` opens the share sheet a
    /// beat after the preview appears, so the sheet - and the `.txt` file row it
    /// names - can be screenshotted without a UI test driving a tap (`simctl`
    /// cannot tap). Production never passes the argument.
    private func presentShareIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-diagnosticsAutoShare") else { return }
        guard model.previewText != nil else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            presentShare()
        }
    }
}
