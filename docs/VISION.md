# Tankbook – Product Vision

*iOS-first fuel & car-cost tracker · working title · August 2026*

A car cost log where you never fill in a form. Point the camera at the receipt or the pump – the app reads it, converts it, and files it. Fuel, charging, service, and everything your car costs you, in one private on-device history.

## 1 · The gap in the market

The category is crowded but stale. Fuelio, Drivvo, Fuelly, Spritmonitor, and Simply Auto all rely on hand-typed forms, dated UI, and ads. Recurring review complaints: intrusive ads, subscription fatigue, inaccurate consumption math, painful backup/export. Almost none of the consumer apps do receipt scanning – it exists only in fleet products like AUTOsist.

| App | Strength | Receipt OCR | EV support | Multi-currency | Top complaint |
|---|---|---|---|---|---|
| Fuelio | Fuel log, crowd gas prices, CarPlay, widgets | Yes (offline, receipts only) | Yes | Basic | Feature creep into Premium ("no reason to stay") |
| Drivvo | Broad expense + maintenance, EV kWh logs | No | Yes (bolted-on) | Basic | Huge ads / tiny font, export paywalled, wrong economy math |
| Fuelly | Community MPG benchmarks, 29k ratings | Photo attachments only, no OCR | No | No | Upsell nags, data loss after account migration, sporadic updates |
| Spritmonitor | Huge consumption dataset (DE), deepest EV analytics | Yes (invoice scan: date/price/qty) | Yes (AC/DC, partial charges) | Basic | Web-era UX, account-centric, DACH niche |
| CarScope (RU-origin, iOS) | Modern UX, importers from all majors | Photo attach only | No | No | Subscription rug-pull locked users to 1 vehicle |
| AUTOsist | Fleet workflows, receipt scan | Yes | No | No | Fleet pricing, not consumer |

**The opening (revised after reading current App Store listings):** the field is converging on us faster than the blog-level research suggested – Fuelio already ships offline receipt OCR and EV support, Drivvo ships EV kWh logs and importers. Receipt scanning alone is no longer the moat. What remains genuinely unowned: **pump-display and dashboard photo capture** (nobody does it), **the arithmetic cross-check as visible trust**, **true multi-currency with historical rates**, **the household EV-vs-petrol cost comparison**, and **no-account privacy** (every incumbent pushes logins, and Fuelly reviewers report losing years of data to forced account migration). The incumbents' shared weakness is also strategic: all of them are ratcheting features into subscriptions and burning goodwill (top reviews on all three complain about it) – a generous free tier with export always free is a differentiator by itself.

### CIS and Russian markets

The Russian-language segment splits into two camps, neither of which competes with us directly: **payment/station apps** (Яндекс Заправки, ЛУКОЙЛ, Газпромнефть АЗС, Татнефть – pay at the pump, find stations, loyalty perks) and **expense trackers** (Авто Расходы / Car Expenses, Car Expenses Pro, Мой Авто – manual-entry logs, dated UI, same form-filling model as the Western apps).

The standout opportunity was assumed to be **fiscal receipt QR codes** – every Russian receipt carries an FNS QR code, and the original reading was that "a QR scan yields 100%-accurate data with zero OCR".

**That was wrong, and the corpus disproved it on 2026-08-24.** The QR payload carries `t/s/fn/i/fp/n` – timestamp, total and three fiscal identifiers – and **nothing else**: no litres, no unit price, no fuel kind. The OFD document that does hold the line items is addressed by an opaque id that is **not derivable from the QR**, verified against two different OFDs, so there is no route from a scanned QR to a complete fill-up. Only **9 of 16** real receipts in the corpus even carry a decodable QR; a corporate fuel-card receipt has none by design.

So the QR is **not a capture path and not a differentiator on its own**. It is an **anchor that makes OCR trustworthy**, which is worth more than it sounds: picking the wrong total is the parser's worst failure mode, and on the corpus the QR's `s` fixes three of its four total errors outright (it had read the VAT line twice and a rounding line once). On the fourth – a mixed fuel-and-water receipt – the QR's grand total *disagreeing* with the extracted fuel line is precisely how mixedness is detected, which is what hard rule 4 needs. It also gives an exact date and, via `fn+i+fp`, a duplicate key.

