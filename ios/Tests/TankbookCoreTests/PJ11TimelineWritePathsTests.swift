import Foundation
import Testing
@testable import TankbookCore

// PJ.11 - F9a is checked on EVERY write, not just capture (docs/JOURNEYS.md
// F9a, docs/TASKS.md PJ.11). Three guarantees are pinned here at L1:
//
// 1. A service record below its date-neighbour saves `.flagged`, and a
//    plausible one saves `.none` - the save semantics the ServiceEntry view
//    stamps on every create/edit (both halves).
// 2. The import path surfaces and commits the real MFM `9` row flagged and
//    excluded from the consumption span, leaving its 15 neighbours untouched
//    (`Spike/ImportFixtures/mfm/README.md`: the defect is deliberate, kept).
// 3. The source-scan guard enumerates the CLASS of entry-write paths in the
//    app (a fifth write path must not appear unflagged), following the
//    `productionCallSitesMatchTheWiredAndUnwiredSplit` pattern.

private let day: TimeInterval = 86_400
private let epoch = Date(timeIntervalSince1970: 1_752_000_000)

// MARK: - Fixtures

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string)!
}

private func vehicle() -> Vehicle {
    Vehicle(
        id: UUID.v7(), createdAt: epoch, updatedAt: epoch, deletedAt: nil,
        name: "Volvo V60", make: "Volvo", model: "V60", year: 2015, plate: nil,
        powertrain: .ice, fuelKinds: [.diesel, .petrol95], tankCapacityL: 71,
        batteryCapacityKWh: nil, homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                             energy: .kWhPer100),
        photo: nil, archived: false, paceLimitKmPerDay: 1500,
        initialOdometer: 100_000)
}

private func fill(date: Date, odometer: Int, volumeL: Double = 40,
                  vehicleId: UUID = UUID.v7()) -> FillUp {
    FillUp(
        id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
        vehicleId: vehicleId, date: date, odometer: odometer,
        money: nil, note: nil, attachments: [], provenance: .manual,
        conflict: .none, purchaseGroupId: nil, volumeL: volumeL,
        unitPrice: nil, fuelKind: .diesel, fuelGrade: nil,
        isFull: true, tankLevelAfterPct: 100, stationId: nil,
        crossCheck: .notApplicable, extraction: nil)
}

/// The exact save semantics of `ServiceEntryView.save` (PJ.11): build the
/// record from the form's draft, stamp `conflict` from `TimelineValidator`
/// against the merged timeline, persist. Extracted so the L1 test drives the
/// same conversion the view does - never a hand-rolled record.
private func saveService(draft: ServiceEntryDraft,
                         into repository: TankbookRepository,
                         vehicle: Vehicle) throws -> ServiceRecord {
    var service = draft.build(vehicleId: vehicle.id, homeCurrency: vehicle.homeCurrency)
    let existing = try repository.liveEntries(forVehicle: vehicle.id)
    let validations = TimelineValidator.validate(entries: existing + [service],
                                                 vehicle: vehicle)
    service.conflict = validations.first { $0.entryID == service.id }?.conflict ?? .none
    try repository.upsertServiceRecord(service)
    return service
}

// MARK: - 1. The service save stamps conflict (both halves)

@Suite("PJ.11 service save stamps conflict")
struct PJ11ServiceSaveTests {

    private static func draft(date: Date, odometer: Int?) -> ServiceEntryDraft {
        ServiceEntryDraft(
            vendor: "Bosch Service",
            items: [ServiceItem.make(title: "Oil service incl. filter", category: .oil,
                                     cost: Money(amount: decimal("89.00"), currency: .eur,
                                                 homeCurrency: .eur))],
            date: date, odometer: odometer)
    }

