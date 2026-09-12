# REVIEW-SCENARIO run: J11 - 2026-09-12b (re-walk, after RV.260)

- **Scenario:** `J11` (`docs/JOURNEYS.md:515-520`)
- **Run id:** REVIEW-SCENARIO-J11-2026-09-12b
- **Report path:** `diagnostics/REVIEW-SCENARIO-J11-2026-09-12b.md`
- **Context:** Re-walk after `RV.260` (`d99824fb`, the local restore-from-backup door) and `RV.261` (`24a7683a`, last-odometer recency + source-device marked [v2]). Re-checks ONLY the two items the first walk (`REVIEW-SCENARIO-J11-2026-09-12.md`) gated on. Open, not deferred: RV.256 (unkeyed sync state), RV.257 (nondeterministic sign-in L4); both decided below as not touching J11's promises. Read-only; no code, no build, no commit.

## Verdict

**IMPLEMENTED.**

## Ticked rows found to be untrue

None. The two gated items are now ticked and hold against the tree (below).

## The open rows, decided

| Row | Touches a J11 promise? | Reasoning |
|---|---|---|
| RV.256 (persisted sync state is one account-unkeyed key) | **No** | Display-state bleed on the Settings account card after a sign-out then a different sign-in (account A's `lastFailure`/`lastSuccessAt` render on B until B's first cycle). That surface is J11a's "Confirm" stage, not a J11 promise: J11's journey promises the *restore* (F7 stats, text-in-seconds, "Open my garage", the local fallback), and the restore's own cursor was already keyed by account in RV.249. A `small` display polish; it never corrupts a restore and never blocks the fallback. Cited, not re-filed. |
| RV.257 (nondeterministic sign-in L4) | **No** | `no-scenario: test determinism` in its own cell - a flaky test, not a promise. Cited, not re-filed. |

## Promise-to-code map

Re-walk scope: the two gated items only; the rest was MET/N-A in the first walk and is unchanged (its citations stand).

| Journey promise (J11) | Status | Citation |
|---|---|---|
| **The local file export always available as the user-held fallback** (gated #1) | **MET** | The production caller now exists: `RestoreFromBackupModel.importBackup` stages the picked folder and runs `VehicleArchiveReader.importArchive(at: mode: .singleCar)` with no network and no session (`RestoreFromBackupModel.swift:76-96`). The door is `Route.restoreFromBackup` (`Routes.swift:81`, `Destinations.swift:46`), reachable from `EmptyRestoreView` (`RestoreFailureViews.swift:76`), `RestoreUnreachableView` (`RestoreFailureViews.swift:207`) and Settings beside Export (`SettingsView.swift:331`). The third-party wizard keeps its own door beside it on both failure screens (`RestoreFailureViews.swift:83,214`). Scope is the load-bearing guard: `.singleCar` mode + `.account` scope is refused (`VehicleArchiveReader.swift:191-204`), so a full-account export is refused locally with its named next step (`RestoreFromBackupView.swift:149,170`) rather than treated as one car. The per-car archive round-trips through the real `ExportBuilder` path (`RestoreBackupTestSeed`), and `RestoreFromBackupUITests` walks all three doors (EN + RU on the empty-restore door) and asserts the third-party source picker never appears. |
| **"last odometer with its source device" - the v1 recency, the [v2] device** (gated #2) | **MET** | The v1-computable recency now renders: `RestoringView.recencySuffix` emits " · N days ago" from `snapshot.lastOdometerDaysAgo` (`RestoringView.swift:128-131`, `L10n.relativeDay` at `L10n.swift:262-268`), decoupled from the device name that never rendered. The always-nil `RestoreSnapshot.lastOdometerDeviceName` and the dead `L10n.lastOdometerSource` are gone (no matches in the tree). The source-device half is marked `[v2]` in the journey text (`docs/JOURNEYS.md:518`), matching `SCHEMA.md` and `ERRORS.md`. L4 `SignInUITests.swift:237-271` asserts the suffix in EN and RU from the seeded `-signInRestoreDaysAgo` (`SignInTestSeed.swift:69`). |

## Sequence trace

Fresh iPhone → Welcome "Already use Tankbook? Restore your garage" → Sign in (Apple) → pull from cursor 0 → `RestoringView` "Welcome back / cars, entries, date range, Last odometer N km · 3 days ago" → "Open my garage" → restored garage. The two facts that used to stop being carried now carry:

1. **The export fallback** (was dead at the wizard): a user whose sync restore fails taps "Import a file you exported yourself" and now reaches `RestoreFromBackupView` (`RestoreFailureViews.swift:76` / `:207`), which reads the Tankbook archive the user exported - the third-party MFM/Drivvo wizard is the *adjacent* door, not the fallback. The per-car archive's car and entries land on Home (`RestoreFromBackupUITests.swift:27-46`); a full-account archive is refused with "Sign in with the same account to restore everything" (`RestoreFromBackupView.swift:170`).
2. **The last-odometer recency** (was discarded at the nil device-name guard): now renders as its own suffix, independent of the v2 device attribution.

## Proposed rows

None. Both gated items are shipped and verified; the two open rows (RV.256, RV.257) do not touch J11's promises; PR.20 and PJ.35 are [v1.1] and N/A to v1.

## Not settled

- The first walk's "not filed" notes stand unchanged and are not J11 promises: F7 source 2 ("a server backup snapshot") is F7's sentence, not J11's; and the absence of a progress surface during the text pull itself is not promised by J11. Neither blocks this verdict.
