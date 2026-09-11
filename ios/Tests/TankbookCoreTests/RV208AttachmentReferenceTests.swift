import Foundation
import XCTest
@testable import TankbookCore

/// RV.208: an entry's attachment references are never swept. An id with no live
/// `Attachment` row on this device is not locally decidable between "never
/// written" (RV.173's dangling id) and "not pulled yet" (a device mid-restore,
/// or a group whose attachment record is still blob-pending on the origin
/// device) - so the reference is left in place and Edit entry surfaces the
/// missing photo with a re-attach next step (docs/SYNC.md -> Attachments,
/// docs/ERRORS.md -> Edit entry). These are the pure-resolver oracles; the
/// viewer half is pinned at L4 (`EditEntryRV208UITests`).
final class RV208AttachmentReferenceTests: XCTestCase {

    private func attachment(id: UUID) -> Attachment {
        Attachment(id: id, createdAt: Date(), updatedAt: Date(), deletedAt: nil,
                   kind: .photo,
                   file: LocalFileRef(sha256: String(repeating: "a", count: 64),
                                      relativePath: "blobs/\(id.uuidString).jpg"),
                   extractedTimestamp: nil, ocrText: nil, thumbnailBase64: nil,
                   extractionMeta: nil)
    }

    /// Case 1: the row exists, the rendition file has not landed, the blob is
    /// pending upload or download. The row IS the reference's existence, so this
    /// must not be reported - a sweep that cleared it would delete a valid link
    /// for every user mid-restore.
    func testALiveRowWhoseBlobIsStillPendingIsNotUnresolved() {
        let id = UUID.v7()
        let unresolved = AttachmentReference.unresolved([id], liveAttachments: [attachment(id: id)])
        XCTAssertTrue(unresolved.isEmpty,
                      "a row that exists but whose file has not synced is NOT dangling")
    }

    /// Case 3: no `Attachment` row at all - RV.173's dangling id. The resolver
    /// reports it and the entry's stored list is byte-identical afterwards: the
    /// decision is to surface it, never to clear it.
    func testAReferenceWithNoLiveRowIsReportedUnresolvedAndLeftInPlace() {
        let dangling = UUID.v7()
        let live = UUID.v7()
        let references = [dangling, live]
        let unresolved = AttachmentReference.unresolved(references,
                                                        liveAttachments: [attachment(id: live)])
        XCTAssertEqual(unresolved, [dangling])
        XCTAssertEqual(references, [dangling, live],
                       "resolving must not mutate the entry's stored reference list")
    }

    /// `liveAttachments()` is the live set by definition, so a tombstoned row
    /// resolves to nothing. The reference is reported like any other missing one
    /// - never silently dropped.
    func testATombstonedRowDoesNotResolve() {
        let tombstoned = UUID.v7()
        XCTAssertEqual(AttachmentReference.unresolved([tombstoned], liveAttachments: []),
                       [tombstoned])
    }

    /// No migration ships, so "idempotent" is the resolver's purity: two passes
    /// over the same input return the same list and mutate nothing. Duplicates
    /// in the entry's list are preserved - the count the UI shows is the entry's
    /// own, not a deduplicated one.
    func testResolvingTwiceChangesNothing() {
        let dangling = UUID.v7()
        let live = UUID.v7()
        let references = [dangling, live, dangling]
        let liveAttachments = [attachment(id: live)]
        let first = AttachmentReference.unresolved(references, liveAttachments: liveAttachments)
        let second = AttachmentReference.unresolved(references, liveAttachments: liveAttachments)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, [dangling, dangling])
        XCTAssertEqual(references, [dangling, live, dangling])
    }

    /// The resolved half keeps the entry's own order and skips the missing ids,
    /// so the strip renders the photos in the order the entry stored them.
    func testResolvedReturnsTheLiveRowsInTheEntrysReferenceOrder() {
        let first = UUID.v7()
        let second = UUID.v7()
        let missing = UUID.v7()
        let rows = [attachment(id: second), attachment(id: first)]
        let resolved = AttachmentReference.resolved([first, missing, second], liveAttachments: rows)
        XCTAssertEqual(resolved.map(\.id), [first, second])
    }
}
