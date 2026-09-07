import Testing
import Foundation
import os
@testable import TankbookCore

// Tests for ios/Sources/TankbookCore/Feedback - the About & feedback feature
// (PJ.20). The load-bearing invariants live here at L1:
//   1. consent defaults off and persists across a fresh instance;
//   2. a case is queued only with consent (the queue stays empty without it);
//   3. a fully populated payload through the log path leaks no domain value.
// They run in-process against injected stores and a stub transport, no sockets
// (docs/TESTING.md).

// MARK: - Fixtures

private func testDirector() -> ConfigTransportDirector {
    ConfigTransportDirector(
        baseURL: { URL(string: "https://api.tankbook.live")! },
        report: { _ in })
}

private struct NoTokenProvider: AuthorizationTokenProvider {
    func token() -> String? { nil }
}

private struct StubFeedbackTransport: TankbookHTTPTransport {
    enum Behavior { case success, rateLimited, offline }
    let behavior: Behavior

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        switch behavior {
        case .success: return TankbookHTTPResponse(status: 202)
        case .rateLimited: return TankbookHTTPResponse(status: 429, headers: ["Retry-After": "3600"])
        case .offline: throw URLError(.notConnectedToInternet)
        }
    }
}

private func makeClient(_ behavior: StubFeedbackTransport.Behavior) -> FeedbackClient {
    makeClient(transport: StubFeedbackTransport(behavior: behavior))
}

private func makeClient(transport: any TankbookHTTPTransport) -> FeedbackClient {
    FeedbackClient(
        httpClient: TankbookHTTPClient(transport: transport,
                                       tokenProvider: NoTokenProvider()),
        director: testDirector(),
        deviceID: "device-test-0001")
}

private func makeOutbox(_ behavior: StubFeedbackTransport.Behavior,
                        consentStore: FeedbackConsentStore,
                        sink: InMemorySink) -> FeedbackOutbox {
    let queue = FeedbackQueue(consentStore: consentStore, store: InMemoryFeedbackQueueStore())
    return FeedbackOutbox(client: makeClient(behavior), queue: queue, log: testLog(sink: sink))
}

private func testLog(sink: InMemorySink) -> TankbookLog {
    TankbookLog(sink: sink, context: {
        LogContext(deviceId: "device-test-0001", appVersion: "9.9.9-test", platform: "ios")
    })
}

private func makeConsentStore() -> (store: FeedbackConsentStore, suite: String) {
    let suite = "feedback-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (FeedbackConsentStore(defaults: defaults), suite)
}

private func populatedPayload() -> (payload: FeedbackPayload, forbidden: [String]) {
    let payload = FeedbackPayload(
        category: .problem,
        text: "The Shell station read 42.3 L at 64.20 EUR near the A5.",
        appVersion: "1.0",
        deviceModel: "iPhone17,2",
        replyTo: "owner@example.com")
    let forbidden = ["Shell", "42.3", "64.20", "A5", "iPhone17,2", "owner@example.com"]
    return (payload, forbidden)
}

// MARK: - Consent (docs/ERRORS.md -> About & feedback)

@Test func consentDefaultsOff() {
    let (store, _) = makeConsentStore()
    #expect(store.hasConsented == false)
}

@Test func consentPersistsAcrossAFreshInstance() {
    let (first, suite) = makeConsentStore()
    #expect(first.hasConsented == false)

    first.setConsented(true)

    // A SECOND store over the same UserDefaults must see the persisted value.
    // Reusing `first` would pass even if the value were cached in memory and
    // never written - which is exactly the persistence bug this pins.
    let defaults = UserDefaults(suiteName: suite)!
    let second = FeedbackConsentStore(defaults: defaults)
    #expect(second.hasConsented == true)
}

@Test func consentCanBeTurnedBackOff() {
    let (store, _) = makeConsentStore()
    store.setConsented(true)
    store.setConsented(false)
    #expect(store.hasConsented == false)
}

// MARK: - The queue's consent gate (the load-bearing rule)

@Test func queueStaysEmptyWithoutConsent() async {
    let (store, _) = makeConsentStore()
    let queue = FeedbackQueue(consentStore: store, store: InMemoryFeedbackQueueStore())
    let (payload, _) = populatedPayload()

    let id = await queue.enqueue(payload)

    #expect(id == nil)
    let pending = await queue.pending()
    #expect(pending.isEmpty)
}

@Test func queueAcceptsWithConsent() async {
    let (store, _) = makeConsentStore()
    store.setConsented(true)
    let queue = FeedbackQueue(consentStore: store, store: InMemoryFeedbackQueueStore())
    let (payload, _) = populatedPayload()

    let id = await queue.enqueue(payload)

    #expect(id != nil)
    let pending = await queue.pending()
    #expect(pending.count == 1)
    #expect(pending.first?.payload == payload)
}

// MARK: - The outbox maps the wire outcomes

