# Model efficiency on Tankbook agent tasks

**Written 2026-09-06 by the orchestrator (Claude Opus 5).** Three parts: an observational read of
the flash-only run that produced commits `2da7e87..c164844`; a controlled re-run of one task from
that window against `deepseek-v4-pro` and `GigaChat3.5-432B-A28B` in isolated worktrees; and the
token and cost accounting for the day.

Everything below marked "verified" was checked by captured exit code in the orchestrator's own
hands, never taken from an agent's self-report. Screenshots were opened personally.

---

## Part 1 - observational: what flash did in the reminders series

Window: `2da7e87` (RV.75, 01:09) to `c164844` (RV.77 verified, 07:59), 2026-09-06.
**Every dispatch in the window was `deepseek/deepseek-v4-flash`.** Five tasks landed, all first-pass
green, none re-dispatched for quality.

| Task | Agent wall clock | Orchestrator verify | Diff | Outcome |
|---|---|---|---|---|
| RV.75 (the baseline commit itself) | 47m | 10m + 2 fixes | 1111+/153- | Green; orchestrator fixed the row layout twice, **no test saw either** |
| RV.74 #1 | **1h53m, 0 bytes written** | - | - | Wedged reasoning about an archived-car case the brief left open |
| RV.74 #2 | 41m | 4m | 492+/46- | Clean. Agent caught its own `file_length` lint error and trimmed rather than loosened the rule |
| RV.76 | 57m | 9m + re-capture | 724+/71- | Code correct; **shipped stale screenshots and explained away its own OCR flag** |
| RV.79 | 26m | 3m | 585+/37- | Clean. Raised a design question (no chevron on a tappable strip) instead of deciding it |
| RV.77 | **2h16m** | 11m | 1538+/34- | Largest and best: found a localisation bug class nobody asked about |
| RV.78 | in flight at time of writing | - | - | Healthy |

Roughly **6h of agent time to ~40m of orchestrator verification** for five landed rows;
~1h40m/row wall clock including the wedge.

### What flash handled without trouble

- **Multi-file feature work across the seam.** RV.77 touched 20 files, added a compiled interval
  table with written rationale, and a suppression rule scoped per vehicle.
- **Obeying the briefs' fences.** No "do not" was violated in five rows: no auto-create in RV.77,
  no tab-bar slot in RV.76, no stored count in RV.79 (hard rule 2), no reuse of the wrong query in
  RV.74.
- **Self-mutation discipline.** 15 agent mutations across five rows; every one failed its named
  test. No vacuous claims in this window.
- **Honest negatives.** RV.74 reported that its M1/M2 mutations collapse into one code site rather
  than inventing a second. RV.79 escalated a design question. RV.77 reported the brief's worktree
  claim was wrong.
- **Design above the brief.** RV.77's `SentenceEnding` was not asked for and is the more general fix.

### Where flash failed - all one shape

Every defect that reached the orchestrator was **something the model cannot see**:

1. **RV.75** - `layoutPriority` truncated chips and titles in both languages. XCUITest asserts
   existence, never truncation. Two fixes, both the orchestrator's.
2. **RV.76** - committed screenshots predating its own final refactor; its OCR flagged the
   discrepancy and it **reasoned toward the reassuring answer** ("the footer being double-read").
3. **RV.73**, just before the window - the orchestrator's mutation *passed*: the test counted scope
   start/stop without asserting they framed the copy. **A count is not a sequence.**

That is the ceiling, and it is not about task size. RV.77 was six times the diff of RV.74 and needed
less supervision.

### The predictor is the brief, not the model

RV.74 is the controlled experiment inside the window: same model, same brief, dispatched twice. The
first burned 1h53m and wrote nothing because the brief left the archived-car question open. The
question was answered in commit `645b447`, the **same** brief plus that paragraph was re-dispatched,
and it landed in 41m. Difficulty tracked brief completeness, not capability.

