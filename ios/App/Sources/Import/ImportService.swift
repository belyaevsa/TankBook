import Foundation
import os
import TankbookCore

/// RV.86: one distinct source car in the file, and the user's decision about
/// where it lands. `.undecided` until the mapping step decides it; the wizard
/// never guesses a destination (hard rule 13), so a multi-car file shows the
/// cars and asks.
enum ImportCarDestination: Equatable {
    case undecided
    case leaveOut
    /// Import into an existing garage car (a merge, with the S2 duplicate count
    /// surfaced) or a new car. `.new` carries a synthesized `Vehicle` built ONCE
    /// when the user picks it, so the classification, the preview and the
    /// commit all share the same id (a fresh id per build would orphan the fills).
    case existing(Vehicle)
    case new(Vehicle)

    var targetCar: TargetCar? {
        switch self {
        case .undecided, .leaveOut: return nil
        case .existing(let vehicle): return .existing(vehicle)
        case .new(let vehicle): return .new(vehicle)
        }
    }
}

/// RV.86: one distinct source car in a parsed file and the user's mapping
/// decision for it (`.cars` wizard step). `group` is the parse's vehicle group
/// (name + source rows); `destination` is undecided until the mapping screen
/// asks - the wizard never guesses a destination (hard rule 13), so a
/// multi-car file shows the cars and asks.
struct ImportCarRow: Identifiable, Equatable {
    let group: ImportVehicleGroup
    var destination: ImportCarDestination = .undecided

    init(group: ImportVehicleGroup, destination: ImportCarDestination = .undecided) {
        self.group = group
        self.destination = destination
    }

    /// Group names are distinct by construction (the parser groups by name), so
    /// the name is a stable identity within a parse.
    var id: String { group.name }

    var isDecided: Bool { destination != .undecided }

    /// The destination garage car, when the user chose one (an existing car or
    /// a new one). nil while undecided or left out.
    var destinationVehicle: Vehicle? {
        switch destination {
        case .undecided, .leaveOut: return nil
        case .existing(let vehicle): return vehicle
        case .new(let vehicle): return vehicle
        }
    }

    var destinationVehicleID: UUID? { destinationVehicle?.id }
}

/// RV.93: one successfully-parsed file of a whole-export pick. The batch holds
/// one of these per file that parsed; the wizard's merged view (`ImportBatchMerge`)
/// re-keys their rows into one space and unions their cars, but the per-file
/// parse is kept so the stored server parse can be deleted on cancel/confirm.
struct ImportParseFile {
    let fileName: String
    let rawData: Data
    let parse: ImportParseResponse
}

/// RV.93: a staged, already-read pick waiting to be uploaded. The bytes are in
/// the app's own container (RV.73), read under the pick's scope; this is what a
/// whole-export pick hands to `beginBatchParse` - N uploads, N parse calls.
struct ImportFileUpload {
    let fileName: String
    let data: Data
}

/// RV.93: one picked file that failed to parse, named with its own failure, so
/// the source step can report it per file and the run survives the rest (hard
/// rule 7). The successful files are unaffected - a failed file never kills the
/// batch.
struct ImportFileFailure: Identifiable {
    let id: UUID
    let fileName: String
    let failure: ImportFlowModel.ParseFailure

    init(fileName: String, failure: ImportFlowModel.ParseFailure) {
        self.id = UUID()
        self.fileName = fileName
        self.failure = failure
    }
}

/// One source car's file facts, derived from ITS OWN candidates (RV.86: the
/// odometer span of one car is a real number; the span across five cars is the
/// lie that shipped).
struct ImportCarFigures: Equatable {
    let count: Int
    let firstDate: Date?
    let lastDate: Date?
    let odometerMin: Int?
    let odometerMax: Int?
}

extension ArchiveImportRecord {
    /// The vehicle the record belongs to, when it has one (the import writes
    /// only vehicle-scoped records, so a kept record always has one). Lets the
    /// multi-car mapping count the distinct destinations a commit will touch.
    var importVehicleID: UUID? {
        switch self {
        case .vehicle(let vehicle): return vehicle.id
        case .fillUp(let fill): return fill.vehicleId
        case .chargeSession(let charge): return charge.vehicleId
        case .serviceRecord(let service): return service.vehicleId
        case .expense(let expense): return expense.vehicleId
        case .reminder(let reminder): return reminder.vehicleId
        case .station, .tariff, .attachment: return nil
        }
    }
}

/// Where the import lands: an existing car (a merge, with the S2 duplicate
/// count surfaced) or a new car. `.new` carries a synthesized `Vehicle` built
/// ONCE when the user picks it, so the classification, the preview and the
/// commit all share the same id (a fresh id per build would orphan the fills).
enum TargetCar: Equatable {
    case existing(Vehicle)
    case new(Vehicle)

    var vehicleValue: Vehicle {
        switch self {
        case .existing(let vehicle): return vehicle
        case .new(let vehicle): return vehicle
        }
    }

