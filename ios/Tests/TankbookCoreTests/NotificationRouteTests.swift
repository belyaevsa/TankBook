import Foundation
import Testing
@testable import TankbookCore

/// PJ.5 identifier -> route mapping tests (docs/NOTIFICATIONS.md -> "Tap lands
/// on", docs/SCREENMAP.md). The mapping is a pure function over the identifier
/// string, so it tests as data - the same split P3.6 established for the
/// planning layer. These assert the ROUTE a tap resolves to, never that a
/// function returns: an L1 that pins the mapping is the difference between a
/// deep link that exists and one that merely compiles (the app has no unit-test
/// target; anything in `ios/App` is only reachable by XCUITest, which asserts
/// behaviour and never values - the P3.7 lesson, `TabBarMetrics`).
///
/// Three rules the tests exist to pin:
/// 1. `reminder.<uuid>.<kind>` routes to Reminders for THAT reminder, whatever
///    the kind (the kind is format, never destination).
/// 2. `monthly-summary.*` routes to Trends.
/// 3. Unknown and malformed identifiers are `.none` - the app opens normally,
///    routes nowhere, and never dead-ends (hard rule 7: a stale notification is
///    not a trap).
@Suite struct NotificationRouteTests {

    @Test func reminderIdentifierRoutesToItsReminder() {
        let id = UUID()
        #expect(NotificationRouteParser.resolve(identifier: "reminder.\(id.uuidString).date")
                    == .reminder(id))
        #expect(NotificationRouteParser.resolve(identifier: "reminder.\(id.uuidString).odometer")
                    == .reminder(id))
        #expect(NotificationRouteParser.resolve(identifier: "reminder.\(id.uuidString).overdue")
                    == .reminder(id))
    }

    /// The identifier's UUID is the destination - two reminders produce two
    /// different routes, so dropping the id could never route to the right one.
    @Test func twoReminderIdentifiersRouteToTheirOwnReminders() {
        let first = UUID()
        let second = UUID()
        #expect(NotificationRouteParser.resolve(
            identifier: "reminder.\(first.uuidString).date") == .reminder(first))
        #expect(NotificationRouteParser.resolve(
            identifier: "reminder.\(second.uuidString).overdue") == .reminder(second))
    }

    @Test func monthlySummaryRoutesToTrends() {
        let vehicleID = UUID()
        #expect(NotificationRouteParser.resolve(
            identifier: "monthly-summary.\(vehicleID.uuidString).2026-08") == .trends)
        // The `monthly-summary.*` glob: any identifier of that family lands on
        // Trends - the vehicle and month are payload, never the destination.
        #expect(NotificationRouteParser.resolve(identifier: "monthly-summary.anything") == .trends)
    }

    @Test func unknownIdentifiersAreInert() {
        #expect(NotificationRouteParser.resolve(identifier: "some.other.identifier") == .none)
        #expect(NotificationRouteParser.resolve(identifier: "com.apple.reminders") == .none)
        #expect(NotificationRouteParser.resolve(identifier: "tankbook") == .none)
    }

    @Test func malformedIdentifiersAreInert() {
        // No dots.
        #expect(NotificationRouteParser.resolve(identifier: "reminder") == .none)
        #expect(NotificationRouteParser.resolve(identifier: "monthly-summary") == .none)
        // A bad UUID.
        #expect(NotificationRouteParser.resolve(identifier: "reminder.not-a-uuid.date") == .none)
        // Missing the kind component.
        #expect(NotificationRouteParser.resolve(identifier: "reminder.\(UUID().uuidString)") == .none)
        // A kind this app version does not produce - malformed, never guessed at.
        #expect(NotificationRouteParser.resolve(
            identifier: "reminder.\(UUID().uuidString).fiscal") == .none)
        // Empty.
        #expect(NotificationRouteParser.resolve(identifier: "") == .none)
    }
}