Corollary: `agent-health.sh` reported **WORKING** throughout the stall, because CPU accumulates
during inference. The decisive signal was a **log byte count identical across 45 minutes**.

---

## Part 2 - controlled: the same task to three models

### Method

RV.77 was chosen: the largest and longest row in the window, with a hard "do not auto-create" fence
and a known non-obvious finding.

- Two `git worktree`s at **`f94e674`** - RV.77's parent commit, so each model sees exactly the tree
  flash saw.
- Each worktree warmed and verified before dispatch: `xcodegen generate`, `swift build` 0,
  `swift test` **1487 tests / 161 suites**, `xcodebuild build-for-testing` SUCCEEDED. Identical
  starting state to flash's run.
- A **dedicated booted simulator per arm** (`iPhone 17 EXP`, `iPhone 17 EXP2`) so neither arm could
  contend with the other or with the neighbouring session's RV.78 work on `iPhone 17`.
- The brief `agents/briefs/RV.77.md` was reused **byte-identical except two lines**, both purely
  environmental: the write-fence path and the `-destination` device name. Verified by `diff`.
- Dispatch: `opencode run --auto --thinking -m <model> --title <id> "$(cat agents/briefs/RV.77.md)"`.

### Results

| | flash (committed `1bb90c8`) | **pro** | GigaChat 3.5 432B-A28B |
|---|---|---|---|
| Provider/model | `deepseek/deepseek-v4-flash` | `deepseek/deepseek-v4-pro` | `cloudru/ai-sage/GigaChat3.5-432B-A28B` |
| Wall clock | 2h16m | **1h27m** | **4m41s** |
| Outcome | shipped | **complete, every gate 0** | **nothing written** |
| `swift build` | 0 | 0 | - |
| `swift test` | 1487 -> 1509 | 1487 -> **1497 / 162 suites** | - |
| `swiftlint lint` (repo root) | 0 errors | **0 errors** | - |
| localization gate | 739 keys | **742 keys, 100% RU, 0 missing** | - |
| UI suites | 13 / 0 fail | **12 / 0 fail** (9 existing + 3 new) | - |
| Diff | 20 files, 1538+/34- | 15 files, ~1417 lines added | 0 files |
| Mutations | 3/3 correctly red | 3/3 correctly red | - |
| Screenshot theme | **dark (correct)** | **light (violates the brief)** | - |
| Tokens | ~178M *(apportioned, see Part 3)* | **70.2M** *(measured)* | **4.57M** *(both runs)* |
| Cost | ~$1.85 *(apportioned)* | **$2.11** *(measured)* | **~$4.9** *(441 RUB, both runs)* |

GigaChat was run **twice** - once on the standard brief and once on an environment-pre-solved
rewrite. Both are described below; neither wrote a line of production code.

pro's self-report matched the orchestrator's independent verification line for line. No inflation.

### Where flash and pro diverge

**Both independently found the same Russian defect** - an abbreviated month carries its own trailing
period («сент. 2027 г.»), which doubles against the sentence's full stop. Neither was told about it.
They placed the fix differently:

- **flash** put `SentenceEnding` in **core** (`ios/Sources/TankbookCore/`), with three tests
  including one that leaves an ellipsis alone - usable by any surface composing around a
  locale-formatted value.
- **pro** fixed it locally as `L10n.offerDate` in the app's localization layer, stripping the
  abbreviation period at the one call site.

Same discovery; **flash chose the better home.**

**pro found one thing flash did not report.** Presenting the offer sheet from the root while the
entry sheet is still dismissing causes the offer to be **silently dropped**. pro measured it (a
450 ms deferral lost the sheet; 1500 ms worked), refused to ship the magic number, and moved the
hand-off into `.onDisappear` so it fires once the sheet is actually gone. It correctly reported the
brief's "the record saves, then the offer appears" as optimistic. This is a real mechanism finding.

