import Foundation
import Testing
@testable import TankbookCore

// RV.93 - one export is several files (fuel.csv, costs.csv, vehicles.csv, ...)
// and the wizard takes them in ONE pass. The server stays a per-file pure
// function (N files = N `POST /v1/import/parse` calls); the device-side merge
// (`ImportBatchMerge`) re-keys every file's rows into one space and unions the
// cars by name, so ONE mapping question answers for every file, and the rows of
// one car from DIFFERENT files validate as ONE timeline.

// MARK: - Fixtures

/// A fill-up candidate whose numbers mirror the committed MFM fixtures
/// (`Spike/ImportFixtures/mfm/fuel.csv`).
private func rv93Fill(_ row: Int, name: String, date: Date, odo: Int,
                      note: String? = nil) -> ImportCandidate {
    ImportCandidate(
        entityType: "fillUp", date: date, odometer: odo, volumeL: 60,
        unitPrice: "1.85", money: ImportMoney(amount: "111.00", currency: "USD"),
        fuelKind: "diesel", isFull: true, tankLevelAfterPct: 100, note: note,
        vehicleName: name, provenance: ImportProvenance(tag: "import", source: "mfm"),
        sourceRow: row)
}

/// A service candidate mirroring the committed costs fixture
/// (`Spike/ImportFixtures/mfm/costs.csv`: the Volvo's 4/27/2026 106722 km
/// "Replacement parts" row). It must convert to a `.noFuel` review row, never a
/// fill, and never a timeline flag when it sits between two real fills.
private func rv93Service(_ row: Int, name: String, date: Date, odo: Int,
                         note: String = "Замена колес зима -> лето") -> ImportCandidate {
    let money = ImportMoney(amount: "133", currency: "USD")
    return ImportCandidate(
        entityType: "serviceRecord", date: date, odometer: odo,
        volumeL: nil, unitPrice: nil, money: money,
        fuelKind: nil, isFull: nil, tankLevelAfterPct: nil, note: note,
        vehicleName: name, provenance: ImportProvenance(tag: "import", source: "mfm"),
        sourceRow: row,
        items: [ImportServiceItem(title: "Replacement parts",
                                  category: ImportCategoryTag(tag: "parts"),
                                  cost: money)])
}

private func rv93Parse(id: String, candidates: [ImportCandidate],
                       groups: [ImportVehicleGroup]) -> ImportParseResponse {
    ImportParseResponse(importId: id, format: "mfm", scope: "vehicle",
                        candidates: candidates, unparsed: [],
                        ambiguities: [],
                        vehicleGroups: groups)
}

private func rv93Vehicle(named name: String) -> Vehicle {
    Vehicle(
        id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
        name: name, make: nil, model: nil, year: nil, plate: nil,
        powertrain: .ice, fuelKinds: [.diesel], tankCapacityL: 70,
        batteryCapacityKWh: nil, homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                              energy: .kWhPer100),
        photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: nil)
}

private let april20 = Date(timeIntervalSince1970: 1_776_643_200)  // 2026-04-20
private let april27 = Date(timeIntervalSince1970: 1_777_248_000)  // 2026-04-27
private let may3 = Date(timeIntervalSince1970: 1_777_766_400)     // 2026-05-03

// MARK: - The union grouping asks once per distinct car

@Suite("RV.93 the union grouping asks once per distinct car")
struct RV93UnionGroupingTests {

