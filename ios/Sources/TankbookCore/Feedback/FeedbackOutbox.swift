import Foundation

// The feedback orchestrator: enqueue (consent-gated), then attempt a send. A
// failed send leaves the case queued for a later retry (docs/ERRORS.md -> About
// & feedback: offline -> "sends automatically when you're online", 429 ->
// "queued for tomorrow"). Nothing is lost silently (hard rule 8): the only
// terminal non-queued outcome is a success.

/// Why a case stayed queued. `.rateLimited` is the documented 429 state; the
/// other two map to the generic "will send automatically" surface.
public enum FeedbackSubmissionReason: Sendable, Equatable {
    case offline
    case rateLimited
    case serverError
}

/// The result of submitting a case.
public enum FeedbackSubmission: Sendable, Equatable {
    /// No consent: nothing was queued and nothing was sent (the load-bearing
    /// rule - consent defaults off and a case is queued only with it).
    case consentRequired
    /// Accepted by the server (`202`); removed from the queue.
    case sent
    /// Queued and retried later, with the reason.
    case queued(reason: FeedbackSubmissionReason)
}

/// Orchestrates `FeedbackQueue` + `FeedbackClient` + `TankbookLog`.
public actor FeedbackOutbox {
    private let client: FeedbackClient
    private let queue: FeedbackQueue
    private let log: TankbookLog

    public init(client: FeedbackClient, queue: FeedbackQueue, log: TankbookLog) {
        self.client = client
        self.queue = queue
        self.log = log
    }

    /// Submits one case: enqueue (consent-gated), then attempt the send. On a
    /// failed send the case stays queued and the outcome names the reason.
    public func submit(_ payload: FeedbackPayload) async -> FeedbackSubmission {
        guard let id = await queue.enqueue(payload) else {
            return .consentRequired
        }
        log.emit(FeedbackQueued(payload: payload))
        return await send(payload, id: id)
    }

    /// Re-attempts every queued case (called when connectivity returns or on a
    /// later foreground). Stops at the first failure - the queue preserves
    /// order and a rate limit applies to the whole remaining window.
    public func flush() async {
        for item in await queue.pending() {
            let outcome = await send(item.payload, id: item.id)
            if case .queued = outcome { return }
        }
    }

    private func send(_ payload: FeedbackPayload, id: UUID) async -> FeedbackSubmission {
        let startedAt = Date()
        do {
            try await client.send(payload)
            await queue.remove(id: id)
            log.emit(FeedbackSent(payload: payload, durationMs: elapsedMs(startedAt)))
            return .sent
        } catch FeedbackClientError.rateLimited {
            log.emit(FeedbackFailed(payload: payload, errorCode: "rate_limited",
                                    durationMs: elapsedMs(startedAt)))
            return .queued(reason: .rateLimited)
        } catch FeedbackClientError.transportUnreachable {
            log.emit(FeedbackFailed(payload: payload, errorCode: "transport_unreachable",
                                    durationMs: elapsedMs(startedAt)))
            return .queued(reason: .offline)
        } catch {
            log.emit(FeedbackFailed(payload: payload, errorCode: "send_failed",
                                    durationMs: elapsedMs(startedAt)))
            return .queued(reason: .serverError)
        }
    }

    private func elapsedMs(_ from: Date) -> Int {
        Int(Date().timeIntervalSince(from) * 1000)
    }
}
