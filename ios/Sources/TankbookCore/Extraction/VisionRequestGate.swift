import Foundation

// MARK: - The Vision concurrency gate (docs/TESTING.md -> "Vision OCR
// concurrency ceiling")
//
// Vision's text recognizer deadlocks when Swift concurrency's cooperative thread
// pool - the pool `swift test` runs test cases on and `Task.detached` runs the
// app's capture pipeline on - is exhausted while a request is in flight. Two
// distinct ways of exhausting it have been measured (the numbers are in the
// TESTING.md section):
//
//   1. Running the `perform` itself on cooperative threads: past a ceiling of
//      concurrent performs the process hangs in `_dispatch_semaphore_wait_slow`
//      inside `VNControlledCapacityTasksQueue`.
//   2. Merely BLOCKING cooperative threads while one perform runs: on macOS 27
//      the detector completes through Swift concurrency of its own, so a pool
//      full of callers parked in a semaphore leaves it no thread to complete
//      on, and a single in-flight request hangs forever. A gate limit of 1 does
//      not help; the blocked waiters are the problem.
//
// So `withSlot` does three things, and none of them is interchangeable:
//   1. The slot wait is `async` and SUSPENDS - a waiting caller holds no thread.
//      That is the fix for (2), and it is why there is no synchronous entry
//      point: a caller that could block would reintroduce the hang.
//   2. The body (the actual `perform`) runs on a background dispatch thread and
//      resumes a continuation, so no cooperative thread is ever inside the
//      recognizer. That is the fix for (1).
//   3. A bounded slot count caps how many of those background performs are in
//      flight at once, so a future suite that adds many OCR tests cannot
//      exhaust the dispatch pool. That is defence-in-depth, not a hang fix.

/// The process-wide ceiling for in-flight Vision OCR requests (see above). 8 =
/// the measured safe ceiling of 11 minus 3 of margin, so a machine that measures
/// a degree lower than the one this was measured on still stays clear. On the
/// dispatch threads the recognizer actually runs on, the ceiling is far higher,
/// so 8 is safely below both.
public enum VisionOCRConcurrency {
    public static let limit = 8
}

/// A bounded slot gate whose wait suspends rather than blocks. `withSlot` waits
/// for a free slot, runs `body` on a background dispatch thread (so no
/// cooperative thread ever sits inside Vision), and releases the slot on both
/// the success and the throwing path - a leaked slot on an error path would
/// deadlock the suite the first time an OCR call fails.
public final class VisionRequestGate: Sendable {
    public let limit: Int

    private let slots: AsyncSlots

    public init(limit: Int) {
        self.limit = limit
        self.slots = AsyncSlots(limit: limit)
    }

    public func withSlot<Value: Sendable>(
        _ body: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        await slots.acquire()
        defer { slots.release() }

        // The body runs on a BACKGROUND DISPATCH THREAD, never the caller's,
        // and the caller suspends on the continuation instead of waiting on a
        // semaphore - see the header for why both halves are required.
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try body() })
            }
        }
    }
}

/// A counting semaphore for Swift concurrency: `acquire` suspends when no slot
/// is free and `release` resumes the longest-waiting caller. Fair (FIFO) so a
/// burst of callers cannot starve one of them.
private final class AsyncSlots: @unchecked Sendable {
    private let lock = NSLock()
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        available = limit
    }

    func acquire() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if available > 0 {
                available -= 1
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func release() {
        lock.lock()
        if waiters.isEmpty {
            available += 1
            lock.unlock()
        } else {
            let next = waiters.removeFirst()
            lock.unlock()
            next.resume()
        }
    }
}
