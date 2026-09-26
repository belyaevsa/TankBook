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
    @State private var showsCaptureLab = false
    @State private var showsSendDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                identityCard
                #if EXPERIMENTS
                experimentsSection
                #endif
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
        .sheet(isPresented: $showsCaptureLab) {
            #if EXPERIMENTS
            CaptureLabView()
            #endif
        }
        .sheet(isPresented: $showsSendDiagnostics) {
            #if EXPERIMENTS
            DiagnosticsCaseView(model: DiagnosticsCaseModel.make())
            #endif
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
            #if DEBUG
            presentCaptureLabIfRequested()
            presentSendDiagnosticsIfRequested()
            #endif
        }
    }

    /// The beta's experiments, one row per `BetaExperiment` case, directly under
    /// the identity card so a tester sees what this build carries. Compiled into
    /// Debug and Beta only; the store build has no such section.
    #if EXPERIMENTS
    private var experimentsSection: some View {
        VStack(spacing: 8) {
            SectionEyebrow("Experiments")
            ForEach(BetaExperiment.allCases) { experiment in
                experimentRow(experiment)
            }
        }
    }

    private func experimentRow(_ experiment: BetaExperiment) -> some View {
        Button {
            switch experiment {
            case .captureLab: showsCaptureLab = true
            case .sendDiagnostics: showsSendDiagnostics = true
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(experiment.title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .formCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(experiment.rawValue)Row")
    }
    #endif

    #if DEBUG
    /// Screenshot seam: `-presentCaptureLab` opens the lab a beat after About
    /// appears, so the lab can be screenshotted without a UI test driving a tap
    /// (`simctl` cannot tap).
    private func presentCaptureLabIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-presentCaptureLab") else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            showsCaptureLab = true
        }
    }
    #endif

    #if DEBUG
    /// Screenshot seam: `-presentSendDiagnostics` opens the send sheet a beat
    /// after About appears (`simctl` cannot tap).
    private func presentSendDiagnosticsIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-presentSendDiagnostics") else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            showsSendDiagnostics = true
        }
    }
    #endif

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
        var line = build.map { "\(short) (\($0))" } ?? short
        // The commit the binary was built from and the channel, so a hand
        // install, a beta and a store build can be told apart - the
        // Experiments section exists only in the first two. Both are machine
        // tokens.
        if let commit = Bundle.main.object(forInfoDictionaryKey: "TankbookBuildCommit") as? String {
            line += " · \(commit)"
        }
        #if DEBUG
        line += " · debug"
        #elseif EXPERIMENTS
        line += " · beta"
        #endif
        return line
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
