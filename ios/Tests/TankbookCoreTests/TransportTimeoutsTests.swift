import Foundation
import os
import Testing
@testable import TankbookCore

// PR.6 - transport timeouts named once per tier (docs/PRACTICES.md U6, §6). A
// half-connected radio froze "Sign in", "Sync now" and "Import" for a full 60 s
// with no error and no cancel; the budget below, the per-request override and
// the grep gate are what remove that. The suite is `.serialized` because the
// URLProtocol double shares a capture box through a static.

// MARK: - URLProtocol doubles

/// Stalls forever: it never calls back, so the only thing that ends the request
/// is the session's own timeout - the "half-connected radio" model, driven
/// without a real wall-clock sleep (the fix for the four GatewayBudgetTests races
/// was to never race a real-time assertion against the scheduler).
private class StallingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}

/// A lock-guarded list of the `timeoutInterval` values the transport wrote onto
/// each `URLRequest`.
private final class TimeoutCapture: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [TimeInterval]())
    func record(_ interval: TimeInterval) { lock.withLock { $0.append(interval) } }
    func values() -> [TimeInterval] { lock.withLock { $0 } }
}

/// Captures the request's `timeoutInterval` and answers 200 so `execute` returns.
private class CapturingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var capture: TimeoutCapture?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        CapturingURLProtocol.capture?.record(request.timeoutInterval)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Recording transport and token provider

private final class RecordingRequestTransport: TankbookHTTPTransport, @unchecked Sendable {
    private struct State {
        var received: [TankbookHTTPRequest] = []
        var responses: [TankbookHTTPResponse] = []
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())

    func script(_ responses: [TankbookHTTPResponse]) {
        lock.withLock { $0.responses = responses }
    }

    func received() -> [TankbookHTTPRequest] {
        lock.withLock { $0.received }
    }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        lock.withLock { state in
            state.received.append(request)
            if state.responses.isEmpty { return TankbookHTTPResponse(status: 200) }
            return state.responses.removeFirst()
        }
    }
}

private struct StaticTokenProvider: AuthorizationTokenProvider {
    func token() -> String? { "test-token" }
}

/// A transport that throws the error a timed-out socket produces, so the
/// "timeout -> unavailable" mapping is tested without a real stall.
private struct TimedOutTransport: TankbookHTTPTransport {
    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        throw URLError(.timedOut)
    }
}

@Suite("Transport timeouts (PR.6)", .serialized)
struct TransportTimeoutsTests {

    private static let iosRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // TankbookCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // ios

    private static let parseBody = """
    {
      "importId": "00000000-0000-4000-8000-000000000101",
      "format": "mfm",
      "scope": "vehicle",
      "candidates": [],
      "unparsed": [],
      "ambiguities": []
    }
    """

    private static let importFormat = ImportFormat(id: "mfm", displayName: "My Fuel Manager",
                                                   fileKinds: ["csv"], helpUrl: nil,
                                                   addedInPackVersion: 1)

    // MARK: - The numbers (assert the values, not that a configuration exists)

    @Test("the session configuration equals the named budgets - the numbers")
    func configurationCarriesTheNamedBudgets() {
        #expect(TransportTimeouts.readJSON == 30)
        #expect(TransportTimeouts.upload == 120)
        #expect(TransportTimeouts.resource == 300)

        let configuration = TransportTimeouts.defaultConfiguration()
        #expect(configuration.timeoutIntervalForRequest == TransportTimeouts.readJSON)
        #expect(configuration.timeoutIntervalForResource == TransportTimeouts.resource)
    }

    @Test("URLSessionTransport builds its own session from the named configuration")
    func transportBuildsItsOwnSession() {
        let configuration = URLSessionTransport().session.configuration
        #expect(configuration.timeoutIntervalForRequest == TransportTimeouts.readJSON)
        #expect(configuration.timeoutIntervalForResource == TransportTimeouts.resource)
    }

    // MARK: - A stalled transport throws inside the budget

