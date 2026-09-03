import SwiftUI
import TankbookCore

/// RV.22 - the sync state chip beside the Settings gear (docs/SYNC.md -> "The
/// sync state chip"). Reads the app's one sync surface (`AppSync.surfaceState`)
/// and resolves its state through `SyncSurface.chipState(_:)` - presentation
/// over the existing, L1-tested state model, never a second one.
///
/// One SF Symbols family (`icloud.*`) and one colour per state, so the chip
/// reads as ONE object changing state and colour never carries the meaning alone
/// (the accessibility floor: the glyph and label are the channel, the colour is
/// the reinforcement). The decision lives in core (`SyncChipState`); this view
/// only renders the verdict.
struct SyncStateChip: View {
    /// State 1's destination: presenting the sign-in sheet. The other states
    /// navigate to Settings (a `NavigationLink` on the tab's own stack), so the
    /// chip needs no closure for those.
    let onSignIn: () -> Void

    @Environment(AppSync.self) private var sync
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    /// The RV.8 precedent: the moving part degrades to a still glyph under
    /// Reduce Motion, and `-forceReduceMotion` drives the same state from a UI
    /// test (the system setting alone would not).
    private var reduceMotion: Bool {
        accessibilityReduceMotion || ProcessInfo.processInfo.arguments.contains("-forceReduceMotion")
    }

    private var state: SyncChipState {
        sync.forcedChipState ?? SyncSurface.chipState(sync.surfaceState)
    }

    private var dirtyCount: Int {
        sync.forcedChipDirtyCount ?? sync.dirtyCount
    }

    private var flaggedCount: Int {
        sync.forcedChipFlaggedCount ?? sync.flaggedCount
    }

    private var showsWarnDot: Bool {
        flaggedCount > 0
    }

    var body: some View {
        chipBody
            .overlay(alignment: .topTrailing) {
                if showsWarnDot {
                    flaggedDot
                        .offset(x: 5, y: -5)
                }
            }
    }

    /// The chip's body. State 1 (signed out) is a Button to sign in; every
    /// other state navigates to Settings. For the attention states (2) the tap
    /// also records which card to scroll to, so Settings lands on the card that
    /// names the fix (docs/SYNC.md).
    @ViewBuilder
    private var chipBody: some View {
        if state == .signedOut {
            Button(action: onSignIn) { chipLabel }
                .buttonStyle(.plain)
                .accessibilityIdentifier("syncStateChip")
                .accessibilityLabel(label)
        } else {
            NavigationLink(value: Route.settings) { chipLabel }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    sync.settingsScrollTarget = scrollTarget
                })
                .accessibilityIdentifier("syncStateChip")
                .accessibilityLabel(label)
        }
    }

    private var chipLabel: some View {
        HStack(spacing: 5) {
            indicator
            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(colour)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.Palette.dash))
        .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
    }

    /// The moving part. The in-flight state is the system `ProgressView`, which
    /// degrades to a still glyph under Reduce Motion (the RV.8 precedent) - the
    /// accessibility floor is non-negotiable, and the label carries the meaning
    /// on its own.
    @ViewBuilder
    private var indicator: some View {
        if state == .syncing && !reduceMotion {
            ProgressView()
                .controlSize(.small)
                .tint(Theme.Palette.action)
        } else {
            Image(systemName: glyph)
                .font(.caption)
        }
    }

    private var glyph: String {
        switch state {
        case .signedOut: "icloud.slash"
        case .deviceRevoked, .authExpired, .quotaFull: "exclamationmark.icloud"
        case .syncing: "arrow.triangle.2.circlepath"
        case .waiting: "icloud.and.arrow.up"
        case .synced: "checkmark.icloud"
        }
    }

    private var colour: Color {
        switch state {
        case .deviceRevoked, .authExpired, .quotaFull: Theme.Palette.warn
        case .syncing: Theme.Palette.action
        case .signedOut, .waiting: Theme.Palette.inkSoft
        case .synced: Theme.Palette.ok
        }
    }

    private var label: String {
        switch state {
        case .signedOut: L10n.chipNotSignedIn
        case .deviceRevoked: L10n.chipDeviceSignedOut
        case .authExpired: L10n.chipSignInAgain
        case .quotaFull: L10n.chipStorageFull
        case .syncing: L10n.chipSyncing
        case .waiting: L10n.waitingToSync(dirtyCount)
        case .synced: L10n.chipSynced
        }
    }

    private var scrollTarget: SettingsScrollTarget? {
        switch state {
        case .deviceRevoked: .revokedCard
        case .authExpired: .account
        case .quotaFull: .quotaCard
        default: nil
        }
    }

    /// The warn dot that rides the chip's corner when entries are flagged - NOT
    /// a sixth state. It taps to the Log filtered to flagged entries, never
    /// Settings (hard rule 8: the badge lives where the data lives).
    private var flaggedDot: some View {
        NavigationLink(value: Route.flaggedEntries) {
            Circle()
                .fill(Theme.Palette.warn)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Theme.Palette.midnight, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .frame(width: 24, height: 24)
        .contentShape(Circle())
        .accessibilityIdentifier("syncFlaggedDot")
        .accessibilityLabel(L10n.flaggedEntries(flaggedCount))
    }
}
