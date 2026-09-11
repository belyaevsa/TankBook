# Process and backlog review - 2026-09-11

**Question from the product owner:** does the current plan make sense, or should the approach
change, so the app gets built with less friction and fewer repetitive dispatches? And of the open
rows, which are still critical, and how far along are the scenarios?

Companion to `2026-09-11-rv-backlog-and-process.md`, which carries the numbers this review reads.

## The short answer

**The verification half of the process is right and should not move. The dispatch half is drawn
one row too narrow, and that is where the repetition comes from.** Three adjustments, in order of
leverage:

1. **The seam is the unit of dispatch, not the row.** Group siblings into one brief whose acceptance
   is *asserted from every entry kind so they cannot drift*.
2. **Walk the scenario BEFORE dispatching its work, not after.** The completion review already
   exists; run it first, so briefs are written against the whole promise.
3. **Mechanise the fixed cost** - a shared brief preamble, a dispatch script with the health check
   and retry built in, and the two-bundle test rule in the standing checks.

## What the evidence says

- **37 of 214 RV rows (17%) describe themselves as the sibling or remainder of an earlier row.**
  `PJ.28` -> `RV.149` -> `RV.173` -> `RV.202`: one defect, four briefs, four dispatches, four
  verification cycles, ten days. `RV.195` -> `RV.211`. `RV.200` -> `RV.201` -> `RV.206` -> `RV.214`.
- **Today's three dispatches filed seven new rows** (`RV.212`-`RV.217`, plus `RV.215` from
  `RV.201`). Every agent report ends in a *found and not fixed* list, and every brief's fence turns
  that list into the next dispatch. The backlog grows at roughly two rows per dispatch **by
  construction**, not because the code is getting worse.
- **The fence was often right and still cost a dispatch.** `RV.206`'s agent found the service
  gate, judged it a different decision, and filed `RV.214` - correctly. But `RV.212`/`RV.213`
  (lifetime on one door, lifetime only after first save) are the same seam as `PJ.22`, and
  `RV.216`/`RV.217` are the same card as `RV.201`. Those did not need a second round.
- **Briefs are 155-180 lines and the task-specific part ends around line 106-128.** A third of
  every brief is fences repeated verbatim (`pgrep -x`, no `stash`, `SKIP_BUILD`, the concurrent
  corpus run, the standing checks). They exist because each one was earned, but they are typed
  every time.
- **One dispatch in four dies on the provider** and is re-dispatched by hand after a manual health
  check. `RV.201` died once today at 42 KB of log.
- **Zero of 39 scenarios are marked implemented.** Six have every row closed and have never been
  walked (`F2`, `F3`, `F5`, `F6b`, `F8`, `J5`). The one `Status:` line in `JOURNEYS.md` is the
  template example.
- **Where `RV.201` did it right.** Its brief said *the merge is ONE function over any entry kind -
  asserted from a fill-up, a service and an expense in the same test file*. The agent generalised
  once and the mutation went red on the service case while the fill-up stayed green. That is the
  shape every sibling group should take.

## What to keep, unchanged

The analysis is unambiguous on this: **every defect that shipped this week was caught by a
hand-run mutation or by a person opening the screenshot** - three on the strongest model tier, two
today (`RV.216`, `RV.217`) that no test could see. Exit-code verification, the named mutation, and
the orchestrator opening every frame stay exactly as they are. They are the safety net; the model
tier is not.

## The three adjustments

### 1. Dispatch by seam

**Rule:** a brief covers every entry kind, door or screen that shares the code it changes, and its
L1 asserts the behaviour from each one in the same test file. The agent is **authorised** to fix a
sibling in the same run when it is the same function or the same line; it **files** when it is a
different decision (`RV.206`'s agent drew this line correctly on its own - the brief should license
it rather than fence it).

**Applied to today's open rows**, eight rows become three briefs:

