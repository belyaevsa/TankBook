# What is missing from Tankbook, who would pay for it, and where

Product-analysis pass, 2026-09-06. Grounded in `docs/VISION.md`, `docs/COMPETITORS.md`,
`docs/STORE.md` §§1-2, `docs/JOURNEYS.md`, `docs/TASKS.md`, `docs/AGENT.md`, `docs/SCHEMA.md`
and the shipped code under `ios/App/Sources/` and `ios/Sources/TankbookCore/`. Anything already
carrying a task id is called **scheduled**, not missing. Reminders (RV.74-RV.79) are excluded per
the brief.

## 1. What is missing, and why does it matter?

Ranked by user pain, not ease.

**G1 · An EV can be added but cannot log anything it does. (Missing, and the listing already sells it.)**
`AddVehicleView.swift:197-214` fully supports an `.ev` car (battery kWh instead of tank litres).
But `CaptureMode.modes(for: .ev)` (`ios/Sources/TankbookCore/Domain/CaptureMode.swift:45`) offers
only Service and Expense, there is **no screen anywhere that creates a `ChargeSession`** (grep:
only test seeds, sync and edit paths touch it), and the consumption engine's EV math reads charge
sessions (`ConsumptionEngine.swift:212-213`), so an EV's headline number can never exist.
`HomeSections.swift:541` even renders kWh for sessions that cannot be created. Evidence it
matters: both store listings promise "Petrol, diesel, hybrid and electric in one history"
(`STORE.md` §§3-4) and the EN keyword string carries `ev` (`STORE.md` §2); COMPETITORS calls the
mixed-household EV-vs-petrol comparison "genuinely unowned" and notes CarScope has "no EV support
at all - a gap exactly where EV penetration is highest"; PJ.12's own consequence note says "an EV
user now has no primary logging path... owner's call". Schema: **fully supported** (ChargeSession,
Tariff, engine, log rendering) - this needs UI, not entities. J6 is `[v1.x]` in VISION but has
**no task row** (TASKS.md PJ preamble: "not filed"), and the listing contradiction is v1 and
unscheduled.

**G2 · Five of the six promised importers do not exist. (Scheduled v1.1 - but the v1 listing over-promises today.)**
`STORE.md` §3 tells switchers "Import from Fuelio, Drivvo, Fuelly/aCar, Spritmonitor, CarScope
and My Fuel Manager"; the backend has exactly one parser
(`backend/src/Tankbook.Api/Import/MfmParser.cs`), P5.4b is `[v1.1]` and blocked on real export
fixtures that "do not exist". J2 is the acquisition journey and STORE.md §1's closing line says
both audiences search "how do I move my data from Fuelio/Drivvo/the old phone"; COMPETITORS calls
importer parity "table stakes" (Drivvo and CarScope import from everyone). This is the same
over-promise class the repo has already fixed three times (PJ.3b Welcome tagline, W6 site,
PJ.12b capture caption). The gap is scheduled; **the listing copy is the unscheduled bug** -
either the importers ship before submission or the sentence names what works (PJ.33's guide
already "says so" in-app).

**G3 · A signed-out user's history survives only if they remember to export. (Missing, no task row.)**
The EN audience's strongest low-star trigger is data-portability failure (STORE.md §1: Simply
Auto "lost all my data... a few years of data logged", Fuelly "ALL MY DATA IS GONE"), and our own
EN listing leads with "your history survives". Yet for a guest - the persona the no-account pitch
exists for - the only protection is a manual export (PJ.36/PJ.38, built) or signing in. Nothing
schedules a backup, nothing notices 200 unexported entries, nothing prompts before the phone
change that STORE.md says is coming. Fuelio ships iCloud backup (COMPETITORS). Schema: the
versioned per-car archive is built and round-trip-tested (P5.5a); the missing piece is a nudge or
a local scheduled snapshot - no new entities. I could not find any row for this in TASKS.md.

**G4 · No widget, Shortcut or lock-screen door. (Promised v1.x in VISION, no backlog row.)**
J3's opening beat is "lock-screen widget / app opens on capture" and Flow A step 1 names the
widget; VISION's feature table lists "Widgets, Shortcuts, Siri" at v1.x; Fuelio ships widgets and
CarPlay (COMPETITORS). `project.yml` has no widget target (verified). The core was deliberately
built as a reusable package for exactly this (P0.1: "widgets/extensions can reuse it"). This is
the habit feature - "median capture-to-save < 15 s" (J3 metric) is unreachable if reaching the
camera costs finding an app icon. No new entities.

