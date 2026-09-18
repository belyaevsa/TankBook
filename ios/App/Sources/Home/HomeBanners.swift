import SwiftUI
import TankbookCore
import UIKit

// MARK: - Banners (S5 / reminder)

/// The error/warning surfaces that can sit above Home content. S5 is a sync
/// fixture until P4.7; the reminder strip is REAL data (PJ.4, RV.122) - it
/// derives from the active reminders (`ReminderChips.items`, hard rule 2's
/// spirit), so a production build reaches it with no launch argument. Each
/// names its next step (docs/ERRORS.md -> Home).
///
/// The S2 possible-duplicate card is NOT here anymore: since P1.8 it is real
/// data - the combined card lives in the log stream (LogStream's `.duplicate`
/// row), because a duplicate is now detected from the entries themselves rather
/// than presented as a fixture.
struct HomeBanners: View {
    let presentables: HomePresentables
    let vehicleName: String
    /// RV.122: the due reminders as chips, derived at read time
    /// (`ReminderChips.items`); empty hides the strip entirely - presence IS
    /// the derivation, never a flag. This replaced PJ.4's single banner: a
    /// driver with three things due sees three chips, not one and a number.
    var reminderChips: [ReminderChipItem] = []

    var body: some View {
        VStack(spacing: 8) {
            if presentables.archivedReturned {
                archivedReturnedCard
            }
            HomeReminderChips(items: reminderChips)
        }
    }

    private var archivedReturnedCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "archivebox")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            VStack(alignment: .leading, spacing: 8) {
                Text("\(vehicleName) came back with 1 new entry – stays archived.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                HStack(spacing: 14) {
                    Button("Delete again") {}
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Palette.action)
                        .accessibilityIdentifier("homeDeleteAgainButton")
                    Button("Keep") {}
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Palette.action)
                        .accessibilityIdentifier("homeKeepButton")
                }
                .font(.caption.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .formCard()
    }
}

// MARK: - The reminders entry row (RV.76)

/// The calm door into Reminders (design/screens/RemindersEntry.dc.html): a
/// permanent Home row, present whether or not anything is due, that navigates
/// to the merged all-cars list - it never creates (a `+` here could only guess
/// the car, hard rule 13, or open the form one tap later than the list's own
/// card). It is deliberately placed directly below the urgent banner strip in
/// `HomeView.fullLayout`, so the calm path is always the next thing under the
/// amber one and never scrolls below the fold.
///
/// The count is the point: the amber chip ("2 due") is what makes the row worth
/// a tap, and it is derived at read time (hard rule 2) from the same live rows
/// the merged list groups - never stored, never seeded as a number. It renders
/// only when something is actually due: amber is attention (hard rule 5), so a
/// chip that showed "0 due" would be a warning that warns about nothing. At
/// zero the row is the plain calm doorway; the count's voice is the chip.
struct HomeRemindersEntryRow: View {
    /// How many live reminders across every active car demand attention.
    let attentionCount: Int

    var body: some View {
        NavigationLink(value: Route.remindersAll) {
            HStack(spacing: 12) {
                Image(systemName: "bell")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Reminders")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("Across all your cars")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                Spacer(minLength: 8)
                if attentionCount > 0 {
                    Text(countText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.Palette.warn)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.Palette.warn.opacity(0.12)))
                        .accessibilityIdentifier("homeRemindersDueCount")
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft.opacity(0.7))
            }
            .contentShape(Rectangle())
            .padding(14)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("homeRemindersRow")
    }

    /// "2 due" - a full localized count phrase (real Russian plural rules: 2
    /// needs «напоминания», never «напоминаний»), never concatenation.
    private var countText: String {
        String(localized: "\(attentionCount) due")
    }
}

// MARK: - Sync toast (S7)

/// The post-outage sync toast (docs/ERRORS.md -> Home, row S7). Fixture-driven
/// until P4.7; the tap-to-Log-filtered path lands with the Log stream (P1.5).
struct HomeSyncToast: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(Theme.Palette.taillight)
            Text("Synced. 2 entries need a look")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .accessibilityIdentifier("homeSyncToast")
    }
}
