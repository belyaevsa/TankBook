# Tankbook – Data Schema

*The single source of truth for entities, fields, invariants, and derived math. Companion to `VISION.md` (product), `JOURNEYS.md` (flows and failure states), `SYNC.md` (multi-device), and the consumption walkthrough (four-drivers simulation). Types are written in Swift-ish notation; the same shapes serialize to the backup format and to sync record payloads. Naming here is canonical across Swift, C#, SQL, and analytics – no synonyms.*

## Principles

1. **Local-first.** The on-device database is authoritative and fully functional with no account. Signing in turns on multi-device sync through our backend (see `SYNC.md`); the server stores the account's record stream but no feature requires it to be reachable.
2. **Store facts, derive conclusions.** Segments, averages, trends, and anomaly flags are never persisted – they recompute from entries. Editing one entry can change two segments; storing them would mean cache invalidation bugs forever.
3. **Money is always a pair.** Every amount stores the original currency *and* the conversion into the vehicle's home currency with the rate and its date. Conversions are snapshots – history never shifts when rates move.
4. **Provenance travels with data.** Every entry knows how it was created (scan/QR/manual/import) and every OCR-extracted field keeps its source-image crop and confidence – that's what powers tap-to-verify (F2) and trust UX.
5. **Soft delete everywhere.** Entities carry tombstones (`deletedAt`) so sync and backup restore can merge deletions; hard purge happens on a schedule, locally.

## Identifiers & sync envelope

Every persisted entity shares:

```swift
id: UUID            // v7 (time-ordered) – generated on device, stable across sync/backup
createdAt: Date     // device clock at creation
updatedAt: Date     // bumped on every edit; = clientUpdatedAt in the sync LWW merge (SYNC.md)
deletedAt: Date?    // tombstone; nil = live
```

Author attribution for shared garages (v2) comes from the sync record's `origin_device`/account, not domain fields.

## Entities

### Vehicle

```swift
Vehicle {
  id, createdAt, updatedAt, deletedAt
  name: String                  // "Volvo V60" – user-facing, free text
  make: String?; model: String?; year: Int?
  plate: String?
  powertrain: .ice | .ev | .hybrid | .phev
  fuelKinds: [FuelKind]         // what this car accepts: [.diesel], [.petrol95, .lpg], [.electricity]…
  tankCapacityL: Double?        // enables tank-level math and "liters to full"
  batteryCapacityKWh: Double?   // EV/PHEV: enables %→kWh estimates
  homeCurrency: CurrencyCode    // reporting currency for ALL stats of this vehicle
  units: { distance: .km|.mi, volume: .l|.galUS|.galUK, consumption: .lPer100|.mpgUS|.mpgUK|.kmPerL, energy: .kWhPer100|.miPerKWh }
  photo: AttachmentID?
  archived: Bool                // sold cars: history retained, out of active stats (J13)
  archivedAt: Date?             // when it was archived; nil = never archived (J13)
  paceLimitKmPerDay: Double = 1500   // plausibility bound for timeline validation (F9a)
  initialOdometer: Int?         // "Current odometer" from Add car, in the vehicle's distance unit
}
```

**On `initialOdometer`** (added 2026-08-23, when P1.2 found the Add-car artboard collecting a value the model could not store): the Add-car screen asks for the car's current odometer, and without this field that input was silently discarded. It is the reading **as of `createdAt`**, and it is the one odometer value that is *not* on an entry.It does not violate "stats are derived, never stored". A derived odometer would be `max(entry.odometer)` over the timeline; this is **user-entered baseline data** for the moment before any entry exists. It earns its place twice:

- **Home has something honest to show on day one.** The Home artboard renders `119 486 km · updated Aug 17`; with zero entries there is nothing to derive from, so the alternative is a blank or a lie.
- **Timeline validation gets a lower bound from the first entry, not the second.** The `INVARIANT` below (odometer strictly increases with date) and the pace check need a prior reading; `initialOdometer` supplies it for entry number one, which otherwise has nothing to be compared against.

It is optional, never blocks saving a car (`ERRORS.md` → Add car: the implausible-odometer warning is a warning), and once entries exist the derived value takes over – `initialOdometer` stays as the floor, it is not rewritten.

**On `archivedAt`** (added 2026-08-23, when P1.11 found the Car switcher wanting to say *"Archived · sold Mar 2026 · history kept"* with no field to hold the "when"): `archived` is the flag, `archivedAt` is the *when*. The switcher and the vehicle detail render "sold <month>" from it instead of fabricating a date. Set it on archive, clear it on unarchive; `archived == false` implies `archivedAt == nil`, so the two never disagree. It is cosmetic for stats – archived cars are out of active stats by `archived`, not by this date – but it is the honest label J13 promises.

### Entry (common envelope)

`FillUp`, `ChargeSession`, `ServiceRecord`, and `Expense` are distinct types sharing this envelope. The Log renders their union ordered by `date`.

```swift
EntryCommon {
  id, createdAt, updatedAt, deletedAt
  vehicleId: UUID
  date: Date                    // when it happened (not when logged)
  odometer: Int?                // in vehicle's distance unit; REQUIRED on FillUp, optional elsewhere
  money: Money?                 // see below; nil for free events (home charge logged by kWh only gets computed cost)
  note: String?
  attachments: [AttachmentID]    // a scanned save writes ONE Attachment and references the SAME id
                                 // from the fill-up and from every accepted expense - one photograph of
                                 // one receipt, never a copy per row (PJ.2)
  provenance: .receiptScan | .pumpPhoto | .fiscalQR | .screenshot | .manual | .import(source: String)
                                 // never `.manual` when a prefill was applied (PJ.2): the provenance
                                 // names the door the capture came through, not the typing that refined it
  conflict: ConflictState       // see Validation
  purchaseGroupId: UUID?        // entries born from ONE receipt (fuel + car wash + coffee) share this;
                                // they share attachments, sum to ≤ the receipt's grand total, and the
                                // Log can render them as one visual group. Nil for standalone entries.
                                // (P1.5) The group's displayed total is derived as the sum of its
                                // members' home amounts - never the fill-up's amount alone (CHECK 3),
                                // and counted ONCE in a month divider. Until P2.4 stores the receipt's
                                // own total, lines left un-logged (coffee) are simply not part of the
                                // figure the group shows.
}

Money {
  amount: Decimal; currency: CurrencyCode          // as paid: 289.50 PLN
  homeAmount: Decimal?; homeCurrency: CurrencyCode // converted: 67.79 EUR (vehicle.homeCurrency at save time)
  rate: Decimal?; rateDate: Date?                  // the snapshot; nil rate = ratePending (F3/F9)
  rateSource: .ecb | .cis | .manual = .ecb         // manual = user typed/edited the rate on the entry
}

// Conversion semantics (normative):
//   rate is ORIGINAL per HOME: homeAmount = amount / rate     (289.50 / 4.2706 = 67.79, rounded to the home currency’s minor units)
//   rateDate = entry.date (the day it happened), NEVER "today" – a wrong-date rate is worse than none (F9).
//   homeAmount is a SNAPSHOT: written once when the rate is known, immutable afterwards; later feed
//   updates never touch it. If currency == homeCurrency, homeAmount = amount, rate = 1, rateSource = .ecb.
//   Backfill rule (rate arrives later, incl. via sync on another device): fill ONLY if homeAmount is nil;
//   never recompute an existing snapshot. Editing `amount` or `currency` clears the snapshot for re-conversion;
//   changing vehicle.homeCurrency re-converts NOTHING retroactively – old entries keep their snapshot, and
//   stats mixing home currencies render per-currency subtotals (rare, surfaced honestly).
```

