# RV.256 - the persisted sync state is one account-unkeyed key

**Scenarios: J11 · the account card after a switch, J11a · first sign-in.** Sibling of `RV.249`,
which keyed the pull CURSOR by account; this is the same unkeyed shape on the persisted STATE.

`UserDefaultsSyncStateStore` (`SyncStateStore.swift:102`) stores `PersistedSyncState` under one
key, `tankbook.sync.state`, whoever is signed in - so after a sign-out and a DIFFERENT sign-in,
account A's `lastFailure` / `lastSuccessAt` ("session expired", "device signed out") render on
B's card until B's first cycle overwrites them. `syncPayloadMemory` does NOT have the defect
(keyed by record UUID).

## Build

Key the store by account id exactly as `UserDefaultsSyncCursorStore(accountId:)` does
(`SyncTransport.swift:31-87`): per-account key, one-time migration of the unkeyed value into the
signed-in account's slot, old key deleted. `SyncService.makeCoordinator` already receives the
account id (`RV.249`) - pass it through. A guest builds no coordinator, so no state store is
needed without an account; say how the OB.3 relaunch read (`AppSync.refresh` → `coordinator()`)
still sees the persisted state for the signed-in account.

## Tests

- **L1, FAILS TODAY**: two accounts on one device keep separate persisted sync state.
- **L1, FAILS TODAY**: a failure recorded for A is not readable for B.
- **L1**: the legacy unkeyed value migrates once and the old key is gone.
- `SyncStateStore`'s existing tests stay green; `SettingsUITests` in its own invocation (the card
  reads this state) - report the count.

## Mutation - named

Drop the account key (one key again); the two-accounts L1 goes red. Verbatim. No UI change.
