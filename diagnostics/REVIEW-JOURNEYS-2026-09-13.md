# REVIEW-JOURNEYS run, 2026-09-13 - Groups A, B, C, D

**Walked by:** the orchestrator (product owner, 2026-09-12: walks are not dispatched) · **Tree:** `c11f1099` · **Since:** the 2026-09-12 walks (A+B at `1848830b`, C+D at `87c264e5`); **28 rows shipped** in between, all four of the owner's own reports of 2026-09-13 among them.

## 1. Re-check of what the previous runs gated on

| Item | Then | Now |
|---|---|---|
| A+B §7: guest Home frames not viewed by the agent | open | the orchestrator opened all eight at `RV.251` (`e6972b3d`) - switcher, Type-it menu, reminders row, no-car button present |
| A+B §7: guest reachability of the Garage tab and Vehicle detail | unverified | the tab bar and `TabRoots` carry no session gate (`grep isGuest\|signedIn` over `AppTabBar`/`TabRoots*`: none); `RV.251`'s L4 adds a second car from the Garage as a guest - reachable |
| A+B §7: tire-set creation offered only on Edit entry, never at the purchase moment | owner question | still an owner question; J7b's text does not say *when* - cited below, not filed |
| C+D §7: the J9 act reminder due today | owner call | decided and shipped (`RV.268`: the shared one-year default, opened for edit) |
| C+D §7: the J9 evidence chart as two bars | owner call | left as is; recorded in the J9 walk of 2026-09-12 |

## 2. Ticked rows whose behaviour the code does not have

**None.** Each of the 28 rows was gated with the orchestrator's own named mutation at ship time (the tick records it). Seven re-checked today by grep: `RV.256` (state store keyed by account: 4 sites), `RV.267` (`discardStagedScan` + `session.discard()`), `RV.264` (the two plural keys, 4 catalogue entries), `RV.271` (`DistanceMath` in 2 app files), `RV.275` (`VehicleTile(` in 4 files), `RV.248` (`reminderHistory` read at 7 sites), `RV.240` (no `reason` left on the anomaly card).

## 3. Pass 1 - reachability from a cold launch, no debug flag

