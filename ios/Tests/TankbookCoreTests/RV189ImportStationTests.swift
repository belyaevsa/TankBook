import Foundation
import Testing
@testable import TankbookCore

// RV.189: the owner's Drivvo import ignored the file's station column, so every
// imported fill titled itself with the fuel kind ("92") where RV.142 promised
// the station name. The server parser reads the column (verified against this
// same committed export in the backend), and the conversion + commit materialise
// a Station - but `ImportBatchMerge`, which EVERY pick runs through (a single
// file is merged as a one-file batch), rebuilt each candidate without its
// `station`. The name was gone before conversion, so the fill had no stationId,
// no Station row was written, and the Log fell back to the fuel kind.
//
// These tests drive the owner's real export through the device's production
// merge and conversion, so the break cannot hide behind a hand-written fixture.

// MARK: - The owner's real export, as the server's parse delivers it

private enum RV189DrivvoFixture {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func url() -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory.appendingPathComponent(
                "Spike/ImportFixtures/drivvo/drivvo-ru-3sections.csv")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory = directory.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: "Spike/ImportFixtures/drivvo/drivvo-ru-3sections.csv")
    }

    /// The `##Refuelling` data rows as candidates. Only the fields this row
    /// needs are mapped; the `Азс` column is index 23 and is the station name.
    /// The server's own parse of this file is asserted in the backend
    /// (`DrivvoParserTests`), so this reader re-derives nothing it does not use.
    static func refuellingCandidates() throws -> [ImportCandidate] {
        let text = try String(contentsOf: url(), encoding: .utf8)
        var section = ""
        var row = 0
        var candidates: [ImportCandidate] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("##") { section = String(line.dropFirst(2)); continue }
            guard !line.isEmpty, section == "Refuelling" else { continue }
            let fields = line.hasPrefix("\"") && line.hasSuffix("\"")
                ? String(line.dropFirst().dropLast()).components(separatedBy: "\",\"")
                : line.components(separatedBy: ",")
            guard fields.count > 23, let date = dateFormatter.date(from: fields[1]) else { continue }
            let rawOdometer = Double(fields[0]) ?? 0
            let volume = Double(fields[5].replacingOccurrences(of: ",", with: ".")) ?? 0
            let station = fields[23].trimmingCharacters(in: .whitespacesAndNewlines)
            row += 1
            candidates.append(ImportCandidate(
                entityType: "fillUp", date: date,
                odometer: rawOdometer == 0 ? nil : Int(rawOdometer),
                volumeL: volume, unitPrice: fields[3],
                money: ImportMoney(amount: fields[4], currency: ""),
                fuelKind: fields[2].contains("95") ? "petrol95" : "petrol92",
                isFull: true, tankLevelAfterPct: nil, note: nil,
                vehicleName: nil,
                provenance: ImportProvenance(tag: "import", source: "drivvo"),
                sourceRow: row, station: station.isEmpty ? nil : station))
        }
        return candidates
    }

    static func parse(_ candidates: [ImportCandidate]) -> ImportParseResponse {
        ImportParseResponse(importId: "00000000-0000-4000-8000-000000000189",
                            format: "drivvo", scope: "vehicle",
                            candidates: candidates, unparsed: [], ambiguities: [])
    }

    static func vehicle() -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            name: "Škoda Octavia", make: "Škoda", model: "Octavia", year: 2020,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol92],
            tankCapacityL: 50, batteryCapacityKWh: nil, homeCurrency: .rub,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 357_790)
    }

    /// The merged view of the owner's file through the production batch merge
    /// (the same call a one-file pick makes).
    static func merged() throws -> [ImportCandidate] {
        let files = [ImportParsedFile(parse: parse(try refuellingCandidates()),
                                      rawLines: [:])]
        let view = ImportBatchMerge.merge(files: files, dateFormatAnswer: nil)
        return view?.parse.candidates ?? []
    }
}

// MARK: - The break: the batch merge must carry the station

@Suite("RV.189 an imported station survives the batch merge")
struct RV189ImportStationTests {

    /// The owner's file names stations in `Азс` (index 23); the parser reads
    /// them (backend, same fixture). The device's batch merge must carry the
    /// value through re-keying, or nothing downstream can resolve it. This is
    /// the link that was broken: `remappingSourceRow` rebuilt the candidate
    /// without `station`.
    @Test func ownerFixtureStationSurvivesTheBatchMerge() throws {
        let merged = try RV189DrivvoFixture.merged()
        #expect(!merged.isEmpty, "the fixture must parse into candidates")

        let named = merged.filter { $0.trimmedStation != nil }
        #expect(!named.isEmpty,
                "the owner's file names stations on its rows; none survived the merge")

