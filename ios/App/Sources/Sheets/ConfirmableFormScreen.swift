import SwiftUI
import TankbookCore

/// True while a screen carrying a **primary confirmation action** is on top.
///
/// Read by `TabRoots` to hide the owned tab bar for the duration. A screen whose
/// job is "fill this in and confirm it" must not also offer the capture button:
/// the two are both taillight-red primary actions stacked in the same corner of
/// the screen, and the raised capture circle draws straight over a pinned save
/// bar (found on the P3.4 reminder form). Worse than the visual collision, a tap
/// meant for Save that lands on Capture abandons a half-filled form.
///
/// The sheet-presented forms - ConfirmManual, ServiceEntry - never had this
/// problem, because a sheet covers the bar. This preference gives PUSHED forms
/// the same guarantee without changing the navigation graph
/// (`docs/SCREENMAP.md` keeps ReminderForm a pushed screen with its back
/// chevron; only the bar's visibility changes).
struct ConfirmableFormPreference: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// The shared shell for **any form with a confirmation button**: the content
/// scrolls, the primary action is pinned above the safe area, and the tab bar
/// steps aside while it is on screen.
///
/// Adopting this shell is what makes a screen a "form with a confirmation
/// button" - there is no second list to keep in sync. `docs/DESIGN.md` records
/// the rule; this type is its only implementation.
///
/// The disabled state carries a **hint that names the next step** (hard rule 7):
/// a Save the user cannot press, with nothing saying why, is the failure mode
/// `docs/ERRORS.md` exists to prevent.
struct ConfirmableFormScreen<Content: View>: View {
    /// The primary action's label ("Save reminder", "Save service").
    let confirmTitle: LocalizedStringKey
    /// Whether the form can be confirmed right now.
    let isEnabled: Bool
    /// Shown under the button while it is disabled; names what is missing.
    ///
    /// An **already-localized** `String`, not a `LocalizedStringKey`: a hint is
    /// chosen at runtime from the form's state, so it is resolved through
    /// `L10n.localize` at the call site. `Text(_: String)` does not localise,
    /// which is exactly why the value must arrive translated - the rule at the
    /// top of `L10n.swift`, and the shape behind five shipped bugs.
    let hint: String?
    /// Accessibility identifier for the button; the hint gets `<id>Hint`.
    let identifier: String
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(Theme.Palette.midnight)
            .safeAreaInset(edge: .bottom) { confirmBar }
            .preference(key: ConfirmableFormPreference.self, value: true)
    }

    private var confirmBar: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Text(confirmTitle)
                    .font(.body.weight(.bold))
                    .foregroundStyle(isEnabled ? Color.white : Theme.Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isEnabled ? Theme.Palette.taillight : Theme.Palette.dash)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .shadow(color: isEnabled ? Theme.Palette.taillight.opacity(0.3) : .clear,
                            radius: 18, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityIdentifier(identifier)

            if !isEnabled, let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("\(identifier)Hint")
            }
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Theme.Palette.midnight)
    }
}
