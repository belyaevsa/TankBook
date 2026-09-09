# Defect patterns

*Written 2026-09-09 from one session's evidence: 20 rows shipped, 14 filed from findings, and a
recurring set of shapes that produced most of them. This is not a style guide - every pattern below
is derived from a defect that reached a user or a shipped build, and each carries the check that
would have caught it.*

**Read this before writing a brief or a fix.** The patterns are the ones this codebase actually
produces; the checks are what stops the sequel.

---

## 1. A defect has SIBLINGS. Fixing the reported one guarantees a sequel

The single most expensive shape in the project. The same logic, copied across surfaces, fixed one
surface at a time over five separate rows:

| Shape | Rows, in order |
|---|---|
| A rate-pending row summed as **zero** | `RV.106` divider → `RV.112` vitals tile + Trends series → `RV.145` currency-blind sum → `RV.147` costPerKm → `RV.148` monthly push *(still open)* |
| The **echo loop** - a pull re-dirtying a row it just applied | `RV.35` record-level → `RV.136` `.fieldMerge` arm → `RV.136` again, `Vehicle` missing from the switch |
| A write failure that **loses data silently** | `PJ.28` expense receipt → `RV.149` fill-up receipt *(still open)* |

Each fix was correct. Each was scoped to the surface that was reported. The cost is not the code -
it is five rounds of diagnosis, briefing, verification and a shipped build in between.

**The check.** When a defect is understood, **grep for the shape before fixing it**, and put the
inventory in the row. A fix ships with either every sibling fixed or every sibling filed - never with
the siblings unlooked-for. `RV.147`'s brief did this and found `monthlyCostSeries`, which the row had
not named.

---

## 2. A `default:` or fallback reachable by the normal path is a bug generator

Three defects, one shape - a fallback written for an exceptional case that the ordinary case reaches:

- **`RecordMerge.recordsEqual`** switched over every synced entity but `Vehicle`, so a Vehicle fell to
  `default:` and was compared by **raw payload bytes** - the exact comparison the call-site comment
  identified as the echo loop. Two prior fixes missed it. (`RV.136`)
- **`AddVehicleSupport.currencySymbol`** returns the **empty string** when the symbol equals the code,
  so `CHF` renders as an amount with no currency marker at all. (`RV.145`)
- **The arithmetic fallback** - built for label-free pump displays - **overrode a printed total** on a
  receipt that stated its own, and did it with a confident `lock` because the two misread numbers
  agreed with each other. (`RV.153`)

**The check.** A fallback must be reachable **only** by input the build genuinely cannot handle. Where
the discriminator is a runtime value (a `String` entity type, a currency code), compile-time
exhaustiveness is unavailable - so **enumerate the known cases in a test** and fail when one reaches
the fallback. `RV.136` shipped exactly that: a test that walks the synced-entity catalog.

---

## 3. A doc or comment that names a behaviour, with no test binding it to a call site

The project has been burned by this repeatedly, and `docs/SYNC.md` even documents its own past
instance - *"the same fiction the 'launch, foreground and timer cycles' phrasing once hid"*.

- `SYNC.md:151` promised a sync **"after every local write (debounced)"**. It never existed. The
  sentence sat **outside** the source-scan guard that had been added for precisely this class.
  (`RV.157`)
- The currency chips' hint said **"Recent first"** while nothing in that row looked at history.
  (`RV.146`)
- `recordsEqual`'s doc comment said *"two records for the same **non-`Vehicle`** entity type"* -
  **documenting the bug as if it were deliberate**, which is how two audits walked past it. (`RV.136`)
- The station row's comment said the row would come alive when `PJ.19` shipped. `PJ.19` shipped and
  did not. (`RV.156`)
- `ERRORS.md`'s "Storage full" sheet: documented, unbuilt. *(still open)*

**The check.** A doc that names a trigger, a control or a behaviour needs a **source-scan test that
fails when the call site is absent**. `SYNC.md` had one, it worked, and the drift happened in the one
sentence it did not cover - so the guard's *coverage* is the thing to check, not its existence. For
comments: **`CLAUDE.md` → Code comments already requires auditing every comment in a touched file**;
the two above survived because nobody touched those files.

---

## 4. A feature built on an entity nothing creates