        // The first data row is the file's own 491791 / 2025-08-24 / Газпром.
        let first = try #require(merged.first)
        #expect(first.trimmedStation == "Газпром",
                "row 1's station must survive the merge, was \(first.trimmedStation ?? "nil")")
    }

    /// The whole chain the row exists for: after the production merge, the
    /// conversion and the commit, every imported fill's `stationId` resolves to
    /// a live Station row. A nil stationId (the defect) fails on the first fill.
    @Test func committedOwnerFixtureFillsResolveToLiveStationRows() throws {
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        let vehicle = RV189DrivvoFixture.vehicle()
        try repository.upsertVehicle(vehicle)

        let merged = try RV189DrivvoFixture.merged()
        let (ready, review) = ImportReviewClassifier.partition(
            candidates: merged,
            unparsed: [],
            rawLinesByRow: [:],
            vehicle: vehicle,
            source: "drivvo",
            existingEntries: [],
            existingStations: [])
        // Every fill the import would write, exactly as the wizard assembles it.
        let fills = ready + review.compactMap(\.fill)
        #expect(fills.count == merged.count, "every fixture row must convert to a fill")

        let existing = try repository.liveStations()
        var nameByID: [UUID: String] = [:]
        for candidate in merged {
            guard let name = candidate.trimmedStation else { continue }
            nameByID[ImportStationResolver.station(for: name, existing: existing).id] = name
        }
        let missing = ImportStationResolver.missingStations(
            keptStationIDs: Set(fills.compactMap(\.stationId)),
            nameByID: nameByID,
            existing: existing)
        try repository.commitImport(
            fills.map(ArchiveImportRecord.fillUp) + missing.map(ArchiveImportRecord.station),
            source: "drivvo")

        let stations = try repository.liveStations()
        #expect(!stations.isEmpty, "the file named stations, so the commit must write them")
        let stored = try repository.liveFillUps(forVehicle: vehicle.id)
        #expect(stored.count == fills.count)
        #expect(stored.allSatisfy { fill in
            guard let id = fill.stationId else { return false }
            return stations.contains { $0.id == id }
        }, "every imported fill's stationId must resolve to a live Station row")
    }

    /// The owner's file names seven distinct stations across 250 rows. Two rows
    /// naming one station must produce ONE Station, never two - the shared
    /// `ImportStationResolver` mints by name, and the commit must reuse it.
    @Test func twoRowsNamingOneStationProduceOneStation() throws {
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        let vehicle = RV189DrivvoFixture.vehicle()
        try repository.upsertVehicle(vehicle)

        let merged = try RV189DrivvoFixture.merged()
        let fills = merged.compactMap {
            ImportConverter.makeFill(from: $0, vehicle: vehicle, source: "drivvo")
        }
        let distinctNames = Set(merged.compactMap(\.trimmedStation))
        #expect(distinctNames.count > 1, "the fixture must carry several station names")

        var nameByID: [UUID: String] = [:]
        for name in distinctNames {
            nameByID[ImportStationResolver.station(for: name, existing: []).id] = name
        }
        let missing = ImportStationResolver.missingStations(
            keptStationIDs: Set(fills.compactMap(\.stationId)),
            nameByID: nameByID, existing: [])
        try repository.commitImport(
            fills.map(ArchiveImportRecord.fillUp) + missing.map(ArchiveImportRecord.station),
            source: "drivvo")

        let stations = try repository.liveStations()
        #expect(stations.count == distinctNames.count,
                "each distinct name is ONE Station, never one per row")
        #expect(Set(stations.map(\.name)).count == stations.count,
                "no two Station rows may share a name")
        #expect(stations.contains { $0.name == "Газпром" })
    }

    /// A row whose station column is blank stamps no id and writes no Station -
    /// an honest absence, never a guessed name (hard rule 13).
    @Test func blankStationColumnStampsNoIDAndWritesNoStation() throws {
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        let vehicle = RV189DrivvoFixture.vehicle()
        try repository.upsertVehicle(vehicle)

        let candidate = ImportCandidate(
            entityType: "fillUp",
            date: Date(timeIntervalSinceReferenceDate: 700_000_000),
            odometer: 100_000, volumeL: 40, unitPrice: "200",
            money: ImportMoney(amount: "8000", currency: ""),
            fuelKind: "petrol92", isFull: true, tankLevelAfterPct: nil,
            note: nil, vehicleName: nil,
            provenance: ImportProvenance(tag: "import", source: "drivvo"),
            sourceRow: 1, station: nil)
        let fill = try #require(ImportConverter.makeFill(from: candidate, vehicle: vehicle,
                                                         source: "drivvo"))
        #expect(fill.stationId == nil, "a blank station column must stamp no id")

        try repository.commitImport([.fillUp(fill)], source: "drivvo")
        #expect(try repository.liveStations().isEmpty,
                "a row with no station must mint no Station row")
    }
}
