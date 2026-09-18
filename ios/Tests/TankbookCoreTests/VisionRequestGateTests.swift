import Foundation
import Testing
@testable import TankbookCore

// The L1 for the Vision request gate. The gate's contract is a pure decision:
// it admits at most `limit` bodies concurrently, it releases the slot on both
// the success and the throwing path, and a caller waiting for a slot SUSPENDS
// rather than blocks. A gate that leaked a slot on an error would deadlock the
// suite the first time an OCR call fails, so the throw path is asserted
// directly rather than trusted; a gate that blocked its waiters would hang the
// suite on macOS 27 (docs/TESTING.md -> "Vision OCR concurrency ceiling"), so
// the suspension is asserted by parking more waiters than the cooperative pool
// has threads and checking the bodies still complete.

@Suite("Vision request gate (RV.52)")
struct VisionRequestGateTests {

    private enum TestError: Error { case boom }

    /// Tracks the peak number of bodies executing at once, across threads.
    private final class Peak: @unchecked Sendable {
        private let lock = NSLock()
        private var current = 0
        private var max = 0

        func enter() {
            lock.lock()
            current += 1
            max = Swift.max(max, current)
            lock.unlock()
        }

        func exit() {
            lock.lock()
            current -= 1
            lock.unlock()
        }

        var peak: Int {
            lock.lock()
            defer { lock.unlock() }
            return max
        }
    }

    /// Runs `count` concurrent callers and returns the peak body concurrency.
    private func peakConcurrency(gate: VisionRequestGate, count: Int) async -> Int {
        let peak = Peak()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<count {
                group.addTask {
                    try? await gate.withSlot {
                        peak.enter()
                        Thread.sleep(forTimeInterval: 0.1)
                        peak.exit()
                    }
                }
            }
        }
        return peak.peak
    }

    @Test("the gate admits at most its limit concurrently, and not just one")
    func gateAdmitsAtMostItsLimitConcurrently() async {
        let peak = await peakConcurrency(gate: VisionRequestGate(limit: 4), count: 40)
        // 40 callers would run ~12+ at once unconstrained on this machine; the
        // gate must hold them to 4, and must actually use all 4 (a strict-serial
        // gate that admitted one at a time would also pass "<=" but fail "==").
        #expect(peak <= 4)
        #expect(peak == 4)
    }

    @Test("the gate releases its slot when the body throws")
    func gateReleasesItsSlotWhenTheBodyThrows() async {
        let gate = VisionRequestGate(limit: 3)
        do {
            _ = try await gate.withSlot { () -> Int in throw TestError.boom }
        } catch {
            // expected
        }
        // If the throw leaked a slot, the gate would now admit only 2; the
        // workload below must still reach the full limit of 3.
        #expect(await peakConcurrency(gate: gate, count: 30) == 3)
    }

    @Test("the gate returns the body's value")
    func gateReturnsTheBodysValue() async throws {
        let gate = VisionRequestGate(limit: 2)
        let value = try await gate.withSlot { 42 }
        #expect(value == 42)
    }

    @Test("waiters suspend: a body that needs the cooperative pool still finishes under a full queue of waiters",
          .timeLimit(.minutes(1)))
    func waitersSuspendRatherThanBlock() async {
        // Models Vision on macOS 27: the body, on its dispatch thread, cannot
        // finish until a Task runs on the cooperative pool. With a blocking
        // wait, `waiters` callers parked on a semaphore occupy every cooperative
        // thread, that Task never runs, and the run hangs (the time limit is
        // the failure signal). A suspending wait holds no thread, so the Task
        // runs and every caller finishes. The count is well above any
        // machine's core count.
        let gate = VisionRequestGate(limit: 1)
        let waiters = 64
        let completed = Peak()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<waiters {
                group.addTask {
                    try? await gate.withSlot {
                        let poolTurn = DispatchSemaphore(value: 0)
                        Task { poolTurn.signal() }
                        poolTurn.wait()
                        completed.enter()
                    }
                }
            }
        }
        #expect(completed.peak == waiters)
    }
}
