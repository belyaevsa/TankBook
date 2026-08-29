import Foundation
import Testing
@testable import TankbookCore

// P6.3 - the 3 s budget is a UI wait, never an abort (docs/API.md rule 2:
// "the budget is about the user's next step, not about aborting the work").
// The distinguishing test: an injected slow transport makes the budget fire,
// and the request is NOT cancelled - it completes afterwards with the answer.

/// A transport whose `extract` sleeps `delay` before returning a fixture, and
/// records whether its work was cancelled. `Task.sleep` is the canary: it
/// throws `CancellationError` exactly when the surrounding task is cancelled,
/// which is precisely the "hard 3 s abort" the doc forbids.
private struct SlowGatewayTransport: GatewayExtractTransport {
    let delay: Duration
    let extraction: GatewayExtraction

    /// Written when the transport's `Task.sleep` throws a cancellation.
    let cancelled = CancellationFlag()

    func extract(_ request: GatewayExtractRequest) async throws -> GatewayExtraction {
        do {
            try await Task.sleep(for: delay)
        } catch {
            cancelled.set()
            throw error
        }
        return extraction
    }
}

/// A thread-safe flag a transport sets when it observes cancellation.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        defer { lock.unlock() }
        value = true
    }
}

@Suite("LLM gateway budget (P6.3)")
struct GatewayBudgetTests {

    private static func fixture() -> GatewayExtraction {
        GatewayExtraction(
            total: .init(value: Decimal(string: "71.02")!, confidence: 0.9),
            volume: .init(value: 42.30, confidence: 0.9),
            unitPrice: .init(value: Decimal(string: "1.679")!, confidence: 0.9),
            pipeline: "test"
        )
    }

    @Test("the budget expires against a slow transport and the request is NOT cancelled")
    func budgetExpiresButTheRequestCompletes() async throws {
        let transport = SlowGatewayTransport(
            delay: .seconds(5),
            extraction: Self.fixture()
        )
        let task = Task { try await transport.extract(.init(kind: "receipt", imageJPEG: Data())) }

        // A 1 s budget against a 5 s transport: the budget must fire...
        let outcome = try await GatewayWaiter.wait(task, timeout: .seconds(1))
        guard case .stillRunning(let running) = outcome else {
            Issue.record("the budget must fire before a 5 s answer")
            return
        }

        // ...the request must NOT have been cancelled - the wait is a UI wait,
        // never an abort...
        #expect(!transport.cancelled.isSet,
                "the budget must never cancel the request")

        // ...and the work finishes in the background with the answer.
        let extraction = try await running.value
        #expect(extraction == Self.fixture())
        #expect(!transport.cancelled.isSet)
    }

    @Test("an answer within the budget is delivered without firing the budget")
    func answerWithinBudgetIsDelivered() async throws {
        let transport = SlowGatewayTransport(
            delay: .milliseconds(50),
            extraction: Self.fixture()
        )
        let task = Task { try await transport.extract(.init(kind: "receipt", imageJPEG: Data())) }
        // A GENEROUS budget on purpose. What this test claims is "an answer that
        // arrives inside the budget is delivered and the budget never fires" -
        // the number is incidental, and `budgetIsThreeSeconds` pins the real 3 s
        // product rule on its own. With `.seconds(3)` here the assertion raced
        // the scheduler instead: `wait` runs the work and the deadline as two
        // detached tasks, and under a saturated machine (this suite's corpus
        // tests peg every core for ~29 s) a 50 ms sleep is not scheduled within
        // 3 s, so the deadline won and the test reported a budget failure that
        // was really machine load. It went red five times on 2026-08-29 and
        // twice consistently once the suite passed 950 tests.
        let outcome = try await GatewayWaiter.wait(task, timeout: .seconds(60))
        guard case .answered(let extraction) = outcome else {
            Issue.record("a 50 ms answer must arrive within the 3 s budget")
            return
        }
        #expect(extraction == Self.fixture())
    }

    @Test("a transport error within the budget propagates to the caller")
    func transportErrorWithinBudgetPropagates() async {
        let failing = FailingGatewayTransport()
        let task = Task { try await failing.extract(.init(kind: "receipt", imageJPEG: Data())) }
        await #expect(throws: SyncServerError.self) {
            // Generous for the same reason as above: the claim is that the
            // error propagates rather than being swallowed by the deadline.
            _ = try await GatewayWaiter.wait(task, timeout: .seconds(60))
        }
    }

    @Test("GatewayBudget.duration is the documented 3 seconds")
    func budgetIsThreeSeconds() {
        #expect(GatewayBudget.duration == .seconds(3))
    }
}

private struct FailingGatewayTransport: GatewayExtractTransport {
    func extract(_ request: GatewayExtractRequest) async throws -> GatewayExtraction {
        throw SyncServerError.tierRefused
    }
}

// MARK: - The mutation that proves the budget is a wait, not an abort

/// The exact break the doc warns against: cancelling the request when the
/// budget expires. This is what the implementation must NEVER do; the test
/// above fails against it. Kept as an explicit negative so a future reader
/// sees what the gate exists to prevent.
private enum BudgetAsCancellation {
    static func wait<Value: Sendable>(
        _ task: Task<Value, Error>,
        timeout: Duration
    ) async -> GatewayWait<Value> {
        // The bug: at budget expiry the request is cancelled.
        try? await Task.sleep(for: timeout)
        task.cancel()
        return .stillRunning(task)
    }
}

@Suite("LLM gateway budget anti-pattern (P6.3)")
struct GatewayBudgetAntiPatternTests {
    @Test("a budget implemented as a cancellation must FAIL the no-cancel test")
    func cancellationShapedBudgetIsDetected() async throws {
        let transport = SlowGatewayTransport(
            delay: .seconds(5),
            extraction: GatewayExtraction(pipeline: "x")
        )
        let task = Task { try await transport.extract(.init(kind: "receipt", imageJPEG: Data())) }
        let outcome = await BudgetAsCancellation.wait(task, timeout: .seconds(1))
        guard case .stillRunning(let running) = outcome else {
            Issue.record("unexpected")
            return
        }
        // The request was cancelled; awaiting it now throws.
        await #expect(throws: CancellationError.self) {
            _ = try await running.value
        }
    }
}
