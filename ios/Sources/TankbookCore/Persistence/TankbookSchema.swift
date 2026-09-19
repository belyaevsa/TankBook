import Foundation

/// Canonical table names. `TankbookCore` is the only writer of these tables;
/// the names are shared by migrations, record types and the repository so they
/// can never drift apart. Table/column naming follows docs/SCHEMA.md verbatim
/// (camelCase in SQLite is fine - it is not a PostgreSQL schema).
public enum TankbookSchema {
    public static let vehicle = "vehicle"
    public static let fillUp = "fillUp"
    public static let chargeSession = "chargeSession"
    public static let serviceRecord = "serviceRecord"
    public static let serviceItem = "serviceItem"
    public static let expense = "expense"
    public static let reminder = "reminder"
    public static let station = "station"
    public static let tariff = "tariff"
    public static let tireSet = "tireSet"
    public static let attachment = "attachment"
    public static let preferences = "preferences"
    public static let exchangeRate = "exchangeRate"
    /// Device-local record of S2 duplicate resolutions ("keep both") - NOT in
    /// `syncedTables`: it is derived-state bookkeeping, like the sync cursor.
    public static let duplicateResolution = "duplicateResolution"
    /// Device-local undo log of versions a sync merge overwrote (docs/SYNC.md
    /// S1/S4: "the losing version is kept in a local 30-day undo log"). NOT in
    /// `syncedTables` - it is bookkeeping, like the sync cursor.
    public static let syncOverwrite = "syncOverwrite"
    /// Device-local memory of each record's last-synced payload (docs/SYNC.md
    /// S9: the `Vehicle` field-level merge diffs against it). NOT in
    /// `syncedTables` - it is bookkeeping, like the sync cursor, never synced.
    public static let syncPayloadMemory = "syncPayloadMemory"
    /// Device-local notice that a car this device deleted came back archived
    /// because another device's entries still referenced it (docs/SYNC.md S5).
    /// NOT in `syncedTables` - it is the device's own "delete again?" question,
    /// answered once, here.
    public static let vehicleReturn = "vehicleReturn"

    /// Every synced entity table (has the envelope + syncState bookkeeping).
    /// The reference data (exchangeRate) is deliberately NOT here.
    public static let syncedTables: [String] = [
        vehicle, fillUp, chargeSession, serviceRecord, expense,
        reminder, station, tariff, tireSet, attachment, preferences,
    ]

    /// Entry tables: carry the EntryCommon envelope plus a vehicle FK.
    public static let entryTables: [String] = [
        fillUp, chargeSession, serviceRecord, expense,
    ]

    /// Money columns are flattened per docs/SCHEMA.md (Money). Unprefixed on
    /// entry tables (`amount`, `currency`, ...); prefixed and capitalized on
    /// the serviceItem child table (`costAmount`, `costCurrency`, ...).
    public static func moneyColumn(_ prefix: String, _ base: String) -> String {
        prefix.isEmpty ? base : prefix + base.prefix(1).uppercased() + base.dropFirst()
    }
}
