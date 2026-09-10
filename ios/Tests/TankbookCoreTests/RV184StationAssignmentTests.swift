import Foundation
import Testing
@testable import TankbookCore

/// RV.184 L1 - the station a scan resolved must reach the stored per-field
/// assignment, exactly as total, volume, price, date, currency and fuel kind do,
/// so the recognised page can show it. The value is what the scan CONCLUDED, not
/// the user's selection: it is presentation only and never feeds the entry
/// (hard rule 13). A parse that resolved no station stores no station field at
/// all (RV.48: absent, never blank).
@Suite("RV.184 the station in the stored assignment")
struct RV184StationAssignmentTests {

    private func decimal(_ string: String) -> Decimal { Decimal(string: string)! }

    // MARK: - The assignment written outside a save

    @Test("a scan that resolved a station stores its value in the assignment")
    func stationStoredInAssignment() {
        let extraction = FuelExtraction(total: decimal("71.02"),
                                        stationName: "Circle K Sikupilli")
        let assignment = ScannedSavePlanner.assignment(from: extraction)
        #expect(assignment?.fields[.station]?.value == .text("Circle K Sikupilli"),
                "the station must be stored as the exact text the scan read")
    }

    @Test("a scan that resolved no station stores no station field, never an empty one")
    func noStationStoresNoField() {
        let extraction = FuelExtraction(liters: 26.94)
        let assignment = ScannedSavePlanner.assignment(from: extraction)
        #expect(assignment != nil, "the volume alone must still produce an assignment")
        #expect(assignment?.fields[.station] == nil,
                "an unread station is ABSENT, never an empty string")
    }

    // MARK: - The scanned save path

    @Test("the scanned save carries the station into the stored assignment")
    func scanSavePathCarriesStation() {
        let extraction = FuelExtraction(total: decimal("71.02"),
                                        stationName: "Circle K Sikupilli")
        let plan = ScannedSavePlanner.plan(
            extraction: extraction, hasPhoto: true,
            saved: ScannedSaveValues(total: decimal("71.02"),
                                     stationName: "Circle K Sikupilli"))
        #expect(plan.extraction?.fields[.station]?.value == .text("Circle K Sikupilli"))
        #expect(plan.extraction?.fields[.station]?.userCorrected == false,
                "a station the user left as proposed is not corrected")
    }

    @Test("a station the user changed is marked corrected, but the stored value stays the scan's")
    func changedStationIsMarkedCorrected() {
        let extraction = FuelExtraction(total: decimal("71.02"),
                                        stationName: "Circle K Sikupilli")
        let plan = ScannedSavePlanner.plan(
            extraction: extraction, hasPhoto: true,
            saved: ScannedSaveValues(total: decimal("71.02"),
                                     stationName: "Neste Järvevana"))
        #expect(plan.extraction?.fields[.station]?.value == .text("Circle K Sikupilli"),
                "the record says what was READ, never what the user chose")
        #expect(plan.extraction?.fields[.station]?.userCorrected == true)
    }

    @Test("the station survives the value-bearing subset the attachment persists")
    func stationSurvivesAssignmentOnly() {
        let extraction = FuelExtraction(total: decimal("71.02"),
                                        stationName: "Circle K Sikupilli")
        let plan = ScannedSavePlanner.plan(
            extraction: extraction, hasPhoto: true,
            saved: ScannedSaveValues(total: decimal("71.02"),
                                     stationName: "Circle K Sikupilli"))
        #expect(plan.extraction?.assignmentOnly?.fields[.station]?.value
                == .text("Circle K Sikupilli"))
    }
}
