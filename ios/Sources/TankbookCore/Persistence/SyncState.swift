import Foundation
import GRDB

/// Sync bookkeeping for a local row (docs/SYNC.md, "Client state & merge").
/// Every synced table carries a `syncState` column (`dirty` | `pushing` |
/// `synced` | `rejected`) plus an optional `syncScn` column set once the server
/// assigned a change number. Only `dirty` rows feed the sync queue; a `rejected`
/// row is terminal for that payload until the record is edited again (an edit
/// re-dirties it, and a new app build may emit a different payload).
public enum SyncState: Equatable, Sendable {
    /// A local change waiting to be pushed.
    case dirty
    /// A push is in flight; a failed push returns the row to `.dirty`.
    case pushing
    /// The server accepted the row at `scn`; the row is up to date.
    case synced(scn: Int64?)
    /// The server rejected the payload structurally (`payload_schema_violation`,
    /// `payload_invalid`, …): the same bytes will be rejected again until
    /// something changes (docs/SYNC.md S7's 422 sibling). The code and pointer
    /// are shape-only diagnostics for the `sync.rejected` log line (hard rule
    /// 12: a code and a JSON pointer are loggable, the payload never is). They
    /// are NOT persisted - the stored `syncState` column holds the bare
    /// `"rejected"` marker, and the surface's next step is the fixed "update the
    /// app or edit it to retry", never the code.

    case rejected(code: String, pointer: String?)

    /// Storage value for the `syncState` column.
    var storageValue: String {
        switch self {
        case .dirty: "dirty"
        case .pushing: "pushing"
        case .synced: "synced"
        case .rejected: "rejected"
        }
    }

    /// Reads the state string back from the `syncState` column. The `rejected`
    /// code/pointer are transient (see above), so a read-back row carries empty
    /// diagnostics; the marker is all the surface and the queue need.
    init(storageValue: String) {
        switch storageValue {
        case "pushing": self = .pushing
        case "synced": self = .synced(scn: nil)
        case "rejected": self = .rejected(code: "", pointer: nil)
        default: self = .dirty
        }
    }
}