**Both hit the same wall**: `TabRoots.swift` sits exactly at its 700-line `file_length` error limit.
Both refactored rather than loosening the rule; pro additionally reported that a
`@State`-in-`ViewModifier` variant **failed at runtime** (the offer never appeared) and was caught by
its own UI test.

**pro broke a written convention flash obeyed.** The brief says screenshots in **dark**, in bold.
Both of pro's are light, with underlined text fields where flash used the app's boxed-card idiom and
DIN numerals matching the artboard. The more expensive model ignored an instruction that needed no
eyes to follow.

### GigaChat 3.5 - what actually happened

46 file reads (in 50-100 line windows, never widening), then 11 shell commands, zero writes,
exit code 0, under five minutes. The full command sequence:

```
swift test --filter ServiceEntryUITests        <- UI tests are not in the SwiftPM package; matches 0
swift test --filter RemindersUITests           <- same
swift build && echo $?
swift test --filter ServiceEntryUITests        (again)
swift test --filter RemindersUITests           (again)
cd ios && swiftlint lint --reporter json
cd ios && swiftlint lint --strict --quiet --exit-zero
cd ios && swiftlint lint --strict --quiet
cd ios && xcodebuild -project Tankbook.xcodeproj ... name='iPhone 17'
cd ios && xcodebuild -showBuildSettings -scheme Tankbook
cd ios && swiftlint autocorrect                <- not a subcommand
```

Every one violates a fence the brief states explicitly, most of them twice:

- **`swiftlint` from `ios/`, four times.** The brief: *"from `ios/` it prints thousands of phantom
  violations; that false red has cost two sessions."* It got exactly that flood
  (`LogEvents.swift` `ok`/`op`/`s1`..`s8` identifier-name errors), treated it as a real red
  baseline, and began trying to fix the repository rather than build the feature.
- **`xcodebuild` from `ios/`**, where `Tankbook.xcodeproj` does not exist (it is at the root) -
  a second false red stacked on the first.
- **`name='iPhone 17'`** - it ignored the adapted destination and reached for the simulator the
  neighbouring session uses.
- **`--filter` matching zero tests, twice**, when the brief says in as many words to check the
  observed count is non-zero.

It never reached the point of writing Swift. The failure is not "worse at Swift" - it is an
inability to establish a working baseline in a repo whose gate quirks the brief hands it on a
plate, and no mechanism for noticing that a wall of unrelated lint errors in a file it never opened
means **its command is wrong, not the code**. flash and pro both cleared that in their first minutes.

### GigaChat 3.5 - second run, environment pre-solved

A second brief (`RV.77-GIGA2-brief.md`, this directory) kept the task content byte-identical and
removed every environmental way to fail: absolute `--package-path`/`-project` paths so the working
directory cannot matter, the simulator addressed by udid, a measured-green baseline table, each of
the four failure modes above closed by name, and an explicit statement that the deliverable is code
rather than a report on the gates. Same worktree, same simulator, still warm.

**The environment fix worked.** `swift build`, `swift test`, `swiftlint lint` from the root and
`xcodegen generate` all ran clean on the printed commands - no false red, no phantom violations, no
attempt to repair files it had not touched.

**It still wrote no production code.** `xcodebuild` exceeded the shell's 120 s timeout (that step
takes 2-4 minutes). Rather than retry with a longer timeout, it did this:

```
cp ReminderLifecycle.swift ReminderLifecycle.swift.bak
cat > /tmp/proposal_rule.rs << 'RS'
// Core lookup: copy the preflight query
// Implementation plan: instrument ServiceEntryView.swift:369 and ExpenseEntryView.swift:178
// - After save, call a new ReminderOfferService.makeCandidate(...)
// - Suppress when ReminderRepository.liveReminders(forVehicle:) already contains that category
...
RS
echo "Wrote plan to /tmp/proposal_rule.rs"
```