### FillUp

```swift
FillUp: EntryCommon {
  volumeL: Double               // always stored in liters; displayed in vehicle unit
  unitPrice: Decimal?           // per liter, original currency
  fuelKind: FuelKind            // .diesel, .petrol92, .petrol95, .petrol98, .petrol100, .lpg, .cng, .e85, .adBlue (a FLUID, not a fuel - see "AdBlue" below)…
  fuelGrade: String?            // marketing tier: "V-Power", "Ultimate", "Standard"
  isFull: Bool                  // closes a consumption segment
  tankLevelAfterPct: Double?    // 0–100; 100 ⇒ isFull. The mature partial-fill answer (My Fuel Manager pattern)
  stationId: UUID?
  crossCheck: .verified | .mismatch(field: FieldRef) | .notApplicable
                                // volumeL × unitPrice ≈ money.amount, tolerance max(0.02, 0.5%)
  extraction: ExtractionMeta?   // OCR provenance, see Attachment
  fiscalIdentity: FiscalDocumentIdentity?   // fn + i + fp, set only when the fiscal QR decoded;
                                // nil otherwise (the common case - 14 of 26 corpus receipts).
                                // Two DIFFERENT identities prove two fills are different purchases,
                                // so the duplicate rule consults this before its heuristic (P2.4b).
}
```

`unitPrice` is stored, not derived: receipts print all three numbers and the redundancy IS the confidence signal. When the user types only two, the third derives on save and `crossCheck = .notApplicable`.

### ChargeSession

```swift
ChargeSession: EntryCommon {
  energyKWh: Double
  unitPrice: Decimal?           // per kWh
  chargeType: .acHome | .acPublic | .dcPublic
  provider: String?             // "Ionity"; free text with favorites-style suggestions
  tariffId: UUID?               // home sessions: cost computed = energyKWh × tariff price if money is nil
  durationMin: Int?
  socStartPct: Double?; socEndPct: Double?   // enables %→kWh estimate via batteryCapacityKWh
  extraction: ExtractionMeta?
}

Tariff {
  id, createdAt, updatedAt, deletedAt
  vehicleId: UUID?              // nil = household-wide
  name: String                  // "Home night rate"
  pricePerKWh: Decimal; currency: CurrencyCode
  validFrom: Date               // price changes create a new Tariff row; sessions keep their snapshot via Money
}
```

### ServiceRecord & Expense

```swift
ServiceRecord: EntryCommon {    // work DONE to the car: annual service, repairs, tire swap, filters
  // date + odometer come from the envelope and are both stored on every service entry:
  // date defaults to today (or the invoice's extractedTimestamp), odometer pre-fills from the
  // vehicle's last known value and is REQUIRED whenever any item carries a km lifetime or the
  // record mounts a tire set – km-based reminders and tire mileage anchor on it (J7c).
  vendor: String?               // "Bosch Service"; nil = DIY
  items: [ServiceItem]          // invoice line items, OCR-split (J7); manual fallback = typed rows
  usedParts: [UUID]             // Expense(.parts) entries installed in this service – links, not costs
  tireSetId: UUID?              // which TireSet went ON, when this includes a tire swap
  proposedReminderId: UUID?     // the reminder the app suggested and user accepted
}
ServiceItem {
  title: String; category: ServiceCategory; cost: Money?
  partNumber: String?           // "MANN W 712/75" – enables reorder and lifetime tracking
  lifetime: { km: Int?, months: Int? }?   // set → the record proposes the next reminder itself
}
ServiceCategory: .oil | .brakes | .tires | .battery | .filters | .inspection | .repair | .parts | .wash | .other(String)

Expense: EntryCommon {          // money NOT tied to work: insurance, tax, parking, tolls, fines, accessories –
                                // and PARTS bought standalone (online order, shelf stock)
  category: .insurance | .tax | .parking | .toll | .fine | .accessory | .parts | .other(String)
  title: String
  recurrence: RecurrenceRule?   // yearly insurance auto-suggests next entry + reminder
  installedInServiceId: UUID?   // .parts only: set when a later ServiceRecord installs it.
                                // Cost counts ONCE (here, at purchase); the service links it via usedParts
                                // instead of re-pricing it – no double counting in cost/km.
}

TireSet {                       // v1.x – seasonal sets with their own mileage
  id, createdAt, updatedAt, deletedAt
  vehicleId: UUID
  name: String                  // "Winter Nokian", "Summer Michelin"
  purchaseExpenseId: UUID?      // the Expense(.parts) that bought them
  // km on this set is DERIVED: sum of odometer spans between ServiceRecords that mounted/unmounted it
  // (tireSetId marks mounting; the next tire-swap record ends the span). Never stored – same rule as segments.
}
```

### Reminder

```swift
Reminder {
  id, createdAt, updatedAt, deletedAt
  vehicleId: UUID
  title: String
  category: ServiceCategory | .insurance | .inspection | .custom
  dueDate: Date?                // either or both; both = whichever-first (Reminders screen rule)
  dueOdometer: Int?
  recurrence: { everyKm: Int?, everyMonths: Int? }?   // on completion, next occurrence self-schedules
  sourceEntryId: UUID?          // the service record that spawned it
  status: .scheduled | .attention | .done(entryId: UUID?) | .dismissed(reason: String?)
  // .attention is derived at read time from thresholds, but the *transition* is stored so
  // notifications fire once, not on every recompute
}

// Reminder lifecycle (normative):
//   COMPLETE   → prompt "log the cost?": creates a pre-filled ServiceRecord/Expense (category, title,
//                current odometer) → status = .done(entryId). Declining is fine: .done(nil) – completion
//                never forces bookkeeping. If recurrence is set, the NEXT occurrence is created as a NEW
//                Reminder row, anchored at the COMPLETION date/odometer (not the original due – no drift),
//                linked via sourceEntryId. Old rows stay as history ("oil changed 3× on time").
//   RESCHEDULE → edits dueDate/dueOdometer in place; a fired .attention resets so it can notify again.
//   DELETE     → tombstone (syncs like everything). Distinct from .dismissed, which keeps the row
//                with a reason and feeds anomaly/insight logic ("dismissed: sold the tires").
```

