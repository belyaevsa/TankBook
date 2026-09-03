import SwiftUI
import TankbookCore

/// RV.38 - the notification bell on the tab-root header (docs/JOURNEYS.md F4,
/// amended). A third 44 pt control in the same family as the sync chip and the
/// gear: `dash` fill, hairline stroke, `.title3` glyph - so the three read as
/// one set of "state you should know about" controls rather than an accretion.
///
/// The badge count is a count, never a mere presence: when something is waiting
/// the bell carries the number, and the L4 test asserts that number (asserting
/// "a badge exists" is the vacuous trap named in docs/TASKS.md RV.38). The bell
/// taps to the Inbox screen, which routes to the entry - a second route, never
/// the only place a problem is visible (hard rule 8).
struct InboxBell: View {
    @Environment(AppInbox.self) private var inbox

    private var count: Int { inbox.count }
    private var hasItems: Bool { !inbox.isEmpty }

    var body: some View {
        NavigationLink(value: Route.inbox) {
            Image(systemName: hasItems ? "bell.badge" : "bell")
                .font(.title3)
                .foregroundStyle(hasItems ? Theme.Palette.warn : Theme.Palette.inkSoft)
                .frame(width: 44, height: 44)          // tap target >= 44pt
                .background(Circle().fill(Theme.Palette.dash))
                .overlay(Circle().stroke(Theme.Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if hasItems {
                badge
                    // Inside the frame, never offset out of it (the SyncStateChip
                    // precedent: an offset past the bounds still draws but stops
                    // resolving in the accessibility tree).
                    .offset(x: -2, y: 2)
            }
        }
        .accessibilityIdentifier("inboxBellButton")
        .accessibilityLabel(hasItems ? L10n.inboxItemCount(count) : L10n.inboxTitle)
    }

    /// The count bubble. A NUMBER, not a dot: the inbox is a home for work, so
    /// "how much" matters more than "some". Inside the 44 pt frame's corner
    /// (the circle is inscribed, so the corner is empty space the badge can sit
    /// in and still read as riding the bell's edge). `verbatim` because a count
    /// is a number, never localised copy (hard rule 10: only phrases translate).
    private var badge: some View {
        Text(verbatim: "\(count)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.Palette.midnight)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(Theme.Palette.warn))
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("inboxBellBadge")
            .accessibilityLabel(Text(verbatim: "\(count)"))
    }
}