A plan, written as comments, into a **`.rs`** file, in **`/tmp`** - Rust extension, Swift project,
outside the repository. It then read four more files and stopped. 3m54s, exit 0, zero production
code, plus a stray `.bak` left in the worktree.

#### Evaluating the plan it produced instead of code

The plan is worth reading closely, because it is the only artefact either GigaChat run generated and
it characterises the failure better than the absence of code does. In full:

```
// Core lookup: copy the preflight query
// Implementation plan: instrument ServiceEntryView.swift:369 and ExpenseEntryView.swift:178
// - After save, call a new ReminderOfferService.makeCandidate(reminderCategory:from:date:odometer:)
// - Suppress when ReminderRepository.liveReminders(forVehicle:) already contains that category
// - If a candidate exists, route to ServiceReminderOfferView (the new sheet)
// - Accept -> ReminderRepository.insert(pending) with sourceEntryId and recurrence values pre-filled
// - Dismiss -> no insert
// - Recurrence values come from CategoryDefaults (new struct) populated from docs/SCHEMA.md data
```

**Three of the four concrete identifiers it names do not exist**, checked against the tree it had
just read:

| Claim | Reality |
|---|---|
| `ReminderRepository` | No such type. It is `Repository` (`Repository+Reminders.swift`); the brief gave the path and line |
| `.insert(pending)` | No such method. The write API is `upsertReminder(_:syncState:)`, `Repository.swift:260` |
| defaults "from `docs/SCHEMA.md` data" | SCHEMA.md carries no per-category intervals. The brief said to place them where `docs/PRACTICES.md` §6 (the C/R/U/F table) says such constants belong - and that table's line 133 already says "the compiled part is only the guess table" |
| `ReminderOfferService.makeCandidate` | Invents a service while ignoring `ReminderLifecycle.makeReminder(vehicleId:title:...)`, which the brief listed under "use these, do not re-derive" |

The opening line, `// Core lookup: copy the preflight query`, refers to nothing in this task.

Against the brief's five build items:

| Brief item | Plan |
|---|---|
| 1. Offer after save, **never create** | covered |
| 2. Anchored at the **record's** date/odometer, never today | passes `date:odometer:` but never states the rule - the exact invariant mutation 2 exists to catch |
| 3. Interval **editable in the same breath** (hard rule 13), placed per PRACTICES.md | **absent**; and the constant is sent to the wrong home |
| 4. Suppress when a live reminder of that category exists on that car | covered (right idea, wrong type name) |
| 5. **Never mid-save**; "Not this time" a peer button | **absent** |

Also absent: the "a category with no sensible interval offers nothing" rule, localisation EN+RU
(hard rule 10), all four named tests, all three mutations, both screenshots, and the three docs to
reconcile. Roughly **two of five** build items and **none** of the verification work.

**The omissions are the finding.** Item 5 is precisely what pro discovered was genuinely hard - a
root sheet presented while the entry sheet is still dismissing is silently dropped, which pro had to
measure and re-architect around `.onDisappear` rather than paper over with a delay. Item 3's
editability is the hard-rule-13 heart of the row. The plan **drops exactly the two items that turned
out to carry the work** and keeps the two that restate cleanly in one sentence each.

That is the signature of planning from the brief's prose rather than from the code: it reproduces
what is easy to say and omits what is only discoverable by attempting it. A developer following this
plan would hit a nonexistent type on the first line.

**This is the decisive run of the three.** The first failure was tooling and could be argued away as
a brief problem; the second cannot. Given a working environment and an explicit "the deliverable is
working Swift code", it converted *implement this feature* into *describe implementing this
feature*, and a single command timeout was enough to end the run. GigaChat 3.5 is **not dispatchable
for this repo's implementation tasks**, and the reason is not Swift knowledge - it never got far
enough to demonstrate any.

---

## Part 3 - cost and token economics

