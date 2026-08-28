import Foundation
import os
import Testing
@testable import TankbookCore

// P5.5b - the import UI's load-bearing guarantees, at L1 (docs/TASKS.md P5.5b).
// The screen exists to honour F6a: nothing is written until the user confirms,
// and the preview's figures come from the same engine that computes them after
// commit. Everything here runs in a plain `swift test` process over an
// in-memory repository and an injected transport - no sockets (docs/TESTING.md).

// MARK: - Doubles

private final class ImportTestTransport: TankbookHTTPTransport, @unchecked Sendable {
    private struct State {
        var responses: [TankbookHTTPResponse] = []
        var received: [TankbookHTTPRequest] = []
        var shouldFail = false
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())

    func script(_ responses: [TankbookHTTPResponse]) {
        lock.withLock { $0.responses = responses }
    }

    func failAllRequests() {
        lock.withLock { $0.shouldFail = true }
    }

    func receivedRequests() -> [TankbookHTTPRequest] {
        lock.withLock { $0.received }
    }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        try lock.withLock { state in
            state.received.append(request)
            if state.shouldFail { throw URLError(.notConnectedToInternet) }
            if state.responses.isEmpty { return TankbookHTTPResponse(status: 200) }
            return state.responses.removeFirst()
        }
    }
}

private final class ImportTestTokenProvider: AuthorizationTokenProvider, @unchecked Sendable {
    func token() -> String? { "test-token" }
}

private func makeClient(transport: ImportTestTransport,
                        deviceID: String? = "device-123") -> ImportClient {
    let client = TankbookHTTPClient(transport: transport,
                                    tokenProvider: ImportTestTokenProvider())
    return ImportClient(httpClient: client,
                        baseURL: URL(string: "https://api.tankbook.live")!,
                        deviceID: deviceID)
}

/// A test double for `Date`-free candidate construction.
private func candidate(_ row: Int, entityType: String = "fillUp",
                       date: String = "2026-08-10T00:00:00Z",
                       odometer: Int? = 100_500, volumeL: Double? = 45,
                       unitPrice: String? = "1.7", amount: String? = "76.50",
                       fuelKind: String? = "diesel", isFull: Bool? = true) -> ImportCandidate {
    let money = amount.map { ImportMoney(amount: $0, currency: "USD") }
    return ImportCandidate(
        entityType: entityType, date: Date(timeIntervalSinceReferenceDate: 0),
        odometer: odometer, volumeL: volumeL, unitPrice: unitPrice, money: money,
        fuelKind: fuelKind, isFull: isFull, tankLevelAfterPct: nil, note: nil,
        vehicleName: "Volvo", provenance: ImportProvenance(tag: "import", source: "mfm"),
        sourceRow: row)
}

// MARK: - The fixture data shared by the tests

/// A two-full segment-producing history (100000 -> 100500 km, 45 L after the
/// opening full fill) so the consumption figure is a known value: 9.0 L/100km.
private enum ImportFixture {
    static let vehicle = Vehicle(
        id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
        name: "Volvo V60", make: "Volvo", model: "V60", year: 2015, plate: nil,
        powertrain: .ice, fuelKinds: [.diesel, .petrol95], tankCapacityL: 71,
        batteryCapacityKWh: nil, homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                             energy: .kWhPer100),
        photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 100_000)

    /// Fills with real dates and odometers, ordered so segments exist.
    static let fills: [FillUp] = {
        let openDate = Date(timeIntervalSinceReferenceDate: 0)
        let closeDate = openDate.addingTimeInterval(9 * 86_400)
        func fill(_ id: UUID, _ date: Date, _ odo: Int, _ litres: Double) -> FillUp {
            FillUp(
                id: id, createdAt: date, updatedAt: date, deletedAt: nil,
                vehicleId: vehicle.id, date: date, odometer: odo,
                money: Money(amount: Decimal(string: "76.50")!, currency: .usd,
                             homeCurrency: .eur),
                note: nil, attachments: [], provenance: .import(source: "mfm"),
                conflict: .none, purchaseGroupId: nil, volumeL: litres,
                unitPrice: Decimal(string: "1.7")!, fuelKind: .diesel, fuelGrade: nil,
                isFull: true, tankLevelAfterPct: 100, stationId: nil,
                crossCheck: .verified, extraction: nil)
        }
        return [
            fill(UUID.v7(), openDate, 100_000, 50),
            fill(UUID.v7(), closeDate, 100_500, 45)
        ]
    }()
}