    /// The fuel file holds two cars; the costs file holds one of the same
    /// (Volvo). Per-file mapping would ask THREE questions (Volvo, AUDI from
    /// fuel; Volvo again from costs). The union must ask TWO - one per distinct
    /// source car - and the Volvo's lane must carry every file's Volvo rows.
    @Test func severalFilesYieldOneMappingQuestionPerDistinctCar() {
        let fuel = rv93Parse(
            id: "fuel", candidates: [
                rv93Fill(1, name: "Volvo", date: april20, odo: 106_470),
                rv93Fill(2, name: "Volvo", date: may3, odo: 107_292),
                rv93Fill(3, name: "AUDI A4", date: april20, odo: 420_000),
                rv93Fill(4, name: "AUDI A4", date: may3, odo: 421_000),
            ],
            groups: [ImportVehicleGroup(name: "Volvo", sourceRows: [1, 2]),
                     ImportVehicleGroup(name: "AUDI A4", sourceRows: [3, 4])])
        let costs = rv93Parse(
            id: "costs", candidates: [
                rv93Service(1, name: "Volvo", date: april27, odo: 106_722),
            ],
            groups: [ImportVehicleGroup(name: "Volvo", sourceRows: [1])])

        let merged = ImportBatchMerge.merge(
            files: [ImportParsedFile(parse: fuel, rawLines: [:]),
                    ImportParsedFile(parse: costs, rawLines: [1: "costs row"])],
            dateFormatAnswer: nil)

        #expect(merged != nil)
        let groups = merged?.parse.resolvedVehicleGroups ?? []
        #expect(groups.count == 2,
                "the union names TWO distinct cars, never one per file (was \(groups.map(\.name)))")
        #expect(groups.map(\.name) == ["Volvo", "AUDI A4"])

        // The Volvo lane carries the fuel file's rows AND the costs file's row
        // (its global re-key). The costs file starts after the fuel file's
        // highest local row (4), so its row 1 lands at global 5.
        let volvo = groups[0]
        #expect(volvo.sourceRows == [1, 2, 5],
                "the Volvo's single lane holds every file's Volvo rows: \(volvo.sourceRows)")
        #expect(groups[1].sourceRows == [3, 4])
    }

    /// A single-file pick is byte-for-byte unchanged by the merge: one file,
    /// one group set, no re-keying.
    @Test func aSingleFileMergeLeavesRowsAndGroupsUntouched() {
        let fuel = rv93Parse(
            id: "fuel", candidates: [
                rv93Fill(1, name: "Volvo", date: april20, odo: 106_470),
                rv93Fill(2, name: "AUDI A4", date: may3, odo: 420_000),
            ],
            groups: [ImportVehicleGroup(name: "Volvo", sourceRows: [1]),
                     ImportVehicleGroup(name: "AUDI A4", sourceRows: [2])])

        let merged = ImportBatchMerge.merge(
            files: [ImportParsedFile(parse: fuel, rawLines: [1: "a", 2: "b"])],
            dateFormatAnswer: nil)
        let groups = merged?.parse.resolvedVehicleGroups ?? []
        #expect(groups.map(\.name) == ["Volvo", "AUDI A4"])
        #expect(merged?.parse.candidates.map(\.sourceRow) == [1, 2])
        #expect(merged?.parse.candidates.first?.vehicleName == "Volvo")
        #expect(merged?.rawLinesByRow[1] == "a")
        #expect(merged?.rawLinesByRow[2] == "b")
    }
}

// MARK: - One timeline across the files of one car

@Suite("RV.93 cross-file rows are one timeline")
struct RV93CrossFileTimelineTests {

    private func lane(merged: ImportBatchView, named name: String,
                      vehicle: Vehicle) -> ImportLane? {
        guard let group = merged.parse.resolvedVehicleGroups.first(where: { $0.name == name }) else {
            return nil
        }
        return ImportLane(sourceRows: group.sourceRows, vehicle: vehicle)
    }

