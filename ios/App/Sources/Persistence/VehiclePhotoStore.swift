import CryptoKit
import Foundation

/// Persists a picked car photo as a content-addressed attachment blob
/// (docs/SCHEMA.md, Attachment.file: sha256 + local relative path). The
/// attachments directory lives under Application Support so it stays out of
/// iCloud backups; the blob pipeline that syncs it arrives with P4.6.
enum VehiclePhotoStore {
    static func attachmentsDirectory() throws -> URL {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("Tankbook/Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes JPEG data and returns the `LocalFileRef` fields for the blob.
    static func save(_ data: Data, id: UUID) throws -> (sha256: String, relativePath: String) {
        let name = "\(id.uuidString).jpg"
        try data.write(to: try attachmentsDirectory().appendingPathComponent(name))
        let digest = SHA256.hash(data: data)
        let sha256 = digest.map { String(format: "%02x", $0) }.joined()
        return (sha256, name)
    }
}
