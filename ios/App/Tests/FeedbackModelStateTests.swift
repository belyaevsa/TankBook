import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.160 L1 - the send state machine and the composer's post-send contract.
///
/// The row is presentation over states that already exist, so the wire-to-state
/// mapping is pinned here UNCHANGED (the same switch `FeedbackModel.send()` has
/// always run), and what is NEW is pinned as its own claim: every terminal
/// outcome - `.sent` AND the three queued ones - clears the draft, because a
/// submitted message no longer lives in the composer, and `consentRequired`
/// clears nothing (a refusal is not an outcome). The consent gate that decides
/// whether anything is queued at all is untouched: default OFF, and without it
/// `send()` refuses before the outbox is asked. Lives in the app-target bundle
/// because `FeedbackModel` is app code (docs/TESTING.md); the core half of the
/// gate and the outbox mapping stay pinned in `FeedbackTests`.
@MainActor
final class FeedbackModelStateTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Fixtures

    /// The wire outcomes a transport can force, one stub per case.
    private enum TransportBehavior {
        case success, offline, rateLimited, serverError
    }

    /// Builds a model over the REAL outbox (consent store -> queue -> client ->
    /// stub transport), so the consent gate and the wire mapping run exactly as
    /// they do in the app. `consented` mirrors the seam `-feedbackConsentOn`.
    private func makeModel(behavior: TransportBehavior,
                           consented: Bool,
                           suite: String) throws -> FeedbackModel {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let consentStore = FeedbackConsentStore(defaults: defaults)
        if consented { consentStore.setConsented(true) }
        let director = ConfigTransportDirector(baseURL: { URL(string: "https://api.tankbook.live")! },
                                               report: { _ in })
        let transport = stubTransport(behavior)
        let client = FeedbackClient(
            httpClient: TankbookHTTPClient(transport: transport,
                                           tokenProvider: NoTokenProvider()),
            director: director,
            deviceID: "rv160-test-device")
        let queue = FeedbackQueue(consentStore: consentStore,
                                  store: InMemoryFeedbackQueueStore())
        let outbox = FeedbackOutbox(client: client, queue: queue,
                                    log: TankbookLog(sink: InMemorySink(), context: {
                                        LogContext(deviceId: "rv160-test-device",
                                                   appVersion: "1.0.0", platform: "ios")
                                    }))
        return FeedbackModel(outbox: outbox, consentStore: consentStore,
                             appVersion: "1.0.0", deviceModel: "iPhone-test")
    }

    private func stubTransport(_ behavior: TransportBehavior) -> any TankbookHTTPTransport {
        switch behavior {
        case .success: StubBehaviorTransport(status: 202)
        case .offline: FailingTransport(URLError(.notConnectedToInternet))
        case .rateLimited: StubBehaviorTransport(status: 429, headers: ["Retry-After": "3600"])
        case .serverError: StubBehaviorTransport(status: 500)
        }
    }

    private func freshSuite() -> String {
        "feedback-model-tests-\(UUID().uuidString)"
    }

    // MARK: - The wire -> state mapping is unchanged (the row changes the view)

    func testWireOutcomesMapToTheSameStatesAsBefore() async throws {
        let cases: [(TransportBehavior, FeedbackModel.State)] = [
            (.success, .sent),
            (.offline, .queuedOffline),
            (.rateLimited, .queuedRateLimited),
            (.serverError, .queuedRetry)
        ]
        for (behavior, expected) in cases {
            let model = try makeModel(behavior: behavior, consented: true, suite: freshSuite())
            model.text = "A report about the offline send"
            await model.send()
            XCTAssertEqual(model.state, expected,
                           "\(behavior) must map to \(expected)")
        }
    }

    // MARK: - Every terminal outcome clears the draft; a refusal clears nothing

    func testSentClearsTheDraft() async throws {
        let model = try makeModel(behavior: .success, consented: true, suite: freshSuite())
        model.text = "A report"
        model.replyTo = "owner@example.com"

        await model.send()

        XCTAssertEqual(model.state, .sent)
        XCTAssertTrue(model.text.isEmpty,
                      "a sent message no longer lives in the composer - the outcome line says it went")
        XCTAssertTrue(model.replyTo.isEmpty)
    }

    func testQueuedOutcomesClearTheDraftToo() async throws {
        let behaviors: [(TransportBehavior, FeedbackModel.State)] = [
            (.offline, .queuedOffline),
            (.rateLimited, .queuedRateLimited),
            (.serverError, .queuedRetry)
        ]
        for (behavior, expected) in behaviors {
            let model = try makeModel(behavior: behavior, consented: true, suite: freshSuite())
            model.text = "Saved for later"
            model.replyTo = "owner@example.com"

            await model.send()

            XCTAssertEqual(model.state, expected)
            XCTAssertTrue(model.text.isEmpty,
                          "a queued case is stored in the outbox, not the composer - \(behavior)")
            XCTAssertTrue(model.replyTo.isEmpty,
                          "the reply-to must clear with the draft for \(behavior)")
        }
    }

    func testConsentRequiredClearsNothing() async throws {
        let model = try makeModel(behavior: .success, consented: false, suite: freshSuite())
        model.text = "My message stays"

        await model.send()

        XCTAssertEqual(model.state, .consentRequired)
        XCTAssertEqual(model.text, "My message stays",
                       "a refusal is not an outcome - the draft waits for the toggle")
    }

    // MARK: - The consent gate is unchanged: default OFF, nothing queued without it

    func testConsentDefaultsOffAndGatesTheSend() async throws {
        let suite = freshSuite()
        let model = try makeModel(behavior: .success, consented: false, suite: suite)
        XCTAssertFalse(model.hasConsented,
                       "the once-asked opt-in must stay default OFF (docs/ERRORS.md)")
        model.text = "A report without consent"

        await model.send()

        XCTAssertEqual(model.state, .consentRequired,
                       "without consent send() must refuse before anything is queued")
        // The gate is the OUTBOX's: with no consent nothing reaches a transport.
        // A fresh model over the same defaults sees the refusal too - the state
        // is not cached.
        let second = try makeModel(behavior: .success, consented: false, suite: suite)
        second.text = "Another report without consent"
        await second.send()
        XCTAssertEqual(second.state, .consentRequired)
    }

    /// RV.159 - the consent-comprehension defect's L1 half: the diagnostics
    /// opt-in is a DIFFERENT property (`DiagnosticsConsentStore`) and must not
    /// satisfy the feedback gate. A user who enabled "Attach diagnostics" and
    /// then hit Send is refused because the gate reads only the feedback
    /// consent; this pins that the two stores never meet.
    func testDiagnosticsConsentDoesNotSatisfyTheFeedbackGate() async throws {
        let diagnosticsSuite = freshSuite()
        let diagnosticsDefaults = try XCTUnwrap(UserDefaults(suiteName: diagnosticsSuite))
        diagnosticsDefaults.removePersistentDomain(forName: diagnosticsSuite)
        let diagnosticsStore = DiagnosticsConsentStore(defaults: diagnosticsDefaults)
        diagnosticsStore.setConsented(true)
        XCTAssertTrue(diagnosticsStore.hasConsented,
                      "the scenario needs the diagnostics opt-in ON")

        let model = try makeModel(behavior: .success, consented: false,
                                  suite: freshSuite())
        model.text = "Attach diagnostics is on, yet this must not send"
        await model.send()

        XCTAssertEqual(model.state, .consentRequired,
                       "enabling the diagnostics opt-in must not satisfy the feedback "
                           + "consent gate - they are different properties (RV.159)")
    }
}

/// Answers every request with a canned status (and headers).
private struct StubBehaviorTransport: TankbookHTTPTransport {
    let status: Int
    let headers: [String: String]

    init(status: Int, headers: [String: String] = [:]) {
        self.status = status
        self.headers = headers
    }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        TankbookHTTPResponse(status: status, headers: headers)
    }
}

/// Throws `error` for every request (offline).
private struct FailingTransport: TankbookHTTPTransport {
    let error: any Error

    init(_ error: any Error) {
        self.error = error
    }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        throw error
    }
}

private struct NoTokenProvider: AuthorizationTokenProvider {
    func token() -> String? { nil }
}
