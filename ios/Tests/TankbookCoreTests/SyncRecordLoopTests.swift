import Foundation
import Testing
@testable import TankbookCore

// RV.35: the generic (non-`Vehicle`) arm of `applyPull` decided whether to
// re-dirty a synced record whose local copy won LWW by comparing two JSON
// payloads byte-for-byte. A lossy server round-trip - a normalised number token
// (`1.0` vs `1`), a decimal string with a dropped trailing zero (`289.50` vs
// `289.5`), a date re-serialised without fractional seconds - makes the bytes
// differ while the decoded record is identical, so the row was re-dirtied,
// pushed, pulled back and re-dirtied again. These tests pin the fix: the engine
// compares decoded values (`RecordMerge.recordsEqual`), and a genuine
// divergence still re-dirties and pushes (hard rule 8).

private let rv35T0 = Date(timeIntervalSinceReferenceDate: 0)
private let rv35Policy = SyncSchemaPolicy(minSupported: 1, current: 1)

// MARK: - Payload builders that change bytes without changing the decoded value

/// Rewrites one top-level number token ("42.3" -> "42.30"): the bytes differ,
/// the decoded `Double` does not.
private func retokenizeNumber(_ payload: JSONValue, key: String, to token: String) -> JSONValue {
    guard case .object(var dict) = payload, dict[key] != nil else { return payload }
    dict[key] = .number(token)
    return .object(dict)
}

/// Drops the fractional-seconds suffix of one top-level date string
/// ("…T00:00:00.000Z" -> "…T00:00:00Z"): the bytes differ, the decoded `Date`
/// does not.
private func dropFractionalSeconds(_ payload: JSONValue, key: String) -> JSONValue {
    guard case .object(var dict) = payload, case .string(let raw)? = dict[key] else { return payload }
    dict[key] = .string(raw.replacingOccurrences(of: ".000Z", with: "Z"))
    return .object(dict)
}

/// Rewrites the nested `money.amount` decimal string ("289.5" -> "289.50"):
/// the bytes differ, the decoded `Decimal` does not.
private func retokenizeMoneyAmount(_ payload: JSONValue, to raw: String) -> JSONValue {
    guard case .object(var dict) = payload, case .object(var money)? = dict["money"] else { return payload }
    money["amount"] = .string(raw)
    dict["money"] = .object(money)
    return .object(dict)
}

private func echo(_ pushed: SyncPushChange, payload: JSONValue,
                  clientUpdatedAt: Date) -> SyncPullRecord {
    SyncPullRecord(id: pushed.id, entityType: pushed.entityType,
                   schemaVersion: pushed.schemaVersion, scn: 1,
                   payload: payload, clientUpdatedAt: clientUpdatedAt,
                   deleted: pushed.deleted)
}

// MARK: - The loop, in both directions

@Test func rv35PushedPreferencesPulledBackUnchangedDoesNotPushAgain() async throws {
    // The reported defect: preferences, the singleton. The server echoes the
    // record back with a date serialised without fractional seconds and a
    // `clientUpdatedAt` truncated a second older - the bytes differ, the decoded
    // record does not. Two cycles: one pull cannot show a loop.
    let repo = try makeSyncRepository()
    try repo.upsertPreferences(Preferences(createdAt: rv35T0, updatedAt: rv35T0))

    let transport = SyncTransportDouble()
    let engine = makeSyncEngine(repository: repo, transport: transport)

    let outcome1 = await engine.synchronize()
    #expect(outcome1.pushed == 1, "the initial push is the only legitimate write")
    #expect(transport.recordedPushBatches.count == 1)

    let pushed = transport.recordedPushBatches[0][0]
    transport.enqueuePull(SyncPullResponse(
        records: [echo(pushed, payload: dropFractionalSeconds(pushed.payload, key: "updatedAt"),
                       clientUpdatedAt: pushed.clientUpdatedAt.addingTimeInterval(-1))],
        nextSince: 1, more: false, schemaPolicy: rv35Policy))

    let outcome2 = await engine.synchronize()
    #expect(outcome2.pushed == 0, "an unchanged record must not be re-pushed (RV.35)")
    #expect(transport.recordedPushBatches.count == 1, "no second push batch")
    #expect(try repo.fetchDirtyRows().isEmpty, "the record settles, not stuck dirty")

    guard case .synced = try repo.localSyncRecord(id: pushed.id, entityType: Preferences.entityType)?.syncState else {
        Issue.record("preferences must settle to .synced")
        return
    }
}

