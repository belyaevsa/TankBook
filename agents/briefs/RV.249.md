# RV.249 - the sync cursor is one account-unkeyed key

**Scenarios: J11 · new phone (the pull cursor), J11a · first sign-in.** The last v1 row holding
J11a open; one of J11's last two.

`UserDefaultsSyncCursorStore` (`SyncTransport.swift:31`) is a single key,
`tankbook.sync.cursor`, whoever is signed in. Two consequences, found by the `RV.155` agent and
left deliberately: (1) an in-flight restore page returning `1589` after the app engine persisted
`1679` moves the cursor backwards again - narrower than RV.155's race, still real; (2) a
monotonic guard alone is WRONG, because sign-out (`SessionSignOut.swift:24`) clears the session
and not the cursor, so a guard would make signing into a DIFFERENT account resume from the old
account's SCN and never pull its history.

## Build

1. **Key the cursor by account id.** `UserDefaultsSyncCursorStore` takes the account id (from
   `AuthSession.accountId`, `AuthSession.swift:14`) and stores under a per-account key; the two
   production call sites (`AppSync.swift:42`, `SignInFlow.swift:440`) pass the session's id. Say
   how a store is built when no session exists (guest: no cursor, no sync - it must not crash).
2. **Then a monotonic guard is safe**: `save` ignores a lower advance for the SAME account.
   `SeededSyncCursorStore` (RV.155) still seeds 0 for a restore - a restore pulls from 0 by design
   (`docs/SYNC.md:150`), the guard applies to the durable write-through, not the seed.
3. **Migration**: an existing device has a value under the old key for the account it is signed
   into. Move it to the keyed slot on first load for that account, then delete the old key - or
   state why re-pulling from 0 once is acceptable (it is a full replay, `SYNC.md:150`; say what it
   costs the owner's 1,600-record account).
4. `docs/SYNC.md` → the cursor bullet (`:205`) says the cursor is per account and monotonic.

**Sibling check (`docs/DEFECT-PATTERNS.md`)**: `SyncStateStore` (`SyncStateStore.swift:87`) and
`syncPayloadMemory` (`SYNC.md:203`) are also device-local bookkeeping - are THEY account-keyed? If
not, say whether the same defect applies (a stale payload baseline from account A diffing account
B's vehicle) and file or fix in the same change.

## Tests

- **L1, FAILS TODAY**: two accounts on one device keep separate cursors.
- **L1, FAILS TODAY**: a lower advance for the same account is ignored.
- **L1**: sign-out then sign-in to another account starts from 0.
- **L1**: the old unkeyed value migrates once and the old key is gone.
- `RV155CursorOverlapTests` stays green.

## Mutation - named

Drop the account key (one key again); the two-accounts L1 goes red. Verbatim.

No UI. Run `swift test` in full and the app-target bundle (`AppSync` changes).
