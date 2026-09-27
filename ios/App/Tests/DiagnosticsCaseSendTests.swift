#if EXPERIMENTS
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.313: a diagnostics send runs on iOS's background grace time. When the
/// grace runs out before the upload finishes, the send is cancelled and the
/// sheet says so - it never dies silently with the suspended process.
@MainActor
final class DiagnosticsCaseSendTests: XCTestCase {
    /// A grace whose expiry the test fires by hand.
    private final class ManualGrace: BackgroundGrace {
        var expire: (@MainActor () -> Void)?
        var began = 0
        var ended: [Int] = []
        func begin(name: String, onExpire: @escaping @MainActor () -> Void) -> Int {
            began += 1
            expire = onExpire
            return 7
        }
        func end(_ token: Int) { ended.append(token) }
    }

    func testAnUploadCutByTheEndOfBackgroundTimeSaysItWasInterrupted() async {
        let grace = ManualGrace()
        let model = DiagnosticsCaseModel(background: grace) { _, _ in
            // An upload that only ends when it is cancelled.
            while true { try await Task.sleep(for: .milliseconds(20)) }
        }
        let submit = Task { await model.submit() }
        while grace.expire == nil { await Task.yield() }
        grace.expire?()
        await submit.value
        XCTAssertEqual(model.state, .failed(.interrupted))
        XCTAssertEqual(grace.ended, [7], "the grace is ended exactly once")
    }

    func testASendThatFinishesEndsItsGraceAndShowsTheId() async {
        let grace = ManualGrace()
        let receipt = DebugCaseReceipt(caseId: "K7Q2M-9XDRA", expiresAt: Date(timeIntervalSince1970: 0))
        let model = DiagnosticsCaseModel(background: grace) { _, _ in receipt }
        await model.submit()
        XCTAssertEqual(model.state, .sent(receipt))
        XCTAssertEqual(grace.began, 1)
        XCTAssertEqual(grace.ended, [7])
    }
}
#endif