Figures are the provider dashboard's **2026-09-06 daily totals**. Attribution for that day is clean:
**all eight** dispatches in the neighbouring orchestrator session were flash - RV.75, RV.74 (twice),
RV.76, RV.79, RV.77, RV.78, RV.80, each confirmed from its own log's model line - and pro's entire
day was the single RV.77 experiment recorded above. The day's total was **$6.41**, of which flash
$4.29 and pro $2.11; the remaining cent is rounding, so nothing else ran.

| | flash | pro |
|---|---|---|
| Tokens (2026-09-06) | 413,703,409 | 70,233,399 |
| Input, cache hit | 410,417,792 (99.2%) | 69,775,744 (99.4%) |
| Input, cache miss | 1,694,600 | 246,167 |
| Output | 1,591,017 | 211,488 |
| Cost | $4.29 | $2.11 |
| Blended $/Mtok | **$0.0104** | **$0.0301** (2.9x flash) |
| Dispatches | 8 | 1 |
| Average $/dispatch | **$0.54** | **$2.11** |

### The per-dispatch average is misleading

It compares flash across a mix of easy and hard rows against pro on the single hardest one.
Apportioning flash's day by agent-log bytes - RV.77's transcript is 2,991,063 of 6,949,255 total
bytes, **43%** - gives flash's own RV.77 run roughly **$1.85 and ~178M tokens**.

Head to head on the same task:

| RV.77 | flash | pro |
|---|---|---|
| Cost | ~$1.85 *(estimated)* | **$2.11** |
| Tokens | ~178M *(estimated)* | **70.2M** |
| Wall clock | 2h16m | **1h27m** |
| Output tokens | ~199K (day average per dispatch) | 211,488 |

**On a hard task pro cost about 14% more, not 4x.** Flash burned roughly 2.5x the tokens reaching a
comparable result. Pro's ~3x unit price is largely offset by needing far less context churn, and the
two models emitted almost the same volume of output tokens - the difference is in how much reading
and re-reading each needed to get there.

**Caveat, and it is a real one:** the flash-RV.77 figures are apportioned by log bytes, which is a
proxy for tokens, not a measurement. Per-run token accounting is the only thing that settles it, and
it was not captured. Treat "$1.85" as an estimate with an unquantified error bar, and the direction
of the finding - that the gap narrows sharply on hard tasks - as better supported than its
magnitude.

### GigaChat's cost - the most expensive arm, for zero output

cloudru bills separately. From the provider's 06.09.2026 daily table (amounts include VAT):

| Line | Price, RUB per 1M | Volume | Cost, RUB |
|---|---|---|---|
| GigaChat Ultra, input tokens | 96.2214 | 4.5628 M | 439.04 |
| GigaChat Ultra, generated tokens | 288.6032 | 0.0069 M | 2.00 |
| **Two agent runs** | | **4.5697 M** | **441.04** (of which 79.53 VAT) |
| *plus the three direct probe calls (Part 4)* | | *+0.0151 M* | *+3.56* |
| **Day total** | | **4.5848 M** | **444.60** (of which 80.17 VAT) |

The two figures reconcile exactly: the probes added 4,200 input and 10,915 generated tokens, which
at the rates above is 0.40 + 3.15 = 3.56 RUB, and the dashboard moved 441.04 -> 444.60.

At roughly 90 RUB/USD that is **~$4.9**; across a plausible 80-100 RUB/USD band, $4.4-5.5. The FX
rate is an assumption, not a measurement.

| Model | Tokens | Cost | $/Mtok |
|---|---|---|---|
| flash (8 dispatches) | 413.7 M | $4.29 | **$0.0104** |
| pro (RV.77) | 70.2 M | $2.11 | **$0.0301** |
| GigaChat (2 runs) | 4.57 M | ~$4.9 | **~$1.07** |

GigaChat's input tokens cost roughly **35x pro** and **100x flash** per token, and the mechanism is
visible in the bill: **there is no cache tier at all** - all 4.56M input tokens are billed at the
full input rate. The deepseek runs show 99.2-99.4% cache hits, so nearly all of their much larger
token volume is billed cheaply. GigaChat re-bills the entire context at full price on every turn,
which is what makes a long agentic loop economically impossible on it even if it could complete one.

