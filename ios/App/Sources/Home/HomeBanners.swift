import SwiftUI
import TankbookCore
import UIKit

// MARK: - Banners (S5 / reminder)

/// The error/warning surfaces that can sit above Home content. S5 is a sync
/// fixture until P4.7; the reminder banner is REAL data since PJ.4 - it derives
/// from the active reminders (`ReminderBanner.bannerReminder`, hard rule 2's
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
    /// PJ.4: the earliest attention-due reminder, derived at read time. `nil`
    /// hides the banner entirely - presence IS the derivation, never a flag.
    var bannerReminder: Reminder?
    /// The vehicle's current odometer, for a km-driven reminder's banner text.
    var currentOdometer: Int?

    var body: some View {
        VStack(spacing: 8) {
            if presentables.archivedReturned {
                archivedReturnedCard
            }
            if let bannerReminder {
                reminderBanner(bannerReminder)
            }
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

    private func reminderBanner(_ reminder: Reminder) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "bell")
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
            Text(HomeReminderBannerFormat.title(for: reminder, currentOdometer: currentOdometer))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.warn)
            Spacer(minLength: 0)
            NavigationLink(value: Route.reminders) {
                Text("View")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
            }
            .accessibilityIdentifier("homeReminderViewButton")
        }
        .padding(14)
        .formCard()
    }
}

// MARK: - The banner's real reminder text

/// Composes the banner sentence from a real reminder (PJ.4): the title plus the
/// attention metric that put it in the window - "Insurance renewal in 12 days",
/// "Oil change within 420 km", "Overdue: Inspection". Every phrase is a full
/// localised catalogue phrase per language (the RU pass on P1.4 proved composed
/// strings need their own phrase): the title sits in the nominative head, the
/// count-bearing sub-phrase carries real Russian plural rules (`%@ in %lld
/// days` is a plural key, asserted at 1/2/5/11/21), and the overdue form puts
/// the title behind a colon so nothing governs its case (docs/LOCALIZATION.md).
enum HomeReminderBannerFormat {
    static func title(for reminder: Reminder,
                      currentOdometer: Int?,
                      now: Date = Date()) -> String {
        switch ReminderLifecycle.due(reminder) {
        case .date(let date):
            let days = ReminderLifecycle.daysRemaining(until: date, from: now)
            if days < 0 {
                return overdue(title: reminder.title)
            }
            return String(localized: "\(reminder.title) in \(days) days")
        case .odometer(let odometer):
            guard let km = ReminderLifecycle.kmRemaining(until: odometer, from: currentOdometer) else {
                return String(format: L10n.localize("Due at %1$@ km"),
                              OdometerFormat.grouped(odometer))
            }
            if km < 0 {
                return overdue(title: reminder.title)
            }
            return within(title: reminder.title, km: km)
        case .both(let date, let odometer):
            let days = ReminderLifecycle.daysRemaining(until: date, from: now)
            let km = ReminderLifecycle.kmRemaining(until: odometer, from: currentOdometer)
            // Whichever-comes-first, the same metric the list's attention chip
            // picks: the km half drives when the date is still far out.
            if let km, days > ReminderLifecycle.attentionWindowDays {
                if km < 0 { return overdue(title: reminder.title) }
                return within(title: reminder.title, km: km)
            }
            if days < 0 {
                return overdue(title: reminder.title)
            }
            return String(localized: "\(reminder.title) in \(days) days")
        case nil:
            return reminder.title
        }
    }

    /// "Overdue: Insurance renewal" - the title behind a colon (nominative, no
    /// preposition governs it), the same honest word the list and the
    /// notification use (docs/ERRORS.md -> Reminders).
    private static func overdue(title: String) -> String {
        String(format: L10n.localize("Overdue: %@"), title)
    }

    /// "Oil change within 420 km" - the km-count phrase is app-formatted and
    /// never declines (docs/LOCALIZATION.md).
    private static func within(title: String, km: Int) -> String {
        String(format: L10n.localize("%1$@ within %2$@"),
               title, String(format: L10n.localize("%lld km"), km))
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
