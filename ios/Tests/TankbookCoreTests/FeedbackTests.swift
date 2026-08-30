import Testing
import Foundation
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
    FeedbackClient(
        httpClient: TankbookHTTPClient(transport: StubFeedbackTransport(behavior: behavior),
                                       tokenProvider: NoTokenProvider()),
        director: testDirector(),
        deviceID: "device-test-0001")
}

private func makeOutbox(_ behavior: StubFeedbackTransport.Behavior,
                        consentStore: FeedbackConsentStore,
                        sink: InMemorySink) -> FeedbackOutbox {
    let queue = FeedbackQueue(consentStore: consentStore, store: InMemoryFeedbackQueueStore())
    let log = TankbookLog(sink: sink, context: {
        LogContext(deviceId: "device-test-0001", appVersion: "9.9.9-test", platform: "ios")
    })
    return FeedbackOutbox(client: makeClient(behavior), queue: queue, log: log)
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
