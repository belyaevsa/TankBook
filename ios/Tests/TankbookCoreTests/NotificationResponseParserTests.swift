import Foundation
import Testing
@testable import TankbookCore

/// RV.78 action-response mapping tests (docs/NOTIFICATIONS.md -> the actions).
/// The mapping is a pure function over the platform strings, so it tests as
/// data (docs/TESTING.md L1) - the same split PJ.5 established for
/// `NotificationRouteParser`. The rules these pin:
///
/// 1. A plain tap (default action) and **Mark done** both OPEN the screen the
///    request identifier promises - the completion sheet for a reminder.
///    Mark done is never a silent `.done(nil)`: declining the cost log is the
///    sheet's choice to present, not the banner's to make (J7c).
/// 2. **Push a week** on a reminder is a `.snooze` - no screen; on anything
///    else it is inert.
/// 3. A dismissal, an unknown action, or an unresolvable identifier is `.none`
///    - the app opens normally and routes nowhere (hard rule 7).
@Suite struct NotificationResponseParserTests {

    private func id() -> UUID { UUID() }

    @Test func aTapOpensWhereverTheIdentifierPromises() {
        let reminder = id()
        #expect(NotificationResponseParser.resolve(
            actionIdentifier: nil,
            requestIdentifier: "reminder.\(reminder.uuidString).date") == .open(.reminder(reminder)))
        #expect(NotificationResponseParser.resolve(
            actionIdentifier: NotificationResponseParser.defaultActionIdentifier,
            requestIdentifier: "reminder.\(reminder.uuidString).overdue") == .open(.reminder(reminder)))
    }

    /// The one-code-path rule: Mark done resolves to the SAME open decision a
    /// tap does - there is no separate completion transition for the banner to
    /// drift from the sheet's (`ReminderLifecycle.complete`). The completion
    /// sheet is where the "log the cost?" choice is presented, so the action
    /// that says "done" hands the user that choice instead of making it.
    @Test func markDoneOpensTheCompletionSheetLikeATap() {
        let reminder = id()
        let tap = NotificationResponseParser.resolve(
            actionIdentifier: nil,
            requestIdentifier: "reminder.\(reminder.uuidString).date")
        let markDone = NotificationResponseParser.resolve(
            actionIdentifier: ReminderBannerAction.complete.rawValue,
            requestIdentifier: "reminder.\(reminder.uuidString).date")
        #expect(markDone == tap,
                "Mark done and a tap must share one decision, never a second completion path")
        #expect(markDone == .open(.reminder(reminder)))
    }

    @Test func pushAWeekOnAReminderIsASnooze() {
        let reminder = id()
        #expect(NotificationResponseParser.resolve(
            actionIdentifier: ReminderBannerAction.snooze.rawValue,
            requestIdentifier: "reminder.\(reminder.uuidString).date") == .snooze(reminder))
        #expect(NotificationResponseParser.resolve(
            actionIdentifier: ReminderBannerAction.snooze.rawValue,
            requestIdentifier: "reminder.\(reminder.uuidString).odometer") == .snooze(reminder))
    }

    @Test func dismissIsInert() {
        let reminder = id()
        #expect(NotificationResponseParser.resolve(
            actionIdentifier: NotificationResponseParser.dismissActionIdentifier,
            requestIdentifier: "reminder.\(reminder.uuidString).date") == .none,
            "swiping a banner away is not a request to open the app")
    }

    @Test func unknownActionIdentifiersAreInert() {
        let reminder = id()
        #expect(NotificationResponseParser.resolve(
            actionIdentifier: "com.apple.UNNotificationActionIdentifierSomewhereElse",
            requestIdentifier: "reminder.\(reminder.uuidString).date") == .none)
        #expect(NotificationResponseParser.resolve(
            actionIdentifier: "reminder.action.fiscal",
            requestIdentifier: "reminder.\(reminder.uuidString).date") == .none,
            "an action this build does not register is never guessed at")
    }

    @Test func snoozeOnANonReminderIsInert() {
        let vehicle = id()
        #expect(NotificationResponseParser.resolve(
            actionIdentifier: ReminderBannerAction.snooze.rawValue,
            requestIdentifier: "monthly-summary.\(vehicle.uuidString).2026-08") == .none,
            "a monthly summary has no due to push")
    }

    @Test func actionsOnUnresolvableIdentifiersAreInert() {
        let reminder = id()
        for action in [nil, ReminderBannerAction.complete.rawValue, ReminderBannerAction.snooze.rawValue] {
            #expect(NotificationResponseParser.resolve(
                actionIdentifier: action,
                requestIdentifier: "reminder.not-a-uuid.date") == .none)
            #expect(NotificationResponseParser.resolve(
                actionIdentifier: action,
                requestIdentifier: "reminder.\(reminder.uuidString)") == .none,
                "a malformed identifier stays inert even under an action")
            #expect(NotificationResponseParser.resolve(
                actionIdentifier: action,
                requestIdentifier: "not-a-notification") == .none)
        }
    }

    /// The stable identifiers: the registered category, the request's
    /// `categoryIdentifier`, and the response's `actionIdentifier` must all
    /// agree. These are the strings a category-format change would silently
    /// break across three files, so the two actions and the category id are
    /// pinned as a set.
    @Test func theActionIdentifiersAreTheStableContract() {
        #expect(Set(ReminderBannerAction.allCases.map(\.rawValue))
                    == ["reminder.action.complete", "reminder.action.snooze"])
        #expect(ReminderBannerAction.categoryIdentifier == "reminder.actions")
        #expect(ReminderBannerAction.allCases.count == 2)
    }
}
