# REVIEW-JOURNEYS re-run - 2026-09-09

*Second run of the recurring journeys walk (`agents/briefs/REVIEW-JOURNEYS.md`). Tree `d00293f` at
run time, 644 commits after the 2026-08-29 run at `93d2619`. Single read-only agent (the machine
is memory-constrained and another agent is building RV.141 in this checkout). Nothing edited,
built or tested. This run prioritised: (1) `[x]` rows whose behaviour the code does not have,
(2) the four `DEFECT-PATTERNS.md` Part 2 shapes on everything shipped since `93d2619`, (3) the
journeys this session touched most - J4 (station), J7b (purchase / parts shelf), the money/rate
journeys, and the feedback/About flow.*

---

## 1. `[x]` rows whose behaviour the code does not have

**Result: none found among the 2026-09-09 cluster.** Every ticked row in the last day's work was
checked against its commit and its cited seam, and each holds. The four that `DEFECT-PATTERNS.md`
named as the historically-rotten ones were verified hardest:

| Row | Claim | Verified at |
|---|---|---|
| RV.136 | `Vehicle` compared decoded, not by payload bytes | `RecordMerge.swift:149` `case Vehicle.entityType: return equivalent(local, remote, Vehicle.self)` - the missing arm is present |
| RV.156 | a station can be created | `Repository+StationCreate.swift:40` `upsertStation(resolved, syncState: .dirty)`; call sites `ManualFillUpStationRow.swift:150` (entry) and `StationsListView.swift:152` (Garage list) - both non-seed |
| PJ.19 | the ranking is called as a default input | `ManualFillUpView+StationSuggestion.swift:18` `runStationSuggestion` called at `ManualFillUpView.swift:317`; permission once after the second fill-up (`ForecourtLocationReader.requestPermissionOnce`, `ManualFillUpView+StationSuggestion.swift:25-27`) |
| RV.150 | the save stamps what the ranking reads | `Repository+StationStamp.swift:27` `stampStation`, called at `ManualFillUpView+StationStamp.swift:27` after the fill-up write |
| PJ.25 | the parts shelf has a Garage door | `VehicleDetailView.swift:171` pushes `Route.partsShelf(vehicle.id)` -> `Destinations.swift:38` |
| PJ.28 | a scanned expense keeps its receipt | `ExpenseReceiptWrite.swift:39` `ReceiptAttachmentWriter.write`, called at `ExpenseEntryView.swift:198`; failure names its next step (`:248-252`) |
| RV.150 (door) | the Stations list is reachable | `GarageView.swift:288` `NavigationLink(value: Route.stations)` |

One caveat worth recording, not filing: **RV.139** is ticked "RESOLVED by observation on build
925", and its own row says *"which change fixed it is not established"*. The symptom (no
`/rates/pack` request) is gone and the store holds 4285 rates, so the tick is honest - but the
cause is unproven, and it sits next to `RV.158` (open: the drain fires eight empty-pack requests
in 7 ms). If the missing-request defect returns, the two will be read together.

---

## 2. New gaps found by this run

### PJ.55 - the "favourite" rung of the station ranking is dead: nothing can set `Station.favorite`

**gap** - a shipped rung of a shipped feature reads a field no production writer can make true,
and two docs claim the opposite.

The ranking's rung 1 ("a favourite station within 300 m") filters on `Station.favorite`:
`StationSuggestion.swift:130` (`.filter({ $0.0.favorite })`). The only writers of that field are:

- `ImportStation.swift:43` - `favorite: false` (the import path, and it never sets true);
- `Migrations.swift:325` - the column default, `false`;
- persistence round-trip (`Records+Extras.swift:82,95`) - copies what was stored.

`Repository+StationCreate.swift` (RV.156) and `Repository+StationStamp.swift` (RV.150) write
`lastUsedAt`, `defaults` and `location` and **never** `favorite`. No UI offers a favourite
control: `ManualFillUpStationRow.swift` (add + menu) and `StationsListView.swift` have none, and
`StationSettingsView.swift` (RV.150) shows location + "Remove location" only (`:71-106`).