@Test func outboxWithoutConsentReturnsConsentRequiredAndQueuesNothing() async {
    let (store, _) = makeConsentStore()
    let sink = InMemorySink()
    let outbox = makeOutbox(.success, consentStore: store, sink: sink)
    let (payload, _) = populatedPayload()

    let result = await outbox.submit(payload)

    #expect(result == .consentRequired)
    // The queue is the outbox's private state; the outcome being consentRequired
    // plus no send log line is the observable proof nothing was queued or sent.
    #expect(!sink.all().contains { $0.event == "feedback.send" })
}

@Test func outboxSendsOn202() async {
    let (store, _) = makeConsentStore()
    store.setConsented(true)
    let sink = InMemorySink()
    let outbox = makeOutbox(.success, consentStore: store, sink: sink)
    let (payload, _) = populatedPayload()

    let result = await outbox.submit(payload)

    #expect(result == .sent)
    #expect(sink.all().map(\.event).contains("feedback.queue"))
    #expect(sink.all().map(\.event).contains("feedback.send"))
    #expect(!sink.all().map(\.event).contains("feedback.fail"))
}

@Test func outboxQueuesOffline() async {
    let (store, _) = makeConsentStore()
    store.setConsented(true)
    let sink = InMemorySink()
    let outbox = makeOutbox(.offline, consentStore: store, sink: sink)
    let (payload, _) = populatedPayload()

    let result = await outbox.submit(payload)

    #expect(result == .queued(reason: .offline))
    #expect(sink.all().map(\.event).contains("feedback.fail"))
}

@Test func outboxQueuesRateLimited() async {
    let (store, _) = makeConsentStore()
    store.setConsented(true)
    let sink = InMemorySink()
    let outbox = makeOutbox(.rateLimited, consentStore: store, sink: sink)
    let (payload, _) = populatedPayload()

    let result = await outbox.submit(payload)

    #expect(result == .queued(reason: .rateLimited))
}

// MARK: - Payload log sweep (hard rule 12: nothing but shape)

/// Renders a line's fields without the free-running machine fields. The
/// timestamp (a `LogLine` property, not a field) is omitted entirely, and
/// `durationMs` is blanked: both are free-running numbers that can spell a
/// needle ("42.3" inside `...:42.317Z`, "9876.54" inside a duration) and fire
/// roughly one run in 600. Fix the sweep, never the needle (docs/LOGGING.md).
private func sweptFields(_ line: LogLine) -> String {
    let parts = line.fields.compactMap { field -> String? in
        switch field.kind {
        case .publicValue(let value):
            if field.name == "durationMs" { return nil }
            return "\(field.name)=\(value)"
        case .privateValue:
            return "\(field.name)=<redacted>"
        }
    }
    return "\(line.event) " + parts.joined(separator: " ")
}

@Test func payloadLogSweepLeaksNoDomainValue() {
    let sink = InMemorySink()
    let log = TankbookLog(sink: sink, context: {
        LogContext(deviceId: "device-test-0001", appVersion: "9.9.9-test", platform: "ios")
    })
    let (payload, forbidden) = populatedPayload()

    log.emit(FeedbackQueued(payload: payload))
    log.emit(FeedbackSent(payload: payload, durationMs: 12))
    log.emit(FeedbackFailed(payload: payload, errorCode: "rate_limited", durationMs: 9))

    let output = sink.all().map(sweptFields).joined(separator: "\n")

    // Shape survives.
    #expect(output.contains("feedback.queue"))
    #expect(output.contains("feedback.send"))
    #expect(output.contains("feedback.fail"))
    #expect(output.contains("category=problem"))
    #expect(output.contains("hasReplyTo=true"))
    #expect(output.contains("hasDeviceModel=true"))
    #expect(output.contains("errorCode=rate_limited"))

    // No domain value appears anywhere.
    for value in forbidden {
        #expect(!output.contains(value), "leaked domain value: \(value)")
    }
}

// MARK: - The flush (RV.127): a queued case is retried on the NEXT foreground
//
// The automatic retry lives in the app's launch/foreground pass; these pin the
// outbox half of the promise - flush() sends what a prior session queued. Every
// "next pass" below is a BRAND-NEW outbox built over the same persisted file,
// never a leftover in-memory array: "it is still there from earlier in the test"
// would prove nothing about a real relaunch. The trigger half (that the pass
// calls flush) is pinned in the app target (`FeedbackForegroundFlushTests`).

private func temporaryQueueFile() -> (store: FileFeedbackQueueStore, url: URL) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("feedback-flush-\(UUID().uuidString).json")
    return (FileFeedbackQueueStore(fileURL: url), url)
}

private func makeFileOutbox(_ transport: any TankbookHTTPTransport,
                            consentStore: FeedbackConsentStore,
                            sink: InMemorySink,
                            store: FileFeedbackQueueStore) -> FeedbackOutbox {
    let queue = FeedbackQueue(consentStore: consentStore, store: store)
    return FeedbackOutbox(client: makeClient(transport: transport), queue: queue,
                          log: testLog(sink: sink))
}

