import Foundation
import os
import Testing
@testable import TankbookCore

// OB.3 - the device remembers when it last synced, and how it last failed
// (docs/TASKS.md OB.3 / PR.12). The row's three claims, pinned at L1:
//
//  1. The sync state PERSISTS (a store round-trips) and a coordinator RESTORES
//     it - after a relaunch the Settings surface reads the stored success date
//     and the stored failure before any cycle has run, never a claim of
//     "just now" for a device that has never synced.
//  2. A fired cycle WRITES: a success advances `lastSuccessAt` and clears any
//     earlier failure; a failing cycle writes kind + code + traceId and leaves
//     `lastSuccessAt` untouched. A deferred or inert cycle writes NOTHING.
//  3. The wire code/traceId are carried raw from the transport to the record
//     (a stale code never rides an offline cycle), and the record holds no
//     domain value (hard rule 12).

// MARK: - Test doubles

/// A transport that returns one canned response for every request.
private final class CannedHTTPTransport: TankbookHTTPTransport, @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<TankbookHTTPResponse>
    init(_ response: TankbookHTTPResponse) {
        lock = OSAllocatedUnfairLock(initialState: response)
    }
    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        lock.withLock { $0 }
    }
}

private struct CannedTokenProvider: AuthorizationTokenProvider {
    func token() -> String? { "test-token" }
}

private func cannedDirector() -> ConfigTransportDirector {
    ConfigTransportDirector(baseURL: { URL(string: "https://api.tankbook.live")! }, report: { _ in })
}

