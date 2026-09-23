# Development timeline - how the way we work has changed

**A ledger of changes to the development APPROACH** - not features, not fixes. Every entry names
the commit, the date, the reason, and the evidence that forced the decision. The rule (product
owner, 2026-09-11): **every change to how we develop is recorded here, with commits, dates, reason
and evidence, in the same change that makes it.** A process rule that lives only in someone's head
is the thing this file exists to prevent.

Newest first. The companion analyses in `docs/analysis/` carry the numbers; this file carries the
decisions.

---

## 2026-09-23 · Pump rows apply published methods, and an agent reviews each for completeness

| | |
|---|---|
| **Commits** | this entry's commit (the PU.67-PU.77 tranche, `agents/briefs/RESEARCH-TO-CODE.md`, `agents/briefs/REVIEW-PU-COMPLETENESS.md`) |
| **Reason** | Product owner, after the Qwen whole-pipeline review: *"make an implementation and validation (like journey review agent) plan. The agent reviewer each time validates the completeness of the implementation. Register it. Review the published research to apply it into the code, instead of coming up with our own solution."* |
| **Evidence** | 66 PU rows were built from in-house heuristics tuned on the corpus; several were measured, refused or reverted after the fact (PU.53 and PU.55 moved nothing, PU.58 lost cells, PU.66's three detector retrains were refused, PU.59's cautioned tier measured 1 in 10 and was held). The Qwen review (`agents/reviews/PUMP-REVIEW-2026-09-23-qwen.md`) mapped the open losses to published methods - oriented text detection, fast Hough skew estimation, a-contrario line fitting, temperature scaling, conformal risk control, focal loss, constrained decoding, CRNN/CTC - none of which the pipeline uses. PU.59 also showed a row can be ticked-ready while a promise inside it is unmeasured: the cautioned tier's real number surfaced only in the orchestrator's final run. |
| **What changed** | For the PU.67 tranche: (1) a row that cites a paper gets a **research note first** (`RESEARCH-TO-CODE.md` → `agents/research/<row>.md`): citations checked against the source, the method as published, the mapping onto our code, and every departure named and justified; a departure not in the note needs the owner's OK. (2) The orchestrator builds and gates. (3) **A reviewing agent runs `REVIEW-PU-COMPLETENESS.md` on every row before it is committed** - fidelity to the paper, wired into the app path, measured on the named population, no regression, tests that go red under mutation, docs reconciled, every promise in the row - and the orchestrator commits only on a COMPLETE verdict. This is an agent review, unlike the journey and scenario walks the orchestrator runs itself (2026-09-12); those are unchanged, and J4 gets its scenario walk when the tranche closes. |

## 2026-09-23 · The pump path is debugged in a trace of the app's own run, and a pipeline change reaches that view

