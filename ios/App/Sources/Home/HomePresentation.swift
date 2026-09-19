import Foundation

/// Presentation fixtures for Home states whose data arrives with sync (P4) -
/// the S5 archived-car notice and S7 sync toast. Each is reachable via a launch
/// argument so the state is snapshot- and UI-testable, exactly as P1.2
/// (`-forceCatalogUnavailable`) and P1.3 (`-forceCurrencyLowConfidence`) did
/// for their sync-dependent states. None of these is real data: they are
/// fixtures, and Home renders them only while the fixture flag is up
/// (docs/ERRORS.md -> Home, rows S5 and S7).
///
/// The S2 possible-duplicate card used to be a fixture here; since P1.8 it is
/// REAL data - the heuristic runs over the seeded entries and the combined card
/// renders from LogStream (see `-seedHomeDuplicate`), so a duplicate no longer
/// needs a presentation flag.
///
/// Guest chrome used to be a fixture here too (`-forceGuestHome`). Since PJ.3
/// it is REAL data: the guest Home is what a no-account user sees, reached for
/// real from the Welcome root's "Add your car" path, and driven by the session
/// state (`sync.session == nil`), never by a launch flag.
///
/// The reminder banner used to be a fixture here too (`-forceReminderDue`).
/// Since PJ.4 it is REAL data (the RV.122 chip strip): `ReminderChips.items`
/// derives it from the live reminders at read time, so a Release build reaches the Reminders
/// screen with no launch argument (the reason `-forceReminderDue` existed).
struct HomePresentables {
    /// Post-outage sync batch (S7): "Synced. 2 entries need a look".
    var syncToast = false

    static func fromLaunchArguments(
        _ arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> HomePresentables {
        HomePresentables(syncToast: arguments.contains("-forceSyncToast"))
    }
}
