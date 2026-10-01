# PJ.42 - a demo receipt from the first-entry prompt, saving nothing

Journey: J1 first run -> "a bundled demo receipt if they have none" (`docs/JOURNEYS.md:50`).

**Decided by the product owner, 2026-10-01, replacing the row's "saved entry marked demo":** the demo
**saves nothing**. It runs the real capture pipeline on a bundled receipt and opens the review with
its numbers, and ends with "Done – now try your own" instead of Save. No schema change, nothing in the
log, the stats or sync. Update the row's text in `docs/TASKS.md`? **No - the orchestrator does that.**
Do update `docs/JOURNEYS.md` J1 to say the demo saves nothing.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`: `ios/App/Sources/Home/` (the first-entry prompt
in `HomeGuestLayout.swift`), `ios/App/Sources/Capture/`, `ios/App/Resources/` (the bundled receipt
image), `project.yml` (only to bundle the resource; run `xcodegen generate` after),
`ios/App/Sources/Localizable.xcstrings`, the matching tests, `docs/JOURNEYS.md` J1, `docs/SCREENMAP.md`.
Nothing under `ios/Sources/TankbookCore/Extraction/PumpReader/`.

## Write code first, explore second

## What exists (confirm before you change anything)

- The first-entry prompt: `HomeGuestLayout.swift` ~221-228 ("Scan your first fill-up").
- The capture pipeline and its verify screen ("Check the numbers", `CaptureVerifyView`,
  `ServiceInvoiceSession`/fill-up verify session, `CapturePipeline.process`), which the shutter and the
  Photos picker both feed (PJ.1). DEBUG seeds feed a fixture image with `-captureFixtureImage` and
  `-captureAutoReview` - read how they enter the pipeline; the demo enters the same way in production
  with a bundled image.
- A receipt drawing safe to publish exists: `design/store/assets/receipt-sketch.png` (a line drawing of
  a fuel receipt, 45,22 L x 1,754 EUR/L = 79,32 EUR, no brand, no card; the real pipeline reads it as
  79.32 / 45.22 / 1.754 on the iOS 27 simulator). Bundle that image as the demo receipt for both
  languages unless a reason in your report says otherwise. Never bundle a corpus fixture: those are
  real people's receipts.

## What to build

- On the first-entry prompt, a secondary action **"No receipt to hand? Try a sample"** (RU a full
  phrase). It never replaces or outranks "Scan" or "Type it" (hard rule 15: typing and scanning are
  peers; the demo is a third, quieter door).
- It runs the bundled image through the **real** pipeline - the same verify screen, the same reading
  spinners, the same numbers a user's photo would get. No canned values.
- The verify screen in demo mode: a one-line label that this is a sample receipt; its primary action
  is **"Done – now try your own"**, which returns to the first-entry prompt (or the capture screen -
  pick one, say which). There is no Save, and no path in demo mode writes an entry, an attachment, a
  blob or a sync record.
- Works offline (the image is bundled; the cloud fallback, if the pipeline would call it, must not be
  called in demo mode - say how you guaranteed it).
- A shape-only log event that the demo ran and how far the user got (`docs/LOGGING.md`).

**Out of scope:** PJ.16, PJ.41, PJ.43. Any change to the schema or sync.

## Docs to read, in order

1. `docs/JOURNEYS.md` J1 (authority for the first run) - update it.
2. `docs/SITE.md` copy rule and `CLAUDE.md` hard rule 15 - the demo must not imply "automatic".
3. `docs/DESIGN.md` - secondary action styling; `docs/SCREENMAP.md` - add the demo edge.

## Checks (exit codes; report each)

- `scripts/gate.sh` exit 0; `RELEASE=1 scripts/gate.sh` exit 0 (the demo path ships in Release - it
  must not depend on a DEBUG seam).
- `CaptureUITests` (or the suite covering the first-entry prompt and capture), own `-only-testing:` run,
  COUNT read.

## Tests you must add

- **L2/L4:** the demo opens the verify screen with the bundled receipt's numbers (79.32 / 45.22 /
  1.754 - oracle: the receipt's printed lines, 45,22 x 1,754 = 79,32).
- **L2:** after the demo, the entry count, the attachment count and the outgoing sync queue are all
  unchanged. **Mutation:** route "Done" through the normal save - this test must go red.
- **L4:** the demo action is visible on the first-entry prompt and is not the primary action.

## Vacuous traps

- A demo that shows hard-coded numbers instead of running the pipeline.
- A demo that saves and then deletes (sync may have queued it).
- A demo that calls the cloud reader.

## Screenshots

EN and RU, dark, outside a test run: the first-entry prompt with the demo action, and the demo verify
screen. `design/screenshots/PJ.42-first-entry.png` / `-ru.png`, `PJ.42-demo-verify.png` / `-ru.png`.

## Standing fences

- `swiftlint lint` from the repo ROOT. Check test COUNTS. Never stash/move/checkout for a baseline.
- Never `pgrep -f` / `pkill -f`. Never move, rename or revert a file you did not create.
- Assert frames against the window. Git is read-only for you.

## Report back

Exit codes; counts before/after; run-or-written per test; the mutation's red-then-green; how the cloud
fallback is kept out of demo mode; **anything you found and did not fix**.
