import TankbookCore
import XCTest
@testable import Tankbook

/// RV.116 - the review gate's "not imported" notice is built from what the
/// server declared, never from a list baked into the client. These are L1
/// assertions on the model's display projection; the L4 test drives the real
/// screen.
@MainActor
final class ImportUnsupportedColumnsTests: XCTestCase {

    private func makeModel() throws -> ImportFlowModel {
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        return ImportService.makeModel(
            repository: repository,
            configService: AppConfigService.make(arguments: []))
    }

    /// The anti-hardcoding assertion: a format whose unsupported list the app
    /// has never heard of still renders, in the format's declared order, with
    /// the parse's counts. Nothing here is keyed on "Driver" or any known name.
    func testRendersServerDeclaredColumnsTheAppHasNeverHeardOf() throws {
        let model = try makeModel()
        model.pickedFormat = ImportFormat(
            id: "unknown-app", displayName: "Unknown", fileKinds: ["csv"],
            helpUrl: nil, addedInPackVersion: 1,
            unsupportedColumns: ["Кузов", "VIN", "Скидка"])
        model.parse = ImportParseResponse(
            importId: "00000000-0000-4000-8000-000000000321", format: "unknown-app",
            scope: "vehicle", candidates: [], unparsed: [], ambiguities: [],
            unsupported: ["VIN": 3, "Кузов": 7])

        XCTAssertEqual(model.unsupportedColumns,
                       [ImportUnsupportedColumn(column: "Кузов", rowCount: 7),
                        ImportUnsupportedColumn(column: "VIN", rowCount: 3)],
                       "the client must render whatever the server declared, in its order")
    }

    /// A name the parse reports but the format did not declare still renders -
    /// the notice never silently drops a count the server sent.
    func testParseOnlyColumnStillRenders() throws {
        let model = try makeModel()
        model.pickedFormat = ImportFormat(
            id: "unknown-app", displayName: "Unknown", fileKinds: ["csv"],
            helpUrl: nil, addedInPackVersion: 1, unsupportedColumns: ["VIN"])
        model.parse = ImportParseResponse(
            importId: "00000000-0000-4000-8000-000000000322", format: "unknown-app",
            scope: "vehicle", candidates: [], unparsed: [], ambiguities: [],
            unsupported: ["VIN": 1, "Мотор": 9])

        XCTAssertEqual(model.unsupportedColumns,
                       [ImportUnsupportedColumn(column: "VIN", rowCount: 1),
                        ImportUnsupportedColumn(column: "Мотор", rowCount: 9)])
    }

    /// An older server omits the field entirely: no notice, never a crash.
    func testOlderServerWithoutUnsupportedShowsNoNotice() throws {
        let model = try makeModel()
        model.pickedFormat = ImportFormat(
            id: "drivvo", displayName: "Drivvo", fileKinds: ["csv"],
            helpUrl: nil, addedInPackVersion: 1, unsupportedColumns: ["Driver"])
        model.parse = ImportParseResponse(
            importId: "00000000-0000-4000-8000-000000000323", format: "drivvo",
            scope: "vehicle", candidates: [], unparsed: [], ambiguities: [])

        XCTAssertTrue(model.unsupportedColumns.isEmpty)
        XCTAssertFalse(model.hasUnsupportedColumns)
    }
}
