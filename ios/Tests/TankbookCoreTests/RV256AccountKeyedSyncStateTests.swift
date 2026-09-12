import Foundation
import Testing
@testable import TankbookCore

// RV.256: the persisted sync state is keyed by account id. Before this, one
// device held one state whoever was signed in, so after a sign-out and a
// different sign-in account A's last success and last failure rendered on
// account B's card until B's first cycle overwrote them.

private let legacyStateKey = "tankbook.sync.state"

private func ephemeralStateSuite() -> String { "RV256-\(UUID().uuidString)" }

private func encodedLegacyState(_ state: PersistedSyncState) -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return (try? encoder.encode(state)) ?? Data()
}

@Test func twoAccountsOnOneDeviceKeepSeparatePersistedSyncState() {
    let suite = ephemeralStateSuite()
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let accountA = UserDefaultsSyncStateStore(accountId: "account-a", suiteName: suite)
    let accountB = UserDefaultsSyncStateStore(accountId: "account-b", suiteName: suite)

    let successA = Date(timeIntervalSinceReferenceDate: 100)
    let successB = Date(timeIntervalSinceReferenceDate: 900)
    accountA.save(PersistedSyncState(lastSuccessAt: successA, lastFailure: nil))
    accountB.save(PersistedSyncState(lastSuccessAt: successB, lastFailure: nil))

    #expect(accountA.load().lastSuccessAt == successA, "account A keeps its own state")
    #expect(accountB.load().lastSuccessAt == successB, "account B keeps its own state")
}

@Test func aFailureRecordedForAccountAIsNotReadableForAccountB() {
    let suite = ephemeralStateSuite()
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let accountA = UserDefaultsSyncStateStore(accountId: "account-a", suiteName: suite)
    let accountB = UserDefaultsSyncStateStore(accountId: "account-b", suiteName: suite)

    accountA.save(PersistedSyncState(
        lastSuccessAt: Date(timeIntervalSinceReferenceDate: 200),
        lastFailure: SyncFailureRecord(at: Date(timeIntervalSinceReferenceDate: 300),
                                       kind: .authExpired,
                                       code: "token_invalid",
                                       traceId: "rv256-a")))

    #expect(accountB.load().lastFailure == nil,
            "account B must not inherit account A's failure until its own first cycle")
    #expect(accountB.load().lastSuccessAt == nil,
            "account B must not inherit account A's success date")
}

@Test func theLegacyUnkeyedStateMigratesOnceAndTheOldKeyIsGone() {
    let suite = ephemeralStateSuite()
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let defaults = UserDefaults(suiteName: suite)
    let legacy = PersistedSyncState(
        lastSuccessAt: Date(timeIntervalSinceReferenceDate: 1234),
        lastFailure: SyncFailureRecord(at: Date(timeIntervalSinceReferenceDate: 1300),
                                       kind: .upgradeRequired,
                                       code: "upgrade_required",
                                       traceId: "rv256-legacy"))
    defaults?.set(encodedLegacyState(legacy), forKey: legacyStateKey)

    let store = UserDefaultsSyncStateStore(accountId: "account-a", suiteName: suite)

    #expect(store.load() == legacy, "the pre-RV.256 value lands in this account's slot")
    #expect(defaults?.object(forKey: legacyStateKey) == nil,
            "the old unkeyed key is deleted after migrating")
    #expect(store.load() == legacy, "the migrated value is what later loads read")
}