| Seam | Rows | Why one brief |
|---|---|---|
| The save gate across entry kinds | `RV.214`, `PJ.50` (half-shipped by `RV.206`) | Same decision - what names a row well enough to save on |
| Lifetime across both doors | `RV.212`, `RV.213` | Same editor view, same rule, create and edit |
| The Inbox card's copy and layout | `RV.216`, `RV.217`, `RV.204` | Same card, same label table, same RU column |

### 2. Walk first

`agents/briefs/REVIEW-SCENARIO.md` runs today **after** a scenario's rows close, and its output is
new rows. Run it **before** dispatching a scenario's group instead: it enumerates every promise in
the journey text, the promises cluster into seams, and each seam gets one brief. The after-the-fact
review still runs, but it should find nothing - and when it does, that is the signal the walk was
skipped.

Concretely for `J7`/`J7b`: walk both now (the owner has asked for it), list every promise against
the tree, and brief the gaps as seams rather than filing them as rows.

### 3. Mechanise the fixed cost

- `agents/briefs/PREAMBLE.md` - the fences, once. The dispatch concatenates it. A brief becomes the
  ~100 lines that are actually about the task.
- `scripts/dispatch.sh <id>` - launches, writes the log, checks bytes at 60 s, re-dispatches the same
  brief once on a dead run, prints the PID for the monitor. The manual loop this replaces was run
  ~15 times this week.
- Standing checks gain the rule found today: **`-only-testing` across two bundles runs one of them**;
  the app-target suite and the UI suite are two invocations, each with its count read.

## The open backlog: 109 rows, judged

Read from `docs/TASKS.md` today. Marker counts: 43 `RV`, 28 `PJ`, 17 `PR`, 17 `AG`, 3 `SH`, 1 `T`.
By version marker: 72 v1, 22 v1.1, 9 v1.x, 6 v2 - and the 17 `AG` rows are the v2 agent by
section even where unmarked.

### Not v1 - 23 rows, not critical now

`AG.1`-`AG.17` (the Car Agent, `J14`-`J17`, `F12`), `PJ.18`, `PJ.46`, `PJ.49`, `PJ.52`, `RV.123`.
**One needs re-scoping:** `PJ.50` says the expense scan door *always ends at the keyboard* because
`canSave` demands a title - `RV.206` removed that today. Its remaining half (a merchant-line title
*suggestion*) is polish; close the row against `RV.206` and re-file the suggestion if wanted.

### Deferred by the owner - 31 rows, not launch-critical by definition

`PJ.15`, `16`, `21`, `24`, `29`, `30`, `31`, `32`, `35`, `37`, `39`, `40`, `41`, `42`, `43`, `44`,
`53`, `54`; `PR.3c`, `15`, `20`, `27`, `29`, `30`, `31`; `RV.118`, `119`, `120`, `122`, `124`,
`180`. Each carries `[v1.1]`/`[v1.x]` and most say *"PRIORITY (product owner, 2026-08-31)"* or
*"DEFERRED"* in their own text. They are the v1.1 plan, not v1 debt.

### v1 open - 55 rows, in five groups

**A. Critical - fix before launch (8).** Each is data loss, a hard-rule failure, or an App Review
risk:

| Row | Why it is critical |
|---|---|
| `RV.197` `[!]` | A guest logs a fill-up and never sees it - hard rule 1 in its plainest form; 443 UI tests missed it because every one signs in |
| `RV.208` `[!]` | Entries already on users' phones may hold a dangling attachment id - a migration, not a fix |
| `RV.155` | The pull cursor went backwards and re-fetched 274 records - sync correctness |
| `RV.143` | A home-currency change arriving by sync re-homes nothing on the receiving device - hard rule 3 across devices |
| `RV.148` | The monthly push sums a rate-pending month as complete - a wrong number sent to the user |
| `PJ.58` `[!]` | A second hardcoded `.eur` on service line items - `RV.185`'s fix one entry kind short |
| `PJ.51` | The store listing promises EV logging and six importers; one importer exists and EV is v2 - **App Review will read the listing** |
| `RV.174` | The per-task gate can be green on code that does not compile into the app - the gate itself |