| | |
|---|---|
| **Commits** | this entry's commit |
| **Reason** | Product owner: *"a tab / view, where I can debug step by step on multiple images … how the pipeline works … visually, rather than look at json"*, and *"all the pipeline must be the same as in other parts of the annotator and the app. Only intentionally switch model, classifiers"*, then *"If a pipeline changed, that should be reflected in the annotator tool."* |
| **Evidence** | Building it found the annotator's existing live read (`/api/read` live, compare) running `PumpReader.readPhotoDetailed`, while the app's capture runs `PumpDisplayCapture.classify` - a different path (a fast / slow decision with a 1.5 s cap, the seed-then-search order, the turned-row retry). Its diagnostics also re-ran candidates, verify and read after the answer, so what it drew was a second run. On the batch-10 rain stills the new view places pump-323's wrong commit at stage 6: the total's cells read `3 9 0 7` for `6 5 0 3`, every margin under 0.4 but one. |
| **What changed** | `PumpTrace`, an optional observer threaded through `classify` (nil on the app's path), recorded by `pump-read --trace-serve` and drawn by the annotator's ⛓ pipeline view. `PumpTraceParityTests` pins traced == untraced and that the chosen attempt carries the returned law (red when the trace is allowed to change the path). The server rebuilds the optimised tool when any package Swift is newer and restarts the resident tracer on a new binary. The rule for the next change to the pump path: its hooks, the trace JSON and the view's stages move in the same change. |

## 2026-09-23 · A second frozen draw, and a written rule for which split a capture joins

| | |
|---|---|
| **Commits** | this entry's commit |
| **Reason** | Product owner: *"pick up some with rain drops to non-train corpus"* and *"add to the /corpus-intake rules - what to register to heldout2, heldout or to train"*, with the outside review `agents/reviews/PUMP-REVIEW-2026-09-23-qwen.md` to take into account. The review found that the only frozen set is no longer fully held out of the pipeline's constants (§2.4.4: slicer fractions, the law's windows and the widening margin were swept against heldout live numbers) and that 45/45 committed-correct bounds precision at only ~0.92 (§2.1) - a second, untrained-on, untuned-against draw is the only fix it names. |
| **Evidence** | Batch 10's ten rain stills: auto-annotation through the shipped live path committed **two wrong readings** (`pump-323` 39.07 / 33.88 for 65.03 / 33.89; `pump-325` 70 / 80.7 for 174.01 / 83.10) - the first wrong commits on an owner capture, a condition the heldout had never shown. The detector export would have leaked the new split: `detdata` sent every still whose split was not exactly `heldout` into its train directory. |
| **What changed** | A third split value, `heldout2` (`docs/EXTRACTION.md` → decision 9, amended 2026-09-23): no model trains on it, no constant is tuned against it, it is measured only when a change is judged. The intake rule (`.claude/skills/corpus-intake` step 2b): **train** by default; **`heldout2`** for an under-represented condition, chosen as whole fills with their Live records, before any model trained on them; **`heldout`** never. Video frames never join a heldout one by one (adjacent frames are near-copies). `corpus_db.heldout_names` returns every non-train still; `detdata` writes a `heldout2` still to neither of its directories (test `test_a_second_frozen_draw_reaches_neither_directory`, red when the exclusion is removed). Basis: pump cells 865 → 889; `heldout2` is 4 stills, `heldout` stays 68. |

## 2026-09-23 · A release needs the app's sources committed, not the whole tree

| | |
|---|---|
| **Commits** | this entry's commit |
| **Reason** | Product owner: *"make scripts/release.sh ignore docs and non-app files to prepare release"*. The release script refused to archive while ANY tracked or untracked file differed from HEAD, so a doc edit, a corpus annotation in progress or a stray tool file blocked a release whose archived bytes they could not change. |
| **Evidence** | On 2026-09-23 the working tree held uncommitted corpus files (`corpus.sqlite`, `videos.json`, `video-labels.json`, `pump/windows.json`, `corrections.jsonl`) from annotation work; none is read by the app build (`project.yml` compiles `ios/App/Sources` + `ios/App/Resources` and the `TankbookCore` package), yet each one alone made `scripts/release.sh` exit 2. |
| **What changed** | `scripts/app-paths` lists the paths an app build reads (`project.yml`, `ios/Package.swift`, `ios/Package.resolved`, `ios/Sources/TankbookCore`, `ios/App` minus its two test bundles). `scripts/release.sh` refuses only when one of THOSE differs from HEAD - untracked files under them included, because xcodegen compiles a new source file in - and reports the count of other uncommitted changes as not part of the build. The build's commit stamp (`project.yml`, "Stamp build commit") reads the same list, so a release built beside a doc edit is stamped with its commit, not `-dirty`. The build number is unchanged: still the commit count. |

## 2026-09-22 · A brief counts its population before it is written