    @Test func aServiceRecordBelowItsNeighbourSavesFlagged() throws {
        let repo = try TankbookRepository(database: TankbookDatabase.inMemory())
        let car = vehicle()
        try repo.upsertVehicle(car)
        try repo.upsertFillUp(fill(date: epoch, odometer: 100_000, vehicleId: car.id))

        // The candidate service is dated AFTER the prior fill but its odometer
        // is BELOW it - the F9a typo (119 486 -> 11 948). The save must stamp
        // `.flagged`, never write `.none`.
        let saved = try saveService(draft: Self.draft(date: epoch + 5 * day, odometer: 9_950),
                                    into: repo, vehicle: car)

        #expect(saved.conflict != .none, "a service below its neighbour must save flagged")
        if case .flagged(let kind, _) = saved.conflict {
            #expect(kind == .order)
        }
        #expect(try repo.liveServiceRecords(forVehicle: car.id).first.map { $0.conflict != .none } == true,
                "the flag must land with the save, not be derived later")
    }

    @Test func aPlausibleServiceRecordSavesClean() throws {
        let repo = try TankbookRepository(database: TankbookDatabase.inMemory())
        let car = vehicle()
        try repo.upsertVehicle(car)
        try repo.upsertFillUp(fill(date: epoch, odometer: 100_000, vehicleId: car.id))

        let saved = try saveService(draft: Self.draft(date: epoch + 5 * day, odometer: 100_500),
                                    into: repo, vehicle: car)

        #expect(saved.conflict == .none)
        #expect(try repo.liveServiceRecords(forVehicle: car.id).first.map { $0.conflict == .none } == true,
                "the plausible service must read back clean from the store")
    }

    @Test func aFlaggedServiceIsStillSaveable() throws {
        // Hard rules 7 and 13: the flag is a warning, never a refusal. The
        // save helper persists a flagged record without throwing, and the
        // repository returns it with the flag intact.
        let repo = try TankbookRepository(database: TankbookDatabase.inMemory())
        let car = vehicle()
        try repo.upsertVehicle(car)
        try repo.upsertFillUp(fill(date: epoch, odometer: 100_000, vehicleId: car.id))

        let saved = try saveService(draft: Self.draft(date: epoch + 5 * day, odometer: 9_950),
                                    into: repo, vehicle: car)
        #expect(saved.conflict != .none)
    }
}

// MARK: - 2. The MFM `9` row (Spike/ImportFixtures/mfm, read-only)

@Suite("PJ.11 the MFM 9 row")
struct PJ11MfmNineRowTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // TankbookCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // ios
        .deletingLastPathComponent()  // the repo root

    private static let fixtureURL = repoRoot
        .appendingPathComponent("Spike/ImportFixtures/mfm/parsed.json")

    private static func fixtureCandidates() throws -> [ImportCandidate] {
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ImportParseResponse.self, from: data).candidates
    }

    /// The 16-row slice around the defect: the `9` row (sourceRow 39, the real
    /// Volvo typo on 4/14/2025) plus the 15 rows nearest in date. Picked so the
    /// remaining 15 form a STRICTLY increasing odometer with DISTINCT dates -
    /// the `9` row is the only violation, and its flag is deterministic (the
    /// same-date row 38 is deliberately excluded so no UUID tie-break decides
    /// the outcome).
    private static let sliceRows: Set<Int> = [
        30, 31, 32, 33, 34, 35, 36, 37, 39, 40, 41, 42, 43, 44, 45, 46,
    ]

    @Test func theNineRowCommitsFlaggedAndTheOtherFifteenUntouched() throws {
        let candidates = try Self.fixtureCandidates().filter { Self.sliceRows.contains($0.sourceRow) }
        #expect(candidates.count == 16, "the slice must hold the 9 row plus 15 neighbours")
        guard let nine = candidates.first(where: { $0.sourceRow == 39 }) else {
            Issue.record("the fixture must carry the Volvo 9 row (sourceRow 39)")
            return
        }
        #expect(nine.odometer == 9, "the fixture's defect row reads odometer 9 (Spike README: do not clean it)")
        let realOdometers = Set(candidates.compactMap(\.odometer))

        let car = vehicle()
        let repo = try TankbookRepository(database: TankbookDatabase.inMemory())
        try repo.upsertVehicle(car)

        // The classifier surfaces the 9 row in the review list BEFORE anything
        // is written (F6a) - a flagged-order row the user sees and decides on.
        // F9a: a bad odometer poisons its two date-neighbours too, so rows 37
        // and 40 join the 9 in review; the other 13 are ready.
        let (ready, review) = ImportReviewClassifier.partition(
            candidates: candidates, unparsed: [], rawLinesByRow: [:],
            vehicle: car, source: "mfm", existingEntries: [])
        guard let nineRow = review.first(where: { $0.sourceRow == 39 }) else {
            Issue.record("the 9 row must land in the review list, not the ready set")
            return
        }
        if case .timelineConflict(let kind) = nineRow.kind {
            #expect(kind == .order)
        } else {
            Issue.record("the 9 row must be badged .timelineConflict, got \(nineRow.kind)")
        }
        #expect(ready.count + review.count == 16, "every slice row is either ready or in review")
        #expect(review.allSatisfy { row in
            if case .timelineConflict = row.kind { return true }
            return false
        }, "the 9 row and its poisoned neighbours are all timeline rows, nothing else")

        // Commit everything: the 9 row writes `.flagged`, and NOT ONE row's
        // odometer is repaired, dropped or coerced - the other 15 are
        // untouched (Spike README: do not clean it, hard rule 8).
        let records = (ready + review.compactMap(\.fill)).map { ArchiveImportRecord.fillUp($0) }
        try repo.commitImport(records, source: "mfm")

        let committed = try repo.liveFillUps(forVehicle: car.id)
        #expect(committed.count == 16)
        let nineFills = committed.filter { $0.odometer == 9 }
        #expect(nineFills.count == 1, "the 9 row commits exactly once, never dropped")
        #expect(nineFills[0].conflict != .none,
                "the 9 row must commit flagged (hard rule 8: shown, never silently fixed)")
        #expect(Set(committed.compactMap(\.odometer)) == realOdometers,
                "every committed odometer is the file's real value - the other 15 rows are untouched, never repaired")
    }

    @Test func theNineRowIsExcludedFromTheConsumptionSpan() throws {
        let candidates = try Self.fixtureCandidates().filter { Self.sliceRows.contains($0.sourceRow) }
        let car = vehicle()
        let repo = try TankbookRepository(database: TankbookDatabase.inMemory())
        try repo.upsertVehicle(car)

        let (ready, review) = ImportReviewClassifier.partition(
            candidates: candidates, unparsed: [], rawLinesByRow: [:],
            vehicle: car, source: "mfm", existingEntries: [])
        let records = (ready + review.compactMap(\.fill)).map { ArchiveImportRecord.fillUp($0) }
        try repo.commitImport(records, source: "mfm")
        let committed = try repo.liveFillUps(forVehicle: car.id)
        let nineFill = committed.first { $0.odometer == 9 }!

        // A naive span would read 97 822 - 9 = 97 813 km and report an
        // impossible ~0.06 L/100km. The engine must EXCLUDE the 9 row: no
        // segment may open or close on it, and the consumption it yields is a
        // real car's figure, not the naive one.
        let segments = ConsumptionEngine.recompute(fills: committed,
                                                   tankCapacityL: car.tankCapacityL)
        #expect(segments.allSatisfy { $0.openingFillID != nineFill.id && $0.closingFillID != nineFill.id },
                "a flagged entry's segments are excluded - one bad odometer must not poison the span (F9a)")
        let lifetime = ImportConsumption.compute(fills: committed,
                                                 tankCapacityL: car.tankCapacityL)
        guard let lifetime else {
            Issue.record("the slice must still produce a consumption figure over its conflict-free segments")
            return
        }
        #expect(lifetime > 1, "excluded-span consumption must be a plausible figure, got \(lifetime) L/100km")
        #expect(lifetime < 20, "excluded-span consumption must be plausible, got \(lifetime) L/100km")
    }
}