/// A transport whose pull blocks until released (copied from SyncCoordinatorTests
/// so this suite's inert-cycle assertion is deterministic without sharing the
/// private type).
private final class OB3BlockingPullTransport: SyncTransport, @unchecked Sendable {
    private struct State {
        var pullCount = 0
        var waiting: [@Sendable () -> Void] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func waitUntilPulling() async {
        while true {
            if state.withLock({ $0.pullCount > 0 }) { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    func releasePull() {
        let waiters = state.withLock { snapshot -> [@Sendable () -> Void] in
            defer { snapshot.waiting.removeAll() }
            return snapshot.waiting
        }
        waiters.forEach { $0() }
    }

    func pull(since: Int64, limit: Int) async throws -> SyncPullResponse {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            state.withLock { snapshot in
                snapshot.pullCount += 1
                snapshot.waiting.append { continuation.resume() }
            }
        }
        return SyncPullResponse(records: [], nextSince: since, more: false,
                                schemaPolicy: SyncSchemaPolicy(minSupported: 1, current: 1))
    }

    func push(_ changes: [SyncPushChange]) async throws -> SyncPushResponse {
        var scn: Int64 = 1
        return SyncPushResponse(results: changes.map { change in
            defer { scn += 1 }
            return SyncPushResult(id: change.id, status: .accepted(newScn: scn, clamped: false))
        })
    }
}

private func problemBody(code: String?, traceId: String?, title: String? = nil, detail: String? = nil) -> Data {
    var object: [String: Any] = [:]
    if let code { object["code"] = code }
    if let traceId { object["traceId"] = traceId }
    if let title { object["title"] = title }
    if let detail { object["detail"] = detail }
    return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
}

@Suite("Persisted sync state (OB.3)")
struct OB3SyncStateTests {

    // MARK: - The store round-trips (L1)

    @Test("UserDefaultsSyncStateStore round-trips over an ephemeral suite")
    func userDefaultsStoreRoundTripsOverAnEphemeralSuite() throws {
        let suite = "OB3-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = UserDefaultsSyncStateStore(accountId: "ob3-account", suiteName: suite)

        let successAt = Date(timeIntervalSinceReferenceDate: 1234)
        let failure = SyncFailureRecord(at: successAt.addingTimeInterval(60),
                                        kind: .authExpired, code: "token_invalid", traceId: "ob3-0001")
        let written = PersistedSyncState(lastSuccessAt: successAt, lastFailure: failure)
        store.save(written)
        #expect(store.load() == written,
                "the stored state must survive the store's own round trip")

        // An empty state clears the key rather than resurrecting stale bytes.
        let cleared = PersistedSyncState(lastSuccessAt: nil, lastFailure: nil)
        store.save(cleared)
        #expect(store.load() == cleared)
    }

    // MARK: - A coordinator restores a stored state before any cycle

    @Test("a coordinator built over a stored state reports the stored date and failure")
    func coordinatorRestoresStoredDateAndFailure() throws {
        let repo = try makeSyncRepository()
        let successAt = Date(timeIntervalSinceReferenceDate: 10_000)
        let failure = SyncFailureRecord(at: successAt.addingTimeInterval(-60),
                                        kind: .deviceRevoked, code: "device_revoked", traceId: "ob3-restored")
        let store = InMemorySyncStateStore(seededWith: PersistedSyncState(lastSuccessAt: successAt,
                                                                          lastFailure: failure))
        let coordinator = SyncCoordinator(engine: makeSyncEngine(repository: repo,
                                                                 transport: SyncTransportDouble()),
                                          syncStateStore: store)

        // The restored values, readable BEFORE any cycle has run - this is the
        // relaunch claim: the surface shows the true age and the last failure
        // from the moment it appears, never a fabricated "just now".
        #expect(coordinator.lastSyncDate() == successAt)
        #expect(coordinator.lastFailure() == failure)
    }

    // MARK: - A fired cycle writes the store

    @Test("a successful cycle advances lastSuccessAt and clears a previous failure")
    func successfulCycleAdvancesAndClears() async throws {
        let repo = try makeSyncRepository()
        let previousFailure = SyncFailureRecord(at: Date(timeIntervalSinceReferenceDate: 100),
                                                kind: .refused, code: "blocked", traceId: "old")
        let store = InMemorySyncStateStore(seededWith: PersistedSyncState(
            lastSuccessAt: Date(timeIntervalSinceReferenceDate: 200), lastFailure: previousFailure))
        let coordinator = SyncCoordinator(engine: makeSyncEngine(repository: repo,
                                                                 transport: SyncTransportDouble()),
                                          syncStateStore: store)

        let outcome = await coordinator.syncNow()
        #expect(!outcome.offline && !outcome.serverUnavailable,
                "the harness cycle must succeed so the write is the success branch")

        let loaded = store.load()
        #expect(loaded.lastSuccessAt != nil,
                "a successful cycle must record when it succeeded")
        #expect(loaded.lastSuccessAt! >= Date(timeIntervalSinceReferenceDate: 200),
                "the success date must advance, never regress")
        #expect(loaded.lastFailure == nil,
                "a successful cycle must clear any earlier failure")
        #expect(coordinator.lastFailure() == nil)
    }

    @Test("a failing cycle writes kind + code + traceId and leaves lastSuccessAt untouched")
    func failingCycleWritesKindCodeAndTrace() async throws {
        let repo = try makeSyncRepository()
        let priorSuccess = Date(timeIntervalSinceReferenceDate: 5000)
        let store = InMemorySyncStateStore(seededWith: PersistedSyncState(lastSuccessAt: priorSuccess,
                                                                          lastFailure: nil))
        let diagnostics = SyncFailureDiagnostics()
        let transport = RemoteSyncTransport(
            director: cannedDirector(),
            transport: CannedHTTPTransport(TankbookHTTPResponse(
                status: 401,
                body: problemBody(code: "token_invalid", traceId: "ob3-cycle-1",
                                  title: "Unauthorized", detail: "the token expired"))),
            tokenProvider: CannedTokenProvider(),
            diagnostics: diagnostics)
        let coordinator = SyncCoordinator(
            engine: makeSyncEngine(repository: repo, transport: transport),
            syncStateStore: store,
            failureDiagnostics: diagnostics)

        let outcome = await coordinator.syncNow()
        #expect(outcome.authExpired, "a 401 token_invalid must classify as an auth expiry")

        let failure = try #require(store.load().lastFailure, "the failing cycle must persist a record")
        #expect(failure.kind == .authExpired)
        #expect(failure.code == "token_invalid", "the raw server code must ride the record")
        #expect(failure.traceId == "ob3-cycle-1", "the raw trace id must ride the record")
        #expect(store.load().lastSuccessAt == priorSuccess,
                "a failing cycle must leave the last success date alone")
        #expect(coordinator.lastSyncDate() == priorSuccess,
                "in-memory and stored state must agree on the untouched date")
    }

    // MARK: - Deferred and inert cycles write nothing

    @Test("a deferred cycle writes nothing")
    func deferredCycleWritesNothing() async throws {
        let repo = try makeSyncRepository()
        let power = MutablePowerState(lowPower: true)
        let transport = SyncTransportDouble()
        let store = InMemorySyncStateStore()
        let coordinator = SyncCoordinator(
            engine: makeSyncEngine(repository: repo, transport: transport, powerState: power),
            powerState: power,
            syncStateStore: store)

        let outcome = await coordinator.syncNow(trigger: .background)
        #expect(outcome.deferred, "the harness must actually defer")
        #expect(transport.recordedPullRequests.isEmpty, "a deferred cycle must not pull")

        // A deferred cycle is NOT a failure (it did not fire) and NOT a success:
        // the store must be exactly as it was.
        #expect(store.load() == PersistedSyncState(lastSuccessAt: nil, lastFailure: nil))
        #expect(coordinator.lastFailure() == nil)
    }

    @Test("an inert repeat while a cycle is in flight writes nothing")
    func inertRepeatWritesNothing() async throws {
        let repo = try makeSyncRepository()
        let transport = OB3BlockingPullTransport()
        let store = InMemorySyncStateStore()
        let coordinator = SyncCoordinator(engine: makeSyncEngine(repository: repo, transport: transport),
                                          syncStateStore: store)

        let first = Task { await coordinator.syncNow() }
        await transport.waitUntilPulling()
        _ = await coordinator.syncNow()   // inert: no second cycle, no store write

        // Asserted BEFORE the first cycle is released: an inert trigger must not
        // have touched the store, exactly as it must not have touched the engine.
        #expect(store.load() == PersistedSyncState(lastSuccessAt: nil, lastFailure: nil))

        transport.releasePull()
        _ = await first.value
    }

    // MARK: - Attribution: the wire code is not stale

    @Test("an offline cycle after a server-code failure records no stale code")
    func offlineCycleDoesNotRideAPreviousServerCode() async throws {
        let repo = try makeSyncRepository()
        let priorSuccess = Date(timeIntervalSinceReferenceDate: 9000)
        // The previous cycle failed with a SERVER code (persisted), and the
        // same code is still sitting in the shared diagnostics sink when the
        // offline cycle begins - the exact stale-attribution the coordinator
        // must clear at the start of every cycle.
        let store = InMemorySyncStateStore(seededWith: PersistedSyncState(
            lastSuccessAt: priorSuccess,
            lastFailure: SyncFailureRecord(at: priorSuccess.addingTimeInterval(-60),
                                           kind: .upgradeRequired,
                                           code: "upgrade_required", traceId: "previous-cycle")))
        let diagnostics = SyncFailureDiagnostics()
        diagnostics.record(code: "upgrade_required", traceId: "previous-cycle")
        let transport = SyncTransportDouble()
        transport.setFailAll(true)
        let coordinator = SyncCoordinator(engine: makeSyncEngine(repository: repo, transport: transport),
                                          syncStateStore: store,
                                          failureDiagnostics: diagnostics)

        let outcome = await coordinator.syncNow()
        #expect(outcome.offline, "the harness must actually fail offline")

        let failure = try #require(store.load().lastFailure)
        #expect(failure.kind == .offline)
        #expect(failure.code == nil,
                "an offline cycle must not be attributed a server code from an earlier cycle")
        #expect(failure.traceId == nil)
        #expect(store.load().lastSuccessAt == priorSuccess,
                "an offline cycle must leave the last success date alone")
    }

    // MARK: - The record holds no domain value (hard rule 12)

    @Test("the persisted state a cycle writes is free of domain values")
    func persistedStateIsFreeOfDomainValues() async throws {
        let repo = try makeSyncRepository()
        let stationName = "Zvezda-Lubricants-77"
        let note = "timing-belt-service-ob3"
        let amount = "64.20"
        var vehicle = makeSyncVehicle()
        vehicle.name = stationName
        var fill = makeSyncFillUp(vehicleId: vehicle.id)
        fill.note = note
        fill.money = Money(amount: Decimal(string: amount)!,
                           currency: .eur, homeCurrency: .eur)
        try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))
        try repo.upsertFillUp(fill, syncState: .dirty)

        // 1. A successful cycle over the repository holding those values.
        let successStore = InMemorySyncStateStore()
        let successCoordinator = SyncCoordinator(
            engine: makeSyncEngine(repository: repo, transport: SyncTransportDouble()),
            syncStateStore: successStore)
        _ = await successCoordinator.syncNow()

        // 2. A failing cycle (401) over the same repository.
        let diagnostics = SyncFailureDiagnostics()
        let failingStore = InMemorySyncStateStore()
        let failingTransport = RemoteSyncTransport(
            director: cannedDirector(),
            transport: CannedHTTPTransport(TankbookHTTPResponse(
                status: 401, body: problemBody(code: "token_invalid", traceId: "ob3-sweep"))),
            tokenProvider: CannedTokenProvider(),
            diagnostics: diagnostics)
        let failingCoordinator = SyncCoordinator(
            engine: makeSyncEngine(repository: repo, transport: failingTransport),
            syncStateStore: failingStore,
            failureDiagnostics: diagnostics)
        _ = await failingCoordinator.syncNow()

        // Encode BOTH stores the way they would persist and sweep the whole
        // output: a record that started carrying a domain value fails here even
        // though no per-field test mentions it (the OB.3 privacy contract).
        for store in [successStore, failingStore] {
            let data = try JSONEncoder().encode(store.load())
            let json = try #require(String(data: data, encoding: .utf8))
            for needle in [stationName, note, amount] {
                #expect(!json.contains(needle), "the persisted state leaked: \(needle)")
            }
        }
    }
}

