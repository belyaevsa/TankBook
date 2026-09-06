import Foundation
import Testing
@testable import TankbookCore

// RV.86 - the parse exposes the source file's distinct vehicles so the import
// can ask which cars to bring in (docs/TASKS.md RV.86). The wire carries the
// grouping from the parser; older stored parses and seeds lack the field, so the
// model derives the same groups from each candidate's `vehicleName`.

// MARK: - Fixtures

private func rv86Candidate(_ sourceRow: Int, name: String?, odometer: Int? = nil) -> ImportCandidate {
    ImportCandidate(
        entityType: "fillUp",
        date: Date(timeIntervalSince1970: 1_752_000_000 + TimeInterval(sourceRow * 86_400)),
        odometer: odometer ?? 100_000 + sourceRow, volumeL: 45, unitPrice: "1.7",
        money: ImportMoney(amount: "76.50", currency: "USD"),
        fuelKind: "diesel", isFull: true, tankLevelAfterPct: 100,
        note: nil, vehicleName: name,
        provenance: ImportProvenance(tag: "import", source: "mfm"),
        sourceRow: sourceRow)
}

private func rv86Vehicle(named name: String) -> Vehicle {
    Vehicle(
        id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
        name: name, make: nil, model: nil, year: nil, plate: nil,
        powertrain: .ice, fuelKinds: [.diesel], tankCapacityL: 70,
        batteryCapacityKWh: nil, homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                              energy: .kWhPer100),
        photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: nil)
}

// MARK: - Grouping on the parse

@Suite("RV.86 parse vehicle groups")
struct RV86ParseGroupsTests {

    @Test func groupsAreResolvedFromTheWireField() {
        let candidates = [
            rv86Candidate(1, name: "Volvo"),
            rv86Candidate(2, name: "Volvo"),
            rv86Candidate(3, name: "AUDI A4"),
        ]
        let parse = ImportParseResponse(
            importId: "id", format: "mfm", scope: "vehicle",
            candidates: candidates, unparsed: [], ambiguities: [],
            vehicleGroups: [ImportVehicleGroup(name: "Volvo", sourceRows: [1, 2]),
                            ImportVehicleGroup(name: "AUDI A4", sourceRows: [3])])

        let groups = parse.resolvedVehicleGroups
        #expect(groups.count == 2)
        #expect(groups[0].name == "Volvo")
        #expect(groups[0].sourceRows == [1, 2])
        #expect(groups[1].name == "AUDI A4")
        #expect(parse.candidates(in: groups[0]).map(\.sourceRow) == [1, 2])
    }

    @Test func groupsAreDerivedWhenTheWireFieldIsAbsent() {
        // A parse stored before RV.86 (or a seed) has no vehicleGroups; the
        // device must derive the same grouping from each candidate's name.
        let candidates = [
            rv86Candidate(1, name: "Volvo"),
            rv86Candidate(2, name: "Volvo"),
            rv86Candidate(3, name: "AUDI A4"),
        ]
        let parse = ImportParseResponse(
            importId: "id", format: "mfm", scope: "vehicle",
            candidates: candidates, unparsed: [], ambiguities: [])

        let groups = parse.resolvedVehicleGroups
        #expect(groups.count == 2)
        #expect(groups[0].name == "Volvo")
        #expect(groups[1].name == "AUDI A4")
    }

    @Test func aSingleNameFileResolvesToOneGroup() {
        let parse = ImportParseResponse(
            importId: "id", format: "mfm", scope: "vehicle",
            candidates: [rv86Candidate(1, name: "Volvo"), rv86Candidate(2, name: "Volvo")],
            unparsed: [], ambiguities: [])
        let groups = parse.resolvedVehicleGroups
        #expect(groups.count == 1)
        #expect(groups[0].name == "Volvo")
        #expect(groups[0].sourceRows.count == 2)
    }
}

// MARK: - The commit keeps each group's odometers with its own vehicle

@Suite("RV.86 per-group commit never mixes odometers")
struct RV86PerGroupCommitTests {

    @Test func twoGroupsCommitToTwoVehiclesAndNeverMixOdometers() throws {
        let repo = try TankbookRepository(database: TankbookDatabase.inMemory())
        let volvo = rv86Vehicle(named: "Volvo")
        let audi = rv86Vehicle(named: "Audi A4")
        try repo.upsertVehicle(volvo)
        try repo.upsertVehicle(audi)

        // Volvo group: low odometers. Audi group: much higher odometers. If the
        // commit merged them into one car, the per-car continuity test would
        // see the Audi's high readings inside the Volvo.
        let candidates = [
            rv86Candidate(1, name: "Volvo", odometer: 100_000),
            rv86Candidate(2, name: "Volvo", odometer: 101_000),
            rv86Candidate(3, name: "Audi A4", odometer: 200_000),
            rv86Candidate(4, name: "Audi A4", odometer: 201_500),
        ]
        let parse = ImportParseResponse(
            importId: "id", format: "mfm", scope: "vehicle",
            candidates: candidates, unparsed: [], ambiguities: [],
            vehicleGroups: [ImportVehicleGroup(name: "Volvo", sourceRows: [1, 2]),
                            ImportVehicleGroup(name: "Audi A4", sourceRows: [3, 4])])

        // Build fills targeting each group's own vehicle - the same conversion
        // the import flow performs once the user maps each source car to a car.
        let records: [ArchiveImportRecord] = parse.resolvedVehicleGroups.flatMap { group in
            let vehicle = group.name == "Volvo" ? volvo : audi
            return parse.candidates(in: group).compactMap {
                ImportConverter.makeFill(from: $0, vehicle: vehicle, source: "mfm")
            }.map { ArchiveImportRecord.fillUp($0) }
        }
        #expect(records.count == 4)
        try repo.commitImport(records, source: "mfm")

        let volvoFills = try repo.liveFillUps(forVehicle: volvo.id)
        let audiFills = try repo.liveFillUps(forVehicle: audi.id)
        #expect(volvoFills.count == 2)
        #expect(audiFills.count == 2)
        #expect(volvoFills.compactMap(\.odometer).max() ?? 0 < 102_000,
                "the Volvo must not contain the Audi's odometers")
        #expect(audiFills.compactMap(\.odometer).min() ?? 0 > 199_000,
                "the Audi must not contain the Volvo's odometers")
        #expect(volvoFills.allSatisfy { $0.vehicleId == volvo.id })
        #expect(audiFills.allSatisfy { $0.vehicleId == audi.id })
    }
}
