# How do we raise on-device receipt recognition from here? A fresh analysis

**Research only. You write exactly one file. You change no code.**

## Where you may write

Only this path, inside the worktree you are started in:

    diagnostics/RV.57-options-deepseek.md

Nothing else. **Run no `git` command.** Do not run `swift build`, `swift test`, `xcodebuild` or
`swiftlint` - other agents are reading the same machine and Vision tests serialize badly; everything
you need has already been measured for you. Do not touch `docs/TASKS.md`, `agents/briefs/`, any
`expected.csv`, or any fixture image.

**Never `pgrep -f`** - your brief is your command line, so it matches you. Use `pgrep -x`.

## The question, and it is deliberately open

The app reads a fuel receipt photo entirely on-device: Apple Vision OCR, then a deterministic
parser. Against the committed corpus of 46 real receipts it now scores **173 of 210 asserted
cells (82.4%)**, with **28 of 46 receipts fully correct (61%)**.

**What are ALL the ways to raise that, ranked by expected gain against cost and risk?**

That is the whole question. I am not asking you to confirm a plan - I am asking what you would do
with this corpus and this code. A day of work has already gone into the *parser*, which is the
layer that turns recognised text into fields. **Nobody has examined any other layer.** Consider at
minimum:

- **The recognition layer itself.** `VisionTextRecognizer` is 58 lines and configures
  `VNRecognizeTextRequest` in one particular way - a revision, a recognition level, a language
  list, correction on or off, a minimum text height, custom words. Every one of those is a knob
  nobody has measured. What does the corpus say about them?
- **Image preparation before recognition.** The pipeline hands Vision a full-resolution photo.
  Contrast, deskew, binarisation, cropping to the paper, upscaling a faint region - all standard
  for thermal print, none of them tried here. `receipt-018` and `pump-058` are the low-contrast
  cases; is that where the losses are?
- **A second pass over a region.** The parser already computes crop rects per field
  (`FieldExtraction.cropRect`, and RV.48 now persists them). Re-recognising a single field's
  region at higher effective resolution is a cheap, targeted retry. Would it recover the misses
  that are currently nil?
- **Evidence the document carries and the parser ignores.** Russian receipts print a **fiscal QR**
  (`.qr.txt` files sit beside the fixtures; `CaptureQRDetector` already reads one) that carries
  some fields exactly. Measured earlier on this corpus: a QR is present on **9 of 16** real
  receipts and carries **2 of the 5** fields. How much of the remaining gap does it close, and
  where does it conflict with the OCR?
- **The parser layer**, which is well-trodden but not exhausted.
- **Anything else you see.** The most useful answer would be one nobody in this repo has written
  down yet.

## Your evidence

Two files, generated from the live parser this morning. Use them; they are the point.

- `diagnostics/receipt-field-report.txt` - per fixture, per field: HIT/MISS with expected and
  actual, plus the cross-check outcome and parsed date. **37 misses across 18 fixtures.**
- `diagnostics/receipt-ocr-lines.txt` - the raw Vision output for all 46 receipts with normalised
  bounding boxes and per-line confidence. Lines the cleaning stage removed are marked
  `[FILTERED <class>]`.

Every claim you make must be traceable to a fixture. "OCR quality could be improved" is worth
nothing; "receipt-029's `43.24 Х 58.51` is unresolvable because both operands are plausible prices,
and only the user's history can settle it" is worth a lot.

## What the code and rules already are - read before proposing

1. `CLAUDE.md` - the hard rules. **13** (the app suggests, the user decides: an uncertain field is
   `nil`, never a guess), **1** (local-first: no feature may require the network), **9** (the server
   never reads domain meaning), **15** (typing is a peer path, so a capture is a head start).
2. `docs/EXTRACTION.md` - the pipeline, the four named failure modes, and where a trained model does
   and does not belong. Note it already records that a **cloud LLM arm scored 84/96** against the
   rules parser's 46/96 in a frozen A/B (P4.12), and that the cloud call measured **12-36 seconds**
   against a 3-second budget in production, which is why the product decided the local path
   carries the load.
3. `Spike/ReceiptSpike/fixtures/HIGH-WATER.md` - **read this before proposing any heuristic.** A
   decimal-digit tie-break was removed on purpose: it scored well by luck on one fixture while
   returning `99.400 L at 43.610` on `receipt-007` where the truth is `43.61 L at 99.40`, with the
   arithmetic cross-check reporting PASS because `a x b == b x a`.
4. `Spike/ReceiptSpike/fixtures/high-water.json` - the `_note` field is a written history of every
   change made to this parser today, with per-fixture reasoning. Read it: it will stop you
   proposing something that was already tried, and it names what was deliberately NOT done.
5. `Spike/ReceiptSpike/fixtures/receipts/README.md` - what each fixture is and what it proved.
6. `ios/Sources/TankbookCore/Extraction/` - the parser: `FuelExtractor`, `ReceiptNoiseFilter`,
   `FuelPriceBand*`, `CurrencyDetection`, `FuelKindNormalizer`, `VisionTextRecognizer`.

## Constraints any proposal must respect

- **On-device.** Anything requiring a network call is out of scope for this question; the cloud
  gateway exists and is a separate path with its own latency problem.
- **An abstention beats a wrong value.** The class currently has exactly **three** confident-wrong
  values left (all totals: receipts 017, 018, 025) and every other miss is an honest nil. A
  proposal that raises the score by guessing is a regression, not an improvement, and I will
  reject it. Say for each option what its wrong-answer risk is.
- **No fixture or ground-truth changes.** If you think a cell is wrong, say so with evidence.
- The corpus is 46 receipts. **Beware of fitting to it**: state, for each option, whether it would
  work on a receipt the corpus does not contain.

## What the answer should look like

`diagnostics/RV.57-options-deepseek.md`, as a **ranked list of options**. For each:

    (a) what it is, concretely enough to brief an implementer
    (b) which layer it acts on (recognition / preparation / parser / other evidence)
    (c) expected gain, counted per fixture and per field from the report - not estimated in the
        abstract; say "unknown, and here is how to measure it in an afternoon" when it is unknown
    (d) cost: rough implementation size, and any runtime cost on an iPhone 12, which is the floor
    (e) wrong-answer risk, and what abstains instead
    (f) whether it generalises beyond these 46 receipts, and why you believe that

Then two short sections that matter as much as the list:

- **"The ceiling"**: with everything you propose, what is the honest maximum on this corpus, and
  which misses are unreachable in principle? Name them.
- **"What I would not do"**: the tempting options you rejected, and why.

## Report back

The file path; your top three options with their expected gains; your ceiling number; and a plain
statement of which parts of the evidence you actually read. A proposal built on fixture names alone
is worth less than one built on the OCR lines, and saying so is not a failure.