// MARK: - net.response carries the server's code on a failure (OB.3, OB.1 loose end)

@Suite("net.response errorCode (OB.3)")
struct OB3NetResponseErrorCodeTests {
    private func makeLog(sink: InMemorySink) -> TankbookLog {
        TankbookLog(sink: sink, context: {
            LogContext(deviceId: "ob3-device", appVersion: "9.9.9-test", platform: "ios")
        }, breadcrumbs: nil)
    }

    private func emit(_ response: TankbookHTTPResponse) async throws -> (TankbookLog, InMemorySink) {
        let sink = InMemorySink()
        let log = makeLog(sink: sink)
        let transport = LoggingHTTPTransport(inner: CannedHTTPTransport(response), log: log)
        let request = TankbookHTTPRequest(
            url: URL(string: "https://api.tankbook.live/v1/sync/pull")!,
            method: "GET",
            headers: [:])
        _ = try await transport.execute(request)
        return (log, sink)
    }

    @Test("a 4xx whose body names a code emits net.response with errorCode")
    func fourHundredCarriesTheCode() async throws {
        let (_, sink) = try await emit(TankbookHTTPResponse(
            status: 401,
            body: problemBody(code: "token_invalid", traceId: "ob3-log-1",
                              title: "Unauthorized", detail: "the token expired")))

        let text = sink.rendered().joined(separator: "\n")
        #expect(text.contains("event=net.response"))
        #expect(text.contains("errorCode=token_invalid"),
                "docs/LOGGING.md promises net.response carries errorCode on failure")
        // Only the code member is ever attached - never the title, never the
        // detail, never the trace id of the problem body as a field (hard rule
        // 12; the request's own trace id rides the common fields).
        #expect(!text.contains("Unauthorized"), "title is a body value and must not be logged")
        #expect(!text.contains("the token expired"), "detail is a body value and must not be logged")
    }

    @Test("a 200 emits no errorCode")
    func successEmitsNoErrorCode() async throws {
        let (_, sink) = try await emit(TankbookHTTPResponse(
            status: 200,
            body: Data(#"{"code":"token_invalid"}"#.utf8)))

        let text = sink.rendered().joined(separator: "\n")
        #expect(text.contains("event=net.response"))
        #expect(!text.contains("errorCode="),
                "a success must not attach an errorCode - its body is not an error")
    }

    @Test("a 4xx whose body has no code member emits none")
    func fourHundredWithoutCodeEmitsNone() async throws {
        let (_, sink) = try await emit(TankbookHTTPResponse(
            status: 418,
            body: problemBody(code: nil, traceId: "ob3-log-2", title: "Teapot")))

        let text = sink.rendered().joined(separator: "\n")
        #expect(text.contains("event=net.response"))
        #expect(!text.contains("errorCode="),
                "no code member on the wire means no errorCode on the line")
        #expect(!text.contains("Teapot"))
    }
}