Two docs assert the field is "filled by use" while no use fills it:
- `SCHEMA.md:452-453` - *"`favorite`, `defaults` and `location` are filled by use (the save
  stamp above)"* - but the save stamp above (`SCHEMA.md:432-442`) fills only `lastUsedAt`,
  `defaults` and `location`;
- `JOURNEYS.md` J4 - rung 1 is "a favourite station within 300 m of the device".

This is the exact `DEFECT-PATTERNS.md` Part 2 "orphan state" shape (a feature on a field nothing
creates), and its Pattern 3 twin (a doc naming a behaviour with no call site). The user
consequence is silent: rung 1 never fires, the ranking always falls through to rung 2 (last-used)
and rung 3 (most recent), and there is no way for a driver to say "this is my station".

**Deliverable - one of two, decided and recorded.** Either give the user a way to mark a
favourite (a toggle on the station row / the Station settings screen, alongside the existing
"Remove location" control), or drop rung 1 from the ranking and delete `Station.favorite` (and
its migration column, schema, and the `SCHEMA.md:452` sentence). Do not leave a dead rung and a
doc that says it is live.

**Checks (if the favourite is kept):** L1: a station marked favourite wins rung 1 over a nearer
non-favourite and over a more recent non-favourite, for an authorised + fixed Confirm. L1: an
unmarked station set still ranks rungs 2-3 as today (regression guard). L1: the toggle persists
and rides the ordinary `.dirty` sync path; a pulled favourite on a second device is read by the
ranking (record-level LWW). L4 `ConfirmManualStationSuggestionUITests` + a `Stations`/`Station
settings` suite: the control exists in EN and RU. **Vacuous traps:** asserting the ranking ranks
favourites from a seeded `favorite: true` fixture - that already passes against a field no UI
can set; asserting the toggle renders without asserting it is read by `StationSuggestion.winner`;
keeping `SCHEMA.md:452`'s "filled by use" sentence while the field is now user-set.

**Checks (if dropped):** grep gate: zero `favorite` references outside the migration; the doc
sentence removed; `StationSuggestion.winner` no longer has a rung 1.

---

## 3. Cited, not re-filed (already tracked)

| Observation | Existing row |
|---|---|
| `SheetRoute.reminderComplete` maps to `SheetPlaceholderContent()` (`Color.clear`) at `Destinations.swift:85` and is presented nowhere - the real completion sheet is `ReminderCompleteSheet` presented directly from `RemindersView.swift:144`. Dead `SheetRoute` case; `SCREENMAP.md`'s "Reminder complete (sheet)" node is served by a different path than the enum implies. Not user-facing (the real screen is reachable). | RV.129 (detached implementation) / RV.130 (dead-code tail, `[v1.0.x]`) |
| RV.141 (excluded-entries count names nothing) is **in flight in this checkout** - `Route.excludedEntries`, `ExcludedEntriesView.swift`, `EntryExclusion.swift` and their tests are **uncommitted working-tree files**, not shipped. Excluded from this run's findings as unshipped; the row stays `[ ]` correctly. | RV.141 |
| RV.159 (two identical-looking consents, one gates sending) and RV.160 (feedback send has no visible confirmation) - the feedback/About flow. Both open and accurately filed; no third gap found on that surface. | RV.159, RV.160 |

---

## 4. Where this run stopped

Depth over coverage, per the brief. Walked in depth: **J4** (station) end to end - the ranking,
the permission ask, the creation door in both states, the stamp, and the Garage list/settings
route, which is where PJ.55 surfaced; **J7b** (purchase / parts shelf) - PJ.25's door, PJ.28's
photo, the nested "View shelf" sheet; and the **money/rate** journey (RV.139-RV.158) and the
**feedback/About** flow (RV.159/RV.160), both spot-checked against their open rows.

Not walked stage-by-stage (JOURNEYS.md J1-J3, J5-J13, F1-F12): **J1-J3/J5** (acquisition/capture -
verified transitively through the ticked PJ.1/PJ.2/RV.5/RV.12 rows), **J6** (EV, `[v1.x]`, N/A for
v1), **J7/J7c/J7d** (service + reminder lifecycle - the RV.74-RV.79 cluster is ticked and was not
re-walked), **J8-J10** (Trends / anomaly / cross-border), **J11-J13 + F7/F10** (account/sync/exit).
These are the natural starting point for the next run.