    /// The new-car name, as the user chose it (from the file's vehicle, or the
    /// format name).
    var newName: String { vehicleValue.name }

    /// Builds the synthesized car a new-car destination lands in. `homeCurrency`
    /// is REQUIRED: the import's answer (the file's declared currency, or the
    /// user's choice for a file with none) is a value the user set, so a factory
    /// that can silently default it to EUR is the RV.185 defect - the imported
    /// rows then arrive rate-pending against a home the user never picked.
    static func newCar(named name: String, homeCurrency: CurrencyCode) -> TargetCar {
        let now = Date()
        return .new(Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: name, make: nil, model: nil, year: nil, plate: nil,
            powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: nil, batteryCapacityKWh: nil,
            homeCurrency: homeCurrency,
            units: Vehicle.Units(distance: .km, volume: .l,
                                 consumption: .lPer100, energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: nil))
    }
}

/// The uploaded file's data rows, keyed by the wire's 1-based `sourceRow`, for
/// the review list's "Original row". The header line is skipped so the raw line
/// is the actual CSV line (MFM: title on line 1, header on line 2, data from
/// line 3 - so data row 1 = line 3).
enum ImportRawLines {
    static func dataLines(from data: Data?) -> [Int: String] {
        guard let data, let text = String(data: data, encoding: .utf8) else { return [:] }
        var lines = text.components(separatedBy: .newlines)
        if lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        guard !lines.isEmpty else { return [:] }
        var dataStart = 0
        if let headerIndex = lines.firstIndex(where: { looksLikeHeader($0) }) {
            dataStart = headerIndex + 1
        } else if lines.count > 1 {
            dataStart = 1 // title + header assumed (MFM: line 2 is the header)
        }
        var result: [Int: String] = [:]
        for (offset, line) in lines.dropFirst(dataStart).enumerated() {
            result[offset + 1] = line
        }
        return result
    }

    private static func looksLikeHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let firstToken = trimmed.split(separator: ";").first.map(String.init) ?? ""
        let normalized = firstToken.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            .lowercased()
        return ["date", "fillup volume", "total price", "reminder name", "odometer"]
            .contains(normalized)
    }
}

// Builds the import wizard's model over the app's one HTTP client, with a
// DEBUG/test seam: launch arguments can install a stub transport (serving
// canned formats/parse JSON from the bundle) or force the offline state, so UI
// tests and screenshots drive the flow without a server or the system file
// picker (docs/TESTING.md). Production never passes those arguments.

@MainActor
enum ImportService {

    static func makeModel(repository: TankbookRepository,
                          configService: AppConfigService) -> ImportFlowModel {
        let arguments = ProcessInfo.processInfo.arguments
        let transport: any TankbookHTTPTransport
        #if DEBUG
        if arguments.contains("-importTransportOffline") {
            transport = FailingImportTransport()
        } else if let scenario = ImportScenarioTransport(launchArguments: arguments) {
            // RV.68 screenshot seam: renders each non-offline source-list
            // failure card (server error / contract break / transport failure)
            // against a real, reachable-looking response or transport error.
            transport = scenario
        } else if arguments.contains("-importCancelFirstFormats") {
            // RV.68 L4 seam: the first `/v1/import/formats` request is cancelled
            // (as a SwiftUI `.task` cancelled by a view update would cancel the
            // URLSession call) and every later request is healthy - so a test
            // can assert the wizard does NOT conclude "offline" from a
            // cancellation that is not a connectivity failure.
            let inner = ImportStubTransport(launchArguments: arguments)
                ?? appTransport(URLSessionTransport())
            transport = ImportCancelFirstTransport(inner: inner)
        } else if let stub = ImportStubTransport(launchArguments: arguments) {
            transport = stub
        } else {
            transport = appTransport(URLSessionTransport())
        }
        #else
        transport = appTransport(URLSessionTransport())
        #endif
        let sessionStore = KeychainSessionStore()
        let client = ImportClient(
            httpClient: TankbookHTTPClient(transport: transport,
                                           tokenProvider: KeychainTokenProvider(sessionStore: sessionStore)),
            director: AppConfigStore.shared.director,
            deviceID: Self.deviceID(sessionStore: sessionStore),
            log: AppLog.shared)
        return ImportFlowModel(client: client, repository: repository,
                               configService: configService)
    }

