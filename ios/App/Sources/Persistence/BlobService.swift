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
}