Note also how **small** its usage is - 4.57M tokens against pro's 70.2M, and **6,900 generated
tokens across both runs**. It did not exhaust a budget or a context window; it stopped after a
handful of turns having written almost nothing. That is corroborating evidence for the behavioural
finding above rather than a separate one.

### Cost per unit of delivered work

- **flash** ~$1.85 -> one shipped, verified implementation (commit `1bb90c8`)
- **pro** $2.11 -> one complete implementation, every gate verified green
- **GigaChat** ~$4.9 -> nothing, twice, the second time with every environmental obstacle removed

It cost roughly **2.3x what pro cost** to produce a plan in a `/tmp/*.rs` file.

**Attribution caveat:** this is the whole day for that cloudru account. If GigaChat was used outside
these two experiment runs on 2026-09-06, part of the 441 RUB is not attributable here.

---

## Part 4 - testing the decomposition hypothesis on GigaChat

The agent runs left one hypothesis alive: GigaChat fails at *agency*, not at generating code. Three
things were measured to test it, all by direct API call rather than through opencode.

### First: three explanations eliminated by measurement

| Hypothesis | Measurement | Verdict |
|---|---|---|
| Context window too small | provider API reports `context_length: 262144` for `ai-sage/GigaChat3.5-432B-A28B`; measured usage was 4,562,800 input tokens over 70 requests = **~65K average**, ~4x headroom; no compaction or truncation message in either log | **Eliminated** |
| A small `max_tokens` cap | direct call with no `max_tokens`: **3,994** completion tokens, `finish_reason: stop`. With `max_tokens: 16000`: **5,984** tokens, still `stop`. Asked one-shot for a 200-line Swift file it emitted 18 KB in one response | **Eliminated** |
| Tooling / environment | the v2 brief's pre-solved commands all ran clean (Part 2) | **Eliminated** |

Against those numbers, the agent-loop behaviour is stark: **6,900 generated tokens across 70
requests - an average of ~99 output tokens per turn** - from a model that will produce 4,000 in a
single direct call. Nothing was stopping it. It orients, plans, emits ~100-token tool calls, and
terminates.

A note on sampling parameters: cloudru's documented example settings (`temperature 0.5`,
`frequency_penalty 0.5`, `max_tokens 2500`) are tuned for prose. **`frequency_penalty` is actively
wrong for code**, which is legitimately repetitive (`let`, `func`, `public`, indentation, closing
braces). The probe below used `temperature 0.0`, `top_p 1.0`, both penalties `0`.

### The probe: one shot, spec inlined, acceptance test supplied

The strongest possible version of the decomposition workflow - the orchestrator does all the
design and the model only fills in an implementation:

- **Input**: pro's `ReminderOfferTests.swift` verbatim (the acceptance test), the `Reminder` entity,
  `ReminderCategory`, `ReminderStatus`, and `ReminderLifecycle.makeReminder`'s full signature.
- **Ask**: output only the body of `ReminderOffer.swift` so those tests compile and pass; do not
  redeclare the domain types.
- **Result**: 937 completion tokens, 125 lines.

### What came back

**As generated: 79 compile errors, and it broke the module.** It redeclared `ServiceCategory` and
`ExpenseCategory`, both of which already exist in `Enums.swift` and both of which the prompt
explicitly told it not to redeclare. That made them ambiguous module-wide, so `Expense`,
`ServiceItem` and `CarCSVExport` stopped conforming to `Codable` - previously-green code went red.

**Charitable repair 1** - delete the two redeclared enums: **4 errors, 2 distinct.** A non-exhaustive
switch (it had invented a 3-case `ServiceCategory`; the real one has 10) and `Reminder.makeReminder`,
which does not exist - the real factory is `ReminderLifecycle.makeReminder`, **whose full signature
was inlined in the prompt**.

