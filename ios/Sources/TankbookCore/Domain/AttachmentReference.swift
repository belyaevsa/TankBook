import Foundation

/// Resolves an entry's `attachments` references against the `Attachment` rows on
/// this device.
///
/// An entry stores its receipts as a list of ids (`Entry.attachments`), never as
/// a foreign key, so nothing at the storage layer guarantees the row still
/// exists. `RV.173`'s grouped save could stamp the plan's intended id even when
/// the photo write failed, leaving an `Expense` pointing at an `Attachment` that
/// was never written. The reference is silent until something dereferences it.
///
/// **The unresolved ids are left in place, deliberately (RV.208).** An id with
/// no live `Attachment` row on this device is NOT locally decidable between
/// "never written" and "not here yet":
///
/// - A live attachment record is deferred behind the blob gate until its bytes
///   commit (`docs/SYNC.md` -> Attachments, upload step 5; `SyncEngine`'s
///   `pushCandidate`), so the entry pushes text-first and reaches the server at
///   a LOWER SCN than its attachment.
/// - Pull is by SCN, so a device mid-restore receives the entry before its
///   attachment; the missing row is a pending arrival, not a dangling id.
/// - The server validates payload structure, never domain references (hard rule
///   9), and there is no endpoint to ask whether an attachment id exists - the
///   dangling id carries no `sha256` to check against `GET /blobs/{sha256}`.
///
/// A sweep over "no live row" would therefore delete a valid link for every user
/// mid-restore (and for a group whose attachment record is still pending on the
/// origin device). The honest answer is to leave the ids and let Edit entry show
/// the missing photo with a re-attach next step (`docs/ERRORS.md` -> Edit
/// entry). This type only reports which references are unresolved; it never
/// writes, clears or logs one.
public enum AttachmentReference {

    /// The referenced ids that resolve to no live `Attachment` on this device.
    /// Order is the entry's own, so a caller can name the count and, if it ever
    /// needs to, the position - never a sorted set that hides which reference is
    /// which.
    ///
    /// A live row whose local file is absent (blob pending upload or download)
    /// DOES resolve: the row is the record's existence, and the missing file is
    /// the viewer's own "not on this device yet" state (`docs/SYNC.md` ->
    /// Delivery). Only the absence of the row is reported here.
    public static func unresolved(_ references: [AttachmentID],
                                  liveAttachments: [Attachment]) -> [AttachmentID] {
        var live: Set<AttachmentID> = []
        live.reserveCapacity(liveAttachments.count)
        for attachment in liveAttachments {
            live.insert(attachment.id)
        }
        return references.filter { !live.contains($0) }
    }

    /// The live attachments a set of references resolves to, in the entry's own
    /// reference order. A reference that resolves to nothing is skipped - the
    /// caller reads `unresolved(_:liveAttachments:)` for the missing half.
    public static func resolved(_ references: [AttachmentID],
                                liveAttachments: [Attachment]) -> [Attachment] {
        var byID: [AttachmentID: Attachment] = [:]
        for attachment in liveAttachments {
            byID[attachment.id] = attachment
        }
        return references.compactMap { byID[$0] }
    }
}