**G5 · Income tracking: absent by omission, never argued. (Neither scheduled nor cut.)**
Drivvo (broadest set), CarScope and Мой Авто's premium tier all carry income/profitability;
the MFM importer reads income rows and refuses them to the user's face ("income isn't imported in
v1", F6a). VISION cuts are recorded for tier 2, QR enrichment, CarPlay, Watch, crowd prices and
the Simply Auto tax-mileage lane - but income is simply nowhere. My read: keep it out (it serves
professional drivers, a different product), but **write the decision down**, because every Drivvo
switcher meets its absence in the import preview.

**G6 · Pump-display and dash-odometer capture: the unowned differentiators, honestly stuck. (Gated / not scheduled.)**
Pump capture is built and ships OFF by its own measured gate - 24 of 178 numeric cells, 13%
against a 60% floor (P2.7, CLAUDE.md rule 15). That is a fact, not a gap. The dash-photo odometer
("rest the receipt on the dash", VISION's capture finding, receipt-029) would complete a fill-up
from one photo, since the odometer is the one field no receipt carries - but it is the same
seven-segment problem class that is failing at 13%, and no arithmetic cross-check can validate an
odometer. It needs a corpus and a prototype, not a task row yet.

**Smaller, named for completeness.** CNG cannot be recorded in its own unit (SCHEMA.md open
question 1: "treat CNG as unsupported") while P2.3b makes CNG selectable beside petrol - a small
live inconsistency, CIS-relevant. VIN decoding is deliberately out ("Not a VIN decoder",
SCHEMA.md:721) and EU inspection (TÜV/MOT) and ОСАГО reminders already exist (VISION reminders
row, J7). Fines and taxes are recordable (`ExpenseCategory.fine/.tax`, Enums.swift:89-98).
Scheduled, so not gaps here: Car Agent/Ask (v2, AG.1-13), family sharing (J12, v2), PDF resale
dossier (PJ.37), share-to-Tankbook (PJ.21), station suggestion (PJ.19), per-brand prices
(PJ.31), trend arrows (PJ.30), invoice gateway (PJ.29), the J7 verb cluster (PJ.22-28, the
owner's v1.1 priority queue).

## 2. Which region's problem does each one solve?

- **G1 (EV)**: EN/EU-weighted - EV penetration and the Nordic gap COMPETITORS names; the RU
  listing also promises «электро», so the contradiction is bilingual even if the pain is not.
- **G2 (importers)**: the five missing sources are EN/EU apps; the CIS switcher is already
  served, since My Fuel Manager - the RU-ecosystem fixture - is the one importer that ships.
- **G3 (guest backup)**: genuinely universal, with EN emphasis: STORE.md §1 shows the EN
  audience's fear is the phone change, the RU audience's is the app dying. Local-first already
  answers "servers off" (Мой Авто's collapse); the guest backup answers "phone lost", which is
  the EN one-star.
- **G4 (widgets)**: universal; no regional evidence either way.
- **G5 (income)**: RU/CIS and gig-driver segments (Мой Авто PREMIUM 999 ₽/yr sells
  income/profitability per COMPETITORS); weak in the EN commuter audience we target.
- **G6 (pump/dash)**: universal. Note the RU receipts are not better served by QR here - a
  decodable QR exists on 22 of 48 and carries no volume (VISION).
- **CNG m³**: CIS-first (ГБО), secondary Italy/Germany.
- The RU-specific checklist the brief raises is otherwise **answered by architecture, not
  features**: fiscal QR anchors totals without ever being named (J5/F5, owner decision
  2026-08-30), ОСАГО expiry is a first-class reminder, "всё бесплатно" is true in v1 (P6.16), and
  offline-first is the answer to "отключили сервера". The US checklist: gallons/MPG ship
  (galUS/galUK units, RV.69 fixed their conversion); trip logging is the declined Simply Auto
  lane - though the EN keyword `mileage` will attract users who mean trips, a listing-expectation
  risk worth watching rather than a build.

## 3. Why would a user PAY for it?

v1 has no IAP at all (STORE.md §5), so the honest answer for almost everything above is
**free-tier obligation**:

- **G1, G2, G3, G4, G6, CNG: free, and gating any of them would repeat the competitor sins the
  product is positioned against.** Drivvo paywalls export and its reviews resent it; Fuelio's
  Premium creep drew "no reason to stay"; CarScope's vehicle lock still bleeds. Backup behind a
  paywall is data hostage-taking, the exact sin VISION §7 refuses. Capture behind Pro is
  mid-capture monetization, forbidden by ERRORS/API rules. Import behind Pro kills the switching
  path that acquires the user. Spritmonitor's EV depth is free + $0.99-$8.49 IAPs (COMPETITORS) -
  there is no WTP signal for paid EV logging to cite.
- **G5 (income)**: WTP exists but belongs to fleet/professional products - Drivvo fleet
  $29.99-$119.99/mo, Мой Авто BUSINESS 299-599 ₽/mo (COMPETITORS). That is a segment Tankbook
  does not serve; I would not build it, paid or free.
- **The Pro product is the conversation, not the log**: the Car Agent (v2), justified by real
  per-turn cost (AGENT.md §1). Nothing in this report strengthens Pro, and I say so plainly
  rather than inventing a story. The one Pro-adjacent opportunity G1 unlocks is the household
  EV-vs-petrol comparison as an "advanced insight" (VISION monetization list) - but the logging
  underneath must stay free, or the comparison has nothing to compare.
- **RU monetization is structurally blocked anyway**: Apple has processed no paid transactions in
  Russia since 2022, and STORE.md §7 already records the decision deadline ("where Pro can
  actually be bought"). Whatever ships in v2, the RU storefront needs its own answer.

## 4. UX gaps in what already ships, and how to resolve them

- **The EV dead end (G1's seam).** Screen: Add car → Capture. Files: `AddVehicleView.swift:197`,
  `CaptureMode.swift:45`, `ConsumptionEngine.swift:212`. A user follows a fully supported setup
  path into a car whose Capture screen has no primary mode and whose Trends can never fill.
  Change: ship the minimal typed Charge form (kWh, price, total, odometer - the schema, engine,
  sync and Log rendering all exist; only the form and the chip are missing, which is what PJ.12's
  note promises to restore it with). If J6 truly waits, then Add car must stop selling `.ev` as
  ready, and the listings must drop "electric" - the repo's own over-promise rule (W6) demands
  one of the two.
- **A scanned expense cannot be saved without typing a title.** `ExpenseEntryView.swift:39-42`
  gates Save on a non-blank title; the expense scan (RV.62) pre-fills total/currency/date only,
  because `FuelExtraction` carries no free-text field at all (P6.14). So the receipt scan door
  for expenses always ends with the keyboard - a rule-15 seam. RV.62 noted it and folded it into
  RV.57, which shipped the fill-up half only. Change: extract the merchant line as a
  low-confidence suggestion for the title, dimmed until tapped (hard rule 13 compliant); keep
  "category is never guessed" (J7b) intact.
- **Filed and open, so scheduled rather than missing here**: RV.71 (a diesel receipt on a petrol
  car saves in silence - the corpus proves confident grade misreads), RV.72 (FlaggedEntriesView's
  one-shot `didLoad` shows fixed entries as still flagged - the surface that must never read "my
  correction was lost"), RV.80 (the RU import card renders no "Send us the file" affordance).
- **Scheduled polish that users will feel as UX**: the station field's honest "Not set" until
  PJ.19's ranking lands, no share-sheet entry into Import until PJ.21, Trends' missing hero arrow
  (PJ.30).

## Report

Top three gaps: **(1)** an EV can be garaged but cannot log a single kWh, while both store
listings sell "electric in one history"; **(2)** the listing promises six importers and one
exists, on the exact search intent ("move my data from Fuelio") both audiences use; **(3)** a
signed-out user - the persona the whole no-account pitch courts - is one lost phone away from
the data-portability one-star that STORE.md §1 shows killing this category.

**One engineer, one month: build the EV charge path.** The typed ChargeSession form, the Tariff
row in vehicle settings, the restored `.charge` chip, and the kWh Trends tile - schema, engine,
persistence, sync and Log rendering already exist and are tested, so the work is screens, not
architecture. It closes the largest promise-vs-build gap in the product, converts the `ev`
keyword from a refund risk into an install, and unlocks the one insight COMPETITORS says nobody
owns. If the owner would rather defer J6, the same month should go to the guest-backup nudge
(G3, ~1 week) plus the two-week listing-truth pass (G2) - but shipping electric is the month
that changes what the product is.
