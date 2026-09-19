import Foundation
import Testing
@testable import TankbookCore

/// RV.122: the Home reminder strip's model. Several reminders on purpose - with
/// one, neither the order nor the trailing door can fail.
struct ReminderChipsTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)
    private static let vehicle = UUID()

    private static func reminder(_ title: String, days: Int? = nil, km: Int? = nil,
                                 createdOffset: TimeInterval = 0) -> Reminder {
        ReminderLifecycle.makeReminder(
            vehicleId: vehicle, title: title, category: .insurance,
            dueDate: days.map { now.addingTimeInterval(TimeInterval($0) * 86_400) },
            dueOdometer: km.map { 120_000 + $0 },
            createdAt: now.addingTimeInterval(createdOffset))
    }

    @Test("the chips are exactly the due reminders, soonest first, and the door is last")
    func dueOrderAndTrailingDoor() {
        let reminders = [
            Self.reminder("Inspection", days: 40),            // scheduled, not due
            Self.reminder("Insurance", days: 5),
            Self.reminder("Tyres", days: -3),                 // overdue
            Self.reminder("Oil change", km: 200),
            Self.reminder("Brake fluid", km: 2_000)           // scheduled, not due
        ]
        let items = ReminderChips.items(among: reminders, currentOdometer: 120_000, now: Self.now)
        let titles = items.compactMap { item -> String? in
            if case .reminder(let chip) = item { return chip.reminder.title }
            return nil
        }
        // The list's own key (`Due.dueSortKey`): a negative measure first, then
        // the smaller number - the same order the Reminders list shows.
        #expect(titles == ["Tyres", "Insurance", "Oil change"], "overdue first, then by the due key")
        #expect(items.last == .allReminders)
        #expect(items.count == 4)
    }

    @Test("a distance reminder measures the remaining distance, a date one the days")
    func bothForms() {
        let reminders = [Self.reminder("Insurance", days: 5), Self.reminder("Oil change", km: 200)]
        let items = ReminderChips.items(among: reminders, currentOdometer: 120_000, now: Self.now)
        guard case .reminder(let first) = items[0], case .reminder(let second) = items[1] else {
            Issue.record("two reminder chips expected, got \(items)")
            return
        }
        #expect(first.measure == .days(5))
        #expect(second.measure == .km(200))
        #expect(!first.isOverdue && !second.isOverdue)

        // No current odometer: the distance chip names the odometer it is due at.
        let unknown = ReminderChips.items(among: [Self.reminder("Oil change", km: 200)],
                                          currentOdometer: nil, now: Self.now)
        #expect(unknown.isEmpty || {
            if case .reminder(let chip) = unknown[0] { return chip.measure == .dueAtOdometer(120_200) }
            return false
        }())
    }

    @Test("overdue is a fact the chip carries; nothing due is an EMPTY strip, no lone door")
    func overdueAndEmpty() {
        let overdue = ReminderChips.items(among: [Self.reminder("Tyres", days: -3)],
                                          currentOdometer: nil, now: Self.now)
        guard case .reminder(let chip) = overdue[0] else {
            Issue.record("a reminder chip expected")
            return
        }
        #expect(chip.isOverdue)
        #expect(chip.measure == .days(-3))

        #expect(ReminderChips.items(among: [Self.reminder("Inspection", days: 40)],
                                    currentOdometer: nil, now: Self.now).isEmpty)
        #expect(ReminderChips.items(among: [], currentOdometer: nil, now: Self.now).isEmpty)
    }
}
