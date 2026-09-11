import TankbookCore
import XCTest
@testable import Tankbook

/// RV.220 - the review row's keep actions and "Leave out" are two intents, not
/// one flip-flop. A `noFuel` row is kept when it arrives (its "Import as
/// service" action renders in the accent colour, and an untouched row commits),
/// so the old shared `toggleSkipped` turned the action that NAMES keeping into
/// the action that silently dropped the row (hard rule 8). These pin the model
/// behaviour the buttons call: `keep` is idempotent, only `leaveOut` skips.
@MainActor
final class ImportRV220Tests: XCTestCase {

    private func makeModel() throws -> ImportFlowModel {
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        return ImportService.makeModel(repository: repository,
                                       configService: AppConfigService.make(arguments: []))
    }

    private func serviceRow(_ model: ImportFlowModel) throws -> ImportReviewRow {
        try XCTUnwrap(model.reviewRows.first { $0.nonFuel != nil },
                      "the seeded service row must be in the review list")
    }

    private func serviceCount(_ model: ImportFlowModel) -> Int {
        model.importRecords.filter { record in
            if case .serviceRecord = record { return true }
            return false
        }.count
    }

    /// The row is kept when it arrives, and `keep` leaves it kept however many
    /// times it is called - the deciding action can never drop the record.
    func testKeepIsIdempotent() throws {
        let model = try makeModel()
        model.installSeededServiceParse()
        let row = try serviceRow(model)

        XCTAssertFalse(model.isSkipped(sourceRow: row.sourceRow),
                       "a fresh noFuel row is kept - its action renders in the accent colour")
        XCTAssertEqual(serviceCount(model), 1, "the kept service is in the commit")

        model.keep(sourceRow: row.sourceRow)
        XCTAssertFalse(model.isSkipped(sourceRow: row.sourceRow), "keep keeps a kept row")
        model.keep(sourceRow: row.sourceRow)
        XCTAssertFalse(model.isSkipped(sourceRow: row.sourceRow),
                       "keep is idempotent, never a toggle")
        XCTAssertEqual(serviceCount(model), 1, "keep did not drop the service")
    }

    /// Only `leaveOut` skips; `keep` restores a row the user left out. The two
    /// are not each other's inverse.
    func testLeaveOutSkipsAndKeepRestores() throws {
        let model = try makeModel()
        model.installSeededServiceParse()
        let row = try serviceRow(model)

        model.leaveOut(sourceRow: row.sourceRow)
        XCTAssertTrue(model.isSkipped(sourceRow: row.sourceRow), "leaveOut skips")
        XCTAssertEqual(serviceCount(model), 0, "a left-out service is not committed")

        model.keep(sourceRow: row.sourceRow)
        XCTAssertFalse(model.isSkipped(sourceRow: row.sourceRow), "keep restores a left-out row")
        XCTAssertEqual(serviceCount(model), 1, "the restored service is back in the commit")
    }
}
