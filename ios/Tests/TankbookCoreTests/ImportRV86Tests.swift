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

private func rv86Fill(vehicleId: UUID, odometer: Int, daysAgo: Int) -> FillUp {
    let date = Date(timeIntervalSince1970: 1_752_000_000 - TimeInterval(daysAgo * 86_400))
    return FillUp(
        id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
        vehicleId: vehicleId, date: date, odometer: odometer,
        money: nil, note: nil, attachments: [], provenance: .manual,
        conflict: .none, purchaseGroupId: nil,
        volumeL: 45, unitPrice: nil,
        fuelKind: .diesel, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
        stationId: nil, crossCheck: .notApplicable)
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

// MARK: - The lane partition keeps each car's timeline with its own car

@Suite("RV.86 lane partition never mixes odometers")
struct RV86LanePartitionTests {

    /// Two lanes whose rows INTERLEAVE in file order and whose odometers cross
    /// (car A runs ~500k, car B ~5k). If the wizard classified every row against
    /// one timeline - the RV.86 defect - the interleaving would flag a
    /// timeline break and the low car's rows would ride the high car's vehicle.
    /// Partitioned per lane, each car's history is monotonic and every fill
    /// carries its own lane's vehicle.
    @Test func interleavedLanesKeepTheirOwnVehiclesAndTimelines() {
        let volvo = rv86Vehicle(named: "Volvo")
        let audi = rv86Vehicle(named: "AUDI A4")
        let candidates = [
            rv86Candidate(1, name: "Volvo", odometer: 500_000),
            rv86Candidate(2, name: "AUDI A4", odometer: 5_000),
            rv86Candidate(3, name: "AUDI A4", odometer: 6_000),
            rv86Candidate(4, name: "Volvo", odometer: 501_000),
        ]
        let lanes = [
            ImportLane(sourceRows: [1, 4], vehicle: volvo),
            ImportLane(sourceRows: [2, 3], vehicle: audi),
        ]

        let (ready, review) = ImportReviewClassifier.partitionByLanes(
            candidates: candidates, lanes: lanes,
            existingEntriesByVehicle: [:], unparsed: [], rawLinesByRow: [:],
            source: "mfm")

        #expect(review.isEmpty,
                "per-lane partition must not flag cross-car interleaving as a timeline break")
        #expect(ready.count == 4)
        let volvoFills = ready.filter { $0.vehicleId == volvo.id }
        let audiFills = ready.filter { $0.vehicleId == audi.id }
        #expect(volvoFills.count == 2)
        #expect(audiFills.count == 2)
        #expect(volvoFills.allSatisfy { ($0.odometer ?? 0) > 400_000 },
                "the Volvo lane must never carry the Audi's low odometers")
        #expect(audiFills.allSatisfy { ($0.odometer ?? 0) < 100_000 },
                "the Audi lane must never carry the Volvo's high odometers")
        #expect(ready.allSatisfy { $0.vehicleId == volvo.id || $0.vehicleId == audi.id })
    }

    /// RV.86's headline claim, and the one an orchestrator mutation walked
    /// straight through: each lane must validate against **its own** car's
    /// history. Routing every lane through the union of all cars' entries left
    /// all 1528 tests green, because the rows still LAND in the right vehicle -
    /// only the validation is contaminated, which is exactly the reported
    /// symptom (a Volvo fill judged against the Audi's 426 220 km and flagged
    /// for running backwards).
    ///
    /// The interleaving test above cannot see it: it passes an EMPTY
    /// `existingEntriesByVehicle`, so the union and the per-car lookup are the
    /// same empty list. This one gives each car a real, and very different,
    /// history.
    @Test func aLaneIsValidatedAgainstItsOwnCarsHistoryOnly() {
        let volvo = rv86Vehicle(named: "Volvo")
        let audi = rv86Vehicle(named: "AUDI A4")

        // The Audi is a decade older and 300 000 km ahead - the real shape of
        // the owner's export, where one file holds both.
        let volvoHistory = rv86Fill(vehicleId: volvo.id, odometer: 119_000,
                                    daysAgo: 30)
        let audiHistory = rv86Fill(vehicleId: audi.id, odometer: 420_000,
                                   daysAgo: 30)

        // A perfectly ordinary next Volvo fill: ahead of the Volvo's own last
        // reading, far BEHIND the Audi's.
        let candidates = [rv86Candidate(1, name: "Volvo", odometer: 119_500)]
        let lanes = [ImportLane(sourceRows: [1], vehicle: volvo)]

        let (ready, review) = ImportReviewClassifier.partitionByLanes(
            candidates: candidates, lanes: lanes,
            existingEntriesByVehicle: [volvo.id: [volvoHistory], audi.id: [audiHistory]],
            unparsed: [], rawLinesByRow: [:], source: "mfm")

        #expect(review.isEmpty,
                "a Volvo fill must be judged against the Volvo's own history, never the Audi's")
        #expect(ready.count == 1)
        #expect(ready.first?.vehicleId == volvo.id)
    }

    /// The commit's half is a repository assertion (`commitImport` groups by
    /// vehicle); the lane partition's half is that a fill converted for a lane
    /// really targets the lane's vehicle. A mutation that routes every lane
    /// through the first lane's car fails this before any row is written.
    @Test func eachLanesFillsTargetItsOwnVehicle() throws {
        let volvo = rv86Vehicle(named: "Volvo")
        let audi = rv86Vehicle(named: "AUDI A4")
        let candidates = [
            rv86Candidate(1, name: "Volvo", odometer: 100_000),
            rv86Candidate(2, name: "Volvo", odometer: 101_000),
            rv86Candidate(3, name: "AUDI A4", odometer: 400_000),
            rv86Candidate(4, name: "AUDI A4", odometer: 400_600),
        ]
        let lanes = [
            ImportLane(sourceRows: [1, 2], vehicle: volvo),
            ImportLane(sourceRows: [3, 4], vehicle: audi),
        ]

        let (ready, _) = ImportReviewClassifier.partitionByLanes(
            candidates: candidates, lanes: lanes,
            existingEntriesByVehicle: [:], unparsed: [], rawLinesByRow: [:],
            source: "mfm")

        let byLane = Dictionary(grouping: ready, by: \.vehicleId)
        #expect(byLane[volvo.id]?.count == 2)
        #expect(byLane[audi.id]?.count == 2)
        #expect(byLane[volvo.id]?.compactMap(\.odometer) == [100_000, 101_000])
        #expect(byLane[audi.id]?.compactMap(\.odometer) == [400_000, 400_600])
    }
}
