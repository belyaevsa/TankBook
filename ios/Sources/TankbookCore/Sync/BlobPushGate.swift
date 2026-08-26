import Foundation

/// Supplies an attachment's local rendition bytes - the file written at capture
/// time, content-addressed by `Attachment.file.sha256` (docs/SCHEMA.md). The
/// production implementation reads the attachments directory; tests substitute a
/// fixed byte source so the gate needs no file I/O.
public protocol BlobSource: Sendable {
    func renditionData(for attachment: Attachment) throws -> Data?
}

/// The gate the sync engine consults before it pushes an attachment record:
/// the blob must be committed before the record pushes (docs/SYNC.md, upload
/// step 5 - "records never point at blobs the server can't serve"). Returning
/// false leaves the record dirty for a later cycle - uploads queue offline like
/// everything else (S7) and the entry syncs text-first with the blob pending.
public protocol BlobPushGate: Sendable {
    func ensureBlobCommitted(for attachment: Attachment) async -> Bool
}

/// The production gate: reads the local rendition and runs the upload chain. A
/// missing file or any transport/size/quota failure defers the record (false);
/// `exists` (dedupe) and a successful commit allow the push (true).
public struct LocalFileBlobPushGate: BlobPushGate, Sendable {
    public let uploader: BlobUploader
    public let source: any BlobSource

    public init(uploader: BlobUploader, source: any BlobSource) {
        self.uploader = uploader
        self.source = source
    }

    public func ensureBlobCommitted(for attachment: Attachment) async -> Bool {
        guard let data = try? source.renditionData(for: attachment), !data.isEmpty else {
            return false
        }
        do {
            try await uploader.upload(
                sha256: attachment.file.sha256,
                data: data,
                contentType: Self.contentType(for: attachment.kind)
            )
            return true
        } catch {
            return false
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
