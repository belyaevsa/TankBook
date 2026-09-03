import SwiftUI
import TankbookCore

/// RV.22 - the sync state chip beside the Settings gear (docs/SYNC.md -> "The
/// sync state chip"). Reads the app's one sync surface (`AppSync.surfaceState`)
/// and resolves its state through `SyncSurface.chipState(_:)` - presentation
/// over the existing, L1-tested state model, never a second one.
///
/// One SF Symbols family (`icloud.*`) and one colour per state, so the chip
/// reads as ONE object changing state. The decision lives in core
/// (`SyncChipState`); this view only renders the verdict.
///
/// **Icon only, at the gear's exact size** (product owner, 2026-09-03): 44 pt
/// circle, `dash` fill, hairline stroke, `.title3` glyph - the same treatment
/// `TabRootHeader.settingsLink` draws, so the two read as one pair of controls
/// rather than a label sitting next to a button. Two consequences are
/// deliberate:
///
/// - **The queue COUNT is not on the chip.** It has no text to live in, and a
///   number on the glyph would make the chip re-layout as the queue changes -
///   the thing "the arrow, not the count" was chosen to avoid. The count stays
///   where it can be read properly: the Settings sync row ("Waiting to sync -
///   N changes"), one tap away, which is where this chip's tap already lands.
/// - **The accessibility floor still holds, because the glyph was always the
///   channel.** Every state has a distinct SILHOUETTE (`icloud.slash`,
///   `exclamationmark.icloud`, the spinner, `icloud.and.arrow.up`,
///   `checkmark.icloud`), so colour is still never the only channel
///   (docs/DESIGN.md -> accessibility floor). `accessibilityLabel` continues to
///   name the state in full for VoiceOver - dropping the VISIBLE text is not
///   dropping the label, and the L4 tests assert that label, not the pixels.
struct SyncStateChip: View {
    /// State 1's destination: presenting the sign-in sheet. The other states
    /// navigate to Settings (a `NavigationLink` on the tab's own stack), so the
    /// chip needs no closure for those.
    let onSignIn: () -> Void

    @Environment(AppSync.self) private var sync
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    /// Drives the in-flight glyph's rotation (see `indicator`).
    @State private var spinning = false

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
                    // INSIDE the 44 pt frame, never offset out of it. The chip
                    // is a circle inscribed in that square, so its top-trailing
                    // corner is empty space the dot can sit in and still read as
                    // riding the chip's edge. The old +5/-5 offset put the dot
                    // outside the parent's bounds, where SwiftUI still DREW it
                    // but stopped hit-testing it: the dot was visible in the
                    // screenshot and `app.buttons["syncFlaggedDot"]` no longer
                    // resolved, so its tap-to-filtered-Log route was dead.
                    flaggedDot
                        .offset(x: -1, y: 1)
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
        indicator
            .foregroundStyle(colour)
            .frame(width: 44, height: 44)          // tap target >= 44pt
            .background(Circle().fill(Theme.Palette.dash))
            .overlay(Circle().stroke(Theme.Palette.hairline, lineWidth: 1))
    }

    /// The moving part. The in-flight state is the system `ProgressView`, which
    /// degrades to a still glyph under Reduce Motion (the RV.8 precedent) - the
    /// accessibility floor is non-negotiable, and the label carries the meaning
    /// on its own.
    private var indicator: some View {
        // EVERY state is an `Image`, including the in-flight one, and that is a
        // layout requirement rather than a style choice. `TabRootHeader`'s row
        // is `.firstTextBaseline`-aligned so the gear sits on the title's
        // baseline; a `ProgressView` has NO text baseline, so it fell back to
        // bottom alignment, sat ~10 pt below the gear and grew the header,
        // pushing the whole page down - visible in the first icon-only
        // screenshots, and invisible to the L4 tests, which assert the
        // accessibility label and never a frame. Rotating the glyph keeps one
        // code path, one baseline and one header height across all five states.
        //
        // Reduce Motion degrades it to the same glyph, still (the RV.8
        // precedent): the state is never lost, only its motion.
        Image(systemName: glyph)
            .font(.title3)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(spins ? .linear(duration: 1).repeatForever(autoreverses: false) : nil,
                       value: spinning)
            .onAppear { spinning = spins }
            .onChange(of: spins) { _, newValue in spinning = newValue }
    }

    /// Whether the in-flight glyph should turn: the syncing state, unless the
    /// user asked for less motion.
    private var spins: Bool {
        state == .syncing && !reduceMotion
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
