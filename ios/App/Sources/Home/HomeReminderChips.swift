import SwiftUI
import TankbookCore

// MARK: - The reminder chip strip (RV.122, docs/JOURNEYS.md J7c)

/// A horizontal strip across the top of Home: one chip per due reminder of
/// this car - the title, and under it what is coming and when or how far
/// ("in 12 days", "in 420 km", "Overdue · 3 days ago") - and, last, the
/// door to the merged all-cars list, a chip like the others so the door looks
/// like one. Amber is attention and overdue is still amber (hard rule 5); the
/// words carry "overdue". With nothing due the strip is ABSENT - the calm
/// Reminders row below is the door then, and an empty strip would warn about
/// nothing. Tapping a chip lands on that reminder in the merged list
/// (`Route.reminderDeepLink`).
struct HomeReminderChips: View {
    let items: [ReminderChipItem]

    var body: some View {
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        switch item {
                        case .reminder(let chip):
                            NavigationLink(value: Route.reminderDeepLink(chip.reminder.id)) {
                                reminderChip(chip)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("homeReminderChip_\(chip.reminder.id.uuidString)")
                            .accessibilityLabel(HomeReminderChipFormat.accessibilityLabel(chip))
                        case .allReminders:
                            NavigationLink(value: Route.remindersAll) {
                                allChip
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("homeReminderChipAll")
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .accessibilityIdentifier("homeReminderChips")
        }
    }

    private func reminderChip(_ chip: ReminderChip) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(chip.reminder.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.warn)
                .lineLimit(1)
            Text(HomeReminderChipFormat.measure(chip))
                .font(.caption2)
                .foregroundStyle(Theme.Palette.warn.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Theme.Palette.warn.opacity(0.12)))
        .contentShape(Capsule())
    }

    private var allChip: some View {
        HStack(spacing: 4) {
            Text("All reminders")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.action)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.Palette.action)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 38)
        .background(Capsule().fill(Theme.Palette.dash))
        .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
        .contentShape(Capsule())
    }
}

/// The chip's second line, one whole localised phrase per form (never
/// concatenation): the days-plural key the banner used, a km phrase that
/// never declines, and the odometer form when the car's reading is unknown.
/// Overdue prefixes the honest word the list and the notification use.
enum HomeReminderChipFormat {
    static func measure(_ chip: ReminderChip) -> String {
        switch chip.measure {
        case .days(let days) where days < 0:
            return String(format: L10n.localize("Overdue · %@"), String(localized: "\(-days) days ago"))
        case .days(let days):
            return String(localized: "in \(days) days")
        case .km(let km) where km < 0:
            return String(format: L10n.localize("%lld km overdue"), -km)
        case .km(let km):
            return String(format: L10n.localize("in %lld km"), km)
        case .dueAtOdometer(let odometer):
            return String(format: L10n.localize("Due at %1$@ km"), OdometerFormat.grouped(odometer))
        }
    }

    static func accessibilityLabel(_ chip: ReminderChip) -> String {
        "\(chip.reminder.title), \(measure(chip))"
    }
}
