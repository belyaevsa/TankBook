import Foundation

// MARK: - RV.52 the Vision concurrency ceiling (docs/TESTING.md -> "Vision OCR
// concurrency ceiling")
//
// Vision's text recognizer deadlocks when too many `VNImageRequestHandler.perform`
// calls are in flight *on Swift concurrency's cooperative thread pool* - the pool
// `swift test` runs test cases on. Measured 2026-09-04 on a 12-core Mac: 11
// concurrent performs are safe, a 12th hangs the process in
// `_dispatch_semaphore_wait_slow` inside `VNControlledCapacityTasksQueue`.
//
// The important detail is WHERE the `perform` runs, not how many are gated. A
// *blocking* gate alone - a `DispatchSemaphore` or a serial `DispatchQueue` around
// a `perform` that still runs on the caller's thread - does NOT fix it: a blocked
// cooperative thread still consumes the pool, so 12 blocked test cases hang exactly
// as 12 active ones do (verified: a shared `DispatchSemaphore(value: 4)` still hung
// at 12). But run the same `perform` on a background dispatch thread and let the
// caller wait, and 40 concurrent callers pass clean - on a dispatch thread the
// recognizer has no such ceiling. That is what removes the hang.
//
// So `withSlot` does two things, and they are not interchangeable:
//   1. It runs `body` (the actual `perform`) on a background dispatch thread via a
//      per-call completion semaphore, so no cooperative thread is ever inside the
//      recognizer. That is the hang fix.
//   2. A bounded gate semaphore caps how many of those background performs are in
//      flight at once, so a future suite that adds many OCR tests cannot exhaust
//      the dispatch pool. That is defence-in-depth, not the hang fix - the
//      mutation note in docs/TESTING.md records that raising the limit does not
//      restore the hang, while running the body on the caller's thread does.
//
// The API stays synchronous on purpose: `recognizeText` throws, and the app's
// callers (the capture pipeline, the invoice scanner) stay unchanged.

/// The process-wide ceiling for in-flight Vision OCR requests (see above). 8 =
/// the measured safe ceiling of 11 minus 3 of margin, so a machine that measures
/// a degree lower than the one this was measured on still stays clear. On the
/// dispatch threads the recognizer actually runs on, the ceiling is far higher,
/// so 8 is safely below both.
public enum VisionOCRConcurrency {
    public static let limit = 8
}

/// A synchronous, bounded slot gate. `withSlot` waits for a free slot, runs
/// `body` on a background dispatch thread (so the calling thread never sits
/// inside Vision), and releases the slot on both the success and the throwing
/// path - a leaked slot on an error path would deadlock the suite the first
/// time an OCR call fails.
public final class VisionRequestGate: @unchecked Sendable {
    public let limit: Int

    private let gate: DispatchSemaphore

    public init(limit: Int) {
        self.limit = limit
        self.gate = DispatchSemaphore(value: limit)
    }

    public func withSlot<Value>(_ body: @escaping @Sendable () throws -> Value) throws -> Value {
        gate.wait()
        defer { gate.signal() }

        // The body runs on a BACKGROUND DISPATCH THREAD, never the caller's.
        // This hop is the hang fix, not the slot count above it: the deadlock
        // was Swift concurrency's cooperative thread pool being exhausted by
        // callers blocked inside Vision, and a cooperative thread that blocks
        // there cannot be reclaimed. A dispatch thread can. The caller then
        // waits on its own completion semaphore, so `recognizeText` stays
        // synchronous and its callers (the capture pipeline, the invoice
        // scanner) are unchanged.
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var outcome: Result<Value, Error>?
        DispatchQueue.global(qos: .userInitiated).async {
            outcome = Result { try body() }
            done.signal()
        }
        done.wait()

        // `outcome` is always set: the async block signals only after assigning.
        guard let outcome else {
            throw VisionRequestGateError.slotFinishedWithoutResult
        }
        return try outcome.get()
    }
}

/// The result of a `withSlot` body, written on the background thread and read on
/// the caller after the completion semaphore fires. The happens-before edge is
/// `done.signal()` / `done.wait()`; `@unchecked Sendable` records that.
private final class Box<Value>: @unchecked Sendable {
    var value: Value?
    var error: Error?
}


/// Raised only if a gate slot completes without producing a result, which the
/// implementation makes unreachable - it exists so the success path never has
/// to force-unwrap.
public enum VisionRequestGateError: Error {
    case slotFinishedWithoutResult
}
