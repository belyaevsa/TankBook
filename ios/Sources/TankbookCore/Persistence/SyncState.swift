import Foundation
import GRDB

/// Sync bookkeeping for a local row (docs/SYNC.md, "Client state & merge").
/// Every synced table carries a `syncState` column (`dirty` | `pushing` |
/// `synced`) plus an optional `syncScn` column set once the server assigned
/// a change number. Only `dirty` rows feed the sync queue.
public enum SyncState: Equatable, Sendable {
    /// A local change waiting to be pushed.
    case dirty
    /// A push is in flight; a failed push returns the row to `.dirty`.
    case pushing
    /// The server accepted the row at `scn`; the row is up to date.
    case synced(scn: Int64?)

    /// Storage value for the `syncState` column.
    var storageValue: String {
        switch self {
        case .dirty: "dirty"
        case .pushing: "pushing"
        case .synced: "synced"
        }
    }

    /// Reads the state string back from the `syncState` column.
    init(storageValue: String) {
        switch storageValue {
        case "pushing": self = .pushing
        case "synced": self = .synced(scn: nil)
        default: self = .dirty
        }
    }
}