@Test func rv35PushedFillUpPulledBackWithANormalisedNumberDoesNotPushAgain() async throws {
    // The same class of bug on a second entity type: the server re-formats the
    // `volumeL` number token. Fixing only preferences would leave this looping.
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))
    let fillUpId = UUID.v7()
    try repo.upsertFillUp(makeSyncFillUp(id: fillUpId, vehicleId: vehicleId))

    let transport = SyncTransportDouble()
    let engine = makeSyncEngine(repository: repo, transport: transport)

    let outcome1 = await engine.synchronize()
    #expect(outcome1.pushed == 1, "the initial push is the only legitimate write")
    #expect(transport.recordedPushBatches.count == 1)

    let pushed = transport.recordedPushBatches[0][0]
    transport.enqueuePull(SyncPullResponse(
        records: [echo(pushed, payload: retokenizeNumber(pushed.payload, key: "volumeL", to: "42.30"),
                       clientUpdatedAt: pushed.clientUpdatedAt.addingTimeInterval(-1))],
        nextSince: 1, more: false, schemaPolicy: rv35Policy))

    let outcome2 = await engine.synchronize()
    #expect(outcome2.pushed == 0, "an unchanged record must not be re-pushed (RV.35)")
    #expect(transport.recordedPushBatches.count == 1, "no second push batch")
    #expect(try repo.fetchDirtyRows().isEmpty, "the record settles, not stuck dirty")
}

// MARK: - The counterpart: a genuine divergence must still push

@Test func rv35AGenuinePreferencesDivergenceStillPushes() async throws {
    let repo = try makeSyncRepository()
    try repo.upsertPreferences(Preferences(createdAt: rv35T0, updatedAt: rv35T0),
                               syncState: .synced(scn: 1))

    // The server holds a genuinely different preferences record (an older clock).
    var remote = Preferences(createdAt: rv35T0, updatedAt: rv35T0.addingTimeInterval(-1))
    remote.notifications = Preferences.Notifications(reminders: false, anomalies: false,
                                                     monthlySummary: true)

    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(remote, scn: 2)], nextSince: 2, more: false, schemaPolicy: rv35Policy))
    let outcome = await makeSyncEngine(repository: repo, transport: transport).synchronize()

    #expect(outcome.pushed == 1, "a genuine divergence must still push (hard rule 8)")
    #expect(transport.recordedPushBatches.count == 1)
    #expect(try repo.livePreferences()?.notifications.reminders == true,
            "the newer local value survives and is what pushes")
}

@Test func rv35AGenuineFillUpDivergenceStillPushes() async throws {
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))
    let fillUpId = UUID.v7()
    try repo.upsertFillUp(makeSyncFillUp(id: fillUpId, vehicleId: vehicleId),
                          syncState: .synced(scn: 1))

    var remote = makeSyncFillUp(id: fillUpId, vehicleId: vehicleId, volumeL: 43.3)
    remote.updatedAt = rv35T0.addingTimeInterval(-1)

    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(remote, scn: 2)], nextSince: 2, more: false, schemaPolicy: rv35Policy))
    let outcome = await makeSyncEngine(repository: repo, transport: transport).synchronize()

    #expect(outcome.pushed == 1, "a genuine divergence must still push (hard rule 8)")
    #expect(transport.recordedPushBatches.count == 1)
    guard let pushed = transport.recordedPushBatches.first?.first else { return }
    #expect(pushed.payload.objectValue?["volumeL"] == .number("42.3"),
            "the newer local volume is what pushes, never the stale remote")
}