### Attachment & extraction provenance

```swift
Attachment {
  id, createdAt, updatedAt, deletedAt
  kind: .photo | .pdf
  file: LocalFileRef            // synced as content-addressed blob (sha256 – SYNC.md); backup same
  extractedTimestamp: Date?     // printed date on receipt / QR timestamp – anchors date-side validation (F9a)
  ocrText: String?              // full recognized text, retained for re-parsing after parser upgrades
  thumbnailBase64: String?      // ~120px JPEG, base64, rides INSIDE the payload so lists render photo chips
                                // with zero blob fetches (SYNC.md -> Attachments); nil for a PDF
}

ExtractionMeta {                // embedded in FillUp/ChargeSession
  fields: [FieldRef: FieldExtraction]
  pipeline: String              // "vision+rules v3", "fiscal-qr", "cloud-fallback v1" – regression tracking
}
FieldExtraction {
  cropRect: CGRect?             // normalized region in the attachment image – powers tap-to-verify (F2)
  confidence: Double            // 0–1; UI dims below threshold
  userCorrected: Bool           // corrected fields become OCR training signals (opt-in)
}
FieldRef: .total | .volume | .unitPrice | .date | .station | .fuelKind | .energy | .currency | .vendor | .lineItem(Int)
// .currency: detected from the receipt's symbol/code ("PLN", "zł") – shown as a chip on the confirm
// screen with its own confidence; a low-confidence currency NEVER silently converts (ask, don't guess).

**On `userCorrected` (PJ.2):** the flag is set at SAVE time by the scanned save
(`ScannedSavePlanner`), per field, by comparing the value the entry records
against what the extraction proposed. A field the user left exactly as proposed
is `false`; a field the user changed is `true`. The comparison is against the
PROPOSED value (the QR-resolved total, not the raw OCR one – a user leaving a
QR-corrected total untouched has corrected nothing), at the display precision
the receipt prints (2 decimals for money, 2 for litres, 3 for price per litre).
This is the accuracy feed `docs/EXTRACTION.md` names ("pre-fill overwritten by
the user") and the one place it is produced. Crop rects are recorded in the
source image's pixel space (the same rects tap-to-verify shows).
```

### Preferences (app-level settings)

Split by a simple rule: **what describes the person syncs; what describes the device stays local.**

```swift
// SYNCED – one singleton record per account (well-known id "preferences";
// entityType "preferences"; record-level LWW is fine for a settings blob):
Preferences {
  id (fixed), createdAt, updatedAt, deletedAt
  notifications: { reminders: Bool = true, anomalies: Bool = true, monthlySummary: Bool = false }
                                // content categories – what may notify at all (J9: never alarm-style)
  eagerMediaOnWiFi: Bool = false  // download full attachment renditions ahead of tap (SYNC blob pipeline)
  defaultVehicleId: UUID?       // the garage card shown on launch; capture logs here
  proFeedbackDiagnostics: Bool = false   // the About-screen toggle: attach appVersion/deviceModel to feedback
}

// DEVICE-LOCAL – UserDefaults/AppStorage, never synced, never in backups:
//   appearance (.system|.dark|.light)  – people legitimately run dark phone / light iPad
//   language override                  – follows each device's locale by default
//   capture conveniences               – torch preference, last capture mode
//   last-viewed tab, collapsed sections, draft states
//   sync cursor & auth tokens          – infrastructure, not preferences (tokens in Keychain)
```

The Settings screen renders both kinds in one list; the split is invisible to the user and only matters for sync semantics. Vehicle-level settings (currency, units, tank size) stay on `Vehicle` – reiterated because it's the IA rule too (DESIGN.md).

### Station

```swift
Station {
  id, createdAt, updatedAt, deletedAt
  name: String; brand: String?
  location: CLLocationCoordinate2D?
  favorite: Bool
  defaults: { fuelKind: FuelKind?, fuelGrade: String? }   // pre-fill on next visit (smart defaults)
  lastUsedAt: Date?
}
```

### ExchangeRate (local cache, deliberately NOT synced)

```swift
ExchangeRate { base: CurrencyCode; quote: CurrencyCode; date: Date; rate: Decimal; source: .ecb | .cis }
```

Devices fill this cache from the backend's public `/rates` endpoint (see Reference data below), keep ~2 years rolling, and ship with a seed pack so day-one offline use works; misses queue entries as rate-pending (F9 in JOURNEYS). The cache never syncs – what travels between devices is the `Money` snapshot inside entries, so conversions stay consistent account-wide once written (backfill rule above; sync scenario S8 in `SYNC.md`).

## Validation (runs on every write)

