import SwiftUI
import TankbookCore

/// The ranked resolution fixes under an F9a odometer warning. The ORDER is the
/// validator's (`OdometerConflict.suggestions`), never re-derived here: the
/// first-ranked fix is preselected, and a date change the validator marked as
/// overriding a printed receipt date asks first, naming that date (docs/
/// JOURNEYS.md F9a; docs/SCHEMA.md, PRIORITY; hard rule 7). Shared by the
/// Confirm sheet and the Edit-entry fill screen through
/// `ManualFillUpOdometerCard`.
struct F9aFixRow: View {
    let conflict: OdometerConflict
    @FocusState.Binding var focus: ManualFillUpFocus?
    let onFixDate: () -> Void

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
            Button("Fix") { focus = .odometer }
                .modifier(F9aFixChip(preselected: preselected))
                .accessibilityIdentifier("manualFillUpOdometerFixButton")
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
            Button("Check litres") { focus = .liters }
                .modifier(F9aFixChip(preselected: preselected))
                .accessibilityIdentifier("manualFillUpConsumptionCheckLitersButton")
        case .checkOdometer:
            Button("Check odometer") { focus = .odometer }
                .modifier(F9aFixChip(preselected: preselected))
                .accessibilityIdentifier("manualFillUpConsumptionCheckOdometerButton")
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