    @Test("a stalled transport throws inside the budget, never at the 60 s default")
    func stalledTransportThrowsInsideTheBudget() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StallingURLProtocol.self]
        configuration.timeoutIntervalForRequest = 0.3
        configuration.timeoutIntervalForResource = 2
        let transport = URLSessionTransport(configuration: configuration)

        do {
            _ = try await transport.execute(TankbookHTTPRequest(
                url: URL(string: "https://api.tankbook.live/stall")!))
            Issue.record("a stalling transport must throw, not return")
        } catch let error as URLError {
            #expect(error.code == .timedOut, "a stall must surface as a timeout, got \(error.code)")
        } catch {
            Issue.record("expected URLError, got \(error)")
        }
    }

    // MARK: - The per-request override

    @Test("the per-request override reaches the URLRequest")
    func perRequestOverrideReachesTheURLRequest() async throws {
        let capture = TimeoutCapture()
        CapturingURLProtocol.capture = capture
        defer { CapturingURLProtocol.capture = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let transport = URLSessionTransport(configuration: configuration)

        _ = try await transport.execute(TankbookHTTPRequest(
            url: URL(string: "https://api.tankbook.live/x")!, timeoutInterval: 7))

        #expect(capture.values() == [7],
                "the request's explicit budget must reach the URLRequest, not be shadowed by the 60 s default")
    }

    // MARK: - The long paths ask for the upload budget

    @Test("blob PUT asks for the upload budget explicitly")
    func blobPutAsksForTheUploadBudget() async throws {
        let transport = RecordingRequestTransport()
        let blob = RemoteBlobTransport(
            director: ConfigTransportDirector(baseURL: { URL(string: "https://api.tankbook.live")! },
                                              report: { _ in }),
            transport: transport,
            tokenProvider: StaticTokenProvider())

        try await blob.put(Data([0x01]),
                           to: URL(string: "https://api.tankbook.live/blob")!,
                           contentType: "image/jpeg")

        #expect(transport.received().first?.timeoutInterval == TransportTimeouts.upload,
                "a blob PUT carries megabytes over a mobile uplink; it must ask for the upload budget")
    }

    @Test("import multipart asks for the upload budget explicitly")
    func importMultipartAsksForTheUploadBudget() async throws {
        let transport = RecordingRequestTransport()
        let importClient = ImportClient(
            httpClient: TankbookHTTPClient(transport: transport, tokenProvider: StaticTokenProvider()),
            director: ConfigTransportDirector(baseURL: { URL(string: "https://api.tankbook.live")! },
                                              report: { _ in }),
            deviceID: nil)

        transport.script([TankbookHTTPResponse(status: 200, body: Data(Self.parseBody.utf8))])
        _ = try await importClient.parseFile(data: Data("Date;Volume\n1/1/2024;42.1".utf8),
                                             fileName: "export.csv",
                                             format: Self.importFormat)

        #expect(transport.received().first?.timeoutInterval == TransportTimeouts.upload,
                "the import parse uploads a file; it must ask for the upload budget")
    }

    // MARK: - A timeout surfaces as the offline/unavailable class

    @Test("a timeout surfaces as transport-unreachable, never a generic failure")
    func timeoutSurfacesAsUnavailable() async {
        let importClient = ImportClient(
            httpClient: TankbookHTTPClient(transport: TimedOutTransport(), tokenProvider: StaticTokenProvider()),
            director: ConfigTransportDirector(baseURL: { URL(string: "https://api.tankbook.live")! },
                                              report: { _ in }),
            deviceID: nil)

        await #expect(throws: ImportClientError.transportUnreachable) {
            _ = try await importClient.parseFile(data: Data(), fileName: "f.csv",
                                                 format: Self.importFormat)
        }
    }

    // MARK: - The grep gate

    /// A text scan over production sources: `URLSession.shared` must never appear.
    /// The 60 s default it carries is exactly the frozen-button bug this task
    /// removes (docs/PRACTICES.md U6).
    ///
    /// What this cannot see, said plainly: it matches the literal text
    /// `URLSession.shared`. `URLSession.shared` reached through a variable
    /// (`let session = URLSession.shared` still trips it, but `type(of:)` or a
    /// different spelling would not), and a comment mentioning it would trip the
    /// scan as though it were code. Neither is in the tree today; the transport
    /// is the only place that ever held it.
    @Test("production sources never use URLSession.shared")
    func productionSourcesNeverUseURLSessionShared() throws {
        let core = Self.iosRoot.appendingPathComponent("Sources/TankbookCore", isDirectory: true)
        let app = Self.iosRoot.appendingPathComponent("App/Sources", isDirectory: true)
        let manager = FileManager.default
        var offenders: [String] = []
        for directory in [core, app] {
            guard let enumerator = manager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                Issue.record("cannot enumerate \(directory.path)")
                continue
            }
            for element in enumerator {
                guard let url = element as? URL, url.pathExtension == "swift" else { continue }
                guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
                if contents.contains("URLSession.shared") {
                    offenders.append(url.path)
                }
            }
        }
        #expect(offenders.isEmpty,
                "production code must build its own URLSession from TransportTimeouts; offenders: \(offenders)")
    }
}
