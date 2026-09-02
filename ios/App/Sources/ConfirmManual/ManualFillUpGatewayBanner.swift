import SwiftUI
import TankbookCore

// MARK: - RV.8 the cloud-reading indication on the Confirm sheet
//
// A standalone view rather than a computed property on ManualFillUpView: that
// file is at its 700-line limit, and taking the two things it needs as inputs
// keeps it previewable and free of the sheet's state.

/// The in-flight indication (RV.8) and the 3 s budget message (docs/API.md
/// rule 2, hard rule 7) – the SAME banner in two states rather than two
/// banners, so the row does not appear, vanish and reappear while one request
/// runs.
///
/// It exists because production measured `llm.extract DurationMs=10218` on a
/// real receipt: before RV.8 the first 3 s showed NOTHING at all, and the
/// remaining 7 s showed a motionless hourglass, which reads as a finished
/// statement rather than as work in progress. Neither state told the user there
/// was anything worth waiting for.
///
/// Both states carry the same spinner, because in both the request is still
/// running – the budget moves the USER on, it never aborts the request. Only
/// the words change: before the budget the banner says what is happening, after
/// it names the next step (carry on with what was read on-device). Neither
/// carries an upsell: the Pro tier is deferred, and monetization mid-capture is
/// explicitly forbidden (hard rule 7).
struct GatewayReadingBanner: View {
    let phase: GatewayScanSession.Phase
    let reduceMotion: Bool

    var body: some View {
        switch phase {
        case .running:
            banner("Reading this in the cloud… you can keep typing.",
                   identifier: "gatewayReadingMessage")
        case .budgetExpired:
            banner("Cloud reading continues in the background – keep going with what was read here.",
                   identifier: "gatewayTimeoutMessage")
        case .idle, .answered, .saved:
            EmptyView()
        }
    }

    /// One banner shape for both states, so the switch above changes only the
    /// words and the row keeps its height and its place in the form.
    private func banner(_ text: LocalizedStringKey, identifier: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            indicator
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// The moving part. A system `ProgressView` – DESIGN.md allows system
    /// defaults beside its three orchestrated moments, and this is the same
    /// small `inkSoft` spinner Import and Settings already use, so "the app is
    /// working" looks the same everywhere in the app.
    ///
    /// Under Reduce Motion it degrades to the static hourglass rather than
    /// spinning: the accessibility floor is non-negotiable, and the banner's
    /// text carries the meaning on its own.
    @ViewBuilder
    private var indicator: some View {
        if reduceMotion {
            Image(systemName: "hourglass.bottomhalf.filled")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSoft)
        } else {
            ProgressView()
                .controlSize(.small)
                .tint(Theme.Palette.inkSoft)
        }
    }
}