// MARK: - Source-scan guard over the class of write paths

@Suite("PJ.11 write-path guard")
struct PJ11WritePathGuardTests {

    /// Enumerates every repository entry-write call in the app's PRODUCTION
    /// sources (test-seed fixtures excluded) and pins the decision for each.
    /// A fifth write path cannot appear unflagged.
    ///
    /// The class: `repository.upsert{FillUp,ChargeSession,ServiceRecord,Expense}`
    /// and `repository.commitImport`. Each found site is decided here:
    ///
    /// STAMPS - the validator is consulted on this write:
    /// - ServiceEntryView.save  (upsertServiceRecord) - the typed/scanned service
    /// - ExpenseEntryView.save  (upsertExpense) - the expense entry
    /// - EditEntryView.saveNonFill (upsertChargeSession / upsertServiceRecord /
    ///   upsertExpense) - edits of the three non-fill types
    /// - EditEntryView.saveFill (upsertFillUp) - the fill edit, stamped inside
    ///   `buildUpdatedFill` (EditEntryFormState.swift)
    /// - ManualFillUpView.save (upsertFillUp) - the manual fill, stamped inside
    ///   `buildFillUp`
    /// - ImportFlowModel.confirmImport (commitImport) - stamped at commit by
    ///   core's `stampingImportConflicts` (Repository+ArchiveImport.swift)
    ///
    /// JUSTIFIED EXEMPTIONS - the write cannot introduce a timeline violation:
    /// - ManualFillUpView.save (upsertExpense) - the mixed-receipt expense is
    ///   constructed with `odometer: nil`, so the validator's verdict is
    ///   trivially `.none` (ConfirmManual/** is outside PJ.11's edit scope)
    /// - HomeView.mergeDuplicate (upsertFillUp) - the S2 merge keeps the
    ///   winner's date and odometer (`DuplicateMerge.merge`); both halves were
    ///   already validated rows of this timeline (Home/** is outside PJ.11's
    ///   scope)
    /// - AppInbox.resolve (upsertFillUp) - RV.38's blank-fields-only merge fills
    ///   a nil `unitPrice` and recomputes the cross-check; it never touches
    ///   `date` or `odometer`, so the timeline verdict is unchanged and the
    ///   stored `conflict` is carried through (the inbox is outside PJ.11's
    ///   edit scope)
    ///
    /// EXCLUDED - every `*TestSeed.swift` file and the `TankLevelTestSeed`
    /// block in TankLevelView.swift construct deterministic fixtures, not
    /// write paths. Core's own writers are decided, not scanned: the sync
    /// merge revalidates after (`revalidateTimeline`, SYNC.md S3),
    /// `MoneyBackfillService` changes money only (conflict carried through),
    /// and `VehicleArchiveReader`'s restore preserves the archive's stored
    /// conflict values.
    ///
    /// What a text scan cannot see, said plainly: it matches the literal
    /// `repository.<func>(` call. A write routed through a variable
    /// (`let save = repository.upsertFillUp; ... save(x)`) or a repository
    /// method that writes entries without one of these five names is invisible
    /// to it and would read as "no write path". None of today's writers do
    /// that; if one ever does, extend the scan rather than trusting it.
    @Test func everyProductionEntryWritePathStampsOrIsJustified() throws {
        let found = try Self.entryWriteCallSites()

        let stamps: Set<String> = [
            "(ServiceEntryView, upsertServiceRecord)",
            "(ExpenseEntryView, upsertExpense)",
            "(EditEntryView, upsertChargeSession)",
            "(EditEntryView, upsertServiceRecord)",
            "(EditEntryView, upsertExpense)",
            "(EditEntryView, upsertFillUp)",
            "(ManualFillUpView, upsertFillUp)",
            "(ImportFlowModel, commitImport)",
        ]
        let exemptions: Set<String> = [
            "(ManualFillUpView, upsertExpense)",
            "(HomeView, upsertFillUp)",
            "(AppInbox, upsertFillUp)",
        ]

        let pinned = stamps.union(exemptions)
        #expect(found == pinned,
                "a write path appeared that PJ.11 did not decide: \(found.sorted()) vs \(pinned.sorted())")

