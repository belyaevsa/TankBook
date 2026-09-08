import TankbookCore
import XCTest
@testable import Tankbook

@MainActor
final class ImportFlowModelDistanceUnitTests: XCTestCase {

    /// An unparsed row has no converted record and therefore no destination
    /// vehicle id. This is reachable while a multi-car mapping is still unset;
    /// the row deliberately uses the model's global fallback rather than
    /// inventing a unit. Miles makes a hardcoded-kilometres fallback fail.
    func testUnsetDestinationUsesGlobalDistanceUnitFallback() throws {
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        var vehicle = TargetCar.newCar(named: "Fallback car").vehicleValue
        vehicle.units.distance = .mi
        try repository.upsertVehicle(vehicle)

        let model = ImportService.makeModel(
            repository: repository,
            configService: AppConfigService.make(arguments: []))
        model.targetCar = nil
        model.carPlan = [ImportCarRow(
            group: ImportVehicleGroup(name: "Unmapped car", sourceRows: [1]))]

        let row = ImportReviewRow(
            sourceRow: 1,
            kind: .unparsed(reason: "unmapped"),
            fill: nil,
            rawLine: "unparsed row")

        XCTAssertNil(model.carPlan[0].destinationVehicle)
        XCTAssertEqual(model.distanceUnit, .mi)
        XCTAssertEqual(model.distanceUnit(for: row), .mi)
    }
}
