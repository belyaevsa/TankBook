import Foundation
import GRDB

public struct AdBlueFillRow: FetchableRecord, PersistableRecord {
    public static let databaseTableName = TankbookSchema.adBlueFill
    public var adBlueFill: AdBlueFill
    public var syncState: SyncState
    public var syncScn: Int64?

    public init(adBlueFill: AdBlueFill, syncState: SyncState = .dirty) {
        self.adBlueFill = adBlueFill
        self.syncState = syncState
        self.syncScn = scn(for: syncState)
    }

    public init(row: Row) throws {
        let common = try decodeEntryCommon(row)
        adBlueFill = AdBlueFill(
            id: common.envelope.id,
            createdAt: common.envelope.createdAt,
            updatedAt: common.envelope.updatedAt,
            deletedAt: common.envelope.deletedAt,
            vehicleId: common.vehicleId,
            date: common.date,
            odometer: common.odometer,
            money: common.money,
            note: common.note,
            attachments: common.attachments,
            provenance: common.provenance,
            conflict: common.conflict,
            flagAcceptance: common.flagAcceptance,
            purchaseGroupId: common.purchaseGroupId,
            volumeL: row["volumeL"] as Double,
            unitPrice: row["unitPrice"] as Decimal?,
            stationId: decodeOptionalUUID(row, column: "stationId"))
        (syncState, syncScn) = decodeSync(row)
    }

    public func encode(to container: inout PersistenceContainer) throws {
        try setEntryCommon(adBlueFill, into: &container)
        setSync(syncState, scn: syncScn, into: &container)
        container["volumeL"] = adBlueFill.volumeL
        container["unitPrice"] = adBlueFill.unitPrice
        container["stationId"] = adBlueFill.stationId?.uuidString
    }
}
