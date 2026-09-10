import UIKit
import XCTest
@testable import Tankbook

/// RV.181 L1: the share seam's presentation latch and its outcome record.
///
/// Two contracts are pinned here, and the second is the one the device report
/// argues for. **The latch**: SwiftUI calls `updateUIViewController` repeatedly
/// and presenting twice throws, so the activity is presented once - but only a
/// presentation UIKit ACCEPTED counts, or a dropped attempt leaves a permanent
/// blank host sheet with no retry. **The outcome**: a share that failed at its
/// destination must be distinguishable from one the user cancelled; carrying
/// only `completed` collapses them, which is why "nothing arrived" could not be
/// diagnosed from a device.
///
/// `UIActivityViewController` cannot exercise the hand-off in a unit test, so
/// these pin the guards and the forwarding at the seam.
@MainActor
final class RV181ActivityViewTests: XCTestCase {

    /// A host that models UIKit's two answers to `present`: accepted (the
    /// completion runs, and a presented controller is now in place) or dropped
    /// mid-transition (no completion, nothing presented). A spy that only
    /// counts calls cannot express the second, which is the case the latch is
    /// about.
    private final class SpyHost: UIViewController {
        private(set) var presentCount = 0
        var acceptsPresentation = true
        private var stubPresented: UIViewController?

        override var presentedViewController: UIViewController? { stubPresented }

        override func present(_ viewControllerToPresent: UIViewController,
                              animated flag: Bool,
                              completion: (() -> Void)? = nil) {
            presentCount += 1
            guard acceptsPresentation else { return }
            stubPresented = viewControllerToPresent
            completion?()
        }
    }

    private func makeHostInWindow() -> (SpyHost, UIWindow) {
        let host = SpyHost()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = host
        // `view.window` is only set once the window is on screen; the presenter
        // guard under test keys off exactly that.
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return (host, window)
    }

    /// `updateUIViewController` calls this repeatedly; the second call must not
    /// present again.
    func testPresentingTwicePresentsExactlyOnce() {
        let (host, window) = makeHostInWindow()
        defer { window.isHidden = true }
        let coordinator = ActivityView(items: ["x"]).makeCoordinator()

        coordinator.presentIfNeeded(from: host)
        coordinator.presentIfNeeded(from: host)

        XCTAssertTrue(coordinator.hasPresented)
        XCTAssertEqual(host.presentCount, 1, "the activity must be presented exactly once")
    }

    /// The latch belongs AFTER the presentation, not before it: a presentation
    /// UIKit dropped must be retried by the next `updateUIViewController`, or
    /// the user is left holding an empty host sheet forever.
    func testADroppedPresentationIsRetried() {
        let (host, window) = makeHostInWindow()
        defer { window.isHidden = true }
        host.acceptsPresentation = false
        let coordinator = ActivityView(items: ["x"]).makeCoordinator()

        coordinator.presentIfNeeded(from: host)
        XCTAssertFalse(coordinator.hasPresented,
                       "a presentation UIKit did not accept must not latch")

        host.acceptsPresentation = true
        coordinator.presentIfNeeded(from: host)

        XCTAssertTrue(coordinator.hasPresented)
        XCTAssertEqual(host.presentCount, 2, "the dropped attempt must be retried, once")
    }

    /// The retry is safe because it also checks what the host is already
    /// presenting: a latch that had not yet been written must never produce a
    /// second `present` over a live one, which throws.
    func testNoSecondPresentWhileTheHostAlreadyPresents() {
        let (host, window) = makeHostInWindow()
        defer { window.isHidden = true }
        let coordinator = ActivityView(items: ["x"]).makeCoordinator()

        coordinator.presentIfNeeded(from: host)
        coordinator.presentIfNeeded(from: host)

        XCTAssertEqual(host.presentCount, 1)
    }

