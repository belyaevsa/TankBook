# REVIEW-JOURNEYS – audit the implementation against docs/JOURNEYS.md

*A RECURRING review, not a one-off. Four read-only review agents, one per journey group, in
parallel. Output feeds a dated "Journeys review" section in `docs/TASKS.md`.*

## Run history - read this before starting, and add your run to it

| Run | Tree | Yield |
|---|---|---|
| 2026-08-29 | `93d2619` | 66 `PJ` rows (36 since shipped, 30 open) |
| 2026-09-09 | `4cc801a` | 1 row (`PJ.55`), 0 ticked-but-not-true. One read-only agent, deep on J4 / J7b / money+rates / feedback rather than shallow across all - see `diagnostics/REVIEW-JOURNEYS-2026-09-09.md` |

**The 2026-08-29 run was never repeated, and 643 commits landed after it.** Every product
reachability gap catalogued in `docs/DEFECT-PATTERNS.md` Part 2 was found either by that review or
by the product owner using the app - which is the argument for the cadence below, and the reason
this brief now carries a run history.

## When this runs (convention, 2026-09-09)

**A floor: every 10 shipped rows, or at a phase gate, whichever comes first.**

**And on any of these events, for the journey the change touches - these are the four shapes that
produced every instance in `DEFECT-PATTERNS.md` Part 2:**

1. **A screen or route ships** - walk its journey end to end. (`PJ.4` shipped a Reminders screen
   whose only route was DEBUG-gated: unreachable in Release, with a green suite. `PJ.25`, `PJ.20`.)
2. **A reader of an entity ships** - check something creates it, and that a user can. (`PJ.19`,
   `RV.150` and a Garage list all shipped onto a station set nothing could populate: `RV.156`.)
3. **Copy naming a destination or outcome ships** - check the thing it names exists. (`RV.98`'s
   "moves to Recently deleted"; `PJ.36`'s dead export; `RV.146`'s "Recent first".)
4. **A row ships PARTIALLY** - a brief fenced part of it out. File the remainder AND re-walk the
   journey. (`RV.62` delivered half of `PJ.28` and the photo was dropped for months.)

## What is different on a RE-run

- **Read the run history above and the existing `PJ` rows first.** A gap already tracked is
  **cited, never re-filed** - the same rule the first run followed, and it matters more each time.
- **A `[x]` row whose behaviour the code does not have is the most valuable finding you can make**,
  and it is the one only a re-run can produce. Say so explicitly: *"PJ.n is ticked but …"*.
- Number new rows in a fresh range and say which run produced them.

## Shared instructions (every agent)

- Read `docs/JOURNEYS.md` fully first; your group's journeys are the checklist. Each journey's
  stage table, its ⚠/→ notes, its fallbacks and its "Success metric" are all requirements.
- Then read `docs/TASKS.md` end to end: many gaps are already tracked as `[ ]`, `[~]` or `[!]`
  rows, or as `PR.n` rows. **If a gap is already a task, cite that id instead of proposing a new
  one.** Only propose new tasks for gaps no row covers, or where a `[x]` row claims something the
  code does not do (say so explicitly: "P6.x is ticked but ...").
- Consult the owning doc before judging a behaviour: `docs/SCREENMAP.md` (what screens exist),
  `docs/ERRORS.md` (what each error must say), `docs/EXTRACTION.md`, `docs/SYNC.md`,
  `docs/SCHEMA.md`, `docs/VISION.md` (feature phases - a journey marked v1.x/later in VISION.md
  is N/A for v1, say so rather than filing it).
- Scope: `ios/Sources/TankbookCore`, `ios/App/Sources`, `backend/src`; UI tests in `ios/UITests`
  or similar are evidence a stage is wired, cite them. Read-only: no edits, no builds, no tests.
- For every journey stage/fallback report one of **MET** (file:line), **PARTIAL** (what exists,
  what is missing, file:line for both), **MISSING** (what you searched for), **N/A** (why: a later
  phase per VISION.md, or a v2 journey). Never MET without a citation.
