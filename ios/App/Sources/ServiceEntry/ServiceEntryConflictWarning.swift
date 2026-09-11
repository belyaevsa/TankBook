import SwiftUI
import TankbookCore

/// The PJ.11 F9a warning on the ServiceEntry odometer card: the record's
/// odometer breaks the car's timeline, so it would save flagged (and its
/// segments excluded). Amber only - the save is never blocked (hard rules 5 and
/// 13: an implausible value is a warning, never a refusal). "Fix" focuses the
/// odometer; the quote names the conflicting entry when the order check has one.
///
/// The fix list comes from the form state through `F9aFixPresentation` (RV.211):
/// a service presents the single odometer fix, not the fill-up's ranked list.
struct ServiceEntryConflictWarning: View {
    let conflict: OdometerConflict
    let onFix: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.warn)
                conflictText
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.warn)
                    .accessibilityIdentifier("serviceEntryOdometerConflictWarning")
            }
            ForEach(Array(fixes.enumerated()), id: \.offset) { _, suggestion in
                if case .fixOdometer = suggestion {
                    Button("Fix", action: onFix)
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Palette.action)
                        .accessibilityIdentifier("serviceEntryOdometerConflictFixButton")
                }
            }
        }
        .padding(.top, 2)
    }

    /// The policy's list, with the odometer fix as the floor so a caller that
    /// does not populate `suggestions` still gets the documented next step.
    private var fixes: [TimelineValidator.ResolutionSuggestion] {
        conflict.suggestions.isEmpty
            ? F9aFixPresentation.fixes([], for: .service)
            : conflict.suggestions
    }

    /// The validator's wording when it has one, else the catalogue literal -
    /// via the `LocalizedStringKey` overload, which a coalesced `String?` can't.
    @ViewBuilder
    private var conflictText: some View {
        if let quote = conflict.quote {
            Text(quote)
        } else {
            Text("Odometer breaks the timeline – check it.")
        }
    }
}