**B. Important and groupable - 11 rows, three briefs** (the table under *Dispatch by seam*, plus
`RV.209` two `Attachment` builders, `RV.211` F9a ranking, `RV.215` deferred recognition,
`RV.134` units baked into sentences, `RV.191` RU import card below the fold). None is
launch-blocking alone; together they are the J3/J7 finish.

**C. Needs the owner, not an agent (3).** `RV.114`, `RV.179`, `RV.205` `[!]` - the corpus has zero
non-fuel receipt images and six unscored Estonian pump photos. Nothing here moves until
photographs arrive.

**D. Infrastructure and hardening (~20).** `PR.19`, `21`-`26`, `32`, `33`, `36` (all `[v1.0.x]` by
their own markers), `RV.109`, `129`, `130`, `168`, `169`, `175`, `194`, `203`, `207` `[!]`,
`210`, `T.3`. Post-launch patch work except **`RV.207`** - the field guard counts a pass-through as
a write, so a dead field can hide behind `??` - which is a blind spot in the thing that now proves
schema fields are live.

**E. Decide or drop with the owner (7).** `PJ.60`, `PJ.61` (two dead fields the guard surfaced -
give them a writer or delete them), `RV.115` (station brand list - a product decision), `RV.108`
(`GET /v1/account` is normative in `API.md` and does not exist - fix the doc or build it),
`RV.138`, `RV.158`, `RV.164` (each small, each a judgement), `RV.181` `[!]` (the owner skipped it;
the row should say so or close).

**F. Launch operations (3).** `SH.1`-`SH.3` are the owner's own TestFlight and store work; `SH.3`
is explicitly *"out of scope, I will do it anyway"*.

## Scenario implementation level

**Honest answer: unknown for all 39, because none has been walked.** The rule written on
2026-09-10 says ticked rows are what somebody thought of and the journey is what the user was
promised; `J7`'s *"renames/splits by hand"* is the proof - promised from day one, half shipped,
nobody noticed. Row counts are the only proxy available:

| State | Scenarios |
|---|---|
| Every row closed, never reviewed | `F2`, `F3`, `F5`, `F6b`, `F8`, `J5` (6) |
| Nearly closed (1 open) | `F1`, `F4`, `F6`, `F6a`, `F9a`, `J10`, `J11a`, `J3b`, `J7d`, `J9`, `J15`, `J16` (12) |
| Substantially open | `J3` **13 of 19**, `J7` 8 of 15, `J7b` 7 of 15, `J11` 3 of 4, `J4` 3 of 5, `J8` 3 of 3, `J7c` 3 of 3, `J8b` 3 of 4 |
| v2, untouched by design | `J14` 9 of 9, `J17`, `F12`, `J15`, `J16` |

`J3` - the five-second fill-up, the core journey - has the most open rows **because it is the most
used and the most looked at**, not because it is the least built. Eleven of its thirteen are the
sibling tail filed this week.

## Recommended sequence

1. **Walk the six ready scenarios** - read-only, cheap, and each is either the first `Status:
   implemented` line in the file or a gap list. Then `J7`/`J7b` as the owner asked.
2. **The eight critical rows**, as briefs - `RV.197` and `RV.208` first, they are on users' phones.
3. **The three J3/J7 seam briefs** from the table above - eleven rows, three dispatches.
4. **A decide-or-drop session** with the owner on group E, and `PJ.50` closed against `RV.206`.
5. **The mechanisation** (preamble, dispatch script, two-bundle rule) before the next dispatch loop
   starts, not during it.

That is roughly **twelve dispatches** to clear every v1 row that an agent can clear, against the
~25 the current row-per-brief practice would produce.
