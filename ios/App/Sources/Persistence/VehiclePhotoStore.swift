import CryptoKit
import Foundation
import TankbookCore

/// Persists a picked car photo as a content-addressed attachment blob
/// (docs/SCHEMA.md, Attachment.file: sha256 + local relative path). The
/// attachments directory lives under Application Support next to the database
/// and carries the same `completeUntilFirstUserAuthentication` protection class
/// (docs/SECURITY.md), applied to the directory so every file written into it
/// inherits the class. It is user data, so it stays in device backups like the
/// database does - only the regenerable caches exclude themselves
/// (docs/PRACTICES.md -> S2). The blob pipeline that syncs it arrives with
/// P4.6.
enum VehiclePhotoStore {
    /// A car photo is a full-size picked image and the Garage re-reads every
    /// tile on each vehicle save, so the lists ask for the thumbnail and this
    /// holds the downscaled bytes for the process. `NSCache` is thread-safe;
    /// `nonisolated(unsafe)` records that rather than pretending it is not.
    private nonisolated(unsafe) static let thumbnailCache = NSCache<NSString, NSData>()

    static func attachmentsDirectory() throws -> URL {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("Tankbook/Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileProtection.protect(directory)
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

    /// The bytes of the car's photo attachment, or nil when the car has no
    /// photo or its attachment is tombstoned (`liveAttachments` drops deleted
    /// rows). The ONE loader every surface that shows a car's photo calls -
    /// Home's garage card, Vehicle detail, the Garage and the car switcher - so
    /// they cannot disagree about whether a photo exists.
    ///
    /// The store holds only the full picked JPEG; `thumbnail` asks for the small
    /// rendition the 42pt list tiles draw, derived on first read and cached for
    /// the process. Vehicle detail wants the full bytes, so it takes the default.
    static func data(for vehicle: Vehicle, repository: TankbookRepository,
                     thumbnail: Bool = false) throws -> Data? {
        guard let photoID = vehicle.photo,
              let attachment = try repository.liveAttachments()
                  .first(where: { $0.id == photoID }) else { return nil }
        if thumbnail, let cached = thumbnailCache.object(forKey: photoID.uuidString as NSString) {
            return cached as Data
        }
        let url = try attachmentsDirectory().appendingPathComponent(attachment.file.relativePath)
        guard let full = try? Data(contentsOf: url) else { return nil }
        guard thumbnail else { return full }
        if let base64 = try? AttachmentRendition.thumbnailBase64(for: full, kind: .photo),
           let bytes = Data(base64Encoded: base64) {
            thumbnailCache.setObject(bytes as NSData, forKey: photoID.uuidString as NSString)
            return bytes
        }
        return full
    }
}