| | |
|---|---|
| **Commits** | this entry's commit; the evidence is `agents/reviews/PUMP-DECIDE-2026-09-22-fable.md` (`c77d6004`) |
| **Reason** | Three pump rows in a row were briefed against a population nobody had counted, and all three moved the end-to-end number by **zero**. The reviewer's verdict on the whole arc, PU.1 to PU.60, was that the architecture is right and **the unit of work is wrong**. The briefs were mine, so this is a brief-writing failure, not an execution failure - every one of the three agents did competent work on a question that could not pay. |
| **Evidence** | **PU.53** was briefed as *"five heldout stills carry a rotation (pump-019..023)"*; `Spike/ReceiptSpike/fixtures/pump/split.csv` marks `pump-020`, `021` and `022` as `train` - the heldout population was **2**, and both of those refuse for reasons orientation cannot fix. **PU.54** was briefed against PU.51's *"26 `boardFoundNoPrice`"*; the reachable set was **9**, because the rest fail an earlier guard. **PU.55** was briefed on cut ink at a strip's edge; that signal does not exist - the clipped strip's edge is *quieter* than the framed one, and the row was refuted after a full run. **PU.58** then held the shipped live path at 43 and gained one annotated cell. Four rounds, one measured gain (PU.54's +4), and the reviewer found the 112-vs-47 apportionment - the measurement that would have priced all four - had been asked for by PU.52 and never run. |
| **What changed** | A brief that claims a row will move a number **names the population it will move it over, counted from the corpus at the commit the brief is written against, with the file and the filter that produced the count**. "The histogram says 26" is not a count - it is an upper bound until the rows that fail an earlier guard are subtracted. A row whose population cannot be counted before the work is a **measurement row first**, and the build row waits for it. The `Vacuous traps` section of every brief gains the trap this rule exists for: *building against a population nobody counted*. This does not replace the baseline numbers a brief already carries; it is the denominator those numbers move within. |

## 2026-09-22 · The API is live: every change to it is backward-compatible (hard rule 16)

