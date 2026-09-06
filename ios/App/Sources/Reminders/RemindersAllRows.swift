import Foundation
import TankbookCore

/// Builds the merged "all cars" reminder rows (RV.75) from the repository.
/// The ONE place a cross-car row is assembled, shared by the merged Reminders
/// list (RV.75) and RV.76's Home row, so the list's "Needs attention" group
/// and the Home count can never drift apart:
///
/// - the rows come from `liveRemindersAcrossVehicles()` - the single query
///   that can never silently fall back to one car;
/// - a row's km half is judged against ITS OWN car's current odometer
///   (`currentOdometer`), never a shared reading;
/// - terminal rows (`.done`/`.dismissed`) are excluded before grouping, so a
///   completed reminder drops off the count by construction.
///
/// The loader reads only; it never reconciles notifications (that side effect
/// belongs to the Reminders screen, which calls it after loading rows).
enum RemindersAllRows {

    /// The active reminders across every non-archived vehicle as list rows,
    /// each carrying its own car's odometer. Archived cars' rows are excluded
    /// by the query (J13: a sold car's reminders are history, not work for the
    /// coming weekend).
    static func rows(vehicles: [Vehicle],
                     acrossReminders: [Reminder],
                     repository: TankbookRepository) throws -> [ReminderListRow] {
        var merged: [ReminderListRow] = []
        for car in vehicles where !car.archived {
            // The odometer is only needed to judge odometer-driven reminders;
            // a date-only reminder's attention is odometer-independent, so the
            // entry query is skipped for cars whose across reminders are all
            // date-only (Home reads this on every appearance).
            let needsOdometer = acrossReminders.contains {
                $0.vehicleId == car.id && $0.dueOdometer != nil
            }
            let odometer = needsOdometer
                ? try currentOdometer(for: car.id, repository: repository)
                : nil
            let carRows = acrossReminders
                .filter { $0.vehicleId == car.id && ReminderLifecycle.isActive($0) }
                .map { ReminderListRow(reminder: $0, currentOdometer: odometer) }
            merged.append(contentsOf: carRows)
        }
        return merged
    }

    /// The vehicle's current odometer: the latest entry's reading, else its
    /// initial odometer - the same derivation the per-car list used, so the
    /// merged list and Home cannot disagree about a km-driven reminder's state.
    static func currentOdometer(for vehicleId: UUID,
                                repository: TankbookRepository) throws -> Int? {
        let entries = try repository.liveEntries(forVehicle: vehicleId)
        if let reading = entries.compactMap(\.odometer).max() { return reading }
        return try repository.vehicle(id: vehicleId)?.initialOdometer
    }
}
