# REVIEW-SCENARIO run: J6 · EV charge – 2026-09-11c

- **Run id:** REVIEW-SCENARIO-J6-2026-09-11c
- **Scenario:** J6 (`docs/JOURNEYS.md:234`), heading `[v1.x]`
- **Tree:** read-only; no code, tests, builds or commits made.

## Verdict

**NOT IMPLEMENTED.** Every one of J6's three promises is correctly deferred (N/A-for-v1) and the v1-level consequences of that deferral are closed (`PJ.12` hides the dead Charge chip, `PJ.51` changed the listing words) – but the deferral is **incomplete as a spec**: three promises in J6's own text have no row and no code, and one (the "two-car chart" payoff) is the journey's named emotional beat. A story is not finished because its backlog names the typed form.

## Ticked rows found to be untrue

None. `PJ.12` (`docs/TASKS.md:300`) genuinely holds: `CaptureMode.modes(for: .ev)` returns `[.service, .expense]` and `.charge` is offered to no powertrain (`ios/Sources/TankbookCore/Domain/CaptureMode.swift:44-49`, comment at `:32-39`). `PJ.51` is docs-only and matches the tree. No ticked row claims J6 shipped.

## Promise-to-code map

| J6 promise (`docs/JOURNEYS.md`) | Status | Evidence |
|---|---|---|
| **Public** (`:237`): share charging-app screenshot → confirm card in `headlight` cyan, kWh instead of liters → saved against EV | **N/A (v1.x) – unowned tail** | No share-extension target (`project.yml:20-167` lists only the app and test/UI-test targets). No charge confirm card or kWh prefill; the only confirm sheet is fill-up-shaped (`ios/App/Sources/Capture/ScannedFillUpSheet.swift`). `PJ.49` files the typed path and says "typed first, **scanning later**" but **no row files the scanning/share half**. The `headlight` token exists (`ios/Sources/TankbookCore/Design/Theme.generated.swift:13`) and is wired to the `.charge` entry mark (`ios/App/Sources/Shared/EntryKindMark.swift:24`), but no charge confirm card uses it. |
| **Home** (`:238`): quick-entry "home charge", kWh from wallbox **or % delta → kWh via battery size**, × stored home tariff; tariff in vehicle settings, one-time setup; night/day split later | **N/A (v1.x) – PARTIAL** | Typed charge form (kWh / price-or-total / odometer / tariff) is filed as `PJ.49` (`docs/TASKS.md:789`). But three sub-promises are unowned: the **% delta → kWh** prefill (the schema field exists, `batteryCapacityKWh` at `ios/Sources/TankbookCore/Domain/Entities.swift:50`, no reader/writer); the **tariff in vehicle settings** (the `Tariff` entity exists `Entities.swift:477` and is persisted/synced/exported – `Repository.swift:323`, `Repository+Sync.swift:218`, `CarCSVExport.swift:89-97` – but **nothing creates one in production and no computation reads it**: `ImportService.swift:118` returns `nil` for `.tariff`); the **night/day split**. |
| **Payoff** (`:239`): Trends shows **both household cars in €/100 km on one chart** | **N/A (v1.x) – MISSING** | Per-vehicle €/km exists: `ConsumptionEngine.costPerKm` (`ios/Sources/TankbookCore/Consumption/ConsumptionEngine.swift:232`), surfaced per-car in `TrendsView.swift:146-150` and `HomeGuestLayout.swift:103-106`. There is **no cross-car comparison** anywhere – Trends/Home operate on one vehicle's stats. This is the journey's named beat ("J6's is the two-car chart", `docs/JOURNEYS.md:732`) and it has no row. |
| **Success metric** (`:241`): % of EV owners logging ≥4 sessions/month; comparison screen's weekly views | **N/A (v1.x)** | Depends on the charge path and the comparison screen, both absent. |

## Sequence trace

One user, one EV, the whole J6 flow:

