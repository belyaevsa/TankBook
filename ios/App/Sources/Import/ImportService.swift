import Foundation
import TankbookCore

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

    static func newCar(named name: String) -> TargetCar {
        let now = Date()
        return .new(Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: name, make: nil, model: nil, year: nil, plate: nil,
            powertrain: .ice, fuelKinds: [.petrol95, .diesel],
            tankCapacityL: nil, batteryCapacityKWh: nil,
            homeCurrency: .eur,
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

    static func makeModel(repository: TankbookRepository) -> ImportFlowModel {
        let arguments = ProcessInfo.processInfo.arguments
        let transport: any TankbookHTTPTransport
        if arguments.contains("-importTransportOffline") {
            transport = FailingImportTransport()
        } else if let stub = ImportStubTransport(launchArguments: arguments) {
            transport = stub
        } else {
            transport = URLSessionTransport()
        }
        let baseURL = (try? ConfigDefaults.bundledAppConfig().apiBaseURL)
            ?? URL(string: "https://api.tankbook.live")!
        let sessionStore = KeychainSessionStore()
        let client = ImportClient(
            httpClient: TankbookHTTPClient(transport: transport,
                                           tokenProvider: KeychainTokenProvider(sessionStore: sessionStore)),
            baseURL: baseURL,
            deviceID: Self.deviceID(sessionStore: sessionStore))
        return ImportFlowModel(client: client, repository: repository)
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
}

/// A `TankbookHTTPTransport` that serves canned import responses from bundle
/// resources, driven by launch arguments (`-importStubFormats <name>` and
/// `-importStubParse <name>`). The picker and the preview genuinely render the
/// transport's response - the stub only replaces the bytes, never the code path.
struct ImportStubTransport: TankbookHTTPTransport, @unchecked Sendable {
    private let formatsName: String?
    private let parseName: String?
    private let parse422: Bool

    init?(launchArguments: [String]) {
        formatsName = Self.value(for: "-importStubFormats", in: launchArguments)
        parseName = Self.value(for: "-importStubParse", in: launchArguments)
        parse422 = launchArguments.contains("-importStubParse422")
        if formatsName == nil && parseName == nil && !parse422 { return nil }
    }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        let path = request.url.path
        if path == "/import/formats", let formatsName {
            return Self.resource("import-formats-\(formatsName)")
        }
        if path.hasPrefix("/import/"), request.method == "DELETE" {
            // Idempotent delete, exactly as the endpoint promises.
            return TankbookHTTPResponse(status: 204)
        }
        if path.hasPrefix("/import/") {
            if parse422 { return TankbookHTTPResponse(status: 422) }
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
