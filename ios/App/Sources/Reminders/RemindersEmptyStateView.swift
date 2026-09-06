import SwiftUI
import TankbookCore

/// The Reminders list's empty state (design/screens/RemindersEmpty.dc.html):
/// the discovery path, so its ONE action is loud - a FILLED "New reminder"
/// primary button, never the dashed card, which is this app's idiom for "add
/// one more" at the END of a populated list and reads as an empty slot rather
/// than an invitation on a screen with nothing on it (docs/SCREENMAP.md ->
/// "Reminders across cars"). The dashed card keeps its job once rows exist;
/// the screen omits it here so it cannot offer two different weights for the
/// same action.
///
/// Opened from the merged list the form asks which car; from a car's own list
/// it arrives with that car filled (hard rule 13 - the opener's intent, never
/// a guess). The opener decides by handing the same `createRoute` the dashed
/// card would use.
struct RemindersEmptyStateView: View {
    /// Where "New reminder" opens - the caller's create route (car-empty on
    /// the merged list, pre-filled on a car's own list).
    let createRoute: Route

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell")
                .font(.system(size: 22))
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("Nothing to remember yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.center)
            Text("Insurance, the next oil change, the tyre swap – a date, an odometer, or both.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.center)
            NavigationLink(value: createRoute) {
                Text("New reminder")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.Palette.midnight)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.Palette.taillight)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .accessibilityIdentifier("remindersEmptyNewReminderButton")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminderEmptyState")
    }
}
