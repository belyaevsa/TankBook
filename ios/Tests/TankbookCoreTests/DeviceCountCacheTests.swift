import Foundation
import Testing
@testable import TankbookCore

// RV.6 - the Settings account card's device count ("Synced just now · N
// devices", docs/JOURNEYS.md J11a) must not ride on every surface refresh.
// `AppSync.refresh()` used to re-fetch it on every call while `SettingsView`'s
// `.task` re-runs on every appearance, so a "check my devices" round trip
// (Settings -> Account & devices -> pop back) fetched the count again on the
// pop-back - gear -> account -> back -> account was four GETs with no sync
// cycle involved. The count changes on EVENTS (sign-in, sign-out, a revoke, an
// account delete), never on a clock, so this cache is reused until an event
// clears it. The mutation guard is the fetch COUNT: an unconditional re-fetch
// (the pre-RV.6 shape) makes the round-trip test below go red.
@Suite("Device-count fetch reuse (RV.6)")
struct DeviceCountCacheTests {

    /// The refresh glue `AppSync` runs on each surface appearance, mirrored
    /// here so the tests can count the fetches a navigation actually triggers.
    /// `.fetch` is the only action that issues a request.
    private struct Surface {
        var cache = DeviceCountCache()
        var fetches = 0

        mutating func refresh(signedIn: Bool, serverCount: Int?) {
            switch cache.refreshAction(signedIn: signedIn) {
            case .reuse, .clear:
                break
            case .fetch:
                fetches += 1
                cache.record(serverCount)
            }
        }
    }

    // MARK: - The round trip fetches once (the headline assertion)

    @Test("Settings -> Account & devices -> pop fetches the count exactly once")
    func roundTripFetchesTheCountExactlyOnce() {
        var surface = Surface()

        // Settings appears: the count is unknown, so it is fetched.
        surface.refresh(signedIn: true, serverCount: 3)
        // Push Account & devices (its own list load is a separate client - the
        // count path is untouched) and pop back: Settings' `.task` re-runs.
        surface.refresh(signedIn: true, serverCount: 3)
        // A second gear -> account -> back visit must not fetch again either.
        surface.refresh(signedIn: true, serverCount: 3)

        #expect(surface.fetches == 1,
                "the count must be fetched once and reused on every later Settings appearance")
        #expect(surface.cache.count == 3)
    }

    @Test("a cached count is returned without consulting the fetch seam")
    func aCachedCountIsReused() {
        var cache = DeviceCountCache()
        #expect(cache.refreshAction(signedIn: true) == .fetch)
        cache.record(2)
        #expect(cache.count == 2)
        #expect(cache.refreshAction(signedIn: true) == .reuse,
                "a signed-in refresh with a cached count must reuse it, never fetch")
    }

    // MARK: - Invalidation events

    @Test("a guest refresh forgets the count (sign-out, account delete)")
    func guestRefreshForgetsTheCount() {
        var cache = DeviceCountCache()
        cache.record(2)
        #expect(cache.refreshAction(signedIn: false) == .clear)
        #expect(cache.count == nil,
                "the count must not outlive the account that produced it")
        // The next signed-in refresh (a fresh sign-in) fetches again.
        #expect(cache.refreshAction(signedIn: true) == .fetch)
    }

    @Test("sign-out then sign-in shows the new account's count, never the stale one")
    func signOutThenSignInShowsTheNewCount() {
        var surface = Surface()
        surface.refresh(signedIn: true, serverCount: 2)
        #expect(surface.cache.count == 2)

        // Sign out: Settings re-appears as a guest and the count is forgotten.
        surface.refresh(signedIn: false, serverCount: nil)
        #expect(surface.cache.count == nil)

        // Sign in to an account that has five devices: the read must fetch
        // again and show five - a reused "2" would be the stale-cache bug.
        surface.refresh(signedIn: true, serverCount: 5)
        #expect(surface.fetches == 2, "the sign-in must trigger one new fetch")
        #expect(surface.cache.count == 5,
                "the card must show the new account's count, never the old account's")
    }

    @Test("invalidating after a revoke makes the next read fetch the server truth")
    func revokeInvalidationFetchesTheServerTruth() {
        var surface = Surface()
        surface.refresh(signedIn: true, serverCount: 2)

        // The revoke (on the Account & devices screen) clears the cache.
        surface.cache.invalidate()
        #expect(surface.cache.count == nil)

        // Pop back to Settings: the read fetches again and shows the server's
        // current list.
        surface.refresh(signedIn: true, serverCount: 1)
        #expect(surface.cache.count == 1)
        #expect(surface.fetches == 2)
    }

    @Test("without an event a changed server list stays cached until the next event")
    func noEventMeansTheCachedCountStands() {
        var cache = DeviceCountCache()
        cache.record(2)
        // The server now returns 1 (a revoke happened on ANOTHER device this
        // phone cannot see): the cache stands until a local event or the
        // Account & devices screen (which always reads the list) refreshes it.
        #expect(cache.refreshAction(signedIn: true) == .reuse)
        #expect(cache.count == 2)
    }

    // MARK: - Fetch failure

    @Test("a failed fetch stays unknown and the next appearance retries")
    func failedFetchRetriesOnTheNextAppearance() {
        var surface = Surface()
        // First appearance offline: the fetch fails, the count stays unknown.
        surface.refresh(signedIn: true, serverCount: nil)
        #expect(surface.cache.count == nil)
        #expect(surface.fetches == 1)

        // Back online, the next appearance retries - never a stale value, never
        // a value invented while the fetch was failing.
        surface.refresh(signedIn: true, serverCount: 3)
        #expect(surface.fetches == 2)
        #expect(surface.cache.count == 3)
    }
}
