# Tankbook – The Car Agent (v2, Pro)

*Artboards: `design/screens/v2/Agent*.dc.html`, canvas page "Agent (v2, Pro)". Single authority for the agentic chat: what it is, where it lives in the app, how it is built
without breaking the local-first and privacy rules, the tool catalogue, the safety framing for
diagnosis, and the accuracy gate. Companion to `VISION.md` (the Pro row), `JOURNEYS.md` (J14–J17,
F11–F12), `DESIGN.md` (the five-slot tab bar), `SCREENMAP.md` (the Ask nodes), `API.md`
(`/agent/turn`), `SECURITY.md` and `LOGGING.md` (what leaves the device and what is written down).
Written 2026-08-29 as a v2 design; nothing here is in the v1 launch list.*

## 1 · What it is, in one paragraph

A conversation surface – the **Ask** tab – where the user talks to their car's log: asks questions
over their own history, asks for reminders in plain language, hands over a workshop invoice and
gets it read and explained, and describes a symptom and gets a ranked, honest second opinion in
the context of *this* car. It is a **Pro** feature (product owner, 2026-08-29): it is the one
feature whose marginal cost is real money per use, and it is the reason the Pro tier exists
beyond cloud OCR. It never becomes the only door to anything – every action it can take stays one
tap away in the ordinary UI (hard rule 1, hard rule 15's spirit).

## 2 · The architecture: the phone is the agent, the cloud is a stateless model

The obvious build – a server-side assistant with the user's data in its context window – would
break three written promises at once: the server never interprets domain content (hard rule 9),
"no content analytics" (`VISION.md`), and local-first (hard rule 1). The build that keeps them:

- **The agent loop runs on the device.** `TankbookCore` owns an `AgentSession` that holds the
  conversation, decides which tools to call, calls them locally, and sends the model only what
  the current turn needs.
- **Tools are local functions over the repository.** Reads return structured data (the same
  types `HomeStats`, `TrendsStats`, `ReminderLifecycle` already produce). Writes return
  **drafts** – a pre-filled `ReminderFormView`, a pre-filled `ServiceEntryView`, a pre-filled
  Confirm sheet – and **never commit**. The user saves through the screen that already exists.
  This is hard rule 13 verbatim: the agent suggests, the user decides, and every value is
  editable at the moment it is offered and afterwards.
- **The model is reached through the gateway**, `POST /agent/turn`, a sibling of `/extract`:
  request = system frame + car profile + conversation + this turn's tool results; response =
  the model's text plus zero or more tool calls. The server is a **pure function**: it forwards
  to the provider, meters the account, stores nothing, and logs shape only (turn index, tool
  names, token counts, provider latency). Conversation memory lives on the device.
- **Numbers come from tools; prose comes from the model.** The UI renders every figure from the
  structured tool result – as the same `StatTile` and entry cards the rest of the app uses – and
  the model narrates around them. The model may not *state* a number the app did not compute.
  This is F6a's rule ("the preview is not a receipt") applied to chat: a hallucinated litre count
  is this feature's F2, and the only defence that works is structural, not a prompt instruction.
- **Every write is a Confirm.** "Remind me about the oil change in 15 000 km" produces the
  reminder form, filled in, with Save under the user's thumb – not a saved row and not a chat
  bubble saying "Done".

### 2.1 · The rule-9 exception this needs

`CLAUDE.md` hard rule 9 licenses one endpoint that reads domain meaning (`/import/parse`) and
says a second one needs its own decision written there. `/agent/turn` is that second decision,
with the same five properties, adapted:

1. **Pure function.** Returns text and tool-call requests; commits nothing; owns no user data.
2. **Stores nothing – unlike import, like extract.** No conversation, no car profile, no tool
   result is persisted server-side. The provider call is transient. (Import stores files for
   resumable review; there is nothing to resume here – the device holds the conversation.)
3. **Pro-metered, account-required.** The one feature in the app that requires sign-in, because
   the meter is per account (`llm_usage`) and the cost is per turn. This is stated in the Pro
   copy, never discovered through an error.
4. **Nothing is logged but shape.** Turn count, tool names, token counts, latency, error code.
   Never the question, the answer, a car, a station, an amount, a symptom (hard rule 12).
5. **It does not spread.** `/agent/turn` licenses conversational turns over the device's own
   tool results. It does not license server-side search, stats, or stored memory.

Two things the exception adds that import did not need: the **privacy policy sentence** ("When
you use Ask, the question, the car profile and the figures needed to answer are sent to our
model provider for that turn and are not stored") and the **per-conversation consent** – the
first turn in a session shows what will be sent, once, in plain words, and the car profile card
is visible in the thread so the user can see what the model knows.

### 2.2 · On-device models, re-checked each release

Foundation Models was cut on 2026-08-25 for lacking Russian (`VISION.md` → "Why tier 2 was
cut"). A Russian-capable on-device model would make the agent local-first and free, and the
architecture above does not care where the model runs – only `/agent/turn` changes. Re-check at
every iOS release; the tool catalogue and the numbers-from-tools rule stay identical.

## 3 · Where it lives: the Ask tab

**Decided 2026-08-29: the tab bar gains a fifth slot.** `Log · Trends · ● Capture · Ask · Garage`.
`DESIGN.md` → Layout & navigation carries the geometry; the reasoning:

- The agent must be reachable from every tab – "how much did the Volvo cost this year?" is a
  Trends question, "when did I last change tyres?" is a Garage question. A header button is
  per-screen and disappears on the other tabs; a fifth slot is one thumb-tap from anywhere,
  which is the same argument that put Capture in the centre.
- It is a task, not a setting. `DESIGN.md`'s rule against a fifth tab was about Settings ("the
  bar stays task-focused"); Ask is the most task-shaped thing in the app.
- The raised capture circle stays the front door. Ask sits to its right, glyph-and-label like
  the others, never raised, never accented – accent is meaning, not chrome (hard rule 5).
- **Everyone sees the tab.** A tab that appears only after paying reads as a rug-pull to
  everyone who did not (the CarScope lesson). Free users open Ask and see what it does, three
  example questions they can read, and the Pro card – the one place besides the car-limit sheet
  where Pro is offered (`ERRORS.md` rule: monetization in no error surface, never mid-capture;
  this is neither).
- The rejected alternative – a spark button in the Home header beside the gear, plus long-press
  on Capture – is kept on the canvas as a low-fi sketch (`design/screens/v2/AgentAltHeader.dc.html`). It costs no
  bar space but hides the feature on two of three tabs and makes Pro's headline feature a
  discoverable gesture.
- **RU label.** `Спросить` is 8 characters against `Ask`'s 3 – the exact shape that clipped in
  P6.13. It must be verified at Dynamic Type XL before the bar ships; `Чат` is the fallback
  label if it clips, and either is acceptable copy.

## 4 · Tool catalogue

All tools live in `TankbookCore/Agent/Tools/`, are pure over the repository, and return typed
results the UI can render without the model. A tool call is logged by name only.

**Read tools (v2.0)**

| Tool | Returns | Backs |
|---|---|---|
| `carProfile(vehicle)` | make, model, year, powertrain, fuel kinds, odometer, units, currency, catalog figures | every turn's context card |
| `spend(vehicle, range, byType?)` | totals in home currency, by month, by entry type; count of rate-pending entries | J14 |
| `consumption(vehicle)` | headline, lifetime, cost/km, window span, excluded count – from `ConsumptionEngine` | J14, J17 context |
| `entries(vehicle, range, type?, station?)` | the log rows, with attachments flagged | J14 |
| `lastService(vehicle, category?)` | most recent service record(s) with line items and odometer | J14, J17 |
| `reminders(vehicle, status?)` | open/attention/done reminders with due date/odometer | J14, J15 |
| `anomaly(vehicle)` | the `AnomalyEngine` verdict with rolling/baseline figures and drift | J17 context, J9 explain |
| `tireSets(vehicle)` | sets, mounted state, derived mileage (or "unknown", never estimated) | J14 |
| `stations(vehicle)` | favourites and known stations with average price per litre | J14 |

**Draft tools (v2.0) – return a draft, open a screen, never write**

| Tool | Opens | Rule |
|---|---|---|
| `draftReminder(title, category, dueDate?, dueOdometer?, recurrence?)` | `ReminderFormView` pre-filled | user saves; agent is told the outcome (saved / cancelled) as a tool result |
| `draftServiceEntry(items[], vendor?, date?, odometer?, attachment?)` | `ServiceEntryView` pre-filled | same; line items dimmed like OCR rows until confirmed |
| `draftFillUp(volume?, price?, total?, odometer?, station?)` | `ManualFillUpView` pre-filled | the third door (J3c, voice/text); cross-check locks as for a scan |
| `draftExpense(...)`, `draftNote(vehicle, text)` | `ExpenseEntryView`; a note on the car | same |

**Capture tools (v2.0)** – `captureInvoice()` opens the document camera and returns the
`InvoiceSplitter` result plus page attachments; `captureDashboard()` returns the photo for a
warning-light turn. Both feed the existing pipelines; the model reads the *result*, never the
raw image, unless the user opts the image into the tier-3 pass (the same consent as `/extract`).

**Explicitly not tools:** anything that writes without a screen; anything that fetches external
data (fuel prices, recalls) – v2.1 decisions, each needing its own line here.

## 5 · Diagnosis: the framing that makes it honest

J17 is the genuinely new capability and the one that can hurt someone. Rules:

- **Context first, visibly.** Every diagnosis turn opens with the car context card the tools
  produced (car, mileage, last relevant service, consumption drift). The user sees what the
  model was told.
- **Ranked causes, each with its evidence.** "Most likely / also possible / less likely", each
  naming the fact in the log that supports it ("brake pads were last done 41 000 km ago") or
  saying plainly that it rests on general knowledge of the model, not on the log.
- **Urgency triage is mandatory and comes from a fixed vocabulary**: `drive on · book this week
  · stop driving`. The model chooses, the UI renders it as a fixed row (amber for "book this
  week", the system-red dialog only for "stop driving" – hard rule 5). Safety-critical systems
  (brakes, steering, fuel smell, warning lights in red, smoke) escalate by rule in the system
  frame: the model may not talk someone out of a workshop visit.
- **Next steps are app actions**: draft a reminder, log the symptom as a note on the car,
  "questions to ask the workshop" as copyable text. Never a link to a parts shop.
- **It is a second opinion.** The screen says so once, at the top, in `inkSoft`: "Not a
  mechanic – a second opinion from your log." Not repeated per message; not a modal.

## 6 · Offline, quota, and the states that are not errors

Ask is the one screen that legitimately needs the network, like the LLM fallback. That makes
three states first-class rather than failures (`ERRORS.md` → Ask):

- **Offline**: the thread stays readable; the composer says "Ask needs a connection – your log
  works as always" and the three example questions turn into taps that open the ordinary screen
  that answers them (Trends, Reminders, Garage). Nothing is gated.
- **Not Pro**: the screen with the examples and the Pro card. Tapping an example shows the
  ordinary screen, not a paywall.
- **Quota spent / gateway down**: the same copy as F4 – says so, names the next step (the
  ordinary screens), never an upsell.

## 7 · Privacy, logging, localisation

- What leaves the device per turn: the car profile card, the conversation so far, this turn's
  tool results. What never leaves: photos (unless the tier-3 consent is given for that photo),
  the database, other cars, the account email. The consent screen lists exactly this.
- Logging on both tiers per hard rule 12: turn index, tool names, token counts, latency, error
  code. The question and the answer are `Never` class (`LOGGING.md` §1) – not even in DEBUG.
- The diagnostics export (PR.11) includes agent turn *shapes*, never text.
- RU from day one: the system frame is localised, the fixed vocabularies (urgency, categories)
  come from the String Catalog, and the model answers in the app language. The RU review
  (`LOCALIZATION.md`) applies to every fixed string; the model's prose is checked by the gate in §8.

## 8 · The gate: an answer is correct when its numbers are the app's

OCR has a corpus and a ratcheting L5 gate; the agent gets the same, or it ships the
conversational version of P2.4's unmet gate without knowing.

- **Fixture set** `ios/Tests/Fixtures/agent/*.json`: a seeded garage, a question (EN and RU),
  the expected tool calls (names and arguments, order-insensitive), figures that **must** appear
  verbatim in the rendered cards, figures that **must not** appear anywhere in the answer, and
  for diagnosis fixtures the required urgency value.
- **L1 – tool routing** runs offline against a recorded model: the session calls the expected
  tools for each fixture and renders the expected cards. This is the test that runs in CI.
- **L5 – answer quality** runs against the live provider on demand, like the OCR corpus: the
  answer contains every must-figure (as a tool-rendered card, not as model text), no
  must-not-figure, the required urgency, and no number in the prose that is absent from the
  tool results. Ratchets; recorded in `TESTING.md`.
- **Mutation that matters**: let the model state a figure directly and confirm the gate fails.
  A gate that passes when the prose invents a number is vacuous.

## 9 · Success metrics (per journey, in `JOURNEYS.md`)

Pro conversion from the Ask tab; questions per Pro user per month; drafts confirmed vs
dismissed (a dismissed draft is the agent being wrong, tracked as a count only); diagnosis
turns that end in a reminder or a note; "that's not right" taps per 100 answers. All counts,
never content (hard rule 12).

## 10 · Out of scope, and why

Fuel-price feeds and station comparison (external data; turns a private log into a tracker),
audio engine diagnosis (cannot be framed honestly), server-side conversation memory (rule 9),
the agent as the only path to any action (rule 1), and any answer that renders a number the
tools did not return (§2).

## 11 · Build plan – the AG tasks

*Mirrored into `docs/TASKS.md` → "AG · Car Agent (v2, Pro)" when the backlog file is not mid-edit
by a running agent; until then this list is the record. Ordering is dependency order. Sizes S/M/L
as in the launch triage. Nothing here is a v1 condition.*

| ID | Task | Done when |
|---|---|---|
| AG.1 | **Decisions written down**: the rule-9 second exception (done in `CLAUDE.md`), the privacy-policy sentence in `SECURITY.md` and on the site, the Pro entitlement name and per-month turn quota in `CONFIG.md` (`llmQuota.agentTurns`), the five-slot tab bar in `DESIGN.md` (done) | Docs reconciled; product owner signs the quota and the policy sentence |
| AG.2 | **Tab bar: fifth slot** – `AppTabBar` gains Ask (glyph + label, never raised), `Route.ask`, tab root with `NavigationStack`; RU label verified at Dynamic Type XL on 375pt and 390pt, `Чат` fallback wired if `Спросить` clips | L4 `TankbookShellUITests`: five tabs hittable, capture circle unchanged; XL screenshots EN+RU, dark + light (S) |
| AG.3 | **Ask screen, not-Pro and offline states** (`AgentAsk.dc.html`): examples as taps to Trends/Reminders/Garage, the Pro card → Paywall, offline/quota/gateway copy from `ERRORS.md` → Ask | L4 new `AskUITests`: each example opens its screen; free seed shows the Pro card; `-forceOffline` shows the offline line with nothing gated; EN+RU (S) |
| AG.4 | **`AgentSession` + tool catalogue, read tools** in `TankbookCore/Agent/`: `carProfile`, `spend`, `consumption`, `entries`, `lastService`, `reminders`, `anomaly`, `tireSets`, `stations`; each pure over the repository, each returning a typed card model | L1 per tool against seeded repositories; figures equal `HomeStats`/`TrendsStats`/`AnomalyEngine` for the same inputs (M) |
| AG.5 | **`POST /agent/turn` on the gateway**: system frame per locale, provider call, per-account metering in `llm_usage`, 402/429 with `Retry-After`, shape-only logging, stores nothing | L2: turn round-trip on a recorded provider; quota exhaustion → 429; log sweep finds no prompt/answer text; redaction test extended (M) |
| AG.6 | **Thread UI** (`AgentChat.dc.html`): user turns, tool-result cards rendered by the app (`StatTile`, entry rows, station table), narration beneath, "Open in Trends"/entry deep links, composer with mic (dictation) and camera; conversation persisted on device per car | L4 `AskUITests` over a recorded transport: the J14 fixture renders its cards with the app's figures; a number in narration absent from the cards fails (the §8 mutation); EN+RU (L) |
| AG.7 | **Draft tools + confirm hand-off**: `draftReminder` → `ReminderFormView`, `draftServiceEntry` → `ServiceEntryView`, `draftFillUp` → `ManualFillUpView`, `draftExpense`, `draftNote`; dimmed-until-touched fields; outcome (saved/cancelled) returned to the session; `provenance = .agent` | L1: no draft writes without the screen's Save; L4 `AskUITests` + `RemindersUITests`: the J15 RU fixture opens the form with exactly its fields, Save persists, swipe-down persists nothing (M) |
| AG.8 | **Consent and privacy surface**: first-turn consent sheet listing what is sent, the car context card visible in the thread, "That's not right" with opt-in thread attach, diagnostics export carrying turn shapes only | L4: consent shown once per install, never again; L1: attach flag off by default; log sweep (S) |
| AG.9 | **Invoice through the agent** (`AgentInvoice.dc.html`): `captureInvoice()` via the document camera, items card with per-line explanation and category, unplaced lines marked, "Save as service entry" → `ServiceEntryView`, shelf-part suggestion, lifetime follow-up → AG.7 | L1: placed + unplaced sums equal the invoice total; L4 `AskUITests` with a fixture invoice; EN+RU (M) |
| AG.10 | **Diagnosis** (`AgentDiagnosis.dc.html`): context card first, ranked causes each with an evidence label, the fixed urgency row (amber "book this week", system-red dialog only for "stop driving"), safety-critical escalation in the system frame, the three app-action buttons, the once-only second-opinion line | L1: every cause carries a label; brake/steering/fuel-smell fixtures never resolve to "drive on"; L4 renders the row and the dialog; EN+RU (M) |
| AG.11 | **The gate** (§8): fixture set under `ios/Tests/Fixtures/agent/`, L1 tool-routing suite in CI on a recorded model, L5 answer-quality run on demand with the ratchet recorded in `TESTING.md` | The mutation: let the model state a figure → gate fails; ratchet recorded (M) |
| AG.12 | **Paywall + entitlement** (the P6.16-deferred Pro tier, now with a reason): StoreKit subscription/lifetime, entitlement check on the Ask tab and `/extract`, the free tier's "everything else stays free – including export" line | L2 receipt validation; L4 Paywall reachable only from the Ask card and the car-limit sheet (M) |
| AG.13 | **Re-check on-device models** at each iOS release: if a Russian-capable model exists on the floor hardware, route `AgentSession` locally and drop the account requirement for that path | Recorded decision per release in `VISION.md` → "Why tier 2 was cut" (S, recurring) |
