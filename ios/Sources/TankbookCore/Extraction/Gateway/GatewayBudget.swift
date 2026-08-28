import Foundation

// MARK: - P6.3 the 3-second UI budget (docs/API.md -> "The device's side of
// /extract", rule 2).
//
// The corpus measured the gateway at median 6.5-8.3 s, max 40 s; the budget is
// 3 s. That is not a contradiction - the budget is about the user's next step,
// not about aborting the work: at 3 s the UI moves on (the on-device result was
// already on screen, F4), and the request itself may finish in the background.
// At a realistic 1 Mbit/s upstream even a 250 KB rendition takes ~2 s to upload
// before the model has seen a pixel, so a hard 3 s abort would cancel almost
// every request on a mobile link and make the whole tier useless where it is
// needed most.
//
// So the wait below NEVER cancels the running task. It races the answer against
// the budget and hands the still-running task back when the budget wins.

/// The 3-second per-attempt budget (docs/API.md rule 2).
public enum GatewayBudget {
    public static let duration: Duration = .seconds(3)
}

/// The outcome of waiting on a gateway request for the budget.
public enum GatewayWait<Value: Sendable>: Sendable {
    /// The answer arrived within the budget.
    case answered(Value)
    /// The budget expired while the request was still in flight. The caller
    /// moves on - the sheet already shows the on-device result - and the
    /// carried task keeps running; await it later for the late answer.
    case stillRunning(Task<Value, Error>)
}

/// The budget wait. The one rule that makes the feature correct: **the wait
/// must never cancel the work.** The budget is a UI wait, not an abort.
public enum GatewayWaiter {

    /// Races `task` against `timeout` and returns whichever wins. When the
    /// budget wins, `task` is NOT cancelled - it keeps running and is handed
    /// back for a later await. When the task throws within the budget, the
    /// error propagates (the transport failure is the caller's to handle -
    /// the on-device result stands, F4).
    ///
    /// The race is two unstructured, **detached** tasks writing into one
    /// guarded continuation: a watcher that forwards the real task's outcome,
    /// and a deadline that fires at `timeout`. Whichever fires first resumes
    /// the continuation; the other's resume is a no-op. The real `task` is
    /// touched by neither - `Task.value` does not forward cancellation to the
    /// awaited task - so the work keeps running past the budget exactly as the
    /// API contract requires. (A `withTaskGroup` race was tried first and
    /// deadlocked in the app: `group.next()` never observed a sleeping child's
    /// completion. The continuation is fully under our control.)
    public static func wait<Value: Sendable>(
        _ task: Task<Value, Error>,
        timeout: Duration = GatewayBudget.duration
    ) async throws -> GatewayWait<Value> {
        let gate = WaitGate<Value>()
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let value = try await task.value
                    gate.resume(continuation, returning: .answered(value))
                } catch {
                    gate.resume(continuation, throwing: error)
                }
            }
            Task.detached {
                try? await Task.sleep(for: timeout)
                gate.resume(continuation, returning: .stillRunning(task))
            }
        }
    }
}

/// Guards a continuation against double-resume: exactly one of the watcher and
/// the deadline wins the race, and the loser's resume must be dropped.
private final class WaitGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func resume(_ continuation: CheckedContinuation<GatewayWait<Value>, Error>,
                returning value: GatewayWait<Value>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        continuation.resume(returning: value)
    }

    func resume(_ continuation: CheckedContinuation<GatewayWait<Value>, Error>,
                throwing error: Error) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        continuation.resume(throwing: error)
    }
}
