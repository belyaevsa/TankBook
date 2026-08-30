import Foundation
import Testing
@testable import TankbookCore

// PR.7 - the retry schedule is a pure function of (outcome, attempt, jitter),
// so every bound is pinned with no wall clock and no sleep (the GatewayBudget
// lesson: four wall-clock races were fixed there; add no fifth). Each mutation
// the orchestrator demanded maps to one test here:
//
//   1. ignore Retry-After            -> `retryAfterWinsOverTheCurve`
//   2. remove the cap                -> `backoffIsCapped`
//   3. remove the jitter             -> `jitterIsBoundedAndMoves`
//   4. retry a 426                   -> `refusalClassesAreNeverRetried`

@Suite("Sync retry policy (PR.7)")
struct SyncRetryPolicyTests {

    // MARK: - Outcome builders (the exact shapes SyncEngine produces)

    private func rateLimited(_ retryAfter: Int?) -> SyncOutcome {
        var outcome = SyncOutcome()
        outcome.refusedByServer = .rateLimited(retryAfterSeconds: retryAfter)
        outcome.retryAfterSeconds = retryAfter
        return outcome
    }

    private func unavailable() -> SyncOutcome {
        var outcome = SyncOutcome()
        outcome.serverUnavailable = true
        return outcome
    }

    private func offline() -> SyncOutcome {
        var outcome = SyncOutcome()
        outcome.offline = true
        return outcome
    }

    // MARK: - Retry-After wins over the curve

    @Test("Retry-After wins over the curve, exactly, and is not jittered")
    func retryAfterWinsOverTheCurve() {
        let outcome = rateLimited(120)
        // At attempt 5 the curve would be 32 s; the server's 120 s wins.
        #expect(SyncRetryPolicy.delay(after: outcome, attempt: 5, jitter: 0.0) == .seconds(120))
        #expect(SyncRetryPolicy.delay(after: outcome, attempt: 5, jitter: 0.5) == .seconds(120))
        #expect(SyncRetryPolicy.delay(after: outcome, attempt: 5, jitter: 1.0) == .seconds(120))
        #expect(SyncRetryPolicy.delay(after: outcome, attempt: 0, jitter: 0.5) == .seconds(120))
    }

    @Test("a 429 with no Retry-After uses the curve")
    func rateLimitedWithoutRetryAfterUsesTheCurve() {
        let outcome = rateLimited(nil)
        #expect(SyncRetryPolicy.delay(after: outcome, attempt: 0, jitter: 1.0) == .seconds(1))
        #expect(SyncRetryPolicy.delay(after: outcome, attempt: 1, jitter: 1.0) == .seconds(2))
    }

    // MARK: - The exponential curve and its cap

    @Test("a 5xx sequence backs off 1-2-4-8")
    func backoffFollowsOneTwoFourEight() {
        let outcome = unavailable()
        // jitter 1.0 is the upper bound = the unjittered base.
        #expect(SyncRetryPolicy.delay(after: outcome, attempt: 0, jitter: 1.0) == .seconds(1))
        #expect(SyncRetryPolicy.delay(after: outcome, attempt: 1, jitter: 1.0) == .seconds(2))
        #expect(SyncRetryPolicy.delay(after: outcome, attempt: 2, jitter: 1.0) == .seconds(4))
        #expect(SyncRetryPolicy.delay(after: outcome, attempt: 3, jitter: 1.0) == .seconds(8))
    }

    @Test("the backoff is capped at 5 minutes")
    func backoffIsCapped() {
        let outcome = unavailable()
        // attempt 9 is 512 s uncapped; the cap holds it at 300 s.
        #expect(SyncRetryPolicy.delay(after: outcome, attempt: 9, jitter: 1.0) == .seconds(300))
        #expect(SyncRetryPolicy.delay(after: outcome, attempt: 100, jitter: 1.0) == .seconds(300))
        #expect(SyncRetryPolicy.capSeconds == 300)
    }

    @Test("offline retries exactly like a 5xx - both are the transient class")
    func offlineRetriesLikeAnOutage() {
        // Offline and server-down are the same class for RETRY purposes (both
        // resolve themselves); the split is about the surface's next step, not
        // about whether to retry.
        let offline = offline()
        #expect(SyncRetryPolicy.delay(after: offline, attempt: 0, jitter: 1.0) == .seconds(1))
        #expect(SyncRetryPolicy.delay(after: offline, attempt: 1, jitter: 1.0) == .seconds(2))
    }

    // MARK: - Jitter is bounded and actually moves the delay

    @Test("jitter stays inside [base/2, base] and moves the delay")
    func jitterIsBoundedAndMoves() {
        let base = SyncRetryPolicy.backoff(attempt: 1) // 2 s
        // The lower bound (jitter 0) is half, the upper (jitter 1) is the base.
        #expect(SyncRetryPolicy.jittered(base, jitter: 0.0) == .seconds(1.0))
        #expect(SyncRetryPolicy.jittered(base, jitter: 1.0) == .seconds(2.0))
        #expect(SyncRetryPolicy.jittered(base, jitter: 0.5) == .seconds(1.5))

        let outcome = unavailable()
        #expect(SyncRetryPolicy.delay(after: outcome, attempt: 1, jitter: 0.0) == .seconds(1.0))
        #expect(SyncRetryPolicy.delay(after: outcome, attempt: 1, jitter: 0.5) == .seconds(1.5))
        // A jitter outside [0, 1] clamps rather than escaping the bound.
        #expect(SyncRetryPolicy.delay(after: outcome, attempt: 1, jitter: 2.0) == .seconds(2.0))
        #expect(SyncRetryPolicy.delay(after: outcome, attempt: 1, jitter: -1.0) == .seconds(1.0))
    }

    // MARK: - The refusal classes are never retried

    @Test("401, 402, 410, 426 and an unknown 4xx are never retried")
    func refusalClassesAreNeverRetried() {
        var authExpired = SyncOutcome()
        authExpired.authExpired = true
        var deviceRevoked = SyncOutcome()
        deviceRevoked.deviceRevoked = true
        var upgradeRequired = SyncOutcome()
        upgradeRequired.upgradeRequired = true
        var tierRefused = SyncOutcome()
        tierRefused.refusedByServer = .tierRefused
        var refused = SyncOutcome()
        refused.refusedByServer = .refused(status: 451)

        for outcome in [authExpired, deviceRevoked, upgradeRequired, tierRefused, refused] {
            #expect(SyncRetryPolicy.delay(after: outcome, attempt: 0, jitter: 0.5) == nil,
                    "\(outcome) is a refusal, not a transient fault - it must not be retried")
        }
    }

    @Test("a successful or deferred sync schedules nothing")
    func successAndDeferralScheduleNothing() {
        #expect(SyncRetryPolicy.delay(after: SyncOutcome(), attempt: 0, jitter: 0.5) == nil)
        var deferred = SyncOutcome()
        deferred.deferred = true
        #expect(SyncRetryPolicy.delay(after: deferred, attempt: 0, jitter: 0.5) == nil)
    }
}
