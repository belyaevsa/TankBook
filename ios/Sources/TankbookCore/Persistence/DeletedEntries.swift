import Foundation

/// A tombstoned entry on the Recently deleted screen (docs/SCREENMAP.md,
/// docs/SYNC.md S1/S4: the losing version is kept as the local 30-day undo
/// log). Wraps the entry plus the facts the screen renders: when it was deleted
/// and, when sync says so, which device deleted it.
///
/// The device attribution ("removed on iPad") is real sync data (docs/SCHEMA.md
/// -> Identifiers & sync envelope: "Author attribution ... comes from the sync
/// record's `origin_device`/account, not domain fields"), so until P4 it is nil
/// here and the app target drives it with a presentation fixture.
public struct DeletedEntry: Identifiable {
    public let entry: any Entry
    /// The tombstone stamp. `entry.deletedAt` is authoritative; `updatedAt`
    /// stands in for a live entry passed by mistake (the repository only hands
    /// out tombstones, so this is defensive).
    public let deletedAt: Date
    /// The device that deleted the entry; nil = deleted on this device. Real
    /// value arrives with sync (P4).
    public let deletedOnDevice: String?

    public var id: UUID { entry.id }
    public var vehicleId: UUID { entry.vehicleId }

    public init(entry: any Entry, deletedOnDevice: String? = nil) {
        self.entry = entry
        self.deletedAt = entry.deletedAt ?? entry.updatedAt
        self.deletedOnDevice = deletedOnDevice
    }
}

/// A tombstoned reminder on the Recently deleted screen (PJ.7). A reminder is
/// an `Entity`, not an `Entry` - it has no `date`/`money` - so it cannot ride in
/// `DeletedEntry`; this is the parallel shape the screen renders beside the
/// entry list, with the same 30-day countdown and the same Restore path
/// (`restoreReminder`, which clears the tombstone so the row re-enters the
/// Reminders list with its status and recurrence intact - hard rule 8 holds for
/// reminders exactly as it does for entries).
public struct DeletedReminder: Identifiable {
    public let reminder: Reminder
    /// The tombstone stamp. `reminder.deletedAt` is authoritative.
    public let deletedAt: Date

    public var id: UUID { reminder.id }
    public var vehicleId: UUID { reminder.vehicleId }

    public init(reminder: Reminder, deletedAt: Date? = nil) {
        self.reminder = reminder
        self.deletedAt = deletedAt ?? reminder.deletedAt ?? reminder.updatedAt
    }
}

/// The 30-day countdown arithmetic (docs/SYNC.md: "30-day undo", the purge
/// grace period in Repository). Pure so it is unit-testable without a simulator
/// (docs/TESTING.md L1).
///
/// The day is the whole 24-hour period: an entry deleted today reads 30 days
/// left, tomorrow 29, and so on down to 0 at the purge boundary. The result is
/// clamped so it is never negative (the purge may simply not have run yet) and
/// never above the grace period (a tombstone stamped by a clock in the future).
public enum TombstoneCountdown {
    /// Matches `TankbookRepository.tombstoneGracePeriod` (30 days).
    public static let graceDays = 30

    public static func daysRemaining(deletedAt: Date, now: Date = Date()) -> Int {
        let elapsedDays = Int(now.timeIntervalSince(deletedAt) / 86_400)
        return min(max(graceDays - elapsedDays, 0), graceDays)
    }
}
