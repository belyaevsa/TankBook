import CryptoKit
import Foundation
import TankbookCore

/// The file-backed `AttachmentFileManaging` for invoice pages (P3.1b). Writes
/// JPEG data into the shared attachments directory (the same one
/// `VehiclePhotoStore` uses - one blob pool, docs/SYNC.md), which carries the
/// `completeUntilFirstUserAuthentication` protection class set by
/// `VehiclePhotoStore.attachmentsDirectory` (docs/SECURITY.md), and deletes a
/// page's file when its page is removed. The blob upload arrives with P4.6;
/// this is local files only.
struct InvoiceAttachmentFiles: AttachmentFileManaging {
    func write(_ data: Data, id: UUID) throws -> LocalFileRef {
        let name = "\(id.uuidString).jpg"
        try data.write(to: try VehiclePhotoStore.attachmentsDirectory()
            .appendingPathComponent(name))
        let digest = SHA256.hash(data: data)
        let sha256 = digest.map { String(format: "%02x", $0) }.joined()
        return LocalFileRef(sha256: sha256, relativePath: name)
    }

    func remove(_ ref: LocalFileRef) throws {
        let url = try VehiclePhotoStore.attachmentsDirectory()
            .appendingPathComponent(ref.relativePath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
