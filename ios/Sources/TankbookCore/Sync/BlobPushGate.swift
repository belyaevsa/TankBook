import Foundation

/// Supplies an attachment's local rendition bytes - the file written at capture
/// time, content-addressed by `Attachment.file.sha256` (docs/SCHEMA.md). The
/// production implementation reads the attachments directory; tests substitute a
/// fixed byte source so the gate needs no file I/O.
public protocol BlobSource: Sendable {
    func renditionData(for attachment: Attachment) throws -> Data?
}

/// The gate's verdict for one attachment (RV.253). The engine needs to tell a
/// plain deferral from a quota refusal, because only the latter carries a
/// percent for the Settings card; both leave the record dirty for a later cycle.
public enum BlobCommitOutcome: Sendable, Equatable {
    /// The blob is committed (or already existed) - the record may push.
    case committed
    /// The upload was deferred (missing file, transport down, size refusal):
    /// the record stays dirty, no quota state to surface.
    case deferred
    /// The account's storage quota is exhausted (429). `usedPercent` is the
    /// server's own percentage, nil when the 429 carried none.
    case quotaExceeded(usedPercent: Int?)
}

/// The gate the sync engine consults before it pushes an attachment record:
/// the blob must be committed before the record pushes (docs/SYNC.md, upload
/// step 5 - "records never point at blobs the server can't serve"). Returning
/// false leaves the record dirty for a later cycle - uploads queue offline like
/// everything else (S7) and the entry syncs text-first with the blob pending.
public protocol BlobPushGate: Sendable {
    func ensureBlobCommitted(for attachment: Attachment) async -> BlobCommitOutcome
}

/// The production gate: reads the local rendition and runs the upload chain. A
/// missing file or any transport/size failure defers the record; `exists`
/// (dedupe) and a successful commit allow the push. A quota 429 is a deferral
/// too, but its percent rides out to the sync outcome (RV.253).
public struct LocalFileBlobPushGate: BlobPushGate, Sendable {
    public let uploader: BlobUploader
    public let source: any BlobSource

    public init(uploader: BlobUploader, source: any BlobSource) {
        self.uploader = uploader
        self.source = source
    }

    public func ensureBlobCommitted(for attachment: Attachment) async -> BlobCommitOutcome {
        guard let data = try? source.renditionData(for: attachment), !data.isEmpty else {
            return .deferred
        }
        do {
            try await uploader.upload(
                sha256: attachment.file.sha256,
                data: data,
                contentType: Self.contentType(for: attachment.kind)
            )
            return .committed
        } catch BlobSyncError.quotaExceeded(let usedPercent) {
            return .quotaExceeded(usedPercent: usedPercent)
        } catch {
            return .deferred
        }
    }

    public static func contentType(for kind: AttachmentKind) -> String {
        switch kind {
        case .photo: return "image/jpeg"
        case .pdf: return "application/pdf"
        }
    }
}

/// A `BlobSource` over the attachments directory: reads the file at
/// `attachment.file.relativePath` under `directory`. The directory is the same
/// one `InvoiceAttachmentFiles`/`VehiclePhotoStore` write into (docs/SYNC.md -
/// one blob pool).
public struct FileBackedBlobSource: BlobSource, Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func renditionData(for attachment: Attachment) throws -> Data? {
        let url = directory.appendingPathComponent(attachment.file.relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
}
