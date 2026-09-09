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
///
/// The two branches differ visibly: amber is attention, never action (hard rule
/// 5), so the link's affordance is the app's one "leads somewhere" vocabulary -
/// the trailing `chevron.right` in `inkSoft` (docs/DESIGN.md -> "A row that
/// navigates carries the chevron") - never a recolour. The passive caption stays
/// text alone; a chevron on both branches would restore the byte-identical
/// defect this view exists to avoid.
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
                    HStack(spacing: 4) {
                        label
                        chevron
                    }
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

    /// The affordance is chrome, never content: it never enters the button's own
    /// label, which keeps speaking exactly the count phrase (docs/DESIGN.md ->
    /// "A row that navigates carries the chevron"; pinned by the exact-label UI
    /// test). Its identifier exists so the UI test that pins "the link case and
    /// the passive case are visibly different" can find the glyph.
    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.Palette.inkSoft)
            .accessibilityIdentifier(identifier + "Chevron")
    }
}