/// Counts send attempts and answers every one with the given behaviour.
private final class CountingFeedbackTransport: TankbookHTTPTransport, @unchecked Sendable {
    enum Behavior { case success, offline }
    private let behavior: Behavior
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    init(_ behavior: Behavior) { self.behavior = behavior }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        lock.withLock { $0 += 1 }
        switch behavior {
        case .success: return TankbookHTTPResponse(status: 202)
        case .offline: throw URLError(.notConnectedToInternet)
        }
    }

    func callCount() -> Int { lock.withLock { $0 } }
}

/// Holds every send until `open()` - an overlapping-flush race becomes
/// deterministic state rather than a timing accident.
private actor FeedbackSendGate {
    private var started = 0
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signalStarted() { started += 1 }
    var startedCount: Int { started }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// Answers every send with `202`, but only once `open()` lets it through, and
/// counts how many sends actually left.
private final class GatedFeedbackTransport: TankbookHTTPTransport, @unchecked Sendable {
    private let gate: FeedbackSendGate
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    init(gate: FeedbackSendGate) { self.gate = gate }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        lock.withLock { $0 += 1 }
        await gate.signalStarted()
        await gate.wait()
        return TankbookHTTPResponse(status: 202)
    }

    func callCount() -> Int { lock.withLock { $0 } }
}

// MARK: - RV.127: the flush sends what a prior session queued

/// An item queued and persisted offline is sent by the next flush STARTING FROM
/// A COLD STATE: the second outbox is built over the same file with no memory of
/// the first instance, exactly like a real relaunch.
@Test func flushSendsAPersistedQueuedCaseFromAColdStart() async throws {
    let (storeFile, url) = temporaryQueueFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let (consent, _) = makeConsentStore()
    consent.setConsented(true)
    let (payload, _) = populatedPayload()

    // Phase 1 - "today's offline session": submit fails and leaves the case in
    // the FILE. Nothing about phase 1's instances may survive into phase 2.
    let first = makeFileOutbox(CountingFeedbackTransport(.offline),
                               consentStore: consent, sink: InMemorySink(), store: storeFile)
    #expect(await first.submit(payload) == .queued(reason: .offline))
    #expect(storeFile.load().count == 1, "the failed send must be persisted, not dropped")

    // Phase 2 - "next launch": a brand-new outbox over the SAME file. flush()
    // must send the persisted case and clear it.
    let sending = CountingFeedbackTransport(.success)
    let second = makeFileOutbox(sending, consentStore: consent,
                                sink: InMemorySink(), store: storeFile)
    await second.flush()

    #expect(sending.callCount() == 1, "the persisted case must be sent once")
    #expect(storeFile.load().isEmpty, "a sent case must leave the persisted queue")
}

/// A flush with no connectivity leaves the item queued, not dropped - the retry
/// is the next foreground, and dropping would violate hard rule 8.
@Test func flushWithoutConnectivityKeepsTheCaseQueued() async throws {
    let (storeFile, url) = temporaryQueueFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let (consent, _) = makeConsentStore()
    consent.setConsented(true)
    let (payload, _) = populatedPayload()

    let first = makeFileOutbox(CountingFeedbackTransport(.offline),
                               consentStore: consent, sink: InMemorySink(), store: storeFile)
    #expect(await first.submit(payload) == .queued(reason: .offline))

    let offlineAttempt = CountingFeedbackTransport(.offline)
    let second = makeFileOutbox(offlineAttempt, consentStore: consent,
                                sink: InMemorySink(), store: storeFile)
    await second.flush()

    #expect(offlineAttempt.callCount() == 1, "the next pass must try the queued case")
    #expect(storeFile.load().count == 1,
            "no connectivity must keep the case queued for the pass after that")
}

/// A flush that races a manual retry (a second flush arriving mid-send) POSTs
/// the queued case exactly once. Without the in-flight guard both flushes read
/// the same pending snapshot and double-post - the assertion below counts sends.
@Test func flushThatRacesAManualRetryPostsOnce() async throws {
    let (storeFile, url) = temporaryQueueFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let (consent, _) = makeConsentStore()
    consent.setConsented(true)
    let (payload, _) = populatedPayload()

    let seeder = makeFileOutbox(CountingFeedbackTransport(.offline),
                                consentStore: consent, sink: InMemorySink(), store: storeFile)
    #expect(await seeder.submit(payload) == .queued(reason: .offline))

    let gate = FeedbackSendGate()
    let transport = GatedFeedbackTransport(gate: gate)
    let outbox = makeFileOutbox(transport, consentStore: consent,
                                sink: InMemorySink(), store: storeFile)

    // The foreground flush starts and its send is on the wire (stalled on the
    // gate); a manual retry - a second flush - arrives while it is in flight.
    async let foreground: Void = outbox.flush()
    while await gate.startedCount == 0 {
        try? await Task.sleep(for: .milliseconds(1))
    }
    async let manualRetry: Void = outbox.flush()
    await gate.open()
    await foreground
    await manualRetry

    #expect(transport.callCount() == 1,
            "one queued case must be POSTed once across a racing flush and retry")
    #expect(storeFile.load().isEmpty, "the case is sent, not duplicated")
}
