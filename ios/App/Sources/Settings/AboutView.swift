import SwiftUI
import TankbookCore

/// The About screen (P6.18b, design/screens/About.dc.html). Reached from
/// Settings -> "About & feedback" (`Route.about`). Hosts the `.recommended`
/// update row: a dismissible, quiet notice that a newer build exists - it is
/// information, never an interruption, and it withholds nothing.
///
/// The artboard's remaining rows (What's new, Rate, Privacy, the feedback
/// composer) are later tasks; this screen exists to host the update surface
/// and the identity header the artboard draws.
struct AboutView: View {
    @Environment(AppConfigService.self) private var config
    @State private var feedbackModel: FeedbackModel?
    @State private var diagnosticsModel: DiagnosticsModel?
    @State private var showsDiagnosticsPreview = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                identityCard
                if config.requirement == .recommended {
                    UpdateRecommendedRow()
                }
                if let diagnosticsModel {
                    DiagnosticsSection(model: diagnosticsModel) {
                        showsDiagnosticsPreview = true
                    }
                }
                if let feedbackModel {
                    FeedbackComposerView(model: feedbackModel)
                }
                footer
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Theme.Palette.midnight)
        .sheet(isPresented: $showsDiagnosticsPreview) {
            if let diagnosticsModel {
                DiagnosticsPreviewView(model: diagnosticsModel)
            }
        }
        .task {
            if feedbackModel == nil {
                feedbackModel = FeedbackService.makeModel()
            }
            await feedbackModel?.autoSendIfRequested()
            // OB.4: the diagnostics row and its consent, plus the DEBUG/test
            // seams that seed data and drive the screenshot preview.
            if diagnosticsModel == nil {
                // The seed is DEBUG-only (it writes fixture data); the model is
                // production. Guarding the call is what keeps a Release build
                // compiling - RV.78 caught this the only way it can be caught,
                // by building Release, which the per-task gate does not.
                #if DEBUG
                DiagnosticsTestSeed.seedIfRequested()
                #endif
                diagnosticsModel = DiagnosticsService.makeModel()
            }
            presentDiagnosticsPreviewIfRequested()
        }
    }

    /// The artboard's identity block: the 58 pt app mark, the name, and the
    /// version line read from the bundle (never hardcoded).
    private var identityCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15)
                    .fill(Theme.Palette.dash)
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.Palette.hairline, lineWidth: 1))
                Image(systemName: "fuelpump")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.Palette.taillight)
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tankbook")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("Version \(versionLine)")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fontDesign(.monospaced)
                    .accessibilityIdentifier("aboutVersionLine")
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .formCard()
    }

    /// "1.0 (1)" - the short version and build number, read from the bundle.
    /// The artboard draws "Version 1.0 (142)".
    private var versionLine: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build { return "\(short) (\(build))" }
        return short
    }

    private var footer: some View {
        Text("Made for drivers who'd rather drive than type.")
            .font(.caption)
            .foregroundStyle(Theme.Palette.inkSoft.opacity(0.7))
            .multilineTextAlignment(.center)
            .padding(.top, 6)
    }

    /// DEBUG/screenshot only: `-diagnosticsAutoOpenPreview` opens the diagnostics
    /// preview a beat after About appears, so the preview can be screenshotted
    /// without a UI test driving a tap (`simctl` cannot tap). Requires the
    /// consent to be on (`-diagnosticsConsentOn`) - the sheet is only reachable
    /// through the real affordance path. Production never passes the argument.
    private func presentDiagnosticsPreviewIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-diagnosticsAutoOpenPreview") else { return }
        // The seam opens the REAL affordance path only: no consent, no preview.
        guard diagnosticsModel?.hasConsented == true else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            showsDiagnosticsPreview = true
        }
    }
}