@Test func rv35ARemoteTombstoneStillPushesTheNewerLiveEdit() async throws {
    // The `deleted` half of the condition: a live local edit newer than a remote
    // tombstone must still re-dirty and push (S4 in the local-wins direction).
    let repo = try makeSyncRepository()
    let vehicleId = UUID.v7()
    try repo.upsertVehicle(makeSyncVehicle(id: vehicleId), syncState: .synced(scn: 1))
    let fillUpId = UUID.v7()

    var live = makeSyncFillUp(id: fillUpId, vehicleId: vehicleId)
    live.updatedAt = rv35T0.addingTimeInterval(2)
    try repo.upsertFillUp(live, syncState: .synced(scn: 1))

    var tombstone = makeSyncFillUp(id: fillUpId, vehicleId: vehicleId)
    tombstone.updatedAt = rv35T0.addingTimeInterval(1)
    tombstone.deletedAt = rv35T0.addingTimeInterval(1)

    let transport = SyncTransportDouble()
    transport.enqueuePull(SyncPullResponse(
        records: [makePullRecord(tombstone, scn: 2, deleted: true)],
        nextSince: 2, more: false, schemaPolicy: rv35Policy))
    let outcome = await makeSyncEngine(repository: repo, transport: transport).synchronize()

    #expect(outcome.pushed == 1, "a tombstoned remote copy must still push the newer live edit")
    #expect(try repo.liveFillUps(forVehicle: vehicleId).count == 1, "the newer live edit survives")
}

// MARK: - The comparison itself, at the level it reasons

@Test func rv35RecordsEqualComparesDecodedValuesNotBytes() throws {
    let vehicleId = UUID.v7()

    // A re-formatted number token decodes to the same record.
    let fill = makeSyncFillUp(id: UUID.v7(), vehicleId: vehicleId, volumeL: 42.3)
    let localFill = makeSyncRecord(fill, clientUpdatedAt: rv35T0)
    let remoteFill = SyncRecord(
        id: localFill.id, entityType: localFill.entityType, schemaVersion: localFill.schemaVersion,
        payload: retokenizeNumber(localFill.payload, key: "volumeL", to: "42.30"),
        clientUpdatedAt: rv35T0, deleted: false)
    #expect(RecordMerge.recordsEqual(localFill, remoteFill),
            "a re-formatted number token is the same decoded record")

    // A decimal string with a dropped trailing zero decodes to the same amount.
    let expense = Expense(id: UUID.v7(), createdAt: rv35T0, updatedAt: rv35T0, vehicleId: vehicleId,
                          date: rv35T0, money: Money(amount: Decimal(string: "289.50")!, currency: .eur,
                                                     homeCurrency: .eur),
                          provenance: .manual, category: .insurance, title: "Insurance")
    let localExpense = makeSyncRecord(expense, clientUpdatedAt: rv35T0)
    let remoteExpense = SyncRecord(
        id: localExpense.id, entityType: localExpense.entityType, schemaVersion: localExpense.schemaVersion,
        payload: retokenizeMoneyAmount(localExpense.payload, to: "289.50"),
        clientUpdatedAt: rv35T0, deleted: false)
    #expect(RecordMerge.recordsEqual(localExpense, remoteExpense),
            "a trailing-zero decimal string is the same decoded record")

    // A genuinely different value is not the same record.
    let changedFill = makeSyncRecord(makeSyncFillUp(id: localFill.id, vehicleId: vehicleId, volumeL: 43.3),
                                     clientUpdatedAt: rv35T0)
    #expect(!RecordMerge.recordsEqual(localFill, changedFill),
            "a genuinely different decoded value is a different record")
}
