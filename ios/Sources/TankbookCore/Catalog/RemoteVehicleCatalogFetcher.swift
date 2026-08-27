import Foundation

/// What kind of pack a response is (docs/API.md -> Vehicle catalog). Every
/// response names its kind - a client never infers it from an entry count or
/// from whether `since_version` was sent. A `.full` pack IS the whole catalog:
/// the client replaces its held set with it, so an entry absent from the pack
/// is withdrawn. A `.delta` pack is only what changed since the held version
/// and is overlaid, never removing anything (docs/SYNC.md -> Applying an
/// update).
public enum CatalogPackKind: String, Codable, Sendable, Equatable {
    case full
    case delta
}

/// A fetched catalog pack: the version, the entries to apply and which kind of
/// pack it is (docs/API.md -> Vehicle catalog). An honest empty delta arrives
/// as `entries: []` with the current `packVersion` - that is not an error and
/// not an empty catalog.
public struct VehicleCatalogPack: Sendable, Equatable {
    public let packVersion: Int
    public let entries: [VehicleCatalogEntry]
    public let kind: CatalogPackKind

    public init(packVersion: Int, entries: [VehicleCatalogEntry], kind: CatalogPackKind = .delta) {
        self.packVersion = packVersion
        self.entries = entries
        self.kind = kind
    }
}

/// Fetches a catalog delta over the injected transport. The endpoint is public
/// - no bearer - but the client is still host-allowlisted before any I/O
/// (docs/SECURITY.md), exactly as `RemoteRateFetcher`.
public protocol VehicleCatalogFetcher: Sendable {
    /// Fetches the delta since the `packVersion` the client holds, sent as
    /// `since_version`. Returns nil for a `304` ("nothing to do"), a pack on
    /// `200`. Every transport or HTTP failure throws - the caller treats it as
    /// one silent miss (docs/ERRORS.md -> Vehicle catalog updates).
    func fetchPack(sinceVersion: Int) async throws -> VehicleCatalogPack?
}

/// The production fetcher over `TankbookHTTPClient` (docs/API.md -> Vehicle
/// catalog). The body is decoded exactly: camelCase, `years` as an inclusive
/// `[firstYear, lastYear]` pair or null, `generation` nullable, `fuelKinds` as
/// an OFFER SET (docs/SCHEMA.md - never one car's fuel).
public struct RemoteVehicleCatalogFetcher: VehicleCatalogFetcher, Sendable {
    private let client: TankbookHTTPClient
    private let baseURL: URL

    public init(baseURL: URL, transport: any TankbookHTTPTransport,
                tokenProvider: any AuthorizationTokenProvider) {
        self.client = TankbookHTTPClient(transport: transport, tokenProvider: tokenProvider)
        self.baseURL = baseURL
    }

    public func fetchPack(sinceVersion: Int) async throws -> VehicleCatalogPack? {
        var components = URLComponents(url: endpoint("catalog"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "since_version", value: String(sinceVersion))
        ]
        guard let url = components?.url else { throw CatalogFetchError.invalidResponse }
        let request = TankbookHTTPRequest(url: url, method: "GET")

        let response: TankbookHTTPResponse
        do {
            response = try await client.send(request)
        } catch {
            // Every transport failure - allowlist refusal, socket error - is
            // one silent miss to the caller.
            throw CatalogFetchError.transportUnavailable
        }

        switch response.status {
        case 304:
            // If-None-Match matched: the catalog is unchanged. Nothing to do.
            return nil
        case 200...299:
            do {
                return try Self.decodePack(response.body)
            } catch {
                throw CatalogFetchError.invalidResponse
            }
        default:
            // A 4xx/5xx is one silent miss; the previous pack stands.
            throw CatalogFetchError.badStatus(response.status)
        }
    }

    private func endpoint(_ path: String) -> URL {
        baseURL.appendingPathComponent("v1").appendingPathComponent(path)
    }

    // MARK: - Wire decoding

    /// Decodes a pack body exactly. A structural problem - bad JSON, a missing
    /// field, an unknown powertrain or fuel kind, a `years` that is neither a
    /// 2-integer pair nor null - throws and the caller rejects the pack WHOLE:
    /// a partially applied pack is worse than a stale one (docs/SYNC.md). A
    /// missing `kind` decodes as a delta: an older server predates the marker,
    /// and overlaying is exactly what the client did before this change, so a
    /// new client against an old server degrades to yesterday's behaviour
    /// rather than to something worse.
    static func decodePack(_ data: Data?) throws -> VehicleCatalogPack {
        guard let data else { throw CatalogFetchError.invalidResponse }
        let wire = try JSONDecoder().decode(VehicleCatalogPackWire.self, from: data)
        let entries = try wire.entries.map { try Self.domain($0, packVersion: wire.packVersion) }
        return VehicleCatalogPack(packVersion: wire.packVersion,
                                  entries: entries,
                                  kind: wire.kind ?? .delta)
    }

    private static func domain(_ wire: VehicleCatalogEntryWire, packVersion: Int) throws -> VehicleCatalogEntry {
        guard let powertrain = Powertrain(rawValue: wire.powertrain) else {
            throw CatalogFetchError.invalidResponse
        }
        let fuelKinds: [FuelKind] = try wire.fuelKinds.map { kind in
            guard let fuel = FuelKind(rawValue: kind) else { throw CatalogFetchError.invalidResponse }
            return fuel
        }
        // The wire `years` is an inclusive [firstYear, lastYear] pair or null
        // (docs/API.md); the domain keeps the seed's `[Int?]` shape, where the
        // open end is nil. A null wire range maps to two nils.
        let years: [Int?] = wire.years.map { [$0[0], $0[1]] } ?? [nil, nil]
        return VehicleCatalogEntry(
            id: wire.id,
            make: wire.make,
            model: wire.model,
            generation: wire.generation ?? "",
            years: years,
            powertrain: powertrain,
            fuelKinds: fuelKinds,
            tankCapacityL: wire.tankCapacityL,
            batteryCapacityKWh: wire.batteryCapacityKwh,
            packVersion: packVersion
        )
    }

    private struct VehicleCatalogPackWire: Decodable {
        let packVersion: Int
        let entries: [VehicleCatalogEntryWire]
        let kind: CatalogPackKind?
    }

    private struct VehicleCatalogEntryWire: Decodable {
        let id: String?
        let make: String
        let model: String
        let generation: String?
        let years: [Int]?
        let powertrain: String
        let fuelKinds: [String]
        let tankCapacityL: Double?
        let batteryCapacityKwh: Double?
    }
}

/// Errors surfaced by `RemoteVehicleCatalogFetcher`. Every one is swallowed by
/// `VehicleCatalogUpdater.refresh()` - a transport failure, a 5xx, a malformed
/// body and a rejected pack are all silent, and no user-facing error value
/// exists in the updater's API (docs/ERRORS.md -> Vehicle catalog updates).
public enum CatalogFetchError: Error, Equatable {
    /// The host could not be reached (or the request was refused before I/O).
    case transportUnavailable
    /// The host answered with a non-2xx/non-304 status (e.g. a 5xx).
    case badStatus(Int)
    /// The body did not decode to the registered pack shape.
    case invalidResponse
}
