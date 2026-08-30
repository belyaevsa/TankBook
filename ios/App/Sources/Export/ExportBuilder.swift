import Foundation
import TankbookCore

// Builds the two export payloads (PJ.36 whole-account on Settings, PJ.38
// per-car on Vehicle detail) into fresh temp directories, sharing the blob
// source and the archive writers' atomic-write discipline.
//
// - `buildAccountArchive` returns the archive directory (scope `.account`).
// - `buildCarExport` returns the per-car archive directory PLUS the four CSV
//   files (PJ.38): the CSVs are written INSIDE the archive directory ("ships
//   inside the archive") and are handed to the share sheet as their own items,
//   so a user can share just the CSV to a spreadsheet app.

enum ExportBuilder {
    /// The whole-account archive for "Export everything" (PJ.36).
    @MainActor
    static func buildAccountArchive() throws -> URL {
        let repository = try AppStore.repository()
        let directory = try makeTemporaryDirectory(name: "Tankbook-Account")
        let writer = VehicleArchiveWriter(repository: repository, blobSource: blobSource())
        _ = try writer.writeAccountArchive(to: directory)
        return directory
    }

    /// The per-car archive with the CSV files riding inside it and as their own
    /// share items (PJ.38).
    @MainActor
    static func buildCarExport(vehicleID: UUID) throws -> ExportShareable {
        let repository = try AppStore.repository()
        let directory = try makeTemporaryDirectory(name: "Tankbook-\(vehicleID.uuidString.prefix(8))")
        let writer = VehicleArchiveWriter(repository: repository, blobSource: blobSource())
        _ = try writer.writeArchive(vehicleID: vehicleID, to: directory)
        let csvURLs = try CarCSVExport.write(into: directory, vehicleID: vehicleID, repository: repository)
        // The CSVs come FIRST so the share sheet names a CSV, and the archive
        // folder (with everything inside it) rides after.
        return ExportShareable(items: csvURLs + [directory])
    }

    private static func blobSource() -> FileBackedBlobSource {
        FileBackedBlobSource(
            directory: (try? VehiclePhotoStore.attachmentsDirectory())
                ?? FileManager.default.temporaryDirectory)
    }

    /// A fresh temp directory for one export - cleaned by the system, never
    /// inside Application Support (an export is a hand-off, not data).
    private static func makeTemporaryDirectory(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tankbook-exports", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
