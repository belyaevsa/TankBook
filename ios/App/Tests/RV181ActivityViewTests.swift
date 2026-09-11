import UIKit
import XCTest
@testable import Tankbook

/// RV.181 L1: the share seam's presentation and its outcome record.
///
/// The device report ("I picked a destination and nothing arrived", iOS 26,
/// iPhone 13) does not reproduce here, and these tests do not claim to. Two
/// contracts are pinned, and both are the ones the fix turns on. **The
/// presenter**: the activity must be presented by the key window's top-most
/// controller, never a host buried in the view tree that SwiftUI can tear down
/// while a destination's own UI is coming up. **The outcome**: a share that
/// failed at its destination must be distinguishable from one the user
/// cancelled; carrying only `completed` collapses them, which is why "nothing
/// arrived" could not be diagnosed from a device.
///
/// `UIActivityViewController` cannot exercise a real hand-off in a unit test,
/// so these pin the walk and the forwarding at the seam.
@MainActor
final class RV181ActivityViewTests: XCTestCase {

    /// A controller whose `presentedViewController` is stubbed, so a chain can
    /// be built without UIKit's real presentation machinery.
    private final class ChainController: UIViewController {
        var stubPresented: UIViewController?
        override var presentedViewController: UIViewController? { stubPresented }
    }

    /// A controller that records what was presented on it. The chain is built
    /// the same way as `ChainController`, so a test can assert WHICH controller
    /// in the stack received the activity.
    private final class PresenterSpy: UIViewController {
        var stubPresented: UIViewController?
        private(set) var presented: [UIViewController] = []
        override var presentedViewController: UIViewController? { stubPresented }

        override func present(_ viewControllerToPresent: UIViewController,
                              animated flag: Bool,
                              completion: (() -> Void)? = nil) {
            presented.append(viewControllerToPresent)
            stubPresented = viewControllerToPresent
            completion?()
        }
    }

    /// The required L1: `topMost` walks a presented chain to its top.
    func testTopMostWalksThePresentedChainToTheTop() {
        let root = ChainController()
        let first = ChainController()
        let second = ChainController()
        let top = ChainController()
        root.stubPresented = first
        first.stubPresented = second
        second.stubPresented = top

        XCTAssertTrue(SharePresenter.topMost(from: root) === top)
    }

    /// A root that presents nothing is its own top-most controller.
    func testTopMostOfAnUnpresentedRootIsTheRoot() {
        let root = ChainController()
        XCTAssertTrue(SharePresenter.topMost(from: root) === root)
    }

    /// The fix's core: the activity is presented on the TOP of the stack, not
    /// the root - the shape that keeps the destination's UI alive.
    func testPresentPresentsFromTheTopMostController() {
        let root = PresenterSpy()
        let middle = PresenterSpy()
        let top = PresenterSpy()
        root.stubPresented = middle
        middle.stubPresented = top

        let activity = SharePresenter.present(items: ["x"], from: root) { _ in }

        XCTAssertNotNil(activity)
        XCTAssertTrue(root.presented.isEmpty, "the root must not present over its own sheet")
        XCTAssertTrue(middle.presented.isEmpty, "the middle controller must not present over its own sheet")
        XCTAssertEqual(top.presented.count, 1, "the top-most controller is the presenter")
        XCTAssertTrue(top.presented.first === activity)
    }

    /// Presenting on a controller that is already showing the activity would
    /// throw; the seam returns nil instead.
    func testPresentDoesNothingWhenTheTopMostAlreadyPresentsTheActivity() {
        let root = PresenterSpy()
        let first = SharePresenter.present(items: ["x"], from: root) { _ in }
        XCTAssertNotNil(first)

        let second = SharePresenter.present(items: ["y"], from: root) { _ in }
        XCTAssertNil(second, "a second presentation over the live activity must be refused")
        XCTAssertEqual(root.presented.count, 1)
    }

    /// A share that ran and then failed is reported as a FAILURE, carrying the
    /// activity and the error's domain and code - the record the device report
    /// needed and did not have.
    func testAFailedShareIsDistinguishableFromACancel() {
        var outcomes: [ShareOutcome] = []
        let failed = SharePresenter.makeActivity(items: ["a"]) { outcomes.append($0) }
        failed.completionWithItemsHandler?(.mail, false, nil, NSError(domain: "TestDomain", code: 42))
        let cancelled = SharePresenter.makeActivity(items: ["b"]) { outcomes.append($0) }
        cancelled.completionWithItemsHandler?(nil, false, nil, nil)

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
        let activity = SharePresenter.makeActivity(items: ["a receipt for 42 litres"]) {
            outcomes.append($0)
        }
        activity.completionWithItemsHandler?(
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
        let activity = SharePresenter.makeActivity(items: ["x"]) { outcomes.append($0) }
        activity.completionWithItemsHandler?(.copyToPasteboard, true, nil, nil)

        XCTAssertEqual(outcomes.map(\.logOutcome), ["completed"])
        XCTAssertNil(outcomes[0].errorDomain)
    }

    /// The callback fires at most once even if UIKit somehow reports twice - a
    /// late second call must not double-log a share.
    func testCompletionFiresAtMostOncePerShare() {
        var count = 0
        let activity = SharePresenter.makeActivity(items: ["x"]) { _ in count += 1 }
        activity.completionWithItemsHandler?(nil, true, nil, nil)
        activity.completionWithItemsHandler?(nil, false, nil, nil)
        activity.completionWithItemsHandler?(nil, true, nil, nil)

        XCTAssertEqual(count, 1)
    }
}
