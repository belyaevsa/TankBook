import Foundation

// PR.7: the client retry schedule (docs/SYNC.md -> "Offline & failure behavior",
// docs/PRACTICES.md U7). Pure and deterministic: the delay is a function of the
// outcome, the attempt number and an injected jitter value in [0, 1], so a test
// pins the schedule with no wall clock and no sleep (the GatewayBudgetTests
// lesson - four wall-clock races were fixed there; add no fifth).
//
// Retried: the unavailable class (offline, 5xx) and the 429 wait. Never the
// refusal classes - authExpired (401), deviceRevoked (410), tierRefused (402),
// upgradeRequired (426) and refused (an unknown 4xx). Retrying those is a loop
// that burns battery and never succeeds.

/// Computes the delay before the next sync attempt, or nil when the outcome
/// must not be retried. The server's `Retry-After` wins over the curve, exactly;
/// otherwise the delay is jittered exponential backoff, capped.
public enum SyncRetryPolicy {
    /// The first backoff delay, in seconds. Attempt n delays `base * 2^n`.
    public static let baseDelaySeconds: Double = 1
    /// The cap (~5 min). No backoff delay exceeds it.
    public static let capSeconds: Double = 300
    /// Equal jitter: the delay lands uniformly in [base/2, base]. Synchronised
    /// retries from a fleet after an outage are a self-inflicted second outage
    /// (docs/PRACTICES.md U7), so jitter is bounded and stated, never decoration.
    public static let jitterFraction: Double = 0.5

    /// The delay before retrying `outcome` after `attempt` prior retries
    /// (0 = the first retry). `jitter` is a value in [0, 1]: 0 yields the lower
    /// bound, 1 the upper. Returns nil when the outcome is not retried - a
    /// refusal, a success, or a deferral.
    public static func delay(after outcome: SyncOutcome, attempt: Int, jitter: Double) -> Duration? {
        if let retryAfter = outcome.retryAfterSeconds, retryAfter > 0 {
            // The server named when its rate-limit window resets. That number
            // wins over the curve, exactly - jittering below it would just be
            // refused again, and the server has already spread the fleet by the
            // size of its window.
            return .seconds(Double(retryAfter))
        }
        if outcome.transportUnavailable {
            return jittered(backoff(attempt: attempt), jitter: jitter)
        }
        if case .rateLimited = outcome.refusedByServer {
            // A 429 with no Retry-After: the server said "later" without naming
            // when, so the curve stands in.
            return jittered(backoff(attempt: attempt), jitter: jitter)
        }
        return nil
    }

    /// The unjittered exponential term: `base * 2^attempt`, capped.
    public static func backoff(attempt: Int) -> Duration {
        let exponent = max(attempt, 0)
        let factor = min(pow(2.0, Double(exponent)), capSeconds / baseDelaySeconds)
        return .seconds(baseDelaySeconds * factor)
    }

    /// Equal jitter: scale `base` into [base * (1 - fraction), base] by a jitter
    /// value in [0, 1]. The bound is stated so a test can pin it.
    public static func jittered(_ base: Duration, jitter: Double) -> Duration {
        let clamped = min(max(jitter, 0), 1)
        return .seconds(seconds(of: base) * (1 - jitterFraction + jitterFraction * clamped))
    }

    private static func seconds(of duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