```
INVARIANT  For a vehicle's entries with odometer set, sorted by date: odometer strictly increases.
CHECK 1    Order: odometer fits between date-neighbors. Violation → discrepancy UI.
CHECK 2    Pace: implied km/day against neighbors ≤ vehicle.paceLimitKmPerDay.
CHECK 3    Cross-check: volume × unitPrice ≈ FillUp.money.amount (tolerance max(0.02, amount × 0.005)).
CHECK 4    AdBlue (2026-08-30): `.adBlue` in Vehicle.fuelKinds requires `.diesel` in the same set; an AdBlue fill never opens, closes or feeds a fuel segment (FuelKind.family) - see → AdBlue.
           SYMMETRY LIMIT: multiplication is commutative, so this check passes just as happily on a
           SWAPPED volume/unitPrice pair. It validates the product, never the assignment – deciding
           which operand is which is the job of the resolution ladder in Reference data → Fuel price
           bands. Never treat a green cross-check as evidence the fields are correctly assigned.
            MIXED RECEIPTS: the fill-up's amount is the FUEL LINE, never the receipt's grand total.
            Detection is the cross-check itself: when volume × unitPrice matches a line item but not
            the grand total, the receipt is mixed – the remainder lines are offered as separate
            Expenses sharing purchaseGroupId and the attachment. Non-car lines (coffee) are simply
            not logged; the full receipt stays readable in the attachment. Group invariant (P2.4):
            the logged group (fill-up + accepted expenses) never exceeds the receipt's LINE-EXTENSION
            total (fuel line + all detected lines) – it can only be less, when a line was dismissed.
            The fiscal/QR total is a separate figure used to DETECT mixedness, not the sum ceiling:
            a receipt's own rounding (ОКРУГЛЕНИЕ) can make its fiscal total slightly lower than the
            line-extension total (receipt-009: fuel 6135.24 + water 129.00 = 6264.24, charged
            6264.00), and that discount belongs to no line.
PRIORITY   If an attachment has extractedTimestamp (receipt/QR), its date is ground truth:
           "fix odometer" is the preselected resolution; overriding the date needs explicit confirmation.
FISCAL QR  The ФНС QR is an authoritative ANCHOR, not a capture path (docs/JOURNEYS.md J5/F5): it
           carries only the total `s`, timestamp `t`, fiscal ids `fn`/`i`/`fp` and type `n` - no
           litres, unit price or fuel kind, and the OFD document URL is keyed on an opaque id not
           derivable from the QR. Its total and date outrank anything OCR produced. The cross-check
           of a QR grand total against an OCR candidate total classifies three ways, all tolerant
           of ЛУКОЙЛ-style whole-rouble rounding (`FiscalQRCrossCheck`, P2.6): within 1 ₽ = agrees;
           less than the total but ≥ half of it = the OCR value is the fuel line of a mixed receipt
           (the fuel line stands - hard rule 4); anything else = disagrees, the QR total wins (the
           OCR value was a VAT or rounding line). `fn`+`i`+`fp` identify the fiscal document, so a
           re-scan is the same purchase, not a second fill-up. The identity is stored on
           `FillUp.fiscalIdentity` (nil when no QR decoded) and is the first thing duplicate
           detection checks: different identities are never duplicates, equal ones always are -
           a proof that outranks the 30-minute/5% heuristic (receipt-015 vs receipt-026).
```

```swift
ConflictState = .none | .flagged(kind: .order | .pace, detectedAt: Date)
```

A user may always save with `.flagged`: the entry shows the amber badge, and **any segment touching it is excluded from consumption math** (Trends footnotes the exclusion count). Resolution clears the flag via the edit screen.

### S2 duplicates (derived, with one persisted fact)

The S2 duplicate heuristic (SYNC.md) is **derived, never stored** – the same entry list always yields the same pairs, so every device computes identical numbers. While a pair is unresolved, **only one member counts** in consumption, month totals and every derived figure (the one a Merge would keep – deterministic: attachment wins, else earlier-created, else lower id). The one **persisted** fact is the user's decision:

```sql
duplicateResolution (id text pk, createdAt real, updatedAt real, deletedAt real,
                     countedEntryID text, excludedEntryID text, resolution text)
```

`resolution = keepBoth` means the user said there really were two purchases: the heuristic is suppressed for that pair and both count from then on. **Device-local** (deliberately NOT a synced table, like the sync cursor) – resolution sync is P4 work. A Merge needs no resolution row: it unions the loser's fields into the survivor and tombstones the loser, so the pair simply stops existing (and the loser lives in Recently deleted for the 30-day undo window – nothing is lost silently).

### The sync payload memory (the field-level merge's baseline)

The `Vehicle` field-level merge (SYNC.md S9) must know which fields *this device* actually changed, so each record's last-synced payload is remembered on the device. It is **device-local** (deliberately NOT a synced table, like the sync cursor) and holds a canonical JSON copy of the payload the device last pushed or pulled:

```sql
syncPayloadMemory (id text pk, payload text not null)
```

`id` is the synced record's id (UUIDs are globally unique, so the key carries no entityType). Written on every successful push or pull; read when a dirty `Vehicle` is diffed. **This table is why the merge survives a relaunch**: the in-memory alternative dies with the process, and the first sync after a relaunch then claims *every* field changed – a stale device can revert another device's newer edit (hard rule 13). It lives in the same protected database as the records it remembers.

## Derived: consumption

Never stored. Recomputed for a vehicle whenever any FillUp in range changes.

```
SEGMENT    Between consecutive isFull fill-ups (conflict-free, same fuelKind family;
           the families are combustion / electric / adBlue - an AdBlue fill never opens,
           closes or feeds a fuel segment):
             km     = odo(close) − odo(open)
             liters = Σ volume of every fill after open, up to and including close
             per100 = liters / km × 100
TANK-LEVEL (v1.x refinement) tankLevelAfterPct + tankCapacityL lets a segment close on a
           non-full fill: liters_adjusted = Σ volume + (levelOpen − levelClose)/100 × capacity.
           Gated on tankCapacityL being set; falls back to full-to-full otherwise.
HEADLINE   headline(segments, window = 90 days, floor = 3):
             take segments closing within `window` of today
             if count < floor: take the `floor` most recent segments overall (window extends)
             value = Σ liters / Σ km × 100        // distance-weighted, not mean of per100s
             label = honest span: "last 3 months" / "last 5 months" / "first estimate · N fill cycles"
LIFETIME   Σ liters / Σ km over all conflict-free segments – secondary stat.
ANOMALY    rolling (trailing 90 days) vs the SEASONALLY-ALIGNED baseline: the same-length window
           one year (365 days) earlier, drawn from the trailing 12 months – NOT month-over-month
           (a winter rise is only an anomaly if it exceeds last winter; docs/VISION.md). Fires
           when rolling ≥ baseline × (1 + minimumRelativeDrift = 0.12), sustained: the trailing
           30 days must be elevated too, so a recovering drift stays quiet. Segment floor of 3 per
           window (the anomaly does NOT extend its window to reach the floor – that would mix
           seasons); a missing seasonally-aligned baseline yields NOTHING, never a guess. The
           verdict is derived, never stored (hard rule 2): recompute is deterministic per
           (segments, asOf). Dismissible per cause = (metric, evaluation month), the reason kept as
           data (AnomalyDismissal: cause, reason, dismissedAt – the ReminderLifecycle precedent);
           a dismissed cause stays quiet across recomputes and a different cause still fires.
           Thresholds tunable, seasonality-aware – J9.
EV         same structure: segments between charges with known SoC, or simple kWh/100km over
           sessions when odometer deltas exist; €/100km = window cost / window km (the household
           comparison needs nothing extra).
COST/KM    all-in: Σ homeAmount of ALL entry types in window / km in window.
           Its honest label follows the same rule as the headline: the span the
           km data actually covers (never the full window when the data is
           younger) - "last 3 months" over a full window, "last month" over two
           weeks of readings.
```


### AdBlue (added 2026-08-30, product owner)

