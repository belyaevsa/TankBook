import Foundation

/// Presentation fixtures for Home states whose data arrives with sync (P4) -
/// the S2 duplicate card, S5 archived-car notice, S7 sync toast and the
/// reminder-due banner. Each is reachable via a launch argument so the state is
/// snapshot- and UI-testable, exactly as P1.2 (`-forceCatalogUnavailable`) and
/// P1.3 (`-forceCurrencyLowConfidence`) did for their sync-dependent states.
/// None of these is real data: they are fixtures, and Home renders them only
/// while the fixture flag is up (docs/ERRORS.md -> Home, rows S2/S5/S7 and the
/// reminder banner).
struct HomePresentables {
    /// Guest chrome (design/screens/GuestHome.dc.html): the app has no account
    /// system until P4, so this is reachable only through `-forceGuestHome`.
    var guest = false
    /// Possible duplicate (S2): "Shell, 42.3 L logged twice".
    var duplicateCard = false
    /// Archived car returned via sync (S5): "…came back with 1 new entry – stays archived."
    var archivedReturned = false
    /// Post-outage sync batch (S7): "Synced. 2 entries need a look".
    var syncToast = false
    /// Reminder due: "Insurance renews in 12 days".
    var reminderDue = false

    static func fromLaunchArguments(
        _ arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> HomePresentables {
        HomePresentables(
            guest: arguments.contains("-forceGuestHome"),
            duplicateCard: arguments.contains("-forceDuplicateCard"),
            archivedReturned: arguments.contains("-forceArchivedReturned"),
            syncToast: arguments.contains("-forceSyncToast"),
            reminderDue: arguments.contains("-forceReminderDue"))
    }
}