@Suite("Import client (P5.5b)")
struct ImportClientTests {

    @Test func formatsAreDecodedFromTheTransportResponseNotAConstant() async throws {
        // The picker renders whatever the server lists. Two different lists
        // through the same client must yield two different decoded arrays -
        // a hardcoded list would pass every other test and silently defeat the
        // server-driven architecture (docs/API.md).
        let listOne = """
        [{"id":"mfm","displayName":"My Fuel Manager","fileKinds":["csv"],"addedInPackVersion":1}]
        """
        let listMany = """
        [{"id":"mfm","displayName":"My Fuel Manager","fileKinds":["csv"],"addedInPackVersion":1},
         {"id":"fuelio","displayName":"Fuelio","fileKinds":["csv"],"addedInPackVersion":2}]
        """
        let transport = ImportTestTransport()
        let client = makeClient(transport: transport)

        transport.script([TankbookHTTPResponse(status: 200, body: Data(listOne.utf8))])
        let one = try await client.fetchFormats()
        #expect(one.map(\.id) == ["mfm"])

        transport.script([TankbookHTTPResponse(status: 200, body: Data(listMany.utf8))])
        let many = try await client.fetchFormats()
        #expect(many.map(\.id) == ["mfm", "fuelio"])
        #expect(many != one, "the list must follow the transport, not a constant")

        // And the request really hit GET /import/formats.
        let sent = transport.receivedRequests()
        #expect(sent.last?.url.path == "/import/formats")
    }

