import SwiftUI
import TankbookCore

/// The ranked resolution fixes under an F9a odometer warning. The ORDER is the
/// validator's (`OdometerConflict.suggestions`), never re-derived here: the
/// first-ranked fix is preselected, and a date change the validator marked as
/// overriding a printed receipt date asks first, naming that date (docs/
/// JOURNEYS.md F9a; docs/SCHEMA.md, PRIORITY; hard rule 7). Shared by the
/// Confirm sheet, the Edit-entry fill screen and the Edit-entry non-fill screen.
///
/// The caller owns what each fix focuses: `onFixOdometer` and `onFixLiters`
/// set the screen's own focus state, so the same component serves the fill-up
/// focus and the non-fill focus without a second copy.
struct F9aFixRow: View {
    let conflict: OdometerConflict
    let onFixOdometer: () -> Void
    let onFixLiters: () -> Void
    let onFixDate: () -> Void
    /// The odometer fix's accessibility identifier. A non-fill screen passes
    /// its own so a UI test can tell the two surfaces apart; the default is the
    /// fill-up's, which the Confirm-sheet tests assert.
    var odometerFixIdentifier: String = "manualFillUpOdometerFixButton"

    /// The "fix date" override confirmation. A printed receipt date is ground
    /// truth, so changing it is an explicit act and the alert names the date
    /// being overridden (hard rule 7).
    @State private var confirmDateChange = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(conflict.suggestions.enumerated()), id: \.offset) { index, suggestion in
                button(suggestion, preselected: index == 0)
            }
        }
        .font(.caption.weight(.semibold))
        .alert("Change the date?", isPresented: $confirmDateChange) {
            Button("Change date") { onFixDate() }
            Button("Keep receipt date", role: .cancel) {}
        } message: {
            Text(conflict.dateConfirmationMessage())
        }
        #if DEBUG
        // Screenshot hook: present the override confirmation so a capture can
        // show the sentence that names the receipt's date (simctl cannot tap).
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-screenshotDateConfirmation") {
                confirmDateChange = true
            }
        }
        #endif
    }

    /// One ranked fix. "Fix" focuses the odometer field; "Fix date" opens the
    /// picker, or asks first when the validator marked the change as overriding
    /// a printed receipt date. The preselected fix carries the selected
    /// treatment and the matching accessibility trait, so which one the ranking
    /// prefers is observable.
    @ViewBuilder
    private func button(_ suggestion: TimelineValidator.ResolutionSuggestion,
                        preselected: Bool) -> some View {
        switch suggestion {
        case .fixOdometer:
            Button("Fix") { onFixOdometer() }
                .modifier(F9aFixChip(preselected: preselected))
                .accessibilityIdentifier(odometerFixIdentifier)
        case .fixDate(_, _, let requiresExplicitConfirmation):
            Button("Fix date") {
                if requiresExplicitConfirmation {
                    confirmDateChange = true
                } else {
                    onFixDate()
                }
            }
            .modifier(F9aFixChip(preselected: preselected))
            .accessibilityIdentifier("manualFillUpOdometerFixDateButton")
        case .checkVolume:
            // CHECK 5 (F2 residue): the litres are the likeliest wrong field, so
            // they rank first. "Check", never "Fix" - the app does not know the
            // value is wrong (hard rule 13).
            Button("Check litres") { onFixLiters() }
                .modifier(F9aFixChip(preselected: preselected))
                .accessibilityIdentifier("manualFillUpConsumptionCheckLitersButton")
        case .checkOdometer:
            Button("Check odometer") { onFixOdometer() }
                .modifier(F9aFixChip(preselected: preselected))
                .accessibilityIdentifier("manualFillUpConsumptionCheckOdometerButton")
        }
    }
}

/// The F9a warn row: the amber triangle, the conflict's own sentence (or the
/// catalogue literal), and the ranked fixes. Shared by the fill-up odometer
/// card and the non-fill edit's odometer card so the two surfaces cannot drift
/// (RV.230). The caller supplies the warning's accessibility identifier and the
/// focus closures.
struct F9aWarningRow: View {
    let conflict: OdometerConflict
    let warningIdentifier: String
    let onFixOdometer: () -> Void
    let onFixLiters: () -> Void
    let onFixDate: () -> Void
    var odometerFixIdentifier: String = "manualFillUpOdometerFixButton"

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
            VStack(alignment: .leading, spacing: 8) {
                conflictText
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.warn)
                    .accessibilityIdentifier(warningIdentifier)
                F9aFixRow(conflict: conflict,
                          onFixOdometer: onFixOdometer,
                          onFixLiters: onFixLiters,
                          onFixDate: onFixDate,
                          odometerFixIdentifier: odometerFixIdentifier)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.bottom, 10)
    }

    /// The validator's own wording when it has one (already localised at its
    /// source), else the catalogue literal - reached through the
    /// `LocalizedStringKey` overload, which a coalesced `String?` cannot be.
    @ViewBuilder
    private var conflictText: some View {
        if let quote = conflict.quote {
            Text(quote)
        } else {
            Text("Odometer breaks the timeline – check it.")
        }
    }
}

/// The shared treatment for one ranked F9a fix. The preselected fix is filled
/// with the action token and marked selected; the rest stay quiet text, so the
/// ranking reads at a glance and to a screen reader alike (hard rule 5: accent
/// is meaning, and the trait is the non-colour channel).
private struct F9aFixChip: ViewModifier {
    let preselected: Bool

    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .font(.caption.weight(preselected ? .bold : .semibold))
            .foregroundStyle(Theme.Palette.action)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(preselected ? Theme.Palette.action.opacity(0.14)
                                                   : Theme.Palette.dash))
            .overlay(Capsule().stroke(preselected ? Theme.Palette.action : Theme.Palette.hairline,
                                      lineWidth: preselected ? 1.5 : 1))
            .accessibilityAddTraits(preselected ? .isSelected : [])
    }
}
