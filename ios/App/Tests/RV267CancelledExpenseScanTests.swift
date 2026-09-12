import Foundation
import UIKit
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.267 - the expense sibling of RV.245. The expense scan stages only memory
/// (`ExpenseEntrySession.pendingCapture` / `pendingPrefill` / `pendingPreset`)
/// and its read runs deferred, so a sheet dismissed WITHOUT a save leaves the
/// abandoned scan in the long-lived session and the NEXT open consumes it.
///
/// The cleanup is one call - `ExpenseEntryView.discardStagedScan` - that the
/// sheet's single dismissal path (`onDisappear`, shared by the X, the
/// swipe-down and any discard prompt) invokes unless a save set `didSave`. These
/// tests drive the REAL session and the REAL seam: the oracle is the session's
/// own state plus the read's routing, never a UI artefact.
@MainActor
final class RV267CancelledExpenseScanTests: XCTestCase {

    /// A one-shot async gate, so a test can hold the read open while it cancels
    /// or saves and then release it - deterministic, no timing race.
    @MainActor
    private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isOpen = false

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { self.continuation = $0 }
        }

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Fixtures

    /// A tiny renderable frame - a captured photo's stand-in.
    private func photoImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 120))
        return renderer.image { context in
            UIColor.systemGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
        }
    }

    private func outcome(category: ExpenseCategory) -> ExpenseScanOutcome {
        let capture = ExpenseScanCapture(image: photoImage(), extraction: FuelExtraction(),
                                         ocrLines: [])
        return ExpenseScanOutcome(
            prefill: ExpensePrefill(total: Decimal(string: "12.40")!, currency: .eur),
            preset: category,
            capture: capture,
            recognition: ExpenseRecognition(
                category: .init(value: category, confidence: 0.8)))
    }

    // MARK: - Cancel

    /// L1, fails before this row: a staged scan that is cancelled must clear the
    /// session and cancel the read. A read that lands AFTER the cancel must not
    /// repopulate the session - `DeferredRecognition.cancel()` bumps the
    /// generation, so `ExpenseEntrySession.start`'s completion closure drops
    /// itself before `onAnswer` runs. `scanRevision` is the second witness: a
    /// cancelled read must not nudge the form it would have filled.
    func testCancellingAStagedScanClearsTheSessionAndCancelsTheRead() async throws {
        let session = ExpenseEntrySession()
        let gate = Gate()

        session.start(
            image: photoImage(),
            work: { await gate.wait(); return self.outcome(category: .parking) },
            onAnswer: { outcome in
                session.pendingPrefill = outcome.prefill
                session.pendingPreset = outcome.preset
                session.pendingCapture = outcome.capture
            },
            onSavedAnswer: { _, _ in XCTFail("a cancelled read must not route to the inbox") })

        // The scan stages its photograph before the read resolves (RV.243).
        XCTAssertNotNil(session.pendingCapture, "the scan must stage its photograph at start")

        ExpenseEntryView.discardStagedScan(session)

        XCTAssertNil(session.pendingPrefill, "a cancel must clear the staged pre-fill")
        XCTAssertNil(session.pendingPreset, "a cancel must clear the staged category")
        XCTAssertNil(session.pendingCapture, "a cancel must clear the staged photograph")

        // The read lands after the cancel: it must not repopulate the session
        // the next `load` would read.
        gate.open()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertNil(session.pendingPrefill, "a read landing after the cancel must not repopulate")
        XCTAssertNil(session.pendingPreset, "a read landing after the cancel must not repopulate")
        XCTAssertNil(session.pendingCapture, "a read landing after the cancel must not repopulate")
        XCTAssertEqual(session.scanRevision, 0,
                       "a cancelled read must not nudge the form it would have filled")
    }

    // MARK: - Save

    /// L1: a save is not a cancel. The session leaves nothing pending for the
    /// next open, and the read still in flight reaches the inbox rather than
    /// being dropped by a discard - the didSave guard's job.
    func testASavedExpenseLeavesNothingPendingAndItsLateReadReachesTheInbox() async throws {
        let session = ExpenseEntrySession()
        let gate = Gate()
        var lateEntryID: UUID?
        let entryID = UUID.v7()

        session.start(
            image: photoImage(),
            work: { await gate.wait(); return self.outcome(category: .parking) },
            onAnswer: { _ in XCTFail("a read after the save must not fill the form") },
            onSavedAnswer: { _, id in lateEntryID = id })

        // The load consumes the staged hand-off; the save happens before the read.
        _ = session.consumePendingCapture()
        session.markSaved(entryID: entryID)

        gate.open()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(lateEntryID, entryID,
                       "a saved expense's late read must still reach the inbox")
        XCTAssertNil(session.pendingPrefill, "a saved expense must leave nothing pending")
        XCTAssertNil(session.pendingPreset)
        XCTAssertNil(session.pendingCapture)
    }

    // MARK: - Wiring

    /// RV.267: the sheet's one dismissal path owns the discard and a save
    /// disarms it. A source scan is the only check that sees the wiring - the
    /// behavioural tests above prove the cleanup works, not that the view calls
    /// it, and the X / swipe-down / discard prompt all funnel through
    /// `onDisappear`.
    func testTheDismissalPathDiscardsTheScanAndASaveDisarmsIt() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // App/Tests
            .deletingLastPathComponent() // App
            .deletingLastPathComponent() // ios
            .appendingPathComponent("App/Sources/ServiceEntry/ExpenseEntryView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains(".onDisappear"),
                      "the sheet's single dismissal path must be onDisappear")
        XCTAssertTrue(source.contains("Self.discardStagedScan(expenseSession)"),
                      "the dismissal path must call the one discard seam")
        XCTAssertTrue(source.contains("guard !didSave"),
                      "a save must disarm the discard")
        XCTAssertTrue(source.contains("didSave = true"),
                      "the save path must set didSave")
    }
}
