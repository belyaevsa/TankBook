# REVIEW-PU-COMPLETENESS – is this pump row actually done?

*The template. Every run gets its own copy, `agents/briefs/REVIEW-COMPLETE-<row>.md`. Dispatched to a
reviewing agent **after every row in the PU.67 tranche is built and gated, before it is committed**
(product owner, 2026-09-23: *"the agent reviewer each time validates the completeness of the
implementation"*). It is to a pump row what `REVIEW-SCENARIO.md` is to a journey: a row is not done
because its code compiles and its tests pass – it is done when what the row promised is in the tree,
wired, measured and written down. The orchestrator commits only on a `COMPLETE` verdict.*

## Fill these in for the run

- **Row:** `PU.68` – Interval estimates, a detector override, and the leak's consequences (`docs/TASKS.md`)
- **Research note:** `agents/research/PU.68.md`
- **The diff under review** (working tree against `c86755d6`; ONLY these paths are PU.68 – another
  session is editing `PumpReader.swift`, `PumpDisplayCapture.swift`, `PumpTrace*.swift`,
  `PumpReadTool/main.swift` and `tools/pump-annotate/` concurrently, which is not under review):
  `ios/Tests/TankbookCoreTests/PumpPrecisionBounds.swift` (new), `PumpPrecisionBoundsTests.swift` (new),
  `PumpLeakConsequenceTests.swift` (new), `PumpReaderPipelineTests.swift`, `PumpReaderTestSupport.swift`,
  and the PU.68 / PU.78 / PU.69 rows in `docs/TASKS.md`.
- **The orchestrator's gate evidence:**
  - `/tmp/agentlogs/pu68-pipeline.log` – `PUMP_CERTIFY=1 swift test --filter PumpReaderPipelineTests`:
    live 45/45 with interval, annotated 111/110 with interval (its 112 floor was red before this row),
    the train-split certificate (124 committed, 117 correct; photo UCB 0.2108 at delta 0.05).
  - `/tmp/agentlogs/pu68-leak.log` – `PumpLeakConsequenceTests` before it was made opt-in: 6 of 116
    routed, 0 commits; the ceiling was then set to 6 and the test gated behind `PUMP_LEAK=1`.
  - `PumpPrecisionBoundsTests`: 3 tests pass; mutation (Wilson centre replaced by x/n) turned it red
    with 10 issues, restored.
  - `/tmp/agentlogs/pu68-swifttest.log` – full `swift test`: exit 1, failures named in its tail;
    `/tmp/agentlogs/pu68-appunit.log` – app unit bundle 301/301. App build exit 0.
  - `swiftlint lint`: 0 errors in the PU.68 files; the tree's one error is in `PumpReader.swift`
    (the other session's edit).

**Row-specific notes for your checklist:**
- Item 2 (wired into the app path) is **not applicable in the usual sense**: PU.68 is a measurement
  instrument and ships nothing to the device, by the note's §7. Check instead that the instrument
  measures the APP's path (`makeReader`, `classify`) and not a test-only reader.
- Item 1: check the formulas against the note's §2 and §4 and that every departure is in §8 (A1-A10).
  In particular: is the photo the loss unit (A4), is the certificate labelled in-sample (A2), are
  Wilson (estimate) and exact binomial (certify) kept in their separate roles (A7)?
- Item 7: the row's Checks cell promises "the leak test scores what each non-pump fixture routed as a
  pump COMMITS (fields, values' presence only - hard rule 12) and names them" and "a second frozen
  heldout draw is the owner's call, asked, not assumed" – say whether each is met; the owner's corpus
  commit `c86755d6` created `heldout2`.
- Say whether any of the full-suite failures in `pu68-swifttest.log` is caused by the PU.68 diff.

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:**
`agents/reviews/PU.68-COMPLETENESS.md`. No code, no builds that write, no commits. You may run
read-only tools and the pump measurement tool (`swift run PumpReadTool`) if a number is missing –
say that you did, and that the machine may be loaded.

## What you are checking – each item MET, PARTIAL or MISSING, always with `file:line`

1. **Fidelity to the published method.** The code does what the research note says the paper does.
   Every departure is one the note lists and justifies, or one the product owner approved. An
   unlisted departure is MISSING, however good it looks – name the paper section it departs from.
2. **Wired into the app path, not only the harness.** The change reaches `PumpDisplayCapture.classify`
   and `CapturePipeline` (the path the phone runs), in Release as well as Debug. A method reachable
   only from `PumpReadTool`, a test or a `#if DEBUG` seam is the "docs naming behaviour with no call
   site" shape (`docs/DEFECT-PATTERNS.md`) – MISSING.
3. **Measured on the app path, on the named population.** The live-path floor
   (`PumpReaderPipelineTests.livePath`, the app's `classify`) ran, the committed/correct counts are
   in the gate evidence, and they match `PumpPhotoGate`'s reader constants. The row's own claimed
   movement is reported over the population the row named, with the interval beside the point
   estimate once PU.68 has landed. **Zero new wrong readings** unless the row says otherwise and the
   owner agreed.
4. **No regression elsewhere.** The receipt leak (non-pump fixtures routed as a pump) did not rise;
   the annotated floor and the law's oracle ratchet did not fall; latency, if the row touches a hot
   path, has a Release number.
5. **Tests that would fail.** Each promise has a test, and the orchestrator's mutation of it turned
   the test red (the mutation and its red output are in the gate evidence). A test that stays green
   when its behaviour is removed is PARTIAL.
6. **Docs reconciled.** `docs/EXTRACTION.md` (the pump reader section, and a numbered decision if the
   row changes one), `docs/TASKS.md` (the row's result, numbers and what was left), `docs/ERRORS.md`
   and `docs/JOURNEYS.md` J4/F2 if the user sees anything different, `CLAUDE.md` comment rules in
   every touched file (current truth only, no task ids in code comments).
7. **Everything the row promised.** Read the row's own Checks cell sentence by sentence; each
   sentence is MET, PARTIAL or MISSING. A promise quietly dropped is how PU.59's second amendment
   nearly shipped untested.

## Verdict

End with one of:
- **COMPLETE** – every item MET. The orchestrator may commit.
- **INCOMPLETE** – list each PARTIAL/MISSING item with what is needed; the orchestrator fixes it and
  re-dispatches this review (a fresh copy, same row). A gap the row cannot close becomes a new row,
  drafted here, never silently dropped.

**The standing fences appended below were written for build briefs.** Their "where you may write"
and "never stash/checkout" rules apply to you; their standing checks (`scripts/gate.sh`, UI suites,
screenshots) do **not** – you change no code. Do not run the long pipeline suites again; the logs
above are the evidence. Another session is editing pump code in this checkout – do not touch it.