- No navigation on Home, Settings, About or the tab roots lives behind `#if DEBUG` (grep over `NavigationLink|Route.|.sheet(|presentSheet|Button` inside DEBUG blocks: none).
- Every screen in `SCREENMAP.md` binds to a live route (`ScreenRouteBindings`, `RV.162`'s guard, green in `swift test`); the two screens added since the last walk (`Restore from backup`, `RV.260`; the reminders History section, `RV.248`) are bound.
- The `PJ.4`/`PJ.59` shape (a section fed only by a fixture) is guarded (`DebugFixtureSectionScanner`, green); the `PJ.40` S5 notice remains the one known fixture section, `[v1.1]`.
- A guest reaches every v1 surface: Home (with switcher, Type-it menu, reminders row, add-car button - `RV.251` family), Garage, Vehicle detail, Reminders, Import, Restore from backup (no session required, `RV.260`).

## 4. Pass 2 - sequence: create → edit → sync → delete → restore, pending → rated

| Chain | Status | Evidence |
|---|---|---|
| Every entity syncs | MET | eleven schemas in `Schemas/v1/` (attachment, chargeSession, expense, fillUp, preferences, reminder, serviceRecord, station, tariff, tireSet, vehicle); `syncOverwrite`, `syncPayloadMemory`, `AnomalyDismissal` are device-local by design (`SYNC.md`) |
| delete → 30-day undo (hard rule 8) | MET | Recently deleted lists entries (fill, charge, service, expense), vehicles (`RV.98`) and reminders (`PJ.7`) - `DeletedEntry` / `DeletedVehicle` / `DeletedReminder`; tire sets and stations have **no delete door at all** (`grep func delete` over their repositories: none), so nothing is lost without a restore |
| a sync overwrite is recoverable | MET | `syncOverwrite` log read by the *Overwritten by sync* section, *Restore my version* (`PJ.59`) |
| pending → rated for the record's money | MET | `MoneyBackfillService` fills and re-homes `FillUp`, `ChargeSession`, `ServiceRecord`, `Expense` (`:9-18` of the apply switch); `RV.140`/`RV.143`/`RV.144` cover the originating device, the receiving device and the edit |
| pending → rated for a **service line item's** money | **GAP** | `ServiceItem.cost` is a full `Money` pair written at creation - the form (`ServiceEntryFormState.swift:90`), the invoice scanner (`ServiceInvoiceScanner.swift:78`), the import (`ImportConversion.makeItem`, `PJ.58`) - and its home side is then **never backfilled, never re-homed on a currency change, and never read**: no totals, Trends, export or Restore consumer touches `item.cost.homeAmount` (grep over Trends/Home/Consumption/Stats/CarCSVExport: none). `PJ.58` asserted record and items agree at import; after `RV.140`'s re-home they no longer do. The `RV.163`/`PJ.60` shape - a stored value with no reader - one level down. Filed as **PJ.300** |
| the car's units at every boundary | MET | `RV.234`/`RV.271`-`RV.274`: labels, values, pre-fill and prices all convert at one boundary each |

## 5. Journey-stage walks

**Group A (acquisition and capture).** J1 implemented 2026-09-12 (after `RV.241`, `RV.251`); J2 2026-09-12b; J3 2026-09-13 (after `RV.272`), J3b 2026-09-13; J5 2026-09-11b; F1, F3, F4, F5 2026-09-11 (their metric rows `RV.225`, `RV.233`, `RV.266` are `[v1.0.x]`); F2 2026-09-12c (after `RV.270`); F8 2026-09-11 with `RV.226` shipped since - the `.restricted` card walks to `CapturePermissionCards` (lock, *type the entry instead*, no Settings toggle). **J4 has no status line and cannot get one**: `RV.114` and `RV.179` need the owner's pump-display photographs; the mode ships off (`VISION.md`).

**Group B (service, parts, reminders, EV).** J7 2026-09-11c; J7b 2026-09-12b (after `RV.246`); J7c 2026-09-13 (after `RV.247`, `RV.248`); J7d 2026-09-12b. `RV.205` (J7b) needs the owner's parts receipt. J6 is `[v1.x]` as a whole (`RV.236`-`238`). Tire-set-at-purchase: owner question, unchanged.

**Group C (periodic, currency, import).** J8 2026-09-11c; J9 2026-09-12 (after `RV.240`/`RV.268`); J10 2026-09-12; F6 2026-09-12 (after `RV.227`, `RV.228`), F6a 2026-09-12b (after `RV.263`), F6b 2026-09-12 (after `RV.229`, `RV.264`, `RV.265`, `RV.269`); F9 2026-09-12; F9a 2026-09-13 (after `RV.276`). The one gap this walk found (PJ.300) sits in this group's money seam.

**Group D (account, sync, exit).** J11a 2026-09-12; J11 2026-09-12b (after `RV.260`, `RV.261`); F7 2026-09-12c; F10 2026-09-12 (after `PJ.59`, `RV.253`). **J13 and J8b walked IMPLEMENTED in code and held** on `RV.181`'s device step (the owner's release build could not share or export). J12 is `[v2]`.

## 6. Proposed rows

| # | Deliverable | Stage | Consequence today | Severity | Check | Scenario |
|---|---|---|---|---|---|---|
| PJ.300 | Decide the service line item's home money: (a) fold `ServiceItem.cost` into the backfill and re-home passes so record and items always agree, or (b) drop the item's home side and keep the item as an original-currency amount whose home figure derives from the record's rate | J7 "the invoice split into lines"; J10 "trends stay in the car's home currency"; PJ.58 | none visible - no surface reads an item's home figure; after a home-currency change the stored items silently disagree with their record, and the disagreement rides sync and export | polish / decide | under (a): L1 a rate-pending item fills when the rate lands and re-homes with the car; under (b): the field gone, `SCHEMA.md` says why, `PJ.58`'s test asserts the original pair only | J7, J10 |

## 7. Cited, not re-filed

`RV.181` [~] (holds J8b, J13) · `RV.114`, `RV.179` (J4 photos) · `RV.205` (J7b photo) · `PJ.35`, `PJ.24` [v1.1] · `RV.242` (guard blind spot, unqueued) · `RV.225`, `RV.233`, `RV.266`, `RV.254`, `RV.252` [v1.0.x] · tire-set at purchase (owner) · the J9 two-bar chart (owner, left as is).

## 8. Could not settle

- The two "older open questions" the orchestrator had been carrying under the names *F8 denied-mode* and *F6b total-only* are filed nowhere - not in `TASKS.md`, `QUEUE.md` or the decisions note. Dropped from the pending list; if the owner remembers them, they are new rows.
