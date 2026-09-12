import Foundation
import Testing
@testable import TankbookCore

// RV.249: the durable pull cursor is keyed by account id and monotonic per
// account. Before this, one device held one cursor whoever was signed in, so a
// restore page returning a lower SCN could move it backwards; and a monotonic
// guard alone was wrong, because sign-out clears the session but never the
// cursor, so signing into a different account would have resumed from the old
// account's SCN and never pulled its history.

private let legacyCursorKey = "tankbook.sync.cursor"

private func ephemeralSuite() -> String { "RV249-\(UUID().uuidString)" }

@Test func twoAccountsOnOneDeviceKeepSeparateCursors() throws {
    let suite = ephemeralSuite()
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let accountA = UserDefaultsSyncCursorStore(accountId: "account-a", suiteName: suite)
    let accountB = UserDefaultsSyncCursorStore(accountId: "account-b", suiteName: suite)

    try accountA.save(100)
    try accountB.save(250)

    #expect(try accountA.load() == 100, "account A keeps its own cursor")
    #expect(try accountB.load() == 250, "account B keeps its own cursor")
}

@Test func aLowerAdvanceForTheSameAccountIsIgnored() throws {
    let suite = ephemeralSuite()
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let store = UserDefaultsSyncCursorStore(accountId: "account-a", suiteName: suite)

    try store.save(1679)
    try store.save(1589)

    #expect(try store.load() == 1679,
            "a stale restore page returning a lower nextSince must not move the cursor back")
}

@Test func signingIntoADifferentAccountStartsFromZero() throws {
    let suite = ephemeralSuite()
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let accountA = UserDefaultsSyncCursorStore(accountId: "account-a", suiteName: suite)
    try accountA.save(900)

    // A fresh store for the other account is what the coordinator builds after
    // sign-out then a different sign-in. No value means the engine pulls from 0.
    let accountB = UserDefaultsSyncCursorStore(accountId: "account-b", suiteName: suite)
    #expect(try accountB.load() == nil, "a different account has no cursor to resume from")
}

@Test func theLegacyUnkeyedCursorMigratesOnceAndTheOldKeyIsGone() throws {
    let suite = ephemeralSuite()
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.set(Int64(1234), forKey: legacyCursorKey)

    let store = UserDefaultsSyncCursorStore(accountId: "account-a", suiteName: suite)

    #expect(try store.load() == 1234, "the pre-RV.249 value lands in this account's slot")
    #expect(defaults.object(forKey: legacyCursorKey) == nil,
            "the old unkeyed key is deleted after migrating")
    #expect(try store.load() == 1234, "the migrated value is what later loads read")
}
