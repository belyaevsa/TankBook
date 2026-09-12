import TankbookCore
import XCTest
@testable import Tankbook

/// RV.255 - the commit reports the car it CREATED, so the wizard can land Home
/// on the imported history. These are the model's half: a single new target, the
/// first new lane of the multi-car gate in displayed order, and nil when the
/// import merged into a car the user already owned (which must not move the
/// selection).
@MainActor
final class ImportRV255SelectionTests: XCTestCase {

    private func makeRepository() throws -> TankbookRepository {
        TankbookRepository(database: try TankbookDatabase.inMemory())
    }

    private func makeModel(_ repository: TankbookRepository) -> ImportFlowModel {
        ImportService.makeModel(repository: repository,
                                configService: AppConfigService.make(arguments: []))
    }

    private func fill(_ row: Int, odometer: Int, vehicleName: String?) -> ImportCandidate {
        ImportCandidate(
            entityType: "fillUp",
            date: Date(timeIntervalSince1970: 1_786_924_800), // 2026-08-17
            odometer: odometer, volumeL: 40, unitPrice: "220",
            money: ImportMoney(amount: "8442", currency: "EUR"),
            fuelKind: "petrol92", isFull: true, tankLevelAfterPct: nil, note: nil,
            vehicleName: vehicleName,
            provenance: ImportProvenance(tag: "import", source: "mfm"),
            sourceRow: row)
    }

    private func singleCarParse() -> ImportParseResponse {
        ImportParseResponse(
            importId: "00000000-0000-4000-8000-000000000501", format: "mfm",
            scope: "vehicle", candidates: [fill(1, odometer: 491_206, vehicleName: nil)],
            unparsed: [], ambiguities: [])
    }

    private func twoCarParse() -> ImportParseResponse {
        ImportParseResponse(
            importId: "00000000-0000-4000-8000-000000000502", format: "mfm",
            scope: "vehicle",
            candidates: [fill(1, odometer: 100_000, vehicleName: "Volvo"),
                         fill(2, odometer: 200_000, vehicleName: "Audi")],
            unparsed: [], ambiguities: [],
            vehicleGroups: [ImportVehicleGroup(name: "Volvo", sourceRows: [1]),
                            ImportVehicleGroup(name: "Audi", sourceRows: [2])])
    }

    /// The single new target: the synthesized car is what the commit reports.
    func testSingleNewTargetReportsTheCarItCreated() async throws {
        let repository = try makeRepository()
        let model = makeModel(repository)
        model.adoptSingleFile(fileName: "export.csv", rawData: Data(), parse: singleCarParse())
        model.routeAfterParse(preferredVehicleID: nil)
        guard case .new(let synthesized) = model.targetCar else {
            return XCTFail("no live car, so the import must target a new one")
        }

        let ok = await model.confirmImport()
        XCTAssertTrue(ok)
        XCTAssertEqual(model.createdVehicle?.id, synthesized.id,
                       "the commit must report the car it created")
        XCTAssertEqual(try repository.liveVehicles().count, 1)
    }

    /// The multi-car gate: the FIRST new lane in displayed order is the created
    /// car the wizard selects (the existing lane beside it is not).
    func testMultiCarGateReportsTheFirstCreatedNewLane() async throws {
        let repository = try makeRepository()
        let existing = TargetCar.newCar(named: "Owned", homeCurrency: .eur).vehicleValue
        try repository.upsertVehicle(existing)

        let model = makeModel(repository)
        model.reloadVehicles()
        model.adoptSingleFile(fileName: "export.csv", rawData: Data(), parse: twoCarParse())
        model.routeAfterParse(preferredVehicleID: nil)
        XCTAssertEqual(model.carPlan.count, 2, "the two-car parse reaches the mapping gate")

        model.importIntoExistingVehicle(existing, at: 0)
        model.importAsNewCar(at: 1)
        model.rebuildClassification()
        guard case .new(let newLane) = model.carPlan[1].destination else {
            return XCTFail("lane 1 must be the new car")
        }

        let ok = await model.confirmImport()
        XCTAssertTrue(ok)
        XCTAssertEqual(model.createdVehicle?.id, newLane.id,
                       "the first created lane in displayed order is the selected car")
        XCTAssertNotEqual(model.createdVehicle?.id, existing.id,
                          "the existing lane the user chose must not be reported as created")
    }

    /// A merge into an existing car reports nothing created - the user chose
    /// that car, so the selection must stay exactly where they put it.
    func testExistingCarImportReportsNoCreatedCar() async throws {
        let repository = try makeRepository()
        let existing = TargetCar.newCar(named: "Owned", homeCurrency: .eur).vehicleValue
        try repository.upsertVehicle(existing)

        let model = makeModel(repository)
        model.reloadVehicles()
        model.adoptSingleFile(fileName: "export.csv", rawData: Data(), parse: singleCarParse())
        model.routeAfterParse(preferredVehicleID: nil)
        model.selectExistingVehicle(existing)
        model.rebuildClassification()

        let ok = await model.confirmImport()
        XCTAssertTrue(ok)
        XCTAssertNil(model.createdVehicle,
                     "an import into an existing car creates nothing, so nothing is selected")
    }
}
