import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.275 L1 - the shared vehicle-photo loader (`VehiclePhotoStore.data`).
///
/// Before this row, Home and Vehicle detail each had a private `loadPhoto` that
/// walked `vehicle.photo` -> `liveAttachments()` -> the attachments directory,
/// and the two lists showed no photo at all. The loader is the one place that
/// resolves a car's photo, so this suite pins its three answers: the attachment's
/// bytes for a car that has a photo, nil for a car that has none, and nil once
/// the attachment is tombstoned (a deleted photo must not keep rendering).
///
/// Lives in the app-target bundle because `VehiclePhotoStore` is app code over
/// the app sandbox's Application Support path; the SwiftPM core tests run on
/// macOS where that path does not exist.
@MainActor
final class RV275VehiclePhotoLoaderTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeRepository() throws -> TankbookRepository {
        try TankbookRepository(database: TankbookDatabase.inMemory())
    }

    private func makeVehicle(photo: UUID?) -> Vehicle {
        let now = Date()
        return Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: photo, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    /// Writes real bytes through the store and records the attachment row the
    /// way Vehicle detail's save does, so the loader is exercised end to end.
    @discardableResult
    private func writePhoto(_ repository: TankbookRepository) throws -> (id: UUID, data: Data) {
        let id = UUID.v7()
        let data = Data("RV.275 vehicle photo".utf8)
        let saved = try VehiclePhotoStore.save(data, id: id)
        let now = Date()
        try repository.upsertAttachment(Attachment(
            id: id, createdAt: now, updatedAt: now, deletedAt: nil, kind: .photo,
            file: LocalFileRef(sha256: saved.sha256, relativePath: saved.relativePath),
            extractedTimestamp: nil, ocrText: nil))
        return (id, data)
    }

    private func removePhotoFile(_ id: UUID) {
        guard let directory = try? VehiclePhotoStore.attachmentsDirectory() else { return }
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent("\(id.uuidString).jpg"))
    }

    func testReturnsTheAttachmentBytesForACarWithAPhoto() throws {
        let repository = try makeRepository()
        let (id, data) = try writePhoto(repository)
        defer { removePhotoFile(id) }
        let vehicle = makeVehicle(photo: id)
        try repository.upsertVehicle(vehicle)

        XCTAssertEqual(try VehiclePhotoStore.data(for: vehicle, repository: repository), data,
                       "the loader returns the attachment's own bytes")
    }

    func testReturnsNilForACarWithoutAPhoto() throws {
        let repository = try makeRepository()
        let vehicle = makeVehicle(photo: nil)
        try repository.upsertVehicle(vehicle)

        XCTAssertNil(try VehiclePhotoStore.data(for: vehicle, repository: repository))
    }

    func testReturnsNilWhenThePhotoAttachmentIsTombstoned() throws {
        let repository = try makeRepository()
        let (id, _) = try writePhoto(repository)
        defer { removePhotoFile(id) }
        let vehicle = makeVehicle(photo: id)
        try repository.upsertVehicle(vehicle)
        try repository.softDeleteAttachment(id: id)

        XCTAssertNil(try VehiclePhotoStore.data(for: vehicle, repository: repository),
                     "a tombstoned photo must not keep rendering")
    }
}
