import TankbookCore
import XCTest
@testable import Tankbook

/// PJ.45 L1: the pace-limit row is a suggestion the user owns (hard rule 13).
/// The form loads the car's value, applies an edit, and refuses to turn a blank
/// or non-positive field into a bound that would flag every entry. Lives in the
/// app-target test bundle because the form state is app code; the SwiftPM core
/// tests run on macOS and cannot reach it.
final class PJ45PaceLimitFormTests: XCTestCase {

    private func vehicle(paceLimit: Double) -> Vehicle {
        let stamp = Date(timeIntervalSinceReferenceDate: 0)
        return Vehicle(
            id: UUID(), createdAt: stamp, updatedAt: stamp, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015, plate: nil,
            powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: 71,
            batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l,
                                 consumption: .lPer100, energy: .kWhPer100),
            photo: nil, paceLimitKmPerDay: paceLimit
        )
    }

    func testEditedPaceLimitIsAppliedAndBlankKeepsTheCarsOwnValue() {
        let original = vehicle(paceLimit: 1500)
        var form = VehicleDetailFormState()
        form.load(from: original, photoData: nil)
        XCTAssertEqual(form.paceLimit, "1500", "the row pre-fills the car's own value")

        form.paceLimit = "2200"
        XCTAssertEqual(form.applying(to: original).paceLimitKmPerDay, 2200,
                       "an edit is the user's value, written onto the car")

        // A blank field is not a decision to remove the bound; neither is a
        // zero, which would flag every entry. The car's own value survives.
        form.paceLimit = ""
        XCTAssertEqual(form.applying(to: original).paceLimitKmPerDay, 1500)
        form.paceLimit = "0"
        XCTAssertEqual(form.applying(to: original).paceLimitKmPerDay, 1500)
    }

    func testLoadedValueRoundTripsWithoutATrailingZero() {
        var form = VehicleDetailFormState()
        form.load(from: vehicle(paceLimit: 900), photoData: nil)
        XCTAssertEqual(form.paceLimit, "900")
        XCTAssertEqual(form.paceLimitValue, 900)
    }
}