    /// A share that ran and then failed is reported as a FAILURE, carrying the
    /// activity and the error's domain and code - the record the device report
    /// needed and did not have.
    func testAFailedShareIsDistinguishableFromACancel() {
        var outcomes: [ShareOutcome] = []
        let failed = ActivityView(items: ["a"]) { outcomes.append($0) }.makeCoordinator()
        failed.activity.completionWithItemsHandler?(
            .mail, false, nil,
            NSError(domain: "TestDomain", code: 42))
        let cancelled = ActivityView(items: ["b"]) { outcomes.append($0) }.makeCoordinator()
        cancelled.activity.completionWithItemsHandler?(nil, false, nil, nil)

        XCTAssertEqual(outcomes.map(\.logOutcome), ["failed", "cancelled"],
                       "a failed share must not be logged as a cancel")
        XCTAssertTrue(outcomes[0].failedAtDestination)
        XCTAssertEqual(outcomes[0].activityType, UIActivity.ActivityType.mail.rawValue)
        XCTAssertEqual(outcomes[0].errorDomain, "TestDomain")
        XCTAssertEqual(outcomes[0].errorCode, 42)
        XCTAssertFalse(outcomes[1].failedAtDestination)
    }

    /// The failure detail is shape only (hard rule 12): an activity identifier
    /// and an error domain and code, never anything that was shared.
    func testTheFailureReasonCarriesOnlyShape() {
        var outcomes: [ShareOutcome] = []
        let coordinator = ActivityView(items: ["a receipt for 42 litres"]) {
            outcomes.append($0)
        }.makeCoordinator()
        coordinator.activity.completionWithItemsHandler?(
            .airDrop, false, nil, NSError(domain: "TestDomain", code: 7))

        let reason = try? XCTUnwrap(outcomes.first).failureReason
        XCTAssertEqual(reason, "activity=\(UIActivity.ActivityType.airDrop.rawValue) "
                       + "error=TestDomain#7")
        XCTAssertFalse(reason?.contains("receipt") ?? true)
        XCTAssertFalse(reason?.contains("42 litres") ?? true)
    }

    /// A completed share carries `completed` and no error.
    func testACompletedShareIsReportedCompleted() {
        var outcomes: [ShareOutcome] = []
        let coordinator = ActivityView(items: ["x"]) { outcomes.append($0) }.makeCoordinator()
        coordinator.activity.completionWithItemsHandler?(.copyToPasteboard, true, nil, nil)

        XCTAssertEqual(outcomes.map(\.logOutcome), ["completed"])
        XCTAssertNil(outcomes[0].errorDomain)
    }

    /// Two shares in a row each yield exactly one callback - the guard against
    /// re-presenting (and re-completing) on every SwiftUI update.
    func testTwoSharesInARowEachYieldOneCallback() {
        var outcomes: [ShareOutcome] = []
        for _ in 0..<2 {
            let (host, window) = makeHostInWindow()
            defer { window.isHidden = true }
            let coordinator = ActivityView(items: ["x"]) { outcomes.append($0) }.makeCoordinator()

            coordinator.presentIfNeeded(from: host)
            coordinator.presentIfNeeded(from: host)
            XCTAssertEqual(host.presentCount, 1)

            coordinator.activity.completionWithItemsHandler?(nil, true, nil, nil)
            // A late second callback from the system must not double-fire.
            coordinator.activity.completionWithItemsHandler?(nil, true, nil, nil)
        }
        XCTAssertEqual(outcomes.map(\.completed), [true, true],
                       "each share must yield exactly one callback")
    }

    /// The callback fires at most once even if the system somehow reports twice;
    /// the sheet dismissal rides the same guard.
    func testCompletionFiresAtMostOncePerShare() {
        var count = 0
        let coordinator = ActivityView(items: ["x"]) { _ in count += 1 }.makeCoordinator()
        coordinator.activity.completionWithItemsHandler?(nil, true, nil, nil)
        coordinator.activity.completionWithItemsHandler?(nil, false, nil, nil)
        coordinator.activity.completionWithItemsHandler?(nil, true, nil, nil)

        XCTAssertTrue(coordinator.hasFinished)
        XCTAssertEqual(count, 1)
    }
}