`PJ.19` shipped station **ranking**. `RV.150` shipped station **stamping**. `PJ.25`/`RV.150` shipped a
Garage **stations list**. All three operated on a set that **nothing in the app could populate** -
`upsertStation` had zero non-seed callers, and the only writer was the import path. A hand-typing
user's station set was empty forever, and the entry row correctly reported "Not set" for good.
(`RV.156`)

**The check.** Before building on an entity, ask **"what creates one, and can a user reach it?"** One
grep for the write path. If the answer is "an import" or "a test seed", the feature is inert for
anyone who has not imported.

---

## 5. Rows rot, and a stale row costs more than a missing one

Three rows were read as current and were not: `PJ.28` (half delivered by `RV.62`), `PJ.19` (the
"inert label" it said to replace had already been removed), `RV.139` (its hypothesised latch had
been ruled out). Worse, the **launch-triage tables** listed `PJ.8`, `PJ.4` and `PJ.5` as outstanding
work more than a week after they shipped - the product owner hit three in a row while reading.

**The check.**
- **Status is generated, never hand-maintained.** `scripts/tasks-index.py` derives every task's status
  from its own row and stamps the triage tables; `--check` fails when stale.
- **Every brief opens by re-verifying the row's premise**, and says so: *"this brief's reading is a
  hypothesis - confirm it before you change anything."* Four orchestrator diagnoses were wrong this
  session and an agent caught each one.

---

## 6. A test can encode the defect

`MoneyBackfillServiceTests` asserted `costPerKm = 0.1` for a window whose pending row was skipped -
the exact behaviour `RV.147` existed to remove. The test was not wrong when written; it froze a
defect nobody had named yet.

**The check.** When a fix makes a test fail, ask **"is this test asserting the bug?"** before changing
the fix. Rewrite it to the new contract in the same change and say so in the commit.

---

## 7. Measurement drifts silently, because a green ratchet only fails downward

Adding nine corpus fixtures broke four separate pinned numbers at once. Worse, the **pump high-water
mark was already stale** - the live score had improved from 31/178 to 37/199 and was never recorded,
because a ratchet that only fails on regression accepts an unrecorded gain in silence.

The same growth revealed a real quality change that no gate would have reported on its own: **pump
precision fell from 100% to 92.5%**, because four new displays produced three confident-wrong values.
Precision had been holding at 100% *on a corpus that did not contain them*.

**The check.** Adding fixtures is a **re-measure-everything event**: `high-water.json`, the
`PumpPhotoGate` constants, the corpus row pins and the compression mark. Re-measure from a live run;
never derive a number by arithmetic. And **a corpus that only gets easier cannot fail** - the fixtures
that matter are the ones the parser gets wrong.

---

## 8. The orchestrator's own process failures, and the fences that now exist

Recorded because each cost real time and each is now cheap to avoid:

| What happened | Fence |
|---|---|
| `swiftlint` run from `ios/` **three times** - exit 2 with ~5000 phantom errors from root-relative `excluded:` paths | Every brief says **run it from the repo ROOT, not `ios/`**, and says why |
| `git add ios/Tests` **swept a running agent's file** into an unrelated commit, landing tests a commit ahead of the code they exercise | Stage **explicit paths**, never a directory, while a dispatch is live |
| Edited the checkout **while an agent was working**; it noticed and reported files changing under it | Assume concurrent writers; tell each agent which tree is off limits |
| An agent ran `git stash` + an `mv` loop to get a clean baseline and **destroyed three of its own new files** | *"Write the test, run it, then change the code"* - never stash, move or checkout |
| A `simctl launch` on an already-running app **ignored the language argument**, so an "RU" screenshot was English with Russian dates - and it passes an md5-difference check | `terminate` first; **the orchestrator opens every screenshot** |
| Two agents dispatched in the same second → `database is locked` | Stagger dispatches; one agent at a time unless the toolchains are disjoint |

---

## The three habits that caught the most

1. **Open every screenshot personally.** Three defects this session were visible only in an image -
   an English "RU" capture among them. No test asserts colour, truncation or language.
2. **Read the failing number, not the report.** Gates are judged by **exit code** in the
   orchestrator's own hands. An agent's summary is a claim; `echo $?` is evidence.
3. **A finding outside the fence gets filed, not fixed.** Six of this session's rows came from agents
   reporting something they were told not to touch - `RV.148`, `RV.149`, `RV.150`, `RV.153`'s
   leftovers, and the two Trends observations. A fence plus a report is how a task stays one task
   and nothing gets lost.