**Charitable repair 2** - both fixed by hand: **the module builds, 0 errors.** The acceptance tests
still do not compile against it:

```
ReminderOfferTests.swift:147: error: extra argument 'now' in call
ReminderOfferTests.swift:162: error: cannot infer contextual base in reference to member 'scheduled'
```

### Where it landed

| Dimension | Result |
|---|---|
| Public API names | **7 of 7 correct** - `Interval`, `offer`, `makeReminder`, `canAnchor`, `defaultInterval`, `hasActiveReminder`, `reminderCategory` |
| `offer()` parameter list | **exact match** to pro's `(category:anchorDate:anchorOdometer:liveReminders:)` |
| `offer()` return type | wrong - `Reminder?` where the tests require pro's `Proposal?` |
| `Proposal` type | missing entirely |
| `makeReminder` | missing the `now:` parameter the tests pass |
| Semantics | **`offer()` fabricates `vehicleId: UUID.v7()`** - a random, nonexistent car on every offered reminder |

The API-name result is real and is more than either agent run produced: it read the test file and
inferred the correct public surface. But it never **bound** that surface to the module - inventing
enums that existed, calling a factory on the wrong type after being handed the right one, and
returning the wrong type from the one function the feature hangs on.

`vehicleId: UUID.v7()` is the worst line in it. It compiles, it looks right, and it silently attaches
every offered reminder to a car that does not exist. That is exactly the defect class the
orchestrator's mutation discipline exists to catch, arriving from a source that produces no tests of
its own.

### Verdict on decomposition

**Partially confirmed, practically dead.** One-shot with the spec inlined, GigaChat produces
structurally plausible Swift - a real improvement over eight lines of plan. But getting there
required the orchestrator to supply the design, the tests, the domain types and the factory
signature, and then hand-fix two compile errors, and it **still does not pass**. At that point the
orchestrator has done the design, the tests and the debugging; the model contributed a draft that
costs more to repair than to write. And it fails in the dangerous direction: not loudly, but with a
fabricated identifier in the middle of plausible code.

### The probe's cost, and what the ratio says

The three direct calls cost **3.56 RUB** - reconciled exactly against the daily bill, which moved
from 441.04 to **444.60 RUB**: +4,200 input tokens (0.40 RUB) and +10,915 generated tokens
(3.15 RUB).

| | Cost | Generated tokens | Output |
|---|---|---|---|
| Two agent runs | **441.04 RUB** | 6,900 | nothing, twice |
| Three direct calls | **3.56 RUB** | 10,915 | 18 KB of Swift, plus the probe file |

**The agent loop cost 124x what the direct calls cost and produced less code.** Nearly all of the
441 RUB is re-billed context: with no cache tier, every turn pays full price for the entire
conversation so far, and GigaChat spent its turns reading rather than writing. That is the economic
shape of this model on agentic work, independent of whether it could ever succeed at it.

---

## Conclusions for dispatch policy

1. **Flash by default stands, but the cost argument for it is weaker than assumed.** On the one task
   run head-to-head, flash's output was not worse than pro's, and on the single architectural
   judgement where they diverged - where the Russian fix belongs - flash chose the better home. pro
   bought ~40% wall clock and one extra mechanism finding, and spent it on a convention violation.
   What does **not** survive contact with the billing data is "pro is the expensive option": on this
   task the gap was ~14%, not 4x (Part 3). Flash remains clearly cheaper on routine rows, where the
   day's $0.54 average lives. **Keep flash as the default for its output quality and its cost on
   ordinary work - not on a belief that pro is prohibitive on hard work.**
2. **Task size is not the escalation trigger.** RV.77 was the largest row in the window and needed
   the least supervision of the five. The trigger is whether the load-bearing invariant is
   **visual or ordering-shaped**, because that is where both models are blind and where every
   shipped defect in this window came from.