| | |
|---|---|
| **Commits** | this entry's commit |
| **Reason** | Product owner, with build 1368 in the store: *"as the app is live, we should put a rule - all the API changes must be backward-compatible"*. A shipped build cannot be recalled and a user may never update, so the contract an older client speaks has no end date. |
| **Evidence** | `docs/API.md` already carried two breaking-change notes whose stated justification was *"the only consumer is this repo's own iOS client, changed in the same commit"* (P6.12's `kind` field; the 2026-09-04 nullable last year). That reasoning was sound before the release and is void after it - the client is now on phones this repo cannot update. |
| **What changed** | Hard rule 16: within `/v1` only additive change (a new optional request field, a new response member, a new endpoint, a new error code, a wider limit); anything else - a removal, a rename, a narrowed type, a newly required field, a changed status or code meaning, a tightened limit, or the same name with a new meaning - is a second endpoint or `/v2`. Every API change states its verdict in `docs/API.md` in the same change and names the oldest client it was checked against. Payload evolution stays under `SYNC.md`'s registry-and-transforms rule. |

## 2026-09-21 · The frozen heldout set takes four night stills

| | |
|---|---|
| **Commits** | this entry's commit (batch 7 of the corpus) |
| **Reason** | Product owner: *"move some night photos captured from train"* - the 64-still heldout draw of 2026-09-19 (decision 9, `docs/EXTRACTION.md`) held no owner-captured night display, so the only honest measurement of the reader said nothing about a forecourt at night. |
| **Evidence** | `pump/split.csv` at the draw: the four night stills in heldout are all third-party (`pump-186`, `187`, `201`, `208`); the 2026-09-21 night set (`pump-274`..`281`) was the first owner-captured one. |
| **What changed** | Decision 9's "never add a heldout row" is amended once, in writing: a still may join the heldout set only **before any model has trained on it**, and the move is recorded in `EXTRACTION.md` under the decision. Four of the eight (`pump-275`, `277`, `280`, `281`) moved; the other four stay train so the classifier sees night glyphs too. The heldout set is 68. The marks measured on the heldout (`PumpReaderHarnessTests`, `PumpReaderPipelineTests`, `PumpDisplayCaptureTests`) carry the added cells as totals only until the measured runtime runs. |

## 2026-09-18 · Pump displays get a trained reader; Python training code enters the repo

| | |
|---|---|
| **Commits** | the PU tranche on branch `pump-reader` (this entry lands with PU's first commit) |
| **Reason** | Product owner: *"we need to develop our own library to recognize pump photos. Not rely on OCR solely."* Steps 1–3 of `docs/EXTRACTION.md`'s order were done and pump mode was still off at 53/320 - the rules parser is blind on seven-segment glyphs and Vision misreads them at confidence 1.00. |
| **Evidence** | `PumpPhotoGate` 53/320 committed-correct (P2.7 off since 2026-08-25); `pump-004` (wrong digit at 1.00), `pump-009` (decimal shift), `pump-013`/`pump-015` (9-as-4); the cloud model's five confident swaps in the P4.12 A/B. |
| **What changed** | Two things. **A trained model is now part of the extraction pipeline** for one narrow, optical, synthesizable problem - the corpus stays held-out and the same gate scores it, which is the condition EXTRACTION.md set. **Python lives in the repo** under `ml/pump-reader/`, outside every gate but its own `pytest`; nothing in `scripts/gate.sh` or CI depends on it. The tranche is built in a worktree (`../fuel-counter-ios-pump-reader`, branch `pump-reader`) - the one exception to the no-worktrees rule, asked for by the product owner. |

## 2026-09-14 · An additive schema change ships a registry refresh migration

| | |
|---|---|
| **Commits** | `RV.284` (this entry's commit) |
| **Reason** | `payload_schemas` is seeded once, by migration 002, with `ON CONFLICT DO NOTHING`. `RV.218` added the `consumption` conflict kind and regenerated `fillUp.schema.json` **same version 1**, so every backend built since embedded the new enum but a database that ran 002 before it kept the old row and no migration touched it: the deployed registry rejected what the app emitted, on every push, forever, with nothing on the device saying so. |
| **Evidence** | Production log 2026-09-14: two `fillUp` records created 2026-09-07 returned `rejected · payload_schema_violation · /conflict/kind` on every push, twice a minute while the app was open. |
| **What changed** | The seeder gains a refresh marker (`DO UPDATE SET json_schema = EXCLUDED.json_schema`); migration 023 is the first refresh, and an additive change inside a version now ships a refresh migration at the current highest number as part of the same change. `docs/SYNC.md` "The schema registry lives in the database" names the rule: additive-only within a version, a removal needs a new `schema_version` and an upcaster. |

## 2026-09-14 · A second dispatch path: Codex on `gpt-5.6-sol`

| | |
|---|---|
| **Commits** | the commit carrying `scripts/dispatch-codex.sh` |
| **Reason** | Every `opencode run` since 19:10 on 2026-09-14 died at its banner - four dispatches, two probes - and the provider was live. The cause was local: opencode's session database had grown to 22 GB on a disk at 97%, and each new run stalled opening it. The product owner directed the dispatch to Codex on the `gpt-5.6-sol` model, and the database was deleted on the owner's instruction (the transcripts in `/tmp/agentlogs` and the ledger in `TASKS-HISTORY.md` are the record; the database held nothing else). |
| **What changed** | `scripts/dispatch-codex.sh` mirrors `dispatch.sh`: brief plus preamble on stdin, detached with its own log (`<id>-codex.log`, the final message in `<id>.last.md`), health-checked by log bytes at 60 s, one retry; approvals and sandbox bypassed, the same standing as `opencode run --auto`, because `xcodebuild` writes outside the workspace. The health threshold is 2 000 bytes, not 8 000 - Codex logs less in its first minute. Everything after launch is unchanged: the pid is monitored, the report is not evidence, the orchestrator verifies. The dispatch ledger names the worker as `codex sol`. **Same evening, corrected**: the database was a real problem, but not this one - `deepseek/deepseek-v4-pro` answered a one-word probe in seconds while `deepseek-v4-flash` still hung at the banner on the fresh database. The product owner's read was right: the flash endpoint is what died. `scripts/dispatch.sh` now defaults to **pro**; flash is passed explicitly when it is worth trying again. The Codex run itself hit the account's usage cap at the moment of its report, so the orchestrator verified the tree without one - which is the standing rule anyway. |

## 2026-09-12 · Scenario and journey walks are the orchestrator's own work

| | |
|---|---|
| **Commits** | this entry's commit (`CLAUDE.md`, `REVIEW-SCENARIO.md`) |
| **Reason** | Product owner, 2026-09-12: *"journey-walks you can do by yourself, don't dispatch to pro agent."* The walks are reading and judgement over the tree and the journey text, which the orchestrator already does when it verifies each agent's report; a pro dispatch added cost, a dead-launch retry one time in three today, and a second-hand report the orchestrator had to re-read anyway. |
| **Evidence** | 2026-09-12: 14 pro walks, 3 of them launched dead first; every verdict was re-read against the tree before its status line was accepted, and two were held on owner evidence the agent could not weigh (J8b, J13 on `RV.181`). |
| **What changed** | `REVIEW-SCENARIO.md` and `REVIEW-JOURNEYS.md` stay as the METHOD; the orchestrator executes them and writes the report to `diagnostics/` under the same names. Build dispatches are unchanged (flash). |

## 2026-09-12 · UI suites run signed; a host-dependent test skips itself

| | |
|---|---|
| **Commits** | `RV.257`+`RV.258` (this entry's commit); `PREAMBLE.md` fence |
| **Reason** | Three agents in one day reported 21 `SettingsUITests` failures and a SignIn cluster "on clean HEAD"; none reproduced in the orchestrator's hands. The RV.257+RV.258 agent found the cause: agents copied `gate.sh`'s `CODE_SIGNING_ALLOWED=NO` onto UI-suite runs, which strips the Keychain entitlement, so every signed-in test fails. Separately, four real-center reminder tests passed or failed with the simulator's notification daemon on the same tree, and one sign-in L4 cost an hour of false bisecting. A gate that is red for reasons the tree cannot change is a gate people learn to ignore. |
| **Evidence** | `RV.260`, `RV.256`, `RV.261` reports (21 failures each, never reproduced); `RV.258`'s four flipping between 205/205 and 201/205 across the day; the RV.249 mis-attribution (memory `never-bisect-a-ui-test-on-one-sample`). |
| **What changed** | `PREAMBLE.md`: UI suites run signed, the flag is for the unit bundle only. `ReminderNotificationActionTests` probes the daemon once per run and `XCTSkip`s the four real-center tests with the documented reason, so the bundle count says what was verified (205 with 4 skipped on a dropping host). `-signInStubAuth` stubs the sync transport too, so the first push is answered instantly; RV.257's stated real-network cause was wrong (the seeded transport was already offline), and the row's tick says so. |

## 2026-09-12 · The baseline gate tests the app target, not only the package

| | |
|---|---|
| **Commits** | `RV.250` (this entry's commit) |
| **Reason** | `RV.174` made the gate compile the app; it still ran only the package tests. The app-target unit bundle (`TankbookTests`, hosted in the app) is a separate bundle `swift test` never runs, so a row can orphan another row's app-target test and every gate stays green. |
| **Evidence** | `RV212ServiceCreateDoorTests.testAMountedTireSetWithNoOdometerStillRefuses` was red from `RV.214` (`daa6959`) until `RV.247`'s agent found it two rows later: `RV.214` made `saveReadiness` branch on `mode == .tires`, the test set only `tireSetId`, and nothing ran the bundle. |
| **What changed** | `scripts/gate.sh` runs `xcodebuild test -only-testing:TankbookTests` as its own step after `swift test`, stopping on non-zero, in its own invocation per the two-bundle rule. `TESTING.md` (baseline gate, rule 9), hard rule 14 and `PREAMBLE.md` name it. Teeth proven: the reconstructed `daa6959` test makes the gate exit 65 at the new step with every package step green; removing the step lets the same test pass. Measured ~15 s of test time (195 tests) on top of the gate. |

## 2026-09-11 · The baseline gate is one script, and it compiles the app

| | |
|---|---|
| **Commits** | `RV.174` (this entry's commit) |
| **Reason** | `swift build` + `swift test` exercise the SwiftPM package only; every screen lives in the app target, which only `xcodebuild` compiles. A task could pass every per-task gate and not compile into the shipping app. |
| **Evidence** | 2026-09-10, finishing `RV.159` by hand: build 0, lint 0, 1826 package tests green, and `xcodebuild` failed at `FeedbackComposerView.swift:50`. The same escape hard rule 14 already named for Debug-vs-Release, through the package-vs-app door. |
| **What changed** | `scripts/gate.sh` runs package build, lint, xcodegen, the app-target Debug build and the tests in that order and stops at the first non-zero; `RELEASE=1` adds Release. `PREAMBLE.md` calls it; `TESTING.md` and hard rule 14 name it. Its teeth were proven with a scratch compile error before it was accepted: exit 65 at the app step, tests never run. |

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