    /// The row's real point, built from the committed fixtures: a Volvo costs
    /// service at 106 722 km on 4/27 sits BETWEEN two real Volvo fuel fills
    /// (4/20 @ 106 470 and 5/3 @ 107 292). In ONE lane the service is offered
    /// as what it is (a `.noFuel` row), and neither fill nor service flags.
    @Test func costsServiceBetweenTwoFillsDoesNotFlagEither() {
        let fuel = rv93Parse(
            id: "fuel", candidates: [
                rv93Fill(1, name: "Volvo", date: april20, odo: 106_470),
                rv93Fill(2, name: "Volvo", date: may3, odo: 107_292),
            ],
            groups: [ImportVehicleGroup(name: "Volvo", sourceRows: [1, 2])])
        let costs = rv93Parse(
            id: "costs", candidates: [
                rv93Service(1, name: "Volvo", date: april27, odo: 106_722),
            ],
            groups: [ImportVehicleGroup(name: "Volvo", sourceRows: [1])])
        let merged = ImportBatchMerge.merge(
            files: [ImportParsedFile(parse: fuel, rawLines: [:]),
                    ImportParsedFile(parse: costs, rawLines: [:])],
            dateFormatAnswer: nil)!

        let vehicle = rv93Vehicle(named: "Volvo")
        guard let volvoLane = lane(merged: merged, named: "Volvo", vehicle: vehicle) else {
            Issue.record("the merged view must expose the Volvo lane")
            return
        }
        let (ready, review) = ImportReviewClassifier.partitionByLanes(
            candidates: merged.parse.candidates, lanes: [volvoLane],
            existingEntriesByVehicle: [:], unparsed: merged.parse.unparsed,
            rawLinesByRow: merged.rawLinesByRow, source: "mfm")

        #expect(ready.count == 2,
                "both fills are ready - the merged timeline must not flag them")
        #expect(ready.compactMap(\.odometer).sorted() == [106_470, 107_292])
        #expect(review.count == 1,
                "the service is the one review row - offered as what it is, never flagged")
        #expect(review.allSatisfy { row in
            if case .timelineConflict = row.kind { return false }
            return true
        }, "a service between two fills must not flag either fill or itself")
        #expect(review.first?.nonFuel != nil,
                "the service row is importable as a service (PJ.9)")
    }

    /// The mechanism the benign case rests on: validation really sees ACROSS
    /// the files. A same-car fill in the second file dated 4/27 at an odometer
    /// ABOVE the first file's 5/3 fill is a genuine contradiction of the ONE
    /// timeline (4/27 107500 then 5/3 107292) and must flag in the merged lane -
    /// whereas validating each file alone (the "sort by file, then date" shape)
    /// would miss it entirely: both files are internally monotonic. A mutation
    /// that classifies per file, never per car, fails here.
    @Test func acrossFileContradictionIsFlaggedBecauseTheTimelineIsOne() {
        let fuel = rv93Parse(
            id: "fuel", candidates: [
                rv93Fill(1, name: "Volvo", date: april20, odo: 106_470),
                rv93Fill(2, name: "Volvo", date: may3, odo: 107_292),
            ],
            groups: [ImportVehicleGroup(name: "Volvo", sourceRows: [1, 2])])
        let second = rv93Parse(
            id: "second", candidates: [
                rv93Fill(1, name: "Volvo", date: april27, odo: 107_500),
            ],
            groups: [ImportVehicleGroup(name: "Volvo", sourceRows: [1])])
        let merged = ImportBatchMerge.merge(
            files: [ImportParsedFile(parse: fuel, rawLines: [:]),
                    ImportParsedFile(parse: second, rawLines: [:])],
            dateFormatAnswer: nil)!

        let vehicle = rv93Vehicle(named: "Volvo")
        guard let volvoLane = lane(merged: merged, named: "Volvo", vehicle: vehicle) else {
            Issue.record("the merged view must expose the Volvo lane")
            return
        }
        let (ready, review) = ImportReviewClassifier.partitionByLanes(
            candidates: merged.parse.candidates, lanes: [volvoLane],
            existingEntriesByVehicle: [:], unparsed: merged.parse.unparsed,
            rawLinesByRow: merged.rawLinesByRow, source: "mfm")

        #expect(review.contains { row in
            if case .timelineConflict = row.kind { return true }
            return row.fill != nil
        }, "the 5/3 fill must land in review, not ready: it is lower than the 4/27 fill")
        #expect(ready.count < 2,
                "the contradictory cross-file pair must not both be ready")
    }
}

// MARK: - The write order: vehicles first, entries second

@Suite("RV.93 vehicles are written before the entries that reference them")
struct RV93WriteOrderTests {

