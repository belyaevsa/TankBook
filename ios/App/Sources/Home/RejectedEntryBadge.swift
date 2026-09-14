import SwiftUI
import TankbookCore

/// RV.284: the entry's OWN badge while its row is in the `rejected` sync state -
/// the server refused it structurally, so it re-pushes only after an edit. A
/// `icloud.slash` chip (distinct from the conflict chevron and the inbox bell),
/// tapping through to the same Edit entry the row opens. The accessibility
/// label is the next step (hard rule 7): "update the app or edit it to retry".
struct RejectedEntryBadge: View {
    let entryID: UUID

    var body: some View {
        NavigationLink(value: Route.editEntry(entryID)) {
            Image(systemName: "icloud.slash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.warn)
                .padding(6)
                .background(Circle().fill(Theme.Palette.warn.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rejectedEntryBadgeButton")
        .accessibilityLabel(L10n.rejectedEntryBadgeLabel)
    }
}