**AdBlue is logged as a fill-up and is never a fuel.** Diesel drivers buy it at the pump, in
litres, at a price per litre, with an odometer reading and a receipt - every property of a
`FillUp` - and the question they ask is a consumption question ("how much AdBlue does this car
use?"). So it is `FuelKind.adBlue`, not an `Expense` category. What keeps it out of the fuel
math is structural, not a flag:

- **Its own family.** `FuelKind.family` is `combustion / electric / adBlue`. A segment never
  spans families, so no AdBlue litre can reach L/100 km, the headline, the lifetime average, the
  anomaly engine or the D1-D4 vectors. `isFull` is stored but meaningless for AdBlue (the tank
  is topped up, not filled) and is ignored by every algorithm.
- **Its own metric.** `ADBLUE RATE = Σ volume of AdBlue fills except the last ÷ (odo(last) −
  odo(first))`, in **L / 1000 km**, distance-weighted over the car's lifetime - never full-to-full,
  because AdBlue fills are not full. Needs ≥ 2 AdBlue fills with odometers, else unavailable and
  shown as `–` (never estimated, the tire-mileage rule). Rendered in Trends as one small tile
  only when the car has ≥ 2 AdBlue fills; absent otherwise.
- **Its money is car money.** AdBlue spend counts wherever fuel spend counts - monthly totals,
  cost/km, the J13 dossier - and never in litres.
- **Offer set.** `Vehicle.fuelKinds` may contain `.adBlue` only alongside `.diesel` (invariant,
  enforced on AddVehicle and Vehicle detail; CHECK 4). The catalog offers it for diesel cars with
  SCR, i.e. Euro 6 / 2015 onward, as a default the user may remove (hard rule 13). On a
  `[.diesel, .adBlue]` car the Confirm fuel row shows two chips - a real choice, per the
  `DESIGN.md` input rule.
- **On a receipt.** A diesel receipt carrying an AdBlue line is a **mixed receipt** whose extra
  line becomes a second `FillUp(.adBlue)` in the same purchase group - not an Expense - and the
  fuel line is still the diesel line (CHECK 3 applies to each fill against its own line).
  **An AdBlue line is never the fuel line**: the extractor must not select it for a diesel car's
  fill even when its litres × price cross-check locks (`EXTRACTION.md` → AdBlue). A standalone
  AdBlue purchase (a 10 L can at a shop) is a plain `FillUp(.adBlue)` with `provenance` as usual.
- **Import.** Sources that carry AdBlue (Spritmonitor, MFM's "AdBlue" fuel type where present)
  map to `.adBlue`; unknown sources leave it as the user's manual re-kind. Never guessed.
- **Payload contract.** Adding the enum value is **additive** in `fillUp.schema.json` (registry
  bump, no `minSchemaVersion` change, no transform); old clients that pull an `.adBlue` fill
  treat the unknown kind per the SYNC.md unknown-value rule - kept, displayed as its raw string,
  never dropped (hard rule 8).

### Recalculation on edit (normative)

Any change to any FillUp of a vehicle (create, edit, delete, restore, sync-merge) triggers a **full recompute of that vehicle's segment list** – no surgical invalidation. Rationale: it's a linear pass (sub-ms at realistic history sizes) and immune to the non-local effects edits have – toggling `isFull` splits or merges segments, a date edit can move a fill into a different segment, an odometer edit changes two segments (a full fill is a boundary). Correct-by-construction beats clever caching here.

- Derived values live in memory only; recompute runs synchronously on save and after every sync merge batch.
- UI reacts immediately: the Home headline digit-rolls if it changed; the edit screen confirms with the delta ("Consumption updated: 6.9 → 6.8 L/100km").
- **No re-firing of past events:** anomaly `.attention` transitions and reminder threshold notifications never fire from historical edits – state re-evaluates silently.
- Sync convergence is free: stats are a deterministic pure function of the entry list, so every device recomputes to identical values; no derived data ever syncs.

Reference implementation and test vectors: the four-drivers simulation (`Spike/` + walkthrough artifact). D1–D4 outputs are the golden values for unit tests. Add edit-cases to the golden set: volume edit shifting the headline, `isFull` toggle splitting/merging segments, date edit re-ordering a fill into another segment.

## Backup format (portable, versioned)

One archive; inner structure:

```
manifest.json   { schemaVersion: 1, scope: "vehicle" | "account", vehicleIds: [...],
                  exportedAt, appVersion, vehicleCount, entryCount,
                  passphraseProtected? }              // always readable (restore UI)
data.json       { vehicles: [...], entries: [...], reminders: [...], stations: [...],
                  tariffs: [...], attachments: [...] }
                // exact shapes above, tombstones included; enums as strings; dates ISO-8601 UTC
attachments/    content-addressed blobs (sha256 filename) referenced by Attachment.file
```

Field notes (clarifications that implementations must match, decided 2026-08-27, P5.5a):

- **`manifest.json` is always plain JSON**, even when `data.json` and the blobs are
  passphrase-protected - the restore UI opens it first, before it knows whether
  the archive is sealed. `passphraseProtected` (optional, absent = false) is the
  flag the reader branches on; it never lives anywhere but the manifest.
- **`entries` is the one mixed-type array**, so each element carries the sync
  envelope's discriminator - `{ entityType, schemaVersion, payload }` with the
  four entry types. The other arrays hold raw entity payloads (their type is the
  array name). Every payload is exactly the sync payload shape (`PayloadCodec`),
  decimals as strings, dates ISO-8601 UTC - **there is one encoder for wire and
  archive**, never a second spelling.
- **`attachments` carries the attachment RECORDS** (references, tombstones
  included); the blob *bytes* live under `attachments/<sha256>` in the archive
  directory. An attachment whose bytes the exporting device no longer holds is
  exported as a reference without a blob file - it lazy-fetches on import,
  exactly like a synced attachment.
- **Reader validation, whole or nothing.** Every payload is checked against the
  registered JSON Schema (the files bundled with the app under
  `Schemas/v<N>/`, kept byte-identical to `docs/schemas/v<N>/`) and then
  typed-decoded through `PayloadCodec`; every blob present must hash to its
  content address. Only after ALL of that passes do the rows commit, in one
  transaction, so a truncated/corrupt/schema-failing archive imports nothing and
  leaves the repository as it was.
- **Atomic writes.** Every archive file is written temp-file-then-rename (the
  `ConfigCache` discipline) and the app-owned files carry the same
  `isExcludedFromBackup` + Data Protection class.
- **Blob files when protected** are individually AES-GCM sealed (each self-
  contained with its salt); `manifest.json` is never sealed. Key derivation:
  PBKDF2-SHA256, 100 000 iterations, 16-byte salt, 32-byte key (docs/SECURITY.md).

### Payload schemas (the machine-checkable contract)

The entity shapes above are not only prose. Each is published as a JSON Schema under `docs/schemas/v<N>/<entityType>.schema.json`, generated from the domain model and committed. That artifact is the contract three consumers share: the iOS client validates what it encodes, the backend validates what it stores (registered in `payload_schemas` – see `SYNC.md` → "Payload contract and versioning"), and the fixture corpus under `docs/fixtures/payloads/v<N>/` proves both agree. A new entity without a registered schema fails the build; a schema change without a version bump and an upcaster fails the migration tests.

### Scope: a user-held export is PER CAR (decided 2026-08-27)

A user exporting their data is exporting **one car** – its `Vehicle`, that car's entries of every
type, its reminders and tariffs, the stations those entries reference, the matching attachments,
and **the tombstones for all of it**. Whole-account archives still exist for backend snapshots and
the F7 restore path; they are not what the export button produces.

**So `manifest.json` declares its `scope`, and a reader must branch on it.** This is the same
failure the catalog wire had before P6.12: a consumer that cannot tell *"here is everything"* from
*"here is a part"* will treat a part as everything – and here that means importing one car's
archive as a full restore, leaving a garage that looks correct and is silently missing every other
car. The scope marker is **mandatory on every archive**, never inferred from `vehicleCount == 1`
(a one-car user's full account and a one-car export are indistinguishable by count).

Consequences that follow from per-car scope:

- **Import lands as a car**, either a new one or merged into a chosen existing car – the user
  decides which, and is told which before it happens (hard rule 13).
- **Merging into a car that already has entries runs the S2 duplicate heuristic**, and conflicts
  are flagged where the data lives, never dropped (hard rule 8, `SYNC.md` S2).
- **Money needs nothing extra**: every `Money` carries its own rate snapshot, so a car's history is
  self-contained and re-imports at the same numbers on a device with no rate cache (hard rule 3).
- **A per-car archive is not a backup of the account.** Anywhere the UI could be read as "your data
  is safe", it must say which car.

Rules: additive schema evolution only (new optional fields); a `schemaVersion` bump requires a migrator both on iOS and (later) Android, plus a declarative server transform when the change is mechanical; the same format serves user-held export, backend backup snapshots, and the future Android bridge. Protection (per the signed-off stance in `SYNC.md`): server-side snapshots live under the backend's at-rest encryption; a user-held export can optionally be passphrase-protected (AES) at export time – no user-held key is ever *required*.

## Backend (C# / PostgreSQL) – the sync hub

The backend stores the account's data as an ordered stream of opaque *records* (entity payloads in the exact shapes above) and synchronizes them across the account's devices. It never interprets domain content – the domain schema evolves without server deployments. Full protocol, server tables (`accounts`, `devices`, `records`, `blobs`, `llm_usage`), merge rules, and offline behavior: **`SYNC.md`**. Backups and the F7 restore path are snapshots of the record stream in the backup format below – not a separate pipeline.

## Reference data (backend-served, read-only, public)

Two datasets the backend curates and every client consumes. Both are **unauthenticated, aggressively cacheable** (CDN-able, ETag) – they must work for no-account users and add zero coupling to the sync stream.

### Exchange rates

```sql
exchange_rates (id bigint identity primary key, date date, base char(3), quote char(3),
                rate numeric(18,8), source text, fetched_at timestamptz, deleted_at timestamptz,
                unique (date, base, quote) where deleted_at is null)
```

`deleted_at` (null = live) and the surrogate `id` key are the correction-path machinery
(migration 009): a soft-deleted row stays physically but frees its `(date, base, quote)` slot, so
a re-fetch inserts a corrected row instead of rewriting the old one. Append-only holds for every
path except that documented correction.

- **Updated by** a daily background job (ASP.NET hosted service, ~17:00 CET after ECB publishes): ECB reference rates for the majors, plus a CIS source (CBR/NBK or a commercial feed) for RUB/KZT/AMD/GEL/BYN – the gap ECB left. Weekends/holidays carry the last published rate forward, stored per-date so `rateDate` lookups are exact. Manual correction path for a bad feed day (soft-delete + re-fetch); rows are append-only otherwise – snapshots in entries mean a correction never rewrites user history.
- **Served as** `GET /rates?date=2026-08-21&base=EUR` → all quotes for that date (one small JSON, cache-forever for past dates), and `GET /rates/pack?from=&to=` → a bulk range for the device's rolling cache and the app-bundle seed pack.
- **Fallback:** the client can hit ECB's public feed directly if our backend is down (majors only); CIS currencies wait for the backend – queued as rate-pending either way, so nothing blocks.

### Fuel price bands (the extraction disambiguator)

```sql
fuel_price_bands (country char(2), currency char(3), fuel_kind text, period_start date,
                  low numeric(10,3), high numeric(10,3), source text, updated_at timestamptz,
                  primary key (country, currency, fuel_kind, period_start))
```

A coarse plausible range for **price per litre**, per country, currency, fuel kind and
period. It exists for one job: **deciding which of two numbers on a receipt is the price
and which is the volume.** It is not a price feed, is never shown as a market rate, and is
never used to reject a fill-up.

**Why it is needed.** Receipts print the fuel line as an unlabelled product, and the two
operand orders are both in the wild:

```
40 л X 195.00        quantity first, unit marked      (ИП Гридяева)
62.89*66.810л        price first, unit marked         (Самаранефтепродукт)
205.00*20            price first, NOTHING marked      (Крым Оил)
43.61 X 99.40        quantity first, nothing marked   (ЛУКОЙЛ)
```

`volume x unitPrice = amount` is symmetric, so **CHECK 3 cannot detect a swapped pair** –
it validates the product, never the assignment. A parser that guesses wrong stores 99.4 L
at 43.61 instead of 43.61 L at 99.40 and computes consumption wrong by 2.3x with every
arithmetic check green. That is the failure this table prevents, and nothing else in the
schema can.

**Resolution ladder**, highest confidence first. The first rule that decides, wins:

1. **A labelled column.** Some printers state it (`Цена за ед. | Кол. | Сумма`). Believe it.
2. **The unit marker's position** – `л`/`L`/`gal` attached to an operand names the volume.
3. **The user's own history**: median `unitPrice` of the last ~10 fill-ups for that vehicle
   in that currency; accept the candidate within roughly +/-60% of it. Preferred over rule 4
   because it needs no network (hard rule 1), tracks inflation, the user's usual grade and
   their usual stations automatically, and is personal rather than national.
4. **This table**, as the cold-start fallback – the first fill ever, or a new country. Pick
   the candidate that falls inside the band; if both do or neither does, do not guess.
5. **Undecided.** Leave the fields empty and let the user type them. An empty field the user
   fills is a far better outcome than a confident wrong one.

**Keyed by all four of country, currency, fuel kind and period, because each one is load-bearing:**

- **Fuel kind** – LPG runs roughly a third of petrol (a real fixture reads 23.99 RUB/L). A
  petrol band rejects the correct answer for an LPG fill.
- **Period** – the corpus spans 48.80 RUB/L (2022) to 450 (2026). Bands are matched against
  the **receipt's own date**, never today's, or every imported backlog misreads.
- **Currency/country** – 1.869 EUR/L and 205 RUB/L are both ordinary.

**Bands are wide and soft on purpose.** They rank candidates; they never veto. A genuine
outlier must still save: the corpus contains AI-100 at 450 RUB/L during a regional shortage,
which any "sensible" band would have called impossible. If a value sits outside every band,
that is not an error state – at most it is a quiet hint, never a block (`ERRORS.md`).

- **Served as** `GET /reference/fuel-price-bands` (public, ETag, CDN-cacheable), and shipped
  as a bundled seed pack so day-one offline capture has a fallback. Rides the existing
  reference-pack mechanism (`ConfigDocument.ReferencePacks`, `CONFIG.md`), so it updates
  without an App Store release.
- **Curated server-side**, coarsely and infrequently – quarterly is enough for a band that
  only has to separate 30 from 100. Precision here is worthless; being wrong by a factor of
  three is what matters.
- **`SYNC.md` → Reference data applies unchanged**: a downloaded pack never overwrites a value
  the user has edited.

**Hard rule 13 governs every field this ladder produces.** Whatever the ladder decides is a
**default input, never a fact**: shown on the Confirm screen already editable, editable again
afterwards on Edit entry, and once the user changes it, it is theirs permanently – no
re-scan, later curation, improved parser or pack update may overwrite it. The extraction
logic is expected to keep improving; that improvement may never reach back and rewrite a
number a human corrected.

### Feedback intake

`POST /feedback { category: feature|problem|other, text, appVersion, deviceModel?, replyTo? }` – the About screen's form. Unauthenticated allowed (no-account users can complain too); account id attached when signed in; `deviceModel`/`appVersion` only with the user's toggle on, never log content. Stored in a plain `feedback` table (id, account_id null, category, text, meta jsonb, created_at); rate-limited per device. This is the roadmap's input channel – counts of "model not found" catalog misses land here too.

### Vehicle catalog

Base dictionary of makes/models with the parameters that matter to us – exactly the fields the Add-car screen wants pre-filled:

```sql
vehicle_catalog (id uuid pk, make text, model text, generation text, years int4range,
                 powertrain text, fuel_kinds text[], tank_capacity_l numeric,
                 battery_capacity_kwh numeric, pack_version int)
```

- **`fuel_kinds` here is an OFFER SET, not the car's fuel** (clarified 2026-08-23, after P1.5 showed why it matters). The catalog's `fuel_kinds` lists what the **model line** is sold with – `V60 → [petrol95, diesel]` means "offered as petrol *or* diesel". `Vehicle.fuelKinds` means something different: what **this one car** accepts, which is normally a single kind. Genuinely multi-fuel cars exist (petrol + LPG bi-fuel, a PHEV taking petrol + electricity), and that is the case the plural is for.
  - So Add car must present the catalog list as **options to choose from, defaulting to one**, and must never copy the whole set onto the `Vehicle`. Copying it wholesale creates a car that claims to accept both petrol and diesel, which no car does.
  - It is not a cosmetic error. `Vehicle.fuelKinds` drives the parser vocabulary (below), the fuel chips on the confirm screens, and – per `DESIGN.md` → entry card content – whether the fuel kind is printed on every row in the log. A car wrongly holding two kinds shows "95" on every entry forever, which is exactly the noise that rule exists to remove.
- **Why it matters:** typing "Volvo V60" pre-fills tank capacity 71 L (→ partial-fill math + OCR volume sanity check), battery size, fuel kinds (→ parser vocabulary) – the "Improves accuracy" section fills itself. Catalog values are *suggestions* written into the Vehicle row; the user can always override, and no Vehicle ever references the catalog by id (decoupled – a catalog correction never mutates user garages).
- **Scope discipline:** base list only – top ~500 models covering the EU + CIS fleet majority (VW/Toyota/Renault/Skoda/Volvo/Lada/Kia/Hyundai/BYD…), curated from open datasets, extended by demand ("model not found" search misses are the roadmap, logged as counts only). Not a VIN decoder, not a spec encyclopedia.
- **Served as** versioned packs: `GET /catalog?since_version=12` → delta or full pack (a few hundred KB JSON), cached on device at `Application Support/Tankbook/catalog.cache.json`, seed pack in the app bundle so Add-car autocomplete works on day one offline. The `pack_version` bumps on curation; clients check occasionally, never at launch-blocking time.
- **The server is the master copy.** Curation happens server-side, and where a downloaded pack overlaps the cached or bundled one, the server's values replace them – that is the entire point of curating. Full protocol, layering and failure behaviour: `SYNC.md` → Reference data; the (invisible) failure states: `ERRORS.md` → Vehicle catalog updates.
- **"Master" governs the catalog, never the garage.** Because catalog values are copied into the `Vehicle` row and no `Vehicle` references a catalog id, a corrected pack changes what the *next* car pre-fills and **never rewrites a car already saved** – including a figure the user typed over. A user's override is permanent. This is the load-bearing consequence of the decoupling above, so it is stated twice on purpose.

## Import mapping (launch importers)

| Source | Format | Notable mappings |
|---|---|---|
| My Fuel Manager | **CSV, `;`-delimited, header on line 2** (real export committed at `Spike/ImportFixtures/mfm/`, parse output at `Spike/ImportFixtures/mfm/parsed.json`) | Per-file upload. `fuel.csv` → `FillUp` (**no unit-price column - price/L is derived**); `costs.csv` → `ServiceRecord`/`Expense`; `vehicles.csv` → `Vehicle`; `incomes.csv` and `reminders.csv` are recognised but **unmapped in v1** (accepted, yield nothing - income is out of scope and there is no reminder mapping yet). `Tank status after fillup` (`F`/`P`) + `%` → `tankLevelAfterPct` and the full-tank flag; `Fuel` is a **numeric code, not a name**; dates are `M/D/YYYY` (**ambiguous - the F6 question**); `Currency` is `USD` on every row regardless of where fuel was bought, so it is a default the user corrects (hard rule 13) |
| Fuelio *(deferred, P5.4b)* | CSV | fill-ups, costs, vehicles; units per file header |
| Drivvo | CSV | expenses + income (income → skip in v1, warn) |
| Fuelly / aCar | CSV/XML | service logs map to ServiceRecord with single item |
| Spritmonitor | CSV | bi-fuel rows → separate FillUps by fuelKind |
| CarScope | CSV | closest schema to ours |

Import rules (F6): ambiguity (units/currency) asks once per file; unparseable rows import partially with a review list; `provenance = .import(source)` on every row; conflicts flagged, not dropped.

### MFM mapping, written from the real export (P5.4)

The parser runs server-side (`POST /import/parse`, `docs/API.md`). These are the decisions the real
file forced - each one is a documented mapping, never a silent guess:

- **Fuel is a bitmask code, not a name.** Per-fill `Fuel` is `1` (petrol) or `2` (diesel); the
  vehicle's fuel field is the same bitmask zero-padded (`00100001` = petrol, `00100003` =
  petrol+diesel). Petrol maps to `petrol95` as a **default the user corrects** - the octane is not
  in the file (hard rule 13). An unknown code lands the row in `unparsed` (`unknown_fuel_code`).
- **Odometer is exported as a number with a fractional part** (the fixture carries a `3.22` row
  alongside the `9` and `11436` typo rows). Tankbook stores whole km, so a fractional reading
  rounds to the nearest kilometre - a format mapping, not a repair: `3.22` still reads 3 and still
  lies off the car's timeline, exactly where the preview's derived-consumption figure catches it
  (F6a). The `9` and `11436` are integers and pass through untouched.
- **`costs.csv` finance categories**: `WORK` → `ServiceRecord(.repair)`, `Diagnostic` →
  `.inspection`, `Oil` → `.oil`, `Washing` → `.wash`; `Replacement parts` → `Expense(.parts)`,
  `Parking` → `Expense(.parking)`. Each `ServiceRecord` carries a single item (title = the note,
  cost = the row total). An unknown category lands the row in `unparsed`
  (`unknown_finance_category`). MFM exports an unrecorded cost odometer as `0`, which maps to
  `null` (the field is optional off a fill-up) rather than a nonsense zero reading.
- **`incomes.csv` / `reminders.csv` are accepted and yield nothing**: income is out of scope in v1
  and there is no reminder mapping yet. The response reports them via an `outOfScope` ambiguity
  with the skipped row count, so the client can say what was skipped.
- **Unit price is derived** (`Total price` ÷ `Fillup volume`, rounded to 6 dp) - the format has no
  unit-price column.
- **Date ambiguity** (`M/D/YYYY` vs `D/M/YYYY`) is returned as an ambiguity with the count of rows
  whose day is also ≤ 12 (215 of the 513 fuel rows); candidates carry the M/D reading and the
  client flips the counted rows if the user answers D/M.
- The **8.222 L/100km acceptance number is the Swift consumption engine's**, computed from
  `parsed.json` (rolling 90 days, floor 3, full-tank segments) - it is **not** a backend assertion,
  and the backend does not reimplement consumption.

## Export formats (PJ.36, PJ.38)

`VISION.md`'s "one-tap CSV/JSON export - always free" is two lanes, both local-first (hard rule 1):

- **"Export everything" (Settings, PJ.36)** builds the **whole-account archive** with the same
  writer the per-car export uses, declared `scope: "account"`: every vehicle - live or tombstoned -
  every entry of every type, reminders, stations, tariffs, the matching attachments and every blob
  the device still holds. It is the F7 restore stream's shape in a hand-off. The local importer
  still refuses `.account` scope on commit (P5.5a's guard); the share sheet hands the directory to
  the user.
- **Per-car CSV (Vehicle detail, PJ.38)** writes four files - `fill-ups.csv`, `charge-sessions.csv`,
  `service.csv`, `expenses.csv` - as **flat rows**: one row per entry, tombstoned rows INCLUDED (a
  non-empty `deletedAt` marks a tombstone still inside the 30-day undo window - hard rule 8). The
  CSVs ship inside the per-car archive directory AND as their own share items.

Column rules (the bytes are pinned by a golden-fixture test, so a rename or a date-format change is
a visible diff):

- **Field names are SCHEMA.md's exactly** - the shared envelope columns
  `id, vehicleId, date, odometer, amount, currency, homeAmount, homeCurrency, rate, rateDate,
  deletedAt, note`, then the type's own fields (`volumeL, unitPrice, fuelKind, fuelGrade, isFull,
  tankLevelAfterPct, stationId, crossCheck` for a fill-up; `energyKWh, unitPrice, chargeType,
  provider, tariffId, durationMin, socStartPct, socEndPct` for a charge; `vendor` for a service;
  `category, title` for an expense).
- **Money is a PAIR (hard rule 3)**: `amount` + `currency` (as paid) and `homeAmount` +
  `homeCurrency` (converted) always ride together, with the `rate`/`rateDate` snapshot. Amounts
  render with the currency's minor units (289.50, never 289.5); the rate keeps its full precision.
- **Dates are ISO-8601 in UTC** (`2026-08-22`), matching the archive's UTC convention - an export
  never depends on the device's timezone.
- **RFC 4180 quoting**: a field containing a comma, quote or newline is quoted.

## Open questions

1. **CNG has no volume unit.** `FuelKind` includes `.cng`, but `VolumeUnit` is
   `l / galUS / galUK` only - and CNG is sold by the **cubic metre**, not the litre. A real
   receipt states the convention itself: `1 ед.=1 литр для нефтепродуктов/СУГ`, `1 ед.=1 м3
   для КПГ` (`Spike/ReceiptSpike/fixtures/receipts/receipt-016-...`). So a CNG fill cannot
   currently be recorded in its own unit, and consumption for a CNG vehicle would be computed
   against the wrong dimension. Adding `.m3` touches a persisted enum, the consumption engine's
   unit handling and the display formatters, so it is a deliberate change, not a quick patch -
   flagged for P3/P5 rather than done in passing. Until then, treat CNG as unsupported rather
   than silently storing m3 as litres.

Everything else is decided:

1. **Persistence layer** – decided (Aug 23, 2026): **GRDB**. Full SQL and explicit migrations for the sync client's `syncState`/SCN bookkeeping and the segment-recompute queries; GRDB's observation drives SwiftUI. SwiftData rejected: CloudKit-oriented sync hooks (we run our own engine), young, weaker background-access control.
2. ~~Blob placement~~ – decided: S3-compatible object storage with presigned URLs (`SYNC.md`, blob pipeline).
3. ~~Attachment sync size policy~~ – decided: sync rendition ≤ 2048 px JPEG (~200–600 KB) + inline ~5 KB thumbnail in the record payload; full-res original stays on the capturing device. PDFs pass through, 10 MB cap (`SYNC.md`).