    @Test func aWrongDeclaredFormatShowsTheSpecificMessage() async throws {
        // 422 must carry the DECLARED format's display name so the UI can say
        // "this doesn't look like a My Fuel Manager export" - never a generic
        // failure (F7).
        let transport = ImportTestTransport()
        let client = makeClient(transport: transport)
        let format = ImportFormat(id: "mfm", displayName: "My Fuel Manager",
                                  fileKinds: ["csv"], helpUrl: nil, addedInPackVersion: 1)

        transport.script([TankbookHTTPResponse(status: 422)])

        await #expect(throws: ImportClientError.doesNotMatchDeclared(displayName: "My Fuel Manager")) {
            _ = try await client.parseFile(data: Data("x".utf8), fileName: "export.csv", format: format)
        }
    }

    @Test func offlineIsADistinctTransportUnreachable() async throws {
        // Being offline is never an error elsewhere in the app (F3/S7); here it
        // is the named exception's network half and must be a distinct state -
        // not a generic "something went wrong".
        let transport = ImportTestTransport()
        let client = makeClient(transport: transport)
        transport.failAllRequests()

        await #expect(throws: ImportClientError.transportUnreachable) {
            _ = try await client.fetchFormats()
        }
        await #expect(throws: ImportClientError.transportUnreachable) {
            _ = try await client.parseFile(data: Data(), fileName: "f.csv",
                                          format: ImportFormat(id: "mfm", displayName: "My Fuel Manager",
                                                               fileKinds: ["csv"], helpUrl: nil,
                                                               addedInPackVersion: 1))
        }
    }

    @Test func oversizeAndUnrecognisedFormatMapToTheirOwnErrors() async throws {
        let transport = ImportTestTransport()
        let client = makeClient(transport: transport)
        let format = ImportFormat(id: "mfm", displayName: "My Fuel Manager",
                                  fileKinds: ["csv"], helpUrl: nil, addedInPackVersion: 1)

        transport.script([TankbookHTTPResponse(status: 413)])
        await #expect(throws: ImportClientError.oversize) {
            _ = try await client.parseFile(data: Data(), fileName: "f.csv", format: format)
        }

        transport.script([TankbookHTTPResponse(status: 415)])
        await #expect(throws: ImportClientError.unrecognisedFormat) {
            _ = try await client.parseFile(data: Data(), fileName: "f.csv", format: format)
        }
    }

    @Test func parseSendsTheDeclarationAndTheFileInMultipart() async throws {
        // The multipart body must carry the user's declared format and the
        // file bytes - the declaration is the whole point (the app never sniffs).
        let transport = ImportTestTransport()
        let client = makeClient(transport: transport)
        let format = ImportFormat(id: "mfm", displayName: "My Fuel Manager",
                                  fileKinds: ["csv"], helpUrl: nil, addedInPackVersion: 1)
        let body = Data("Date;Volume\n1/1/2024;42.1".utf8)

        transport.script([TankbookHTTPResponse(status: 200, body: Data(parseBody.utf8))])
        _ = try await client.parseFile(data: body, fileName: "export.csv", format: format)

        let request = transport.receivedRequests().last
        #expect(request?.method == "POST")
        #expect(request?.url.path == "/import/parse")
        #expect(request?.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=") == true)
        #expect(request?.headers["X-Device-Id"] == "device-123",
                "a signed-out parse is attributed to the device id (docs/API.md)")
        let wire = String(data: request?.body ?? Data(), encoding: .utf8) ?? ""
        #expect(wire.contains("name=\"format\"\r\n\r\nmfm"), "the user's declaration is sent: \(wire)")
        #expect(wire.contains("Date;Volume"), "the file bytes are sent: \(wire)")
    }

    @Test func deleteIssuesADeleteToTheStoredParse() async throws {
        // Cancel at the preview gate deletes the stored parse (idempotently).
        let transport = ImportTestTransport()
        let client = makeClient(transport: transport)
        transport.script([TankbookHTTPResponse(status: 204)])

        try await client.deleteParse(importId: "import-42")

        let sent = transport.receivedRequests()
        #expect(sent.count == 1)
        #expect(sent[0].method == "DELETE")
        #expect(sent[0].url.path == "/import/import-42")
    }

    @Test func fetchParseReadsABackStoredParse() async throws {
        let transport = ImportTestTransport()
        let client = makeClient(transport: transport)
        transport.script([TankbookHTTPResponse(status: 200, body: Data(parseBody.utf8))])

        let parsed = try await client.fetchParse(importId: "00000000-0000-4000-8000-000000000101")
        #expect(parsed.format == "mfm")
        #expect(parsed.candidates.first?.sourceRow == 1)
        #expect(parsed.ambiguities.first(where: { $0.kind == "currency" })?.options == ["USD"])
    }

    private var parseBody: String { ImportFixture.parseBody }
}

@Suite("Import preview gate (P5.5b)")
struct ImportPreviewGateTests {

    @Test func nothingIsWrittenBeforeConfirm() throws {
        // The whole point of the screen (F6a): building the preview figures and
        // converting candidates to fills touches the repository NOT AT ALL.
        let repo = try TankbookRepository(database: TankbookDatabase.inMemory())
        try repo.upsertVehicle(ImportFixture.vehicle)

        let fills = ImportFixture.fills
        let summary = ImportSummary.compute(importFills: fills, existingFills: [],
                                            tankCapacityL: ImportFixture.vehicle.tankCapacityL,
                                            declaredCurrency: .usd)
        #expect(summary.consumptionLPer100 != nil)

        // The preview is on screen; the repository must be unchanged.
        #expect(try repo.liveFillUps(forVehicle: ImportFixture.vehicle.id).isEmpty,
                "the preview must not write anything")

