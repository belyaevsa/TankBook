import Foundation
import Testing
@testable import TankbookCore

// RV.22 - the sync state chip beside the Settings gear (docs/SYNC.md -> "The
// sync state chip"). The chip is presentation over the SAME state model the
// Settings surface uses, so the mapping - `SyncChipState`, `chipState(_:)` and
// `showsChipWarnDot(_:)` - lives here in core and tests at L1, exactly like
// `SyncSurface.status(_:)`. `SyncSurfaceTests` is the model this follows.
//
// Each test pins WHICH state came out, not that "a chip appeared" - the vacuous
// assertion the precedence table exists to make impossible. The load-bearing
// behaviours:
//   - attention (deviceRevoked / authExpired / quotaFull) outranks signedOut,
//     because an expired session clears the Keychain (isSignedIn reads false)
//     but is still an account issue the user must act on;
//   - offline and 5xx are NOT states (never a promotion to warning);
//   - the warn dot is derived from flaggedCount, never a sixth state.

@Suite("Sync state chip (RV.22)")
struct SyncChipTests {

    // MARK: - Each condition resolves to its state

    @Test("not signed in resolves to signedOut")
    func signedOutResolves() {
        #expect(SyncSurface.chipState(SyncSurfaceState(isSignedIn: false)) == .signedOut)
    }

    @Test("deviceRevoked resolves to deviceRevoked")
    func deviceRevokedResolves() {
        #expect(SyncSurface.chipState(
            SyncSurfaceState(isSignedIn: true, deviceRevoked: true)) == .deviceRevoked)
    }

    @Test("authExpired resolves to authExpired")
    func authExpiredResolves() {
        #expect(SyncSurface.chipState(
            SyncSurfaceState(isSignedIn: true, authExpired: true)) == .authExpired)
    }

    @Test("quota at 95 resolves to quotaFull, at 94 it does not")
    func quotaBoundary() {
        #expect(SyncSurface.chipState(
            SyncSurfaceState(isSignedIn: true, quotaUsedPercent: 95)) == .quotaFull)
        #expect(SyncSurface.chipState(
            SyncSurfaceState(isSignedIn: true, quotaUsedPercent: 94)) == .synced)
    }

    @Test("isSyncing resolves to syncing")
    func syncingResolves() {
        #expect(SyncSurface.chipState(
            SyncSurfaceState(isSignedIn: true, isSyncing: true)) == .syncing)
    }

    @Test("a dirty queue resolves to waiting")
    func waitingResolves() {
        #expect(SyncSurface.chipState(
            SyncSurfaceState(isSignedIn: true, dirtyCount: 5)) == .waiting)
    }

    @Test("a clean signed-in device resolves to synced")
    func syncedResolves() {
        #expect(SyncSurface.chipState(
            SyncSurfaceState(isSignedIn: true)) == .synced)
    }

    // MARK: - Precedence (first match wins)

    @Test("authExpired outranks signedOut even though the session is cleared")
    func authExpiredOutranksSignedOut() {
        // An expired session clears the Keychain, so isSignedIn reads false -
        // but the chip must still show "Sign in again", never "Not signed in".
        let state = SyncSurfaceState(isSignedIn: false, authExpired: true)
        #expect(SyncSurface.chipState(state) == .authExpired)
    }

    @Test("authExpired outranks a dirty queue")
    func authExpiredOutranksDirtyCount() {
        let state = SyncSurfaceState(isSignedIn: true, dirtyCount: 5, authExpired: true)
        #expect(SyncSurface.chipState(state) == .authExpired)
    }

    @Test("deviceRevoked outranks an in-flight cycle")
    func deviceRevokedOutranksSyncing() {
        let state = SyncSurfaceState(isSignedIn: true, deviceRevoked: true, isSyncing: true)
        #expect(SyncSurface.chipState(state) == .deviceRevoked)
    }

    @Test("quotaFull outranks a dirty queue")
    func quotaOutranksDirtyCount() {
        let state = SyncSurfaceState(isSignedIn: true, dirtyCount: 5, quotaUsedPercent: 96)
        #expect(SyncSurface.chipState(state) == .quotaFull)
    }

    @Test("syncing outranks a dirty queue")
    func syncingOutranksDirtyCount() {
        let state = SyncSurfaceState(isSignedIn: true, dirtyCount: 5, isSyncing: true)
        #expect(SyncSurface.chipState(state) == .syncing)
    }

    // MARK: - Offline and 5xx are NOT states

    @Test("offline with a queue is waiting, never a distinct state")
    func offlineWithQueueIsWaiting() {
        #expect(SyncSurface.chipState(
            SyncSurfaceState(isSignedIn: true, dirtyCount: 5, offline: true)) == .waiting)
    }

    @Test("offline with nothing to push is synced reassurance")
    func offlineNoQueueIsSynced() {
        #expect(SyncSurface.chipState(
            SyncSurfaceState(isSignedIn: true, offline: true)) == .synced)
    }

    @Test("a 5xx with a queue is waiting, never a promotion to warning")
    func serverUnavailableWithQueueIsWaiting() {
        #expect(SyncSurface.chipState(
            SyncSurfaceState(isSignedIn: true, dirtyCount: 5, serverUnavailable: true)) == .waiting)
    }

    @Test("a 5xx with nothing to push is synced, never a promotion to warning")
    func serverUnavailableNoQueueIsSynced() {
        #expect(SyncSurface.chipState(
            SyncSurfaceState(isSignedIn: true, serverUnavailable: true)) == .synced)
    }

    // MARK: - isAttention

    @Test("only the three transport-issue states are attention")
    func attentionIsExactlyTheTransportIssues() {
        #expect(SyncChipState.deviceRevoked.isAttention)
        #expect(SyncChipState.authExpired.isAttention)
        #expect(SyncChipState.quotaFull.isAttention)
        #expect(!SyncChipState.signedOut.isAttention)
        #expect(!SyncChipState.syncing.isAttention)
        #expect(!SyncChipState.waiting.isAttention)
        #expect(!SyncChipState.synced.isAttention)
    }

    // MARK: - The warn dot is derived, never a sixth state

    @Test("the warn dot rides the chip only when entries are flagged")
    func warnDotFollowsFlaggedCount() {
        #expect(SyncSurface.showsChipWarnDot(
            SyncSurfaceState(isSignedIn: true, flaggedCount: 2)))
        #expect(!SyncSurface.showsChipWarnDot(
            SyncSurfaceState(isSignedIn: true, flaggedCount: 0)))
    }

    @Test("the warn dot rides whatever state is showing, without changing it")
    func warnDotDoesNotChangeState() {
        // A flagged queue is still "waiting", not a sixth "conflicts" state.
        let state = SyncSurfaceState(isSignedIn: true, dirtyCount: 5, flaggedCount: 2)
        #expect(SyncSurface.chipState(state) == .waiting)
        #expect(SyncSurface.showsChipWarnDot(state))
    }
}
