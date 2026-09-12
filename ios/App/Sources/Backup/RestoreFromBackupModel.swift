import Foundation
import Observation
import TankbookCore

/// Why a local restore-from-backup failed, mapped from the reader's typed error
/// plus the one failure the reader cannot see (the picked folder could not be
/// copied at all). Every case names a next step at the surface (docs/ERRORS.md,
/// hard rule 7).
enum RestoreFromBackupFailure: Equatable {
    /// The security-scoped folder could not be read (permission refused, an
    /// iCloud folder not downloaded). Distinct from a malformed archive.
    case unreadable
    /// `VehicleArchiveReader`'s refusal, surfaced verbatim by the view's copy.
    case archive(VehicleArchiveError)
}

/// What a successful local restore wrote, for the screen's confirmation (raw
/// counts, never a checkmark - the F7 principle).
struct RestoreFromBackupSummary: Equatable {
    let vehicleIDs: [UUID]
    let vehicleCount: Int
    let entryCount: Int
}

/// The local restore-from-backup flow (RV.260; docs/JOURNEYS.md J11, F7 source
/// 3). The user-held fallback: an archive Tankbook itself wrote (`ExportBuilder`)
/// read back by `VehicleArchiveReader` with NO network and no account at all
/// (hard rule 1).
///
/// The archive is a DIRECTORY - `manifest.json` + `data.json` + `attachments/` -
/// which is exactly what the export hands the share sheet, so the picker accepts
/// a folder.
///
/// Scope is the load-bearing decision, and `VehicleArchiveReader.guardScope` is
/// the guard: this door imports with `.singleCar`, so a per-car export lands as a
/// car and a whole-account archive is REFUSED with its named next step rather
/// than silently treated as one car (docs/SCHEMA.md -> "Scope: a user-held export
/// is PER CAR").
@MainActor
@Observable
final class RestoreFromBackupModel {
    enum Phase: Equatable {
        case idle
        case importing
        case imported(RestoreFromBackupSummary)
        case failed(RestoreFromBackupFailure)
    }

    private(set) var phase: Phase = .idle

    private let repository: TankbookRepository
    private let blobStore: any BlobStore
    private let stager: ImportPickedFile

    init(repository: TankbookRepository, blobStore: any BlobStore,
         stager: ImportPickedFile) {
        self.repository = repository
        self.blobStore = blobStore
        self.stager = stager
    }

    /// The production model over the app's one repository, its one blob pool
    /// (`VehiclePhotoStore.attachmentsDirectory`) and the security-scoped file
    /// stager (RV.73).
    static func makeDefault() throws -> RestoreFromBackupModel {
        let directory = try VehiclePhotoStore.attachmentsDirectory()
        return RestoreFromBackupModel(
            repository: try AppStore.repository(),
            blobStore: FileBackedBlobStore(directory: directory),
            stager: ImportService.makePickedFileStager())
    }

    /// Stages the picked archive under its security scope, imports it with the
    /// per-car mode, and reports the outcome. The staged copy is disposed on
    /// every path - a backup holds user data and never outlives the import.
    func importBackup(at picked: URL) {
        phase = .importing
        switch stager.stage(picked, log: AppLog.shared) {
        case .readFailed:
            phase = .failed(.unreadable)
        case .staged(let staged):
            defer { stager.dispose(staged) }
            do {
                let reader = VehicleArchiveReader(repository: repository, blobStore: blobStore)
                let result = try reader.importArchive(at: staged, mode: .singleCar)
                phase = .imported(RestoreFromBackupSummary(
                    vehicleIDs: result.vehicleIds,
                    vehicleCount: result.vehicleCount,
                    entryCount: result.entryCount))
            } catch let error as VehicleArchiveError {
                phase = .failed(.archive(error))
            } catch {
                phase = .failed(.archive(.underlying(error.localizedDescription)))
            }
        }
    }
}