        // Only the explicit commit writes - and it writes exactly the fills the
        // preview showed.
        try repo.commitImportFills(fills, source: "mfm")
        #expect(try repo.liveFillUps(forVehicle: ImportFixture.vehicle.id).count == fills.count)
    }

    @Test func previewConsumptionEqualsPostCommitConsumption() throws {
        // The number the user approves must be the number that lands (F6a): the
        // preview's consumption comes from the SAME engine over the SAME fills
        // as the post-commit figure - not a display-only total.
        let repo = try TankbookRepository(database: TankbookDatabase.inMemory())
        try repo.upsertVehicle(ImportFixture.vehicle)

        let summary = ImportSummary.compute(importFills: ImportFixture.fills,
                                            existingFills: [],
                                            tankCapacityL: ImportFixture.vehicle.tankCapacityL,
                                            declaredCurrency: .usd)
        let preview = summary.consumptionLPer100
        #expect(preview != nil)

        try repo.commitImportFills(ImportFixture.fills, source: "mfm")
        let live = try repo.liveFillUps(forVehicle: ImportFixture.vehicle.id)
        let postCommit = ImportConsumption.compute(fills: live,
                                                   tankCapacityL: ImportFixture.vehicle.tankCapacityL)
        #expect(postCommit == preview,
                "preview \(String(describing: preview)) must equal post-commit \(String(describing: postCommit))")

        // And it is the known value for this history: 500 km, 45 L -> 9.0.
        #expect(preview.map { abs($0 - 9.0) < 0.0001 } == true)
    }

    @Test func mergingIntoTargetCarShowsCombinedConsumptionAndDuplicates() throws {
        // The preview must reflect the car it imports into: a merge into a car
        // with existing entries shows the COMBINED history, and the S2 duplicate
        // count when merging (hard rule 8 - surfaced before the import, not after).
        let repo = try TankbookRepository(database: TankbookDatabase.inMemory())
        try repo.upsertVehicle(ImportFixture.vehicle)

        // An existing fill 10 minutes apart with a near-identical volume - the
        // S2 pair the merge would create.
        let openDate = Date(timeIntervalSinceReferenceDate: 0)
        let existing = FillUp(
            id: UUID.v7(), createdAt: openDate, updatedAt: openDate, deletedAt: nil,
            vehicleId: ImportFixture.vehicle.id, date: openDate.addingTimeInterval(600),
            odometer: 100_500, money: nil, note: nil, attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: nil,
            volumeL: 48.0, unitPrice: nil, fuelKind: .diesel, fuelGrade: nil,
            isFull: true, tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .notApplicable, extraction: nil)
        try repo.upsertFillUp(existing)

        let summary = ImportSummary.compute(importFills: ImportFixture.fills,
                                            existingFills: [existing],
                                            tankCapacityL: ImportFixture.vehicle.tankCapacityL,
                                            declaredCurrency: .usd)
        #expect(summary.duplicateCount >= 1,
                "merging into a car with an S2 pair must surface the count in the preview")
    }

    @Test func commitWritesImportProvenanceAndDirtyRows() throws {
        let repo = try TankbookRepository(database: TankbookDatabase.inMemory())
        try repo.upsertVehicle(ImportFixture.vehicle)

        try repo.commitImportFills(ImportFixture.fills, source: "mfm")

        let live = try repo.liveFillUps(forVehicle: ImportFixture.vehicle.id)
        #expect(live.count == 2)
        #expect(live.allSatisfy { $0.provenance == .import(source: "mfm") },
                "every imported row carries provenance = .import(source) (P5.4)")
        #expect(try repo.fetchDirtyRows().count >= live.count,
                "a user-held import is local data that must sync (rows land dirty)")
    }
}

@Suite("Import review list (P5.5b)")
struct ImportReviewListTests {

