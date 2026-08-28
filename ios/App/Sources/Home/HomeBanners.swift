import SwiftUI
import TankbookCore
import UIKit

// MARK: - Banners (S5 / reminder)

/// The error/warning surfaces that can sit above Home content. S5 and the
/// reminder banner are fixture-driven until sync (P4) and reminders (P3.4)
/// exist; each names its next step (docs/ERRORS.md -> Home).
///
/// The S2 possible-duplicate card is NOT here anymore: since P1.8 it is real
/// data - the combined card lives in the log stream (LogStream's `.duplicate`
/// row), because a duplicate is now detected from the entries themselves rather
/// than presented as a fixture.
struct HomeBanners: View {
    let presentables: HomePresentables
    let vehicleName: String

    var body: some View {
        VStack(spacing: 8) {
            if presentables.archivedReturned {
                archivedReturnedCard
            }
            if presentables.reminderDue {
                reminderBanner
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

    private var reminderBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "bell")
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
            Text("Insurance renews in 12 days")
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