    /// The commit's effect, not its call order: after the vehicles-first write,
    /// the entries land on the cars the mapping chose, and only those cars.
    @Test func wholeExportCommitLandsEachFileKindOnItsMappedCar() throws {
        let repo = try TankbookRepository(database: TankbookDatabase.inMemory())
        let fuel = rv93Parse(
            id: "fuel", candidates: [
                rv93Fill(1, name: "Volvo", date: april20, odo: 106_470),
                rv93Fill(2, name: "Volvo", date: may3, odo: 107_292),
                rv93Fill(3, name: "AUDI A4", date: april20, odo: 420_000),
            ],
            groups: [ImportVehicleGroup(name: "Volvo", sourceRows: [1, 2]),
                     ImportVehicleGroup(name: "AUDI A4", sourceRows: [3])])
        let costs = rv93Parse(
            id: "costs", candidates: [
                rv93Service(1, name: "Volvo", date: april27, odo: 106_722),
            ],
            groups: [ImportVehicleGroup(name: "Volvo", sourceRows: [1])])
        let merged = ImportBatchMerge.merge(
            files: [ImportParsedFile(parse: fuel, rawLines: [:]),
                    ImportParsedFile(parse: costs, rawLines: [:])],
            dateFormatAnswer: nil)!

        let volvoCar = rv93Vehicle(named: "Volvo")
        let audiCar = rv93Vehicle(named: "AUDI A4")
        let lanes: [ImportLane] = merged.parse.resolvedVehicleGroups.compactMap { group in
            let vehicle = group.name == "Volvo" ? volvoCar : audiCar
            return ImportLane(sourceRows: group.sourceRows, vehicle: vehicle)
        }
        let (ready, review) = ImportReviewClassifier.partitionByLanes(
            candidates: merged.parse.candidates, lanes: lanes,
            existingEntriesByVehicle: [:], unparsed: merged.parse.unparsed,
            rawLinesByRow: merged.rawLinesByRow, source: "mfm")
        var records = ready.map { ArchiveImportRecord.fillUp($0) }
        for row in review where row.nonFuel != nil {
            // The service row is imported as the service it is (PJ.9).
            switch row.nonFuel! {
            case .service(let service): records.append(.serviceRecord(service))
            case .expense(let expense): records.append(.expense(expense))
            }
        }

        // Vehicles first (the app's confirmImport upserts the new cars before
        // the one commitImport), then the single write.
        try repo.upsertVehicle(volvoCar)
        try repo.upsertVehicle(audiCar)
        try repo.commitImport(records, source: "mfm")

        let volvoFills = try repo.liveFillUps(forVehicle: volvoCar.id)
        let audiFills = try repo.liveFillUps(forVehicle: audiCar.id)
        #expect(volvoFills.count == 2,
                "the fuel file's Volvo fills land on the Volvo car")
        #expect(audiFills.count == 1,
                "the fuel file's AUDI fill lands on the AUDI car")
        let volvoServices = try repo.serviceRecordsIncludingDeleted(forVehicle: volvoCar.id)
        #expect(volvoServices.count == 1,
                "the costs file's service lands on the Volvo car - BOTH file kinds land")
        #expect(try repo.liveVehicles().count == 2)
    }

    /// Why the order is load-bearing: an entry cannot be written before its
    /// vehicle exists (foreign keys are on). A mutation that commits the
    /// entries first fails here before any row is visible - the entries cannot
    /// reference a car that does not exist yet.
    @Test func entriesCannotBeWrittenBeforeTheirVehicleExists() throws {
        let repo = try TankbookRepository(database: TankbookDatabase.inMemory())
        let vehicle = rv93Vehicle(named: "Volvo")
        let candidate = rv93Fill(1, name: "Volvo", date: april20, odo: 106_470)
        let fill = try #require(ImportConverter.makeFill(from: candidate, vehicle: vehicle,
                                                         source: "mfm"))

        #expect(throws: Error.self) {
            try repo.commitImport([.fillUp(fill)], source: "mfm")
        }

        // Once the vehicle exists, the same entry commits and lands on it.
        try repo.upsertVehicle(vehicle)
        try repo.commitImport([.fillUp(fill)], source: "mfm")
        #expect(try repo.liveFillUps(forVehicle: vehicle.id).count == 1)
    }
}
