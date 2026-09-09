# RV.153 - a computed total must never beat a printed one

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** If a file is in your way or a test is
red that is not yours, report it and carry on.

**`main` is RED on this.** `RV56TotalPropertyTests.noReceiptTotalIsConfidentlyWrong`
(`ios/Tests/TankbookCoreTests/RV56TotalTests.swift:171`) asserts **zero** confident-wrong totals over
the whole receipts class. Two fixtures added 2026-09-09 break it:

```
receipt-055-circlek-tallinn-98-discount-et.jpg: got 33.96, want 150.0
receipt-057-gpn-valday-95-occluded-ru.jpg:      got 285.0, want 3935.85
```

## The mechanism, diagnosed - confirm it before you build on it

**Both are the same failure: the arithmetic product of two OCR'd numbers overrode a total that was
printed on the receipt and read correctly.**

**receipt-055.** OCR misreads the volume `77,56L` as **`17,56`** - the spike harness
(`swift run ReceiptSpike <folder> --dump-text`) reports `Liters 17.560`, `€/unit 1.934`, and
`17.56 x 1.934 = 33.96`, which is exactly the committed value. Meanwhile the receipt prints its total
**twice**: `KOKKU 150,00` and `KK MAKSE 150,00 EUR`.

**receipt-057.** The unit price is occluded by a thumb, so the line OCRs as `.05 x 57.000`, and
`5 x 57.000 = 285.0`. Meanwhile `=3935.85` is read at **confidence 1.00** on the very next line, and
the `ИТОГО:` line is read again (as `ОГО:` / `-3935.85`).

So in both cases the printed total was **available and correct** and lost to a product of two numbers,
one of which was wrong. Verify this with `--dump-text` on both fixtures before changing a rule - the
spike harness and the app's core extraction are different implementations, and the failing test
exercises the **app's** path (`ios/Sources/TankbookCore/Extraction/`), so confirm where the app's
33.96 and 285.0 are actually produced rather than assuming the spike's numbers transfer.

## What to build

**A printed total outranks a computed one.** When the image carries a total the parser read - anchored
by `ИТОГО` / `KOKKU` / `TOTAL` / `SUMMA` / `GESAMT` / `RAZEM`, or simply printed as a standalone
money value that the cross-check corroborates - it wins over `liters x unitPrice`. The arithmetic
fallback exists for **label-free pump displays** (`README.md`: *"this alone handles label-free pump
displays"*), not to overrule a receipt that states its own total.

**When printed and computed disagree beyond tolerance, ABSTAIN on the disagreement rather than
committing either.** That is the whole point of RV.56's property: a cell scored as a miss costs
recall, which is recoverable; a confident-wrong total pre-fills the Confirm screen looking exactly
like a right one, and hard rule 13 cannot protect a user from a plausible wrong number.
**Decide which side wins when they disagree and say why** - my reading is that the printed total
wins and the *volume* becomes the suspect field (in 055 the printed 150.00 and the printed price
1.934 imply 77.56 L, which is the correct volume and is what the receipt actually says), but this is
yours to establish from the corpus, not to take from me.

**Do not weaken the test.** RV.56's assertion is whole-class **on purpose** - its own comment says
*"so a NEW wrong total added later fails too"*. An allowlist, a quarantine folder, a
`knownFailing` set, or narrowing it to individual fixtures each turn the only test that catches this
into decoration. If you believe the property cannot hold, **stop and report** rather than editing it.

## Re-measure every mark this moves

The corpus marks are literals and this change will move some of them. Re-measure, do not guess:

- `Spike/ReceiptSpike/fixtures/high-water.json` - receipts is currently **223/265**, pump **37/210**.
- `CorpusCompressionTests.recordedReceipts` - currently `(hits: 207, total: 265)`.
- `PumpPhotoGate.measured*` - only if you touch the pump path.

**A recall drop is acceptable here if it buys precision**, and the ratchet's rule is that hits may not
fall - so if an abstention replaces a wrong answer and receipts recall drops, **say so explicitly in
your report with the numbers**, and record the reason in `high-water.json`'s `_note`. Do not quietly
ratchet a mark downward.

## Explicitly out of scope

- The pump path's own precision drop (three confident-wrong values on `pump-074..077`) - related in
  spirit, separate in code, and the pump mode is gated off. Do not chase it here.
- The nine fixtures themselves: they are correct as registered. `receipt-057`'s ground-truth unit
  price 69.05 is deliberately recoverable only by arithmetic (`3935.85 / 57.000`).
- [RV.151]'s rate work, which just landed.

## Docs to read before writing (in order)

1. `Spike/ReceiptSpike/README.md` - how the parser and the arithmetic fallback are meant to work.
2. `Spike/ReceiptSpike/fixtures/receipts/README.md` - the two fixtures' own entries, and the corpus's
   reasoning about confident-wrong values.
3. `docs/EXTRACTION.md` - **the authority**: the pipeline, the four cross-check outcomes, and the
   named failure modes. **Extend it** with the printed-beats-computed rule.
4. `CLAUDE.md` hard rules 13 and 15.

## Checks

Re-measure the baseline yourself and report what you observe. As left, `main` was **1782 tests / 204
suites with ONE red** - this one.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`.
3. `cd ios && swift test` - full, never subsetted. **It must end with zero failures**; report the
   count.
4. UI suites: none expected - this is core extraction. If you touch `ios/App/Sources`, name the suite
   and its observed, non-zero count.
5. Localization gate - exit 0; report keys and RU percentage.
6. Release build only if you touch a `#if DEBUG` seam.

Verify by **exit code** (`echo $?`), and report the codes you observed.

### Tests you must add

- **L1, and it must FAIL on the current code**: a unit test over the two receipts' **OCR text**
  (not the images) asserting the printed total wins - so the fix is pinned by something that does not
  need Vision and runs in a plain `swift test`. The raw lines are in the `--dump-text` output.
- **L1**: a label-free pump-shaped input still resolves by arithmetic - the fallback must keep working
  where it was designed to work.
- **L1**: printed and computed disagreeing beyond tolerance produces **no total**, not either value.
- **L5**: `noReceiptTotalIsConfidentlyWrong` passes over the whole receipts class, both fixtures still
  in it.

### Vacuous traps, named

- **An allowlist, a quarantine, or narrowing the class-wide assertion** - each defeats the only test
  that catches this, and the row exists because that test worked.
- Special-casing either fixture by filename.
- "Fixing" 055 by teaching the OCR to read `77,56` - the misread is real and will recur on other
  receipts; the defect is that a misread number **won** against a printed one.
- Ratcheting a high-water mark down without recording why.
- Asserting a total is non-nil rather than asserting its **value**.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change - or mutate one line to
prove the test's teeth. **Do not** `git stash`, `git checkout`, or move files out of the tree: an
agent did that on 2026-09-08 and a bad `mv` loop destroyed three of its own new files. Here the
headline test genuinely fails today, so run it first and show that output.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; the failing-then-passing output for the headline test; **where the app's 33.96 and
285.0 are actually produced** and whether my diagnosis held; which side you decided wins on a
disagreement and why; every corpus mark you re-measured with its old and new value; and anything you
found and did not fix.
