# Development timeline - how the way we work has changed

**A ledger of changes to the development APPROACH** - not features, not fixes. Every entry names
the commit, the date, the reason, and the evidence that forced the decision. The rule (product
owner, 2026-09-11): **every change to how we develop is recorded here, with commits, dates, reason
and evidence, in the same change that makes it.** A process rule that lives only in someone's head
is the thing this file exists to prevent.

Newest first. The companion analyses in `docs/analysis/` carry the numbers; this file carries the
decisions.

---

## 2026-09-11 · The unit of work becomes a scenario

| | |
|---|---|
| **Commits** | `aa38de4` (queue by scenario, `scenario-index.py` change), `8fbdf41` (queue reorder, seam rule), `8f63c86` (the review that argued for it) |
| **Reason** | *"Set the queue with a goal to complete the defined scenarios / journeys, one after another"* (product owner). Rows were being dispatched one at a time; each agent's *found and not fixed* list became the next dispatch; the backlog grew at ~2 rows per dispatch by construction. |
| **Evidence** | `docs/analysis/2026-09-11-process-and-backlog-review.md`: 37 of 214 RV rows described themselves as the sibling or remainder of an earlier row; three dispatches on 2026-09-11 filed seven new rows; zero of 39 scenarios were marked implemented and six had every row closed and had never been walked. |
| **What changed** | A scenario is worked to its verdict - seam briefs, `REVIEW-SCENARIO` re-run, status line - before anything from the next is dispatched. **The seam is the unit of a brief**, and the agent is authorised to fix a same-function sibling and told to file a different decision. `scripts/scenario-index.py` treats a `[v1.1]`/`[v1.x]`/`[v2]` row as not holding a v1 story open. |
| **First result** | Same day: J5, F5, F8, F6b, F2 walked to IMPLEMENTED (with F3 from the morning, six status lines); one line in the assembler closed two scenarios. |

## 2026-09-11 · The fixed cost of a dispatch is mechanised

| | |
|---|---|
| **Commits** | `2ca6754` |
| **Reason** | A third of every brief was the same fences typed again (155-180 lines, task-specific content ending around line 106-128); one dispatch in four came up dead and was re-dispatched by hand after a manual byte check; a combined `-only-testing` across two bundles ran one and exited 0. |
| **Evidence** | `RV.201` died at 42 KB of log on 2026-09-11 and was relaunched by hand; the two-bundle trap was hit live verifying `RV.201` (12 tests executed, app-target suite never ran, exit 0). |
| **What changed** | `agents/briefs/PREAMBLE.md` carries the fences once; `scripts/dispatch.sh <id> [model]` appends it, launches, checks bytes at 60 s and retries once; the two-bundle rule is in `CLAUDE.md`. |

## 2026-09-11 · Orchestrator model switched from Claude Opus to Claude Fable 5.1

| | |
|---|---|
| **Commits** | Last Opus-attributed: `fd1b84c` 15:23. First Fable-attributed: `8f63c86` 15:29. (`fe782b7`, 2026-08-29, is an earlier isolated Fable session.) |
| **Reason** | Product owner's `/model` switch to **Fable 5.1**, made at the moment the process review was requested. Not a response to a defect in the orchestration; recorded because a model change is an approach change and its effects should be readable against the commits either side of it. |
| **Evidence** | The attribution line on every commit from `8f63c86` onward. |
| **Note for readers** | Everything from the process review onward - the queue rewrite, eight scenario walks, scenarios 1-4, the TASKS sweep - is post-switch. Compare the verification record either side (`docs/TASKS-DONE.md` outcome paragraphs) before attributing any difference to the model; the process also changed at the same moment. |

## 2026-09-11 · Every RV row is measured, from git, with a chart

| | |
|---|---|
| **Commits** | `cf44b27`, `9f4dafd` |
| **Reason** | *"analyze how fast the tasks were added and closed ... a chart that shows both lines from commit to commit"* (product owner). |
| **Evidence** | `docs/analysis/2026-09-11-rv-backlog-and-process.md`, `scripts/rv-backlog-chart.py`, `design/analysis/rv-backlog.png`. Recomputed from 498 commits to the task files; corrected mid-analysis when the first parse missed rows whose id carries a version marker. |
| **What changed** | The backlog's rate is a re-runnable artefact rather than a feeling. |

## 2026-09-10 · Agent model upgraded from DeepSeek v4 flash to v4.1 (provider-side)

| | |
|---|---|
| **Commits** | none - the model id in every dispatch is unchanged (`deepseek/deepseek-v4-flash`); the upgrade happened on the provider's side under the same alias. Product owner's statement, 2026-09-11: *"yesterday there was an upgrade from flash-v4 to v4-1."* |
| **Evidence** | `opencode models` on 2026-09-11 lists no `v4.1` id (`agents/QUEUE.md` -> Models available here), so the version served behind `deepseek-v4-flash` is the only place the change exists. Dispatches from 2026-09-10 onward ran on 4.1: `RV.170`, `RV.171`, `PJ.22`, `RV.206`, `RV.201`, and every scenario row on 2026-09-11. |
| **Note for readers** | This overlaps the orchestrator switch below by one day and the scenario-first process by two. Three variables moved in 48 hours; do not attribute a change in agent report quality to any one of them without checking the verification record in `docs/TASKS-DONE.md` either side. |

## 2026-09-10 · Every task belongs to a scenario, and a scenario is not done until it is reviewed