        // Every stamped site consults the validator. The four app-local stamp
        // sites hold a TimelineValidator.validate call in the same file; the
        // import commit's stamp lives in core and is pinned separately.
        for site in stamps {
            let file = String(site.split(separator: ",")[0].dropFirst())
            if file == "ImportFlowModel" { continue }
            #expect(try Self.appSource(named: file).contains("TimelineValidator.validate"),
                    "\(file) must consult TimelineValidator.validate on its write (a stamped path)")
        }
        let archive = try Self.coreSource("Backup/Repository+ArchiveImport.swift")
        #expect(archive.contains("stampingImportConflicts"),
                "the import commit must re-stamp conflicts in core (Repository+ArchiveImport.swift)")

        // The TankLevelView seed write is pinned as a fixture, not a path.
        let tankLevel = try Self.appSource(named: "TankLevelView")
        #expect(tankLevel.contains("upsertFillUp(prior)"),
                "TankLevelTestSeed's fixture fill stays as documented - excluded from the class, never silently covered")
    }

    // MARK: - Source-scan helpers

    private static let iosRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // TankbookCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // ios

    private static func swiftFiles(under directory: URL) throws -> [URL] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else {
            Issue.record("cannot enumerate \(directory.path)")
            return []
        }
        return enumerator.compactMap { element -> URL? in
            guard let url = element as? URL, url.pathExtension == "swift" else { return nil }
            return url
        }
    }

    private static func appSource(named: String) throws -> String {
        let app = iosRoot.appendingPathComponent("App/Sources", isDirectory: true)
        for file in try swiftFiles(under: app)
        where file.deletingPathExtension().lastPathComponent == named {
            return try String(contentsOf: file, encoding: .utf8)
        }
        return ""
    }

    private static func coreSource(_ relative: String) throws -> String {
        try String(contentsOf: iosRoot.appendingPathComponent("Sources/TankbookCore/\(relative)"),
                   encoding: .utf8)
    }

    /// The found write-path inventory: `(fileName, functionSignature)` for every
    /// `repository.upsert{FillUp,ChargeSession,ServiceRecord,Expense}(` or
    /// `repository.commitImport(` call in the app's production sources.
    private static func entryWriteCallSites() throws -> Set<String> {
        let app = iosRoot.appendingPathComponent("App/Sources", isDirectory: true)
        let signatures = ["upsertFillUp", "upsertChargeSession",
                          "upsertServiceRecord", "upsertExpense", "commitImport"]
        var found = Set<String>()
        for file in try swiftFiles(under: app) {
            let name = file.deletingPathExtension().lastPathComponent
            // Test-seed files and the TankLevelTestSeed block are fixtures.
            if name.contains("TestSeed") { continue }
            if name == "TankLevelView" { continue }
            let contents = try String(contentsOf: file, encoding: .utf8)
            for line in contents.split(separator: "\n") where line.contains("repository.") {
                let text = String(line)
                for signature in signatures where text.contains("repository.\(signature)(") {
                    found.insert("(\(name), \(signature))")
                }
            }
        }
        return found
    }
}
