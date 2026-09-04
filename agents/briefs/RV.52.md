# RV.52 – serialize the Vision OCR tests so the suite stops hanging

Approved by the product owner 2026-09-04. Adding **one** more OCR test makes `swift test` hang, so
the project currently cannot run its own proof that camera orientation reaches Vision.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` — **`ios/Tests/`, `ios/Sources/` and `docs/`.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `backend/` file.

**A sibling agent may be working in `backend/`** — ignore it. There is also a git worktree at
`.claude/worktrees/rv48` belonging to another session: `swiftlint` from the repo root reports ~22
errors from inside it. **Those are not your gate** — confirm your own files are clean and carry on.
**Never move, rename or delete a file you did not create.**

## The measured problem — confirm it, do not re-derive it

Adding `CaptureOrientationTests` (one OCR test) to the full parallel run makes it hang
**deterministically**: >210 s against a clean ~65 s. Measured 8/8 hangs with it, 5/5 clean without,
and confirmed independently by the orchestrator.

`sample` puts the hang in Apple's own framework:
`VNCRImageReaderDetector → TextRecognition → _dispatch_semaphore_wait_slow` (`semaphore_wait_trap`),
inside **`VNControlledCapacityTasksQueue dispatchSyncByPreservingQueueCapacity`**.

**It is the framework at capacity, not the test.** A trivial one-OCR test with no rotation hangs it
too; a trivial non-Vision test does not. A semaphore (limit 4), a serial queue and `Task.detached`
were all tried and none prevented it — so **do not simply retry those**; if you use one, explain
what you are doing differently.

## The six suites that reach Vision

These are what saturate the queue — they are what must be gated:

- `ios/Tests/TankbookCoreTests/CorpusABRulesDumpTests.swift`
- `ios/Tests/TankbookCoreTests/CorpusCompressionTests.swift`
- `ios/Tests/TankbookCoreTests/ExtractionAssemblerTests.swift`
- `ios/Tests/TankbookCoreTests/AccuracyRatchetTests.swift`
- `ios/Tests/TankbookCoreTests/ScreenshotCrossCheckTests.swift`
- `ios/Tests/TankbookCoreTests/CaptureOrientationTests.swift` ← currently `.disabled`

(`Spike/ReceiptSpike` is a separate package with its own `swift test`; leave it alone unless you can
show it shares the ceiling.)

## What to build

**Serialize the Vision work, not the whole suite.** A shared gate that every OCR request passes
through — so the total in flight stays under the framework's capacity **regardless of how many
suites exist**, including ones added later. Options: a shared serial executor/actor that
`VisionTextRecognizer` funnels through, or `.serialized` on each Vision suite. **Say which you chose
and why**, and make it hard for a future OCR test to bypass it by accident — a gate you must
remember to opt into is one that will be forgotten.

**Measure the ceiling; do not guess a number.** Find the concurrency at which the hang starts (it is
~12–13 today) and set the limit from that with margin. **Record the measurement in
`docs/TESTING.md`** so the next person adding an OCR test knows the constraint exists and why.

**Serializing costs wall-clock. Report it.** The whole suite is ~65 s today; if OCR serialization
takes it to 3 minutes, that is a real trade the product owner should see rather than discover. If
the cost is large, say so and propose the alternative (e.g. gate only above N in flight rather than
strict serial).

## The acceptance check — this is the point of the row

**Re-enable `CaptureOrientationTests`** (remove the `.disabled` trait and the paragraph explaining
it) and show the **full suite passes with that test included**. Passing without it proves nothing —
that is the state today.

**Do NOT buy a green run by deleting or permanently skipping OCR tests.** The suite's OCR coverage
is the point, and this repo has refused that trade elsewhere. If you cannot make it pass with the
test enabled, **leave the test disabled, report exactly what you found, and do not pretend the row
is done.**

## Why this matters beyond one test

Every other gate here is **file-based** — including the corpus accuracy gate — and file OCR goes
through `VNImageRequestHandler(url:)`, which honours EXIF. So all of them stayed green for the
entire time the camera was handing Vision 90°-rotated images (RV.49). The rotated-fixture test is
the only thing that can tell the difference. **And the ceiling blocks every future OCR test**, in a
repo whose core value is extraction accuracy.

## Read before writing

1. **`CLAUDE.md`** — hard rule 14, and the standing note that a green suite is not evidence a thing
   is correct.
2. `docs/TESTING.md` — verification levels and the CI gates; this is where the measurement goes.
3. `ios/Sources/TankbookCore/Extraction/VisionTextRecognizer.swift` (both entry points — the URL one
   and the `cgImage` one RV.49 added), and the six suites above.

## Tests

- `cd ios && swift build ; swift test` — **1250 today; must not fall**, and must **rise by one**
  when you re-enable `CaptureOrientationTests`.
- **The headline evidence is a timing and a pass**: the full suite completes, with the orientation
  test enabled, in a wall-clock you report. Run it **at least three times** — a hang that reproduces
  8/8 needs more than one green run to be called fixed.
- If you add a concurrency limit in core, it is a pure decision and deserves an L1: the gate admits
  at most N concurrently, and releases on both success and throw (a gate that leaks on an error path
  deadlocks the suite the first time an OCR call fails).

**Vacuous-assertion traps, named:**
- Reporting one green run. The bug is intermittent-looking under load; three runs minimum.
- Reporting the suite green **without** re-enabling the test — that is today's state.
- Asserting the limit constant equals itself rather than that concurrency is actually bounded.

**Mutation-check and report it**: raise the limit far above the measured ceiling (or remove the
gate) and confirm the hang returns. Restore, confirm green. **If the hang does not return, your gate
is not what fixed it** — say so.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"      # report wall-clock, run 3x
    swiftlint lint ; echo "LINT=$?"               # repo ROOT; ignore .claude/worktrees/*
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Echo the exit code from the COMMAND, never through a pipe** (`cmd | tail -2 ; echo $?` reports
`tail`'s status); redirect to a file instead. Match the process NAME (`pgrep -x xcodebuild`);
**never `pgrep -f`/`pkill -f`**.

## Screenshots

None applies — test infrastructure only. Say so rather than fabricating one.

## Report back

- Exit codes (captured, not piped), test count before/after, and **three full-suite wall-clock
  times**.
- **The measured ceiling** — the concurrency at which the hang starts — and the limit you chose.
- Which mechanism you used, and how a future OCR test is prevented from bypassing it.
- **The wall-clock cost** of serializing, stated plainly.
- The mutation result, including whether the hang actually returned.
- Confirmation that no OCR test was deleted or skipped to achieve the green run.
