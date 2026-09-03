import Foundation
import TankbookCore

/// The receipt strip's "is the full rendition here?" check (docs/SYNC.md ->
/// Attachments). A blob is available locally when either the content-addressed
/// cache holds it (downloaded) or the capturing device's own file still exists
/// at `file.relativePath`. Otherwise the entry shows its inline thumbnail with
/// the "photo syncing" shimmer until the blob lands - and is fully usable
/// throughout (hard rule 1).
@MainActor
enum BlobService {
    static func isBlobAvailable(_ attachment: Attachment) -> Bool {
        guard let directory = try? VehiclePhotoStore.attachmentsDirectory() else {
            return false
        }
        let store = FileBackedBlobStore(directory: directory)
        if (try? store.data(for: attachment.file.sha256)) != nil {
            return true
        }
        let local = directory.appendingPathComponent(attachment.file.relativePath)
        return FileManager.default.fileExists(atPath: local.path)
    }

    /// The full rendition's bytes if they are already on this device - the
    /// content-addressed cache first, then the capturing device's own file
    /// (RV.9: the attachment viewer's "is it here?" question). Synchronous and
    /// network-free: nil simply means "not local yet", never an error.
    static func localData(for attachment: Attachment) -> Data? {
        guard let directory = try? VehiclePhotoStore.attachmentsDirectory() else {
            return nil
        }
        let store = FileBackedBlobStore(directory: directory)
        if let cached = try? store.data(for: attachment.file.sha256) {
            return cached
        }
        let local = directory.appendingPathComponent(attachment.file.relativePath)
        guard FileManager.default.fileExists(atPath: local.path) else { return nil }
        return try? Data(contentsOf: local)
    }
}