| | |
|---|---|
| **Commits** | `4ef5192` (`CLAUDE.md` convention, `scripts/scenario-index.py`, `agents/briefs/REVIEW-SCENARIO.md`) |
| **Reason** | Ticked tasks are what somebody thought of; the journey is what the user was promised. Nothing compared the two. |
| **Evidence** | J7's Fallbacks sentence promised *"the user renames/splits by hand"* from the day it was written; `PJ.23` shipped the rename; nobody noticed the split was never filed until the product owner opened the screen. |
| **What changed** | Every open row names its parent journey (`--check` fails one that does not); a completion review runs when a scenario's rows are closed; only its IMPLEMENTED verdict may write `Status: implemented`; a row that changes a story edits `JOURNEYS.md` in the same change. |

## 2026-09-10 · The source-scan guard family

| | |
|---|---|
| **Commits** | `EntityWriterScanner`, `FieldWriterScanner`, `ScreenRouteScanner`, `StationMintingScanner`, `ImportCandidateCopyScanner`, `JourneyLaunchArgumentScanner` (2026-09-10), `ReceiptBindingScanner` (2026-09-11) - see `git log --diff-filter=A -- 'ios/Tests/TankbookCoreTests/*Scanner.swift'` |
| **Reason** | Invariants that lived as conventions kept being broken silently: a field with no writer, an entity nothing creates, a second path beside the one the app runs. |
| **Evidence** | `PJ.55` shipped three features onto a flag nothing could set; `RV.189`'s value was dropped in a copy helper no link covered; `FieldWriterScanner` was built for three known dead fields and reported eight. |
| **What changed** | Each guard is a pure function over source text with a reasoned exception list where a blank reason and a stale unused entry both fail the guard's own self-check. The loop - guard reports, row filed, exception names the row, row deletes the exception - closed four times in the week of 2026-09-10. **Sequencing rule**: build a guard against a seam just settled, never a hypothetical. |

## 2026-09-09 · The journeys walk is recurring, and the defect shapes are written down

| | |
|---|---|
| **Commits** | `d00293f` (recurring walk), `9936629` (`docs/DEFECT-PATTERNS.md`) |
| **Reason** | The walk had run once (2026-08-29), produced 66 `PJ` rows, and was never repeated while 643 commits landed. The same defect shape kept arriving under new names. |
| **Evidence** | Every product-reachability gap in `DEFECT-PATTERNS.md` Part 2 was found by that one review or by the product owner using the app - never by a test, code review or the type checker. `PJ.28` -> `RV.149` -> `RV.173` -> `RV.202`: one shape, four rows, ten days. |
| **What changed** | The walk runs every 10 shipped rows or at a phase gate, plus four named trigger events. Eight defect shapes, each with the check that catches it, are required reading before any brief. |

## 2026-09-08 · The backlog is split from its history, with a generated index

| | |
|---|---|
| **Commits** | `bb7f83b` |
| **Reason** | Open and closed rows were interleaved in one file; picking up work meant reading finished work. |
| **Evidence** | Two findings were filed as new that existing rows already carried (`PJ.23` re-filed as *"RV.195's leftover"*; `RV.165` duplicating `RV.110`). |
| **What changed** | `docs/TASKS.md` (open) / `docs/TASKS-DONE.md` (closed, with reasoning); `scripts/tasks-index.py --check` fails when the index is stale. |

## 2026-09-05 · Flash by default; pro only after flash has failed or for read-only investigation

| | |
|---|---|
| **Commits** | recorded in the orchestrator's memory (`agent-model-routing`), superseding an earlier by-kind split |
| **Reason** | Most "design work" collapses into wiring once the cause is pinned; pro is the slow, expensive option. |
| **Evidence** | `RV.6-INVESTIGATE` on pro cost 89 KB of log, an order of magnitude less than a build run, and produced the brief flash executed cleanly. Every shipped defect that week was caught by a hand-run mutation or an opened screenshot - three of them on pro's work. **Verification, not model tier, is the safety net.** |
| **What changed** | Diagnose first, dispatch to flash, escalate only on evidence; read-only investigations may go to pro first. |

## 2026-08-29 · The full UI suite runs at phase completion, not per task

| | |
|---|---|
| **Commits** | `614a093` |
| **Reason** | Five full runs in one day cost ~2h15m and found one genuine defect and two false reds from contention. |
| **What changed** | Per task: `swift build`, lint, the full unit suite (never subsetted), and only the UI suites the task touched by name, with a non-zero count checked. |

## 2026-08-24 · Validation runs on a separate agent; two doors, always

| | |
|---|---|
| **Commits** | `1d31c62` |
| **Reason** | A validator's summary is still an agent report - read its captured exit codes, not its prose; the orchestrator still opens every screenshot because agents have no image input. Hard rule 15 written the same day: typing and scanning are peers, never scan-with-a-fallback. |

## 2026-08-23 · The founding rules

| | |
|---|---|
| **Commits** | `1e31928` (it builds and it lints), `8fb4835` (commit after independent verification; EN + RU screenshot per UI task), `51905c7` (health-check every dispatch), `a829e04` (every brief written to `agents/briefs/` before dispatch) |
| **Reason** | Each was written the day something went wrong once: a green suite beside a red-accent tab bar (hard rule 5, caught only by looking); a dispatch that sat six hours with an empty log; a brief in a temp directory that could not be told from a bad agent. |
| **What changed** | Verify first, commit second; one task, one commit; roughly one dispatch in four is dead and the decisive signal is log bytes; the brief is the record of what was asked. |