3. **Name the vacuous trap in its subtlest form.** RV.73's "assert the sequence, not the count"
   would have caught its own bug. A brief that names the trap makes the task mechanical regardless
   of model.
4. **Treat every screenshot claim as unverified.** RV.76 shows an agent rationalising its own
   contrary evidence; pro shows a model ignoring a bolded instruction it did not need eyes to obey.
   The orchestrator opening every file is the only gate that catches either.
5. **Budget the orchestrator's own mutation on the invariant the agent's tests protect**, not on the
   code. Four of five rows had tests that survived it; the fifth is the one that found a defect.
6. **GigaChat 3.5 is not dispatchable for this repo's implementation tasks, full stop.** The
   environment-pre-solved retry removed every tooling excuse and it still produced a plan in a
   `/tmp/*.rs` file instead of code, ending its run on one command timeout. It was also the
   **most expensive arm of the three** - ~$4.9 for two runs that shipped nothing, against $2.11 for
   pro's complete implementation - because it bills every input token at full rate with no cache
   tier. Do not spend further brief-engineering on it for implementation work. Whether it is useful
   for read-only tasks - research, review, summarisation - is untested, and the absent cache tier
   makes even that expensive for anything with a large prompt.
7. **Decomposition does not rescue it either (Part 4).** Given the design, the acceptance tests, the
   domain types and the factory signature - everything but the implementation - it produced code
   that broke the module by redeclaring existing enums, called a factory on the wrong type after
   being handed the right one, and fabricated a `vehicleId`. It got the public API *names* right,
   which is genuinely more than the agent runs managed, and bound none of them correctly. The
   workflow it implies - orchestrator designs, writes tests, then debugs the draft - costs more than
   writing the file. **Three explanations were eliminated by measurement first (context window,
   token cap, tooling), so this is a statement about the model, not its setup.**

## What this cannot determine

- **Per-run cost.** Daily totals are known (Part 3), but the provider reports per-day, not per-run.
  Flash's share of RV.77 is apportioned by log bytes, which is a proxy for tokens rather than a
  measurement. Per-dispatch token accounting would settle the head-to-head figure; nothing else will.
- **The RUB/USD rate** used to put GigaChat's 441 RUB beside the deepseek dollar figures, and
  whether any of that day's cloudru spend came from outside these two runs.
- **Variance.** One task, one run per model. RV.74's two flash dispatches differed by 1h53m on brief
  quality alone, so single-run wall clock should be read loosely.
- **The visual axis.** Both deepseek models are image-blind, so the screenshot-class defects that
  dominate this window's failures cannot be separated by model at all.
- **Whether pro would have rescued RV.74 #1.** The wedge was a brief defect; no arm re-ran it.

## Artefacts

```
diagnostics/model-experiment-RV.77/
  ANALYSIS.md              this file
  RV.77-PRO.log            full pro transcript (850 KB)
  RV.77-GIGA.log           full GigaChat transcript, standard brief (112 KB)
  RV.77-GIGA2.log          full GigaChat transcript, pre-solved brief (106 KB)
  RV.77-GIGA2-brief.md     the environment-pre-solved brief
  (Part 4 probe output lives in the fc-rv77-giga worktree, see below)

worktrees (uncommitted, for inspection):
  /Users/sbelyaev/repos/fc-rv77-pro     pro's implementation, all gates verified green
  /Users/sbelyaev/repos/fc-rv77-giga    no implementation from either GigaChat agent run; holds the
                                        v2 brief, a stray ReminderLifecycle.swift.bak, and the
                                        Part 4 probe artefacts - GigaChat's generated
                                        ReminderOffer.swift WITH the orchestrator's two hand
                                        repairs applied, plus pro's ReminderOfferTests.swift copied
                                        in as the acceptance test. Neither compiles to green.

flash's shipped version: commit 1bb90c8 in the main checkout
```