    /// The `X-Device-Id` for parse attribution (docs/API.md): the signed-in
    /// session's device id, else a persistent per-install identifier so a
    /// signed-out parse is still attributable. Import must work signed out.
    static func deviceID(sessionStore: KeychainSessionStore) -> String? {
        if let session = try? sessionStore.load() {
            return session.deviceId
        }
        let key = "tankbook.import.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    /// The stager for a picked file (RV.73): the security-scoped pick is copied
    /// into the app's own container at pick time, under the scope, so every
    /// later read (the parse upload, the send-us-the-file share) works after
    /// the scope is released. The copy lives in Caches/TankbookImport - the
    /// OS may additionally purge it - and is deleted once its consumer is done
    /// (docs/ERRORS.md -> Import wizard). Production closures call the real
    /// Foundation APIs; tests build their own with injected doubles.
    static func makePickedFileStager() -> ImportPickedFile {
        let caches = FileManager.default.urls(for: .cachesDirectory,
                                              in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return ImportPickedFile(stagingDirectory:
            caches.appendingPathComponent("TankbookImport", isDirectory: true))
    }
}

/// A `TankbookHTTPTransport` that serves canned import responses from bundle
/// resources, driven by launch arguments (`-importStubFormats <name>` and
/// `-importStubParse <name>`). The picker and the preview genuinely render the
/// transport's response - the stub only replaces the bytes, never the code path.
#if DEBUG
struct ImportStubTransport: TankbookHTTPTransport, @unchecked Sendable {
    private let formatsName: String?
    private let parseName: String?
    private let parse422: Bool
    private let parseSlow: Bool

    init?(launchArguments: [String]) {
        formatsName = Self.value(for: "-importStubFormats", in: launchArguments)
        parseName = Self.value(for: "-importStubParse", in: launchArguments)
        parse422 = launchArguments.contains("-importStubParse422")
        parseSlow = launchArguments.contains("-importStubParseSlow")
        if formatsName == nil && parseName == nil && !parse422 && !parseSlow { return nil }
    }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        let path = request.url.path
        if path == "/v1/import/formats", let formatsName {
            return Self.resource("import-formats-\(formatsName)")
        }
        if path.hasPrefix("/v1/import/"), request.method == "DELETE" {
            // Idempotent delete, exactly as the endpoint promises.
            return TankbookHTTPResponse(status: 204)
        }
        if path.hasPrefix("/v1/import/") {
            if parse422 { return TankbookHTTPResponse(status: 422) }
            // PR.6: hold the parse in flight so the Cancel affordance (and its
            // UI-test/screenshot state) is visible. `Task.sleep` is cancellation-
            // aware, so the user's Cancel propagates exactly as a real socket
            // would.
            if parseSlow {
                try await Task.sleep(for: .seconds(30))
            }
            if let parseName {
                return Self.resource("import-parse-\(parseName)")
            }
        }
        return TankbookHTTPResponse(status: 404)
    }

    private static func resource(_ name: String) -> TankbookHTTPResponse {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return TankbookHTTPResponse(status: 500)
        }
        return TankbookHTTPResponse(status: 200, body: data)
    }

    private static func value(for argument: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: argument),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

/// Forces the offline state for the "offline says why" UI test/screenshot.
struct FailingImportTransport: TankbookHTTPTransport, @unchecked Sendable {
    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        throw URLError(.notConnectedToInternet)
    }
}

/// RV.68 screenshot seam: fails exactly the `GET /v1/import/formats` request in
/// a named way (`-importTransportScenario server|contract|transportFailure`) so
/// each non-offline source-list failure card renders without a server. Every
/// other request answers 404, matching the pre-RV.68 real-world shape where the
/// unversioned import path did not exist.
struct ImportScenarioTransport: TankbookHTTPTransport, @unchecked Sendable {
    private enum Scenario: String {
        case server
        case contract
        case transportFailure
    }

    private let scenario: Scenario?

    init?(launchArguments: [String]) {
        guard let index = launchArguments.firstIndex(of: "-importTransportScenario"),
              launchArguments.indices.contains(index + 1) else { return nil }
        scenario = Scenario(rawValue: launchArguments[index + 1])
    }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        guard request.url.path == "/v1/import/formats", request.method == "GET" else {
            return TankbookHTTPResponse(status: 404)
        }
        switch scenario {
        case .server:
            return TankbookHTTPResponse(status: 500)
        case .contract:
            return TankbookHTTPResponse(status: 200, body: Data("not the formats json".utf8))
        case .transportFailure:
            throw URLError(.secureConnectionFailed)
        case nil:
            return TankbookHTTPResponse(status: 404)
        }
    }
}

/// RV.68 L4 seam: cancels exactly the FIRST `/v1/import/formats` request, then
/// delegates every later request to a healthy inner transport. Models a
/// SwiftUI `.task` cancelled by a view update: the request is stopped before it
/// has a conclusion, and the wizard must not read that as "offline".
struct ImportCancelFirstTransport: TankbookHTTPTransport, @unchecked Sendable {
    private let inner: any TankbookHTTPTransport
    private let lock = OSAllocatedUnfairLock(initialState: false)

    init(inner: any TankbookHTTPTransport) {
        self.inner = inner
    }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        let isFirstFormatsFetch = request.url.path == "/v1/import/formats"
            && request.method == "GET"
        let shouldCancel = lock.withLock { cancelled in
            guard !cancelled, isFirstFormatsFetch else { return false }
            cancelled = true
            return true
        }
        if shouldCancel { throw URLError(.cancelled) }
        return try await inner.execute(request)
    }
}
#endif
