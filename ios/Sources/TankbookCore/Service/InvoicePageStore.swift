import Foundation

/// The file half of an attachment's lifecycle (docs/SCHEMA.md -> Attachment &
/// extraction provenance; SYNC.md -> blob pipeline). The blob upload itself is
/// P4.6; this protocol is only the local write/remove the app needs so a page
/// can be captured now and deleted without orphaning its file.
public protocol AttachmentFileManaging: Sendable {
    /// Writes a page's bytes and returns the content-addressed reference.
    func write(_ data: Data, id: UUID) throws -> LocalFileRef
    /// Deletes the file a page's reference points at.
    func remove(_ ref: LocalFileRef) throws
}

/// Coordinates invoice pages with their attachments and local files. Each page
/// is an `Attachment` (kind `.photo`, `ocrText` retained for re-parsing after a
/// parser upgrade, `extractedTimestamp` set when the invoice's printed date is
/// readable). Adding a page writes its file AND its row immediately, so removing
/// a page has something concrete to delete - the invariant this type exists to
/// keep: **a removed page leaves no orphaned file**.
public struct InvoicePageStore {
    private let repository: TankbookRepository
    private let files: any AttachmentFileManaging

    public init(repository: TankbookRepository, files: any AttachmentFileManaging) {
        self.repository = repository
        self.files = files
    }

    /// Persists one captured page: writes the file, upserts the attachment row,
    /// and returns the attachment so the caller can render its thumbnail and
    /// link it to the record on save.
    @discardableResult
    public func addPage(imageData: Data,
                        ocrText: String?,
                        extractedTimestamp: Date?) throws -> Attachment {
        let id = UUID.v7()
        let ref = try files.write(imageData, id: id)
        let now = Date()
        let attachment = Attachment(
            id: id, createdAt: now, updatedAt: now, deletedAt: nil,
            kind: .photo, file: ref,
            extractedTimestamp: extractedTimestamp,
            ocrText: ocrText)
        try repository.upsertAttachment(attachment)
        return attachment
    }

    /// Removes a page: soft-deletes its row and deletes its file, in that order
    /// (the row first, so a crash between the two leaves a tombstone, not a
    /// dangling reference to a missing blob).
    public func removePage(_ attachment: Attachment) throws {
        try repository.softDeleteAttachment(id: attachment.id)
        try files.remove(attachment.file)
    }
}
