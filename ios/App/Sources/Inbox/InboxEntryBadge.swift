import SwiftUI
import TankbookCore

/// RV.38: the entry's OWN badge while an inbox item is pending - the bell on
/// the header is a SECOND route to the entry, never the only place the offer is
/// visible (hard rule 8). Renders as a warn `doc.text.magnifyingglass` chip
/// beside the entry, tapping through to the same Edit entry the row opens.
struct InboxEntryBadge: View {
    let entryID: UUID

    var body: some View {
        NavigationLink(value: Route.editEntry(entryID)) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.Palette.warn)
                .padding(6)
                .background(Circle().fill(Theme.Palette.warn.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inboxEntryBadge")
        .accessibilityLabel(L10n.inboxReceiptReady)
    }
}
