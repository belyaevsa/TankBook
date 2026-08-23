import Foundation

/// Presentation fixtures for Home states whose data arrives with sync (P4) -
/// the S5 archived-car notice, S7 sync toast and the reminder-due banner. Each
/// is reachable via a launch argument so the state is snapshot- and
/// UI-testable, exactly as P1.2 (`-forceCatalogUnavailable`) and P1.3
/// (`-forceCurrencyLowConfidence`) did for their sync-dependent states. None of
/// these is real data: they are fixtures, and Home renders them only while the
/// fixture flag is up (docs/ERRORS.md -> Home, rows S5/S7 and the reminder
/// banner).
///
/// The S2 possible-duplicate card used to be a fixture here; since P1.8 it is
/// REAL data - the heuristic runs over the seeded entries and the combined card
/// renders from LogStream (see `-seedHomeDuplicate`), so a duplicate no longer
/// needs a presentation flag.
struct HomePresentables {
    /// Guest chrome (design/screens/GuestHome.dc.html): the app has no account
    /// system until P4, so this is reachable only through `-forceGuestHome`.
    var guest = false
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
            archivedReturned: arguments.contains("-forceArchivedReturned"),
            syncToast: arguments.contains("-forceSyncToast"),
            reminderDue: arguments.contains("-forceReminderDue"))
    }
}