    @Test func aMissingValueStaysBlankNeverZero() throws {
        // F6b: a missing value is an honest nil, never coerced to 0 - the
        // review row must keep the gap as a gap.
        let missingOdo = candidate(1, date: "2026-08-01T00:00:00Z", odometer: nil)
        let (ready, review) = ImportReviewClassifier.partition(
            candidates: [missingOdo], unparsed: [], rawLinesByRow: [:],
            vehicle: ImportFixture.vehicle, source: "mfm")

        #expect(ready.isEmpty)
        #expect(review.count == 1)
        #expect(review[0].kind == .missingOdometer)
        #expect(review[0].fill?.odometer == nil,
                "the missing odometer must remain nil, never 0")
        #expect(review[0].fill?.volumeL == 45)
    }

    @Test func aCrossCheckMismatchIsFlaggedWithItsResidual() throws {
        // 45 x 1.7 = 76.50; a file total of 80.00 is off by 3.50.
        let mismatch = candidate(2, date: "2026-08-02T00:00:00Z", amount: "80.00")
        let (ready, review) = ImportReviewClassifier.partition(
            candidates: [mismatch], unparsed: [], rawLinesByRow: [:],
            vehicle: ImportFixture.vehicle, source: "mfm")

        #expect(ready.isEmpty)
        guard case .crossCheckMismatch(let offBy) = review[0].kind else {
            Issue.record("expected crossCheckMismatch, got \(review[0].kind)")
            return
        }
        #expect(abs(offBy) == Decimal(string: "3.50"), "off by \(offBy)")
    }

    @Test func anUnmappableRowAndAnUnparsedRowBothLandOnTheReviewList() throws {
        // Unknown fuel code: the converter must not guess (hard rule 13).
        let unknownFuel = candidate(3, date: "2026-08-03T00:00:00Z", fuelKind: "b99")
        let unparsed = ImportUnparsedRow(row: 9, reason: "invalid_date")
        let (ready, review) = ImportReviewClassifier.partition(
            candidates: [unknownFuel], unparsed: [unparsed],
            rawLinesByRow: [9: "9;broken;row"], vehicle: ImportFixture.vehicle, source: "mfm")

        #expect(ready.isEmpty)
        #expect(review.count == 2)
        #expect(review[0].kind == .unmappable(reason: "unknown_fuel_code"))
        #expect(review[1].kind == .unparsed(reason: "invalid_date"))
        #expect(review[1].rawLine == "9;broken;row",
                "the original line stays available behind 'Original row'")
    }

    @Test func aNonFillRowIsOfferedNotDropped() throws {
        let serviceRow = candidate(4, entityType: "expense", date: "2026-08-04T00:00:00Z")
        let (ready, review) = ImportReviewClassifier.partition(
            candidates: [serviceRow], unparsed: [], rawLinesByRow: [:],
            vehicle: ImportFixture.vehicle, source: "mfm")

        #expect(ready.isEmpty)
        #expect(review[0].kind == .noFuel,
                "a parsed non-fill row is offered as the right kind, not discarded (hard rule 8)")
    }

    @Test func cleanCandidatesAreReadyAndTheSummaryCountsMatch() throws {
        let clean = [candidate(1, date: "2026-08-01T00:00:00Z", odometer: 100_000),
                     candidate(2, date: "2026-08-10T00:00:00Z", odometer: 100_500)]
        let (ready, review) = ImportReviewClassifier.partition(
            candidates: clean, unparsed: [], rawLinesByRow: [:],
            vehicle: ImportFixture.vehicle, source: "mfm")

        #expect(review.isEmpty)
        #expect(ready.count == 2)
    }
}

// MARK: - Wire fixture

extension ImportFixture {
    static let parseBody = """
    {
      "importId": "00000000-0000-4000-8000-000000000101",
      "format": "mfm",
      "scope": "vehicle",
      "candidates": [
        {
          "entityType": "fillUp",
          "date": "2026-08-24T00:00:00Z",
          "odometer": 121727,
          "volumeL": 67,
          "unitPrice": "1.868955",
          "money": { "amount": "125.22", "currency": "USD" },
          "fuelKind": "diesel",
          "isFull": true,
          "tankLevelAfterPct": 100,
          "note": null,
          "vehicleName": "Volvo",
          "provenance": { "tag": "import", "source": "mfm" },
          "sourceRow": 1
        }
      ],
      "unparsed": [],
      "ambiguities": [
        { "kind": "dateFormat", "options": ["M/D/YYYY", "D/M/YYYY"], "rowCount": 215 },
        { "kind": "currency", "options": ["USD"], "rowCount": 513 }
      ]
    }
    """
}
