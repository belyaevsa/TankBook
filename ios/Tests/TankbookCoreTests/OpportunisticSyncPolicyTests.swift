import Foundation
import Testing
@testable import TankbookCore

// RV.18 - the minimum interval between opportunistic sync cycles. The pure
// decision (docs/TESTING.md L1): a burst of `.active` transitions - the launch
// double-fire, a permission-alert dismissal, the Photos picker - is one cycle,
// not one each. The gate is a function of the last-cycle timestamp and `now`,
// never `Date()` read at a call site, and it gates ONLY the opportunistic door.
@Suite("Opportunistic sync cadence (RV.18)")
struct OpportunisticSyncPolicyTests {

    @Test func firstCycleAlwaysRuns() {
        // nil = no cycle yet, so the launch cycle must run (a fresh install
        // with nothing measured can never be gated).
        #expect(OpportunisticSyncPolicy.shouldRun(lastOpportunisticSyncAt: nil,
                                                  now: Date(timeIntervalSinceReferenceDate: 0)))
    }

    @Test func aCycleWithinTheIntervalIsGated() {
        let base = Date(timeIntervalSinceReferenceDate: 1_000_000)
        // 0.6 s later - the measured launch double-fire gap - must be gated.
        let burst = base.addingTimeInterval(0.6)
        #expect(!OpportunisticSyncPolicy.shouldRun(lastOpportunisticSyncAt: base, now: burst),
                "the launch double-fire (two cycles under a second apart) must collapse to one")
    }

    @Test func aCycleAfterTheIntervalRuns() {
        let base = Date(timeIntervalSinceReferenceDate: 1_000_000)
        // A genuine foreground after a long background must sync, however long
        // ago the last cycle was.
        let later = base.addingTimeInterval(OpportunisticSyncPolicy.minimumInterval + 1)
        #expect(OpportunisticSyncPolicy.shouldRun(lastOpportunisticSyncAt: base, now: later))
    }

    @Test func theIntervalIsTheBoundaryExactly() {
        let base = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let exactly = base.addingTimeInterval(OpportunisticSyncPolicy.minimumInterval)
        // At exactly the interval the next cycle may run (the boundary is
        // inclusive, so a device that returned right on the line is not held).
        #expect(OpportunisticSyncPolicy.shouldRun(lastOpportunisticSyncAt: base, now: exactly))
        let justUnder = base.addingTimeInterval(OpportunisticSyncPolicy.minimumInterval - 0.001)
        #expect(!OpportunisticSyncPolicy.shouldRun(lastOpportunisticSyncAt: base, now: justUnder))
    }
}
