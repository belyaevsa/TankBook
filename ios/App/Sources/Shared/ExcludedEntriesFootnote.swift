import SwiftUI
import TankbookCore

/// The "N entries excluded" footnote shared by Home and Trends (docs/ERRORS.md
/// -> Trends: "Footnote 'N entries excluded' ... Tap -> the flagged entry").
///
/// The count is derived from the engine's flags by the caller, never
/// hard-coded, and the wording uses real plural rules per language (Russian has
/// three forms - 1 запись / 2 записи / 5 записей) via the String Catalog.
///
/// On Trends the footnote is the route to the flagged entry (hard rule 7:
/// every warning names its next step); on Home it stays the passive caption it
/// has always been, so the two screens share one component without Home
/// changing behaviour.
struct ExcludedEntriesFootnote: View {
    let count: Int
    let identifier: String
    /// The flagged entry the footnote opens; `nil` renders a passive caption
    /// (Home) instead of a link.
    var destination: Route?

    var body: some View {
        Group {
            if let destination {
                NavigationLink(value: destination) {
                    label
                }
                .buttonStyle(.plain)
                .accessibilityHint(L10n.localize("Opens the excluded entry"))
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
