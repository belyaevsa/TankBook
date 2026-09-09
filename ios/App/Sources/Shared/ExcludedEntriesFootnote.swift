import SwiftUI
import TankbookCore

/// The "N entries excluded" footnote shared by Home and Trends (docs/ERRORS.md
/// -> Home, rows F9a/S2; -> Trends). The count is derived from the engine's
/// flags by the caller, never hard-coded, and the wording uses real plural rules
/// per language (Russian has three forms - 1 запись / 2 записи / 5 записей) via
/// the String Catalog.
///
/// The footnote IS the route to the excluded entries on both screens (hard rule
/// 7: every warning names its next step). RV.141: the caller chooses the
/// destination - the single excluded entry when exactly one is out, the
/// excluded-entries list (`ExcludedEntriesView`) when more than one is - because
/// a route that opened ONE entry could never reach the other N-1.
struct ExcludedEntriesFootnote: View {
    let count: Int
    let identifier: String
    /// Where the footnote leads; `nil` renders a passive caption instead of a
    /// link. Callers pass a destination whenever the count is non-zero.
    var destination: Route?

    var body: some View {
        Group {
            if let destination {
                NavigationLink(value: destination) {
                    label
                }
                .buttonStyle(.plain)
                .accessibilityHint(L10n.localize("Shows the excluded entries"))
                .accessibilityIdentifier(identifier + "Button")
            } else {
                label
            }
        }
    }

    private var label: some View {
        Text(L10n.entriesExcluded(count))
            .font(.caption2)
            .foregroundStyle(Theme.Palette.warn)
            .accessibilityIdentifier(identifier)
    }
}
