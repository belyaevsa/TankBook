#if DEBUG
import Foundation
import TankbookCore

/// RV.131's Home state: an unresolved S2 duplicate pair whose two members
/// DIFFER in exactly the fields the combined card must show - odometer, total,
/// and the attachment that makes the newer fill the Merge survivor
/// (docs/SYNC.md: "the one with an attachment wins"). A pair whose members were
/// identical could not show the defect the card exists to fix (the user could
/// not tell the entries apart), which is why this is a separate seed from
/// `-seedHomeDuplicate`. Both fills are pinned to a fixed clock time (18:20 /
/// 18:35, two days back), so the card's time-of-day reads the same in a
/// screenshot on any run date.
enum HomeDuplicateTestSeed {
    static func seedFields(_ repository: TankbookRepository) {
        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)
        let shell = makeStation(repository)
        let receipt = makeAttachment(repository)
        let now = Date()
        let atHour = Calendar.current.date(bySettingHour: 18, minute: 20, second: 0,
                                           of: now) ?? now
        let firstDate = Calendar.current.date(byAdding: .day, value: -2, to: atHour) ?? atHour
        try? repository.upsertFillUp(HomeTestSeed.makeFill(
            vehicleID: vehicle.id,
            HomeTestSeed.FillSpec(daysAgo: 2, odometer: 122_800, litres: 42.3,
                                  amount: "71.02", price: "1.679", stationID: shell.id),
            date: firstDate))
        try? repository.upsertFillUp(HomeTestSeed.makeFill(
            vehicleID: vehicle.id,
            HomeTestSeed.FillSpec(daysAgo: 2, odometer: 122_950, litres: 42.9,
                                  amount: "72.05", price: "1.679", stationID: shell.id),
            attachments: [receipt.id],
            date: firstDate.addingTimeInterval(15 * 60)))
    }

    private static func makeStation(_ repository: TankbookRepository) -> Station {
        let now = Date()
        let station = Station(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Shell", brand: nil, location: nil, favorite: true,
            defaults: Station.Defaults(fuelKind: .petrol95, fuelGrade: nil),
            lastUsedAt: nil)
        try? repository.upsertStation(station)
        return station
    }

    private static func makeAttachment(_ repository: TankbookRepository) -> Attachment {
        let now = Date()
        let attachment = Attachment(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            kind: .photo, file: LocalFileRef(sha256: UUID().uuidString,
                                             relativePath: "seed/\(UUID().uuidString).jpg"),
            extractedTimestamp: nil, ocrText: nil)
        try? repository.upsertAttachment(attachment)
        return attachment
    }
}
#endif