- Every PARTIAL/MISSING not already tracked becomes a proposed task: id `PJ.<n>` (numbered per
  your group range), one-line deliverable, the journey stage it closes, the user-facing
  consequence today, severity **bug** (a hard rule or a "never"/"always" in the journey is
  violated) / **gap** (the journey promises it) / **polish** (a → opportunity), and the check that
  makes it done (L1/L4 per `docs/TESTING.md`, naming the UI suite).
- Never quote domain values from fixtures or logs in your report.
- Compact: tables, file:line, no narrative.

## Group A (PJ.1xx) – Acquisition and capture: J1, J2 (entry points only; parsing is Group C),
J3 incl. the mixed-receipt variant, J4, J3b, J5, F1, F2, F3, F4, F5, F8.
Focus: the Welcome/first-launch flow and its three paths; camera readiness, torch suggestion,
photo kept on failure; the Confirm sheet's cross-check lock, dimming, live odometer delta, the
insight one-liner after save; "Also on this receipt" and `purchaseGroupId`; pump-photo gate;
"Type it" reachable in one tap in every state; QR anchoring and the F5 copy; F1 "empty but alive"
with keyboard on Total; F2 amber underline + source crop; F3 rate-pending chip; F4 3 s budget
copy and the quota note in Settings; F8 denied-camera card with deep link and "add from photos".

## Group B (PJ.2xx) – Service, parts, reminders, EV: J6, J7, J7b, J7c.
Focus: EV charge entry (public share-extension, home charge with tariff and %→kWh), the two-car
€/100 km chart; invoice multi-page capture, deterministic split, lump-sum fallback, `.other`
promotion, odometer rule (required only for km lifetimes / tire mount); next-reminder proposal
from item lifetimes; ОСАГО reminder type; parts shelf, "install from shelf" linking without
re-pricing, TireSet creation from purchase, seasonal swap records and derived set mileage shown
as "–" when unknown; reminder Complete → "Log the cost?" → next cycle anchored at completion,
Reschedule re-arms, Delete vs dismiss-with-reason.

## Group C (PJ.3xx) – Periodic, currency, import: J8, J9, J10, J2 (parse/preview/commit),
F6, F6a, F6b, F9, F9a.
Focus: Trends hero metric + trend arrow, monthly bars, price-per-litre per station brand; the
monthly notification; anomaly card (amber, in Log, never push), evidence sheet, dismiss-with-
reason teaching the model, act → reminder; cross-border currency auto-detect and the two-amount
card with rate snapshot; import format auto-detect, per-source export guide, preview figures
(count, range, odometer span, currency/units, spend, derived consumption via the real engine),
target-car choice with S2 duplicate count, cancel deletes the stored file, partial import with
flagged rows as fields (only the broken field marked, "Original row" one tap away), non-fill-up
rows offered as service, the once-per-file units question, the "send us the file" consent;
rate-pending footnote count, manual rate per entry, never today's rate for a past entry; F9a
inline conflict with quoted neighbour, ranked suggestions, receipt-date priority, save-anyway
badge + segment exclusion + Trends footnote.

## Group D (PJ.4xx) – Account, sync, exit: J11a, J11, J12, J13, F7, F10.
Focus: sign-in = registration with Apple/Google, the wrong-provider warn notice and the
reactive empty-account detection with one-tap provider switch; first push never overwrites local;
Welcome's third path "Already use Tankbook?"; restore screen with verification stats before
finishing, background photo download by recency; F7 source order (pull → snapshot → file import),
backend-down copy, empty-garage recovery entry point before any new entry; J12 is v2 (confirm N/A
unless VISION.md says otherwise); J13 PDF dossier + CSV/JSON export + archive with history
retained out of stats; F10 badges (S2 duplicate card, S3 flags, S5 archived-returned notice),
batch toast filtering the Log, "Recently deleted" and "restore my version", duplicate counted
once in stats, "Waiting to sync · N changes" row. Cross-reference `docs/PRACTICES.md` §7 tasks
PR.13/PR.14 before filing anything about sync surfaces.