1. User creates an EV in the Garage (powertrain `.ev`; headlight accents render – `CarSwitcherView.swift:293`, `GarageView.swift:386`, `TrendsView.swift:210`). **Reachable.**
2. User opens the capture surface. Offered modes are `[.service, .expense]` – no Charge (`CaptureMode.swift:44-49`). **The fact stops being carried here**: the EV's energy cost can never enter the history.
3. Because no `ChargeSession` is ever created outside the edit screen and test seeds (`EditEntryView.swift:57`; `PJ.49`), the EV's consumption/cost headline never fills: `HomeStats.swift:131-133` and `TrendsStats.swift:120-122` read `ConsumptionEngine.evSegments` (`ConsumptionEngine.swift:260`) over an empty list, and `HomeSections.swift:540-541` renders kWh for sessions nobody can create.
4. The "home tariff" and "€/100 km comparison" steps are unreachable from there – no tariff setup surface, no comparison screen.

The v1 story an EV owner gets is coherent and correctly worded (garage an EV, log service and expense, no electric claim in the listing – `PJ.51`). The J6 story is entirely behind `PJ.49`'s typed-form first step, and stops there.

## Proposed rows

All attach to **J6**. All are `[v1.x]`/`[v2]` per the deferral – severity is the consequence *to the spec*, not a shipped defect.

| Proposed | Deliverable (one line) | Closes | Consequence today | Severity | Done when |
|---|---|---|---|---|---|
| **J6-public-share** | File the public-charge door: a share extension accepting a charging-app screenshot → headlight confirm card with kWh, the LLM-normalization path the journey's ⚠ already anticipates. | J6 "Public" (`:237`) | The promise is unowned; `PJ.49` defers scanning without filing it, so when EV ships the share path is silently forgotten. | gap | L4 `CaptureUITests`: a charging-app screenshot lands a kWh prefill on a headlight confirm card; L1: the prefill's kWh carries into a `ChargeSession`. Vacuous trap: a `.phev` fixture where the fill-up door hides the gap. |
| **J6-two-car-chart** | File the comparison screen: both household cars' €/100 km on one chart, the journey's emotional beat. | J6 "Payoff" (`:239`) | The one differentiator the journey names has no owner. | gap | L1: the per-car €/100 km equals `ConsumptionEngine.costPerKm` for each car; L4 `TrendsUITests`: the comparison chart renders two cars. Vacuous trap: one car in the fixture, where "comparison" passes with nothing to compare. |
| **J6-home-tariff** | File the home-charge extras: a per-car tariff setting (one-time setup), the % delta → kWh prefill over `batteryCapacityKWh`, and note night/day as deferred. | J6 "Home" (`:238`) | `Tariff` is a dead entity – persisted, synced and exported, never created and never read (the "entity nothing creates" shape; `RV.207` notes it is outside both guards). | gap (latent bug) | L1: a tariff created in vehicle settings survives and is read by the charge math; L1: % delta × `batteryCapacityKWh` yields the kWh prefill. Vacuous trap: asserting the tariff form renders while the computed cost still ignores it. |

## Could not settle

1. **Version-marker drift.** J6's heading is `[v1.x]` (`docs/JOURNEYS.md:234`) and `VISION.md:92` lists EV charging as `v1.x`, but `PJ.49`/`PJ.52` are marked `[v2]` in `docs/TASKS.md` and the 2026-09-11 decision in `PJ.51` says "EV is v2, PJ.49". The journey and the backlog now disagree about which release owns this scenario. Settles by a product-owner call, then re-marking the journey and `VISION.md` in one change (the conflict rule). I did not touch the marker.
2. **`PJ.52` names the wrong journey.** Its row text says "the parts shelf **J6** already describes", but the parts shelf is J7b (`docs/JOURNEYS.md:308`). Cosmetic, but it means a grep for "J6" surfaces a row that belongs to a different scenario. Settles by correcting the reference.
3. **Whether `PJ.49`'s "scanning later" is meant to be a second row or a clause inside `PJ.49`.** I treated it as a separate proposed row (`J6-public-share`) because `PJ.49`'s own scope is explicitly "typed first"; the product owner may instead fold it into `PJ.49`.
