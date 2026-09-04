import Foundation
import Testing
@testable import TankbookCore

// RV.54 (product owner, 2026-09-04, decided - implemented, not relitigated):
// the Settings account card's device count counts LIVE devices only. The
// number answers "how many devices can reach my data"; a revoked device's next
// pull gets 410, so it cannot reach the data and does not count. The revoked
// rows stay in the LIST (marked, never omitted - the history is the point of
// showing them), so the counting excludes them and the list never does.
//
// `GET /account/devices` is unchanged: the server keeps returning revoked rows
// marked. This is a client-side counting decision, and the one place it lives
// in core is `liveDeviceCount`; `AppSync.refresh` records it into the
// `DeviceCountCache` (RV.6), which is why the value can finally move on a
// revoke - the acceptance test RV.6 demanded and could not write while the
// count included revoked rows.
//
// The vacuous traps this file names and avoids: asserting the list "renders"
// (it always did), asserting the count is non-nil (it was non-nil throughout
// the bug), and asserting `count == devices.count` (that is the bug restated
// as a test).
@Suite("Live-only device count (RV.54)")
struct LiveDeviceCountTests {

    /// The refresh glue `AppSync` runs on each surface appearance, mirrored
    /// here exactly as in `DeviceCountCacheTests` so the fetch and the
    /// live-only counting run through the same code the app uses.
    private struct Surface {
        var cache = DeviceCountCache()
        var fetches = 0

        mutating func refresh(signedIn: Bool, server: [AccountDevice]) {
            switch cache.refreshAction(signedIn: signedIn) {
            case .reuse, .clear:
                break
            case .fetch:
                fetches += 1
                cache.record(server.liveDeviceCount)
            }
        }
    }

    private func device(_ id: String, revoked: Bool = false) -> AccountDevice {
        AccountDevice(id: UUID(uuidString: id)!,
                      name: id, platform: "iOS",
                      lastSeenAt: Date(timeIntervalSince1970: 1_700_000_000),
                      revoked: revoked)
    }

    private static let idA = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    private static let idB = "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
    private static let idC = "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"

    // MARK: - The headline: list and count agree (both halves, one assertion set)

    /// A server list of 3 devices of which 1 is revoked: the count reads 2 and
    /// the list still shows 3 rows. Both halves live in one test because they
    /// are one contract - the count is DERIVED from the list, and the list is
    /// never filtered to make the count right (the revoked row stays visible:
    /// the history is the point of showing it).
    @Test("3 devices of which 1 is revoked: count reads 2 and the list shows 3 rows")
    func threeDevicesOneRevokedCountsTwoWhileListShowsAllThree() {
        let list = [device(Self.idA, revoked: false),
                    device(Self.idB, revoked: false),
                    device(Self.idC, revoked: true)]

        // The LIST half: every row the server returned stays in the list.
        #expect(list.count == 3,
                "the list keeps all three rows - the revoked device stays visible, marked")

        // The COUNT half: only the two live devices can reach the account.
        #expect(list.liveDeviceCount == 2,
                "the count excludes the revoked device - it cannot reach the data (410)")
    }

    // MARK: - The RV.6 test that was unwritable: the count VALUE decrements

    /// After a revoke the card's number must decrement - the VALUE, not a
    /// request. This is the assertion RV.6's brief demanded and could not be
    /// written while the count included revoked rows (a revoke then moved
    /// nothing). The revoke is modelled as the server marking the device
    /// revoked (the endpoint keeps returning the row, marked), the Account &
    /// devices screen clearing the cache (RV.6 invalidation), and the pop-back
    /// refresh reading the server truth through the live-only count.
    @Test("after a revoke the count value decrements from 2 to 1")
    func afterARevokeTheCountValueDecrements() {
        var surface = Surface()
        var server = [device(Self.idA, revoked: false),
                      device(Self.idB, revoked: false),
                      device(Self.idC, revoked: true)]
        surface.refresh(signedIn: true, server: server)
        #expect(surface.cache.count == 2, "two live devices render the count 2")

        // The user revokes B on the Account & devices screen: the row survives
        // (now marked), and the screen invalidates the cached count.
        server = [device(Self.idA, revoked: false),
                  device(Self.idB, revoked: true),
                  device(Self.idC, revoked: true)]
        surface.cache.invalidate()
        surface.refresh(signedIn: true, server: server)

        #expect(surface.cache.count == 1,
                "the count value must decrement to 1 - the value is what never moved under the bug")
        #expect(surface.cache.count == server.liveDeviceCount,
                "the count is derived from the same list the screen shows")
    }

    /// A revoke that happens on ANOTHER device this phone cannot see is not an
    /// event here: the cached count stands until a local event or the Account &
    /// devices screen (which always reads the full list) refreshes it. RV.6
    /// semantics, unchanged by RV.54 - this pins that the two do not interact.
    @Test("a remote revoke with no local event leaves the cached count standing")
    func aRemoteRevokeWithoutALocalEventLeavesTheCachedCountStanding() {
        var surface = Surface()
        let before = [device(Self.idA, revoked: false), device(Self.idB, revoked: false)]
        surface.refresh(signedIn: true, server: before)
        #expect(surface.cache.count == 2)

        // The server now shows one live device (a revoke on another phone).
        let after = [device(Self.idA, revoked: false), device(Self.idB, revoked: true)]
        #expect(after.liveDeviceCount == 1)
        #expect(surface.cache.refreshAction(signedIn: true) == .reuse,
                "without a local event the cached count stands until the next event")
        #expect(surface.cache.count == 2)
    }

    // MARK: - All revoked: zero, never nil, never negative

    /// A list of all-revoked devices reads 0: no crash, no negative, and 0 is
    /// a real count (the card says "0 devices"), never the "unknown" nil that a
    /// fetch failure produces and the next appearance retries.
    @Test("an all-revoked list reads 0 - never nil, never negative")
    func anAllRevokedListReadsZero() {
        let list = [device(Self.idA, revoked: true),
                    device(Self.idB, revoked: true),
                    device(Self.idC, revoked: true)]
        #expect(list.liveDeviceCount == 0)

        var surface = Surface()
        surface.refresh(signedIn: true, server: list)
        #expect(surface.cache.count == .some(0),
                "0 must be recorded as a count, never mistaken for the unknown nil")
        #expect((surface.cache.count ?? -1) >= 0, "no negative count can render")
    }

    /// An empty server list (a fresh account) also reads 0 - the same derived
    /// rule, no special case for emptiness.
    @Test("an empty server list reads 0")
    func anEmptyServerListReadsZero() {
        #expect([AccountDevice]().liveDeviceCount == 0)
    }
}