Enrichment (fetching line items from the OFD) is **permanently deferred**, not pending: there is no route to unblock it. Details and the arithmetic: `Spike/ReceiptSpike/fixtures/fiscal/README.md`. Only Мой Авто touches QR at all – paywalled behind its top tier, inside an app whose recent reviews call it "completely broken" (hangs, broken sync, dead website). Detailed store-page profiles for all of these are in `COMPETITORS.md`. For CIS users this beats our OCR pipeline entirely – scan the QR, done – and it's nearly free to build. Constraint to plan around: App Store payment restrictions in Russia make subscriptions impractical there; the RuStore/regional strategy is a later decision, but the QR feature also serves the diaspora and travelers on the regular App Store.

## 2 · Vision and principles

> Logging a fill-up should take five seconds and zero typing. Your car's entire financial history lives on your phone, readable by you and no one else.

- **Capture beats forms.** Camera is the primary input; the form is the fallback, not the default.
- **Local-first, private, portable.** OCR and analytics run on-device; the local database is always authoritative and the app is fully usable with no account at all (single device, everything local). Optional sign-in with Apple ID or Google attaches a **neutral identity email** and turns on multi-device sync through our backend (`SYNC.md`) – which is also restore on a new phone or on Android later – plus the cloud-LLM fallback gateway. We store the account identifier, email, and the synced record stream (TLS + encrypted at rest, per the signed-off stance in `SYNC.md`) – no content analytics; images sent to the LLM fallback are processed transiently, never retained. No ads, no server-side analytics, and never a login wall (Fuelly's forced-login migration destroyed user data and trust – see COMPETITORS.md); if our servers are down, everything except LLM fallback and cross-device restore still works.
- **Powertrain-agnostic.** Petrol, diesel, hybrid, EV – one app, one history. EV charging is a first-class citizen, not a retrofit.
- **Borders don't break the log.** Fill up in Poland, pay in złoty, see it in your home currency at that day's rate – both amounts preserved.
- **Own your data.** One-tap CSV/JSON export – always free (Drivvo paywalls even paper reports, and its reviews resent it). Importers for Fuelio, Drivvo, and Spritmonitor formats are table stakes (Drivvo ships them too), but we need them to open the switching path.

## 3 · Do we need an LLM?

Short answer: **not on the primary path, yes as a thin layer**. The extraction problem splits into "read the pixels" (OCR) and "understand the fields" (semantics). Apple's stack now covers both on-device.

Pipeline:

1. **Capture** – VisionKit document camera, or photo of the pump display
2. **OCR** – Vision framework document recognition (on-device, free, offline)
3. **Parse** – deterministic rules: currency, decimals, `liters × price ≈ total` cross-check
4. ~~**Normalize** – Apple Foundation Models (on-device LLM) resolves ambiguity: "DIESEL B7", station name, fuel grade~~ – **cut 2026-08-25**: the on-device model does not support Russian, which is the corpus's language (§ "Why tier 2 was cut")
5. **Fallback** – cloud multimodal LLM (Haiku-class) only if confidence is low – opt-in, Pro feature

**Decision (amended 2026-08-25):** Apple-first hybrid, now **without** the Foundation Models step. On-device Vision plus the deterministic rules parser carry the primary path at zero marginal cost and full privacy; step 4 was cut because the on-device LLM has no Russian. The cloud LLM fallback handles crumpled thermal paper and glare-heavy pump displays – opt-in, clearly labeled, part of the paid tier so API costs are covered by revenue. The arithmetic cross-check gives a built-in confidence signal that competitors' "inaccurate calculations" complaints show they lack.

## 4 · Feature set

| Feature | Phase | Notes |
|---|---|---|
| Multi-vehicle garage | MVP | Multiple cars per account from day one – vehicle switcher, per-vehicle stats and history, all tied to the one identity/backup. Every competitor gates this behind Pro; CarScope even revoked it retroactively and paid for it in reviews. |
| Fill-up log (manual quick-form) | MVP | Odometer, volume, price, station, fuel type/quality. Partial fills via optional tank-level-after-fillup (% or liters) instead of a bare flag – the My Fuel Manager approach, it keeps consumption computable between partials. Smart defaults per favorite station (station, fuel type, quality pre-filled from last visit). Show "+N km since last" beside the odometer field as a live typo check. |
| Receipt scan | MVP | The hero feature. On-device pipeline above; user confirms pre-filled card. |
| Pump display photo | MVP | For stations without receipts. Reads liters / price / total off the pump. |
| Fiscal QR scan (RU/KZ receipts) | MVP | FNS/ОФД QR codes carry the full purchase machine-readable – 100% accuracy, no OCR needed. Cheap to build, unowned in the CIS market. |
| Multi-currency | MVP | Each vehicle has a **default (home) currency**; any entry can be logged in any currency and stores both the original amount and the conversion into the vehicle's currency at that date's historical rate (ECB + supplementary feed for RUB/CIS currencies). Rates snapshot at entry time – history never shifts. All stats and trends render in the vehicle's currency. |
| Localization: English + Russian | MVP | Full RU + EN from day one – UI, App Store listing, receipt-parser vocabularies (already multilingual in the spike). Architecture rule: every string goes through String Catalogs from the first commit; no hardcoded text, so adding languages later is translation work, not engineering. |
| Trends dashboard | MVP | L/100km (or MPG), cost/km, price-per-liter over time, monthly spend. |
| Import from Fuelio / Drivvo / Fuelly (aCar) / Spritmonitor / CarScope / My Fuel Manager | MVP | CSV/backup importers. Table stakes (Drivvo and CarScope import from everyone), and My Fuel Manager's export doubles as our first real-data test fixture. |
| Service & maintenance records | v1.x | Repairs, parts, tires, insurance, taxes – with receipt scan and photo attachments. |
| Reminders | v1.x | By date or odometer: oil, inspection (TÜV/MOT), insurance, tire swap. |
| EV charging sessions | v1.x | kWh, tariff, home vs public, session screenshots OCR'd from charging apps. |
| Widgets, Shortcuts, Siri | v1.x | "Log fill-up" from lock screen; Shortcut fires when CarPlay disconnects near a gas station. |
| Multi-device sync (optional sign-in, Apple ID / Google) | v1.x | Our backend as the sync hub (`SYNC.md`): sign in on any device, the full garage follows. Strictly optional – no login wall; without an account the app is fully functional on one device. The same identity meters the cloud-LLM fallback and yields backups/restore for free. |
| Family sharing (one car, two drivers) | v2 | Vehicle-scoped sharing over the same sync protocol; entries attributed per member; odometer validation handles out-of-order merges (F9a). |
| Anomaly insights | Later | "Consumption up 12% over 3 months – check tire pressure / air filter." |
| Document wallet | Later | Insurance card, registration, with expiry reminders. |
| Trip cost calculator | Later | "Berlin → Warsaw costs you ~€68 in this car at current prices." |
| Android app | Later | After iOS product-market fit. See platform strategy below. |

## 5 · Core user flows

### Flow A – The 5-second fill-up

1. **Open** – lock-screen widget or app; camera is one tap away
2. **Snap** – receipt or pump display; auto-crop, auto-shutter
3. **Confirm** – pre-filled card: 42.3 L · 1.679 €/L · €71.02 ✓. Odometer is the only manual field (or photo of the dash)
4. **Done** – haptic tick, updated consumption shown immediately: "6.8 L/100km – your best this year"

The confirm screen doubles as the trust-builder: every extracted field shows a confidence tint, and the `liters × price = total` check runs live. Editing a field is one tap. The receipt photo is kept, attached to the entry – useful for expense reports.

### Flow B – Service visit

1. **Scan invoice** – multi-page workshop invoice via document camera
2. **Categorize** – on-device model suggests: "Oil service + brake pads front" → two line items
3. **Remind** – app proposes the next reminder: "Oil change in 15,000 km or 12 months?"

### Flow C – EV charge

1. **Screenshot** – share a charging-app receipt screenshot to the app (share extension)
2. **Extract** – kWh, duration, cost, provider – same OCR pipeline
3. **Compare** – home tariff entries logged by kWh × your electricity price; dashboard shows €/100km vs the household's petrol car

That last comparison – *your EV vs your petrol car, in real money per 100 km* – is a genuinely differentiating insight no mainstream competitor offers, and it matters to exactly the audience (mixed-powertrain households) growing fastest right now.

## 6 · Trends worth tracking

- **Consumption:** full-to-full correctness (partial fills merge into the next full segment – the math Drivvo gets wrong; tank-level entries refine it). The headline average is **time-based, not fill-based**: rolling 90 days of closed segments, because fill cadence varies wildly between users (1–2 full tanks/month vs small top-ups weekly). Floor: fewer than 3 segments in the window auto-extends it backward until 3, with the UI labeling the real span ("last 5 months"). Lifetime average is the secondary stat; anomalies compare the rolling value against the trailing-12-month (seasonally fair) baseline. Per-season and per-fuel-grade splits.
- **Money:** cost per km all-in (fuel + service + insurance), monthly burn, price-per-liter trend per station brand – "Shell costs you 4% more than Orlen for identical consumption."
- **Health signals:** consumption drift as an early-warning proxy; service cost trajectory by age/mileage; resale-relevant, exportable history.
- **EV specifics:** kWh/100km, home vs public charging mix, effective €/kWh, charging-curve cost efficiency by provider.

## 7 · Platform & tech strategy

- **iOS:** SwiftUI; persistence GRDB (decided, `SCHEMA.md`); sync client implementing the `SYNC.md` protocol against our backend (`API.md`); VisionKit + Vision for OCR. (Foundation Models normalization was **cut on 2026-08-25** – no Russian support; see the capability tiers.)

### Platform support and what it costs us

**Decided (Aug 2026): minimum iOS 18 – two versions back.** Note the numbering: Apple jumped 18 → 26, so the sequence is 17 → 18 → **26** (shipping now) → 27 (in beta). Two back from current is therefore iOS 18, not "iOS 24".

Device floor: **A12 – iPhone XR/XS and SE 2nd gen**, roughly a 2018 phone. That reach matters most exactly where our differentiators point: CIS markets, where handsets are held longer, and switchers from cheap Android trackers.

**Hard requirement: the iPhone 12 (A14) is supported.** It is the named reference device – any future proposal to raise the deployment target must be checked against it first. It sits comfortably above the A12 floor and runs both iOS 18 and iOS 26. Note what it does *not* get: with an A14 and 4 GB of RAM it is below the Apple Intelligence line, so it receives tiers 0 and 1 only. Our reference device having no on-device LLM is the clearest possible statement of why tier 0 carries the quality bar.

An earlier draft of this section set the floor at iOS 26 to get `RecognizeDocumentsRequest` (iOS 26.0) unconditionally. That was wrong and is recorded here so it is not re-proposed: we **already** tier capability at runtime because Foundation Models availability must be probed on every launch regardless of OS, so one more availability tier costs almost nothing – while raising the floor would have excluded A12 devices plus every capable-hardware user who has not upgraded. The Spike settles it empirically: its rules parser runs on `VNRecognizeTextRequest` (available since iOS 13) and already meets the accuracy bar, so nothing load-bearing lives above iOS 18.

### Capability tiers (the real architecture)

Every capture path degrades cleanly, and each tier is additive rather than required:

| Tier | Requires | Gives |
|---|---|---|
| **0 – the floor** | iOS 18, any supported device | `VNRecognizeTextRequest` + the deterministic rules parser + the arithmetic cross-check. This is the product's guaranteed quality bar |
| **1 – structured docs** | iOS 26+ | `RecognizeDocumentsRequest`: tables and document structure rather than raw text lines. Better multi-page invoices (J7) and awkward receipt layouts |
| **~~2 – on-device normalization~~** | ~~A17 Pro+ with 8 GB RAM, Apple Intelligence enabled, model downloaded~~ | **Cut 2026-08-25.** Foundation Models does not support Russian, and the app's primary corpus is Russian. See "Why tier 2 was cut" below |
| **3 – cloud fallback** | Pro tier, network, user opt-in | Hard images: crumpled thermal paper, glare-heavy pump displays, odd charging-app screenshots |

Tier 1 is a compile-time `if #available` plus a runtime availability probe; nothing above tier 0 may ever be a precondition for logging a fill-up.

#### Why tier 2 was cut (decided 2026-08-25, do not re-propose)

**The Foundation Models on-device LLM does not support Russian, and Russian is the language of
the corpus this feature existed to improve.**

The evidence, in the order it decides the question:

1. **The framework refuses to run on an unsupported device language.** `UnavailableReason` in the
   shipped iOS 26.5 SDK carries the case `unsupportedLanguageOrLocale`, alongside a
   `SystemLanguageModel.supportedLanguages: Set<Locale.Language>`. This is not a quality
   degradation on unsupported input – it is the model reporting itself unavailable.
2. **Russian is not in that set.** As of 26.1 the supported languages are English, Danish, Dutch,
   French, German, Italian, Norwegian, Portuguese, Spanish, Swedish, Turkish, Chinese
   (Simplified and Traditional), Japanese, Korean and Vietnamese. Russian is absent, with nothing
   announced. Kazakh likewise – and the corpus holds KZ receipts too.
3. **That lands precisely on our worst input.** The corpus is 32 RU/KZ receipts; receipts score
   **41.6%**, and every documented miss is a parsing bug on Cyrillic product lines. So tier 2
   would have been unavailable exactly where tier 0 is weakest, and available only where the
   parser already does best.

Note what is *not* the reason. **The EU is not a blocker** – Apple Intelligence reached the EU in
April 2025 with iOS 18.4; only some Siri features stayed withheld there. The constraint is
language, not jurisdiction, which is why "wait for the EU" would have been the wrong conclusion.

The consequence for the roadmap is that **tier 3 (the cloud LLM gateway) is now the only
normalization path for Russian receipts**, which raises its expected volume further than
consequence 2 below already anticipated. The path back to a re-open is narrow and specific:
Apple adding Russian to `supportedLanguages`. Nothing else changes this – not new hardware, not a
new OS version.

**The binding constraint is not the OS version – it is Apple Intelligence hardware.** The Foundation Models framework requires **A17 Pro or newer with 8 GB RAM**: iPhone 15 Pro/Pro Max, 16e/16/16 Plus/16 Pro/Pro Max, the 17 family, and iPhone Air. The plain **iPhone 15 and 15 Plus are excluded** (A16, 6 GB) despite running iOS 26 – a trap worth stating, since "iPhone 15" sounds new enough. Beyond hardware, the user must have Apple Intelligence enabled and the model downloaded, so availability must be checked at runtime, not assumed from the device.

Three consequences we design around:

1. **The deterministic parser is the product's floor, not a fallback.** For the majority of users – and for years – there is no on-device LLM. The Spike's rules parser plus the arithmetic cross-check must carry the accuracy bar alone; Foundation Models was framed as an enhancement on newer hardware, never a dependency. That framing is what let tier 2 be **cut** (above) without touching the product's floor: P2.8 would have shipped only if it *strictly improved* on rules-only, and it cannot even run on the Russian corpus.
2. **Cloud fallback matters more than first framed**, since on-device normalization is unavailable to most devices - and, after the tier 2 cut, to **every** Russian-language user. That raises expected `/extract` volume and therefore the real API cost behind the Pro tier – price it accordingly rather than assuming most work happens on-device for free.
3. **Runtime availability is a UI state, not an error.** Unsupported hardware, an unsupported language, Apple Intelligence off, or model still downloading all resolve to the same calm behaviour as F4: on-device results render immediately, low-confidence fields stay dimmed, and no upsell appears mid-capture.

**Form factors.** iPhone is the design target: capture happens standing at a pump. Screen widths run from **375 pt (SE 2nd/3rd gen, still supported)** to 440 pt (Pro Max), while our artboards are drawn at 390 pt – the dense screens (Trends tile grid, Service line items, the DIN numerals on Confirm) must be verified at 375 pt, and combined with Dynamic Type XL that is the real layout stressor rather than the wide end. **iPad ships as a scaled phone layout, not a bespoke iPad UI** – multi-device sync makes an iPad plausible as a review device, and a simple correct layout beats a broken ambitious one. **Apple Watch is out of scope** (no capture value). **CarPlay is a post-launch experiment, not a plan**: Apple does operate a fueling category, but the entitlement needs Apple's approval and our primary purpose is logging rather than finding or paying for fuel, so approval is genuinely uncertain – Fuelio having CarPlay is a reason to try, not a reason to promise.
- **Currency:** rates served by our backend's public `/rates` endpoint (daily job: ECB + a CIS source for RUB/KZT/AMD/GEL/BYN – see `SCHEMA.md` Reference data), cached ~2 years on device with an app-bundle seed pack; rates snapshotted per entry so history never shifts. The vehicle's default currency is the reporting currency for all its stats.
- **Localization:** English and Russian ship in v1. String Catalogs from the first commit, localized number/date formatting via the user's locale (comma decimals in RU), and pseudo-localization checks in CI so untranslated or clipped strings fail before release. **Russian correctness inside the strings** - case governance, real plural selection, the `Text(_: String)` blind spot - is governed by `docs/LOCALIZATION.md`, the single authority for RU phrasing written by the P5.3 pass.
- **Backend (three jobs):** a **C# / ASP.NET Core + PostgreSQL** service providing (1) **multi-device sync** – the account's data as an ordered record stream, one protocol serving iOS now and Android later (full design: `SYNC.md`; this replaces CloudKit as the sync engine – one sync system, not two), (2) **backups/restore** as snapshots of that same stream, and (3) the **LLM gateway** (API keys server-side; per-user quotas; images transient, never retained). Auth via Sign in with Apple or Google token verification; the account email is the neutral recovery identity. Hard rule learned from Мой Авто's dead servers and Fuelly's login migration: the app is **local-first** – no account means a fully working single-device app, and with the backend unreachable everything except sync and LLM fallback still works; the documented export format always remains in the user's own hands.
- **Android later:** keep the domain layer (models, consumption math, parsers) portable – either Kotlin Multiplatform from the start or a cleanly isolated Swift core to re-implement. Don't compromise the iOS experience for sharing; the parser rules and data schema are the truly reusable assets.
- **Monetization:** free tier fully usable – multiple vehicles (e.g. up to 3), on-device OCR, export always free; data hostage-taking and vehicle-count rug-pulls are the competitor sins we won't repeat (CarScope retroactively locked users to 1 vehicle and its reviews still bleed from it). Pro subscription or lifetime: unlimited vehicles/fleet, cloud OCR fallback, family sharing, document wallet, advanced insights.

## 8 · Risks and open questions

- **OCR trust:** if the first three scans misread, users revert to typing forever. Mitigation: confidence gating – never silently accept a low-confidence field; the arithmetic cross-check; ship the pump-photo path only when it clears ~95% on a test set of real photos.
- **Odometer friction:** the one field no receipt contains. Options: dash photo OCR, CarPlay/Bluetooth-disconnect prompts, or accepting one typed number per fill-up. Needs prototyping.
- **Crowd price data:** Fuelio's community prices are a moat we can't replicate at launch – decide whether to license a price API per region or skip prices-nearby entirely in v1 (recommended: skip).
- **Naming:** "Tankbook" is a working title; needs trademark and App Store search check ("fuel log", "car log", "tanken" localization angle for DACH).

---

**Next steps:** validate the OCR pipeline with a spike (50 real receipts + 20 pump photos through Vision framework), sketch the confirm-screen UI, and define the v1 data schema.

**Capture finding (2026-08-25): the odometer is often already in the frame.** A corpus receipt (`receipt-029`) was photographed lying on the car's instrument cluster, with the odometer and range legible beside it. That is not an accident of photography - the dashboard is the flat surface to hand when you get back in the car. It matters because **the odometer is the one field a fuel receipt never carries**, and the one J3 must otherwise ask for: a capture that read both would complete a fill-up from a single photo. Worth exploring as a deliberate capture pattern ("rest the receipt on the dash") rather than a curiosity - though it needs its own corpus, since exactly one fixture shows it today and cluster fonts are seven-segment or dot-matrix, closer to the pump-display problem than to receipts.

**OCR pipeline finding (2026-08-24, from the real corpus).** Recognition is not the hard part - Vision reads Russian thermal receipts at confidence 1.00, including labelled columns and glare. **Interpretation is.** Measured against 14 real receipts the parser scored 36.6% of fields, and every miss was a parser bug, not an OCR miss: the total-finder grabbing VAT or a rounding line, the fuel line versus a mixed receipt's grand total, and - most dangerous - **volume and unit price extracted the right way round only sometimes, with the arithmetic cross-check unable to tell**, because `a x b == b x a`. The disambiguation ladder and the curated price bands that fix it are specified in `SCHEMA.md` → Reference data → Fuel price bands. Two consequences for scope: budget P2 effort for parsing rather than recognition, and treat every extracted field as a **suggestion the user can correct at capture and afterwards** (hard rule 13) - the parser is expected to improve for years, and no improvement may rewrite a value a human has already fixed.
